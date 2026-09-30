import Foundation
import LocalAuthentication
import UserNotifications

enum HealthStatus: String {
    case unknown, authorized, denied, unavailable
}

/// The three tabs, also what a notification tap asks RootView to show.
enum MainTab: Hashable {
    case feed, recap, you
}

/// The one source of truth for recaps and moments (PHASE2 contract). Views
/// read from it and call its methods; nothing else touches the stores. The
/// clock is read here and handed to the engine, never inside FrayedCore.
@MainActor
final class AppModel: ObservableObject {
    /// "-demo" launch argument: DemoData, no Health, no lock, nothing persisted.
    let isDemo: Bool
    let calendar: Calendar

    /// Newest first, from the MomentStore.
    @Published private(set) var moments: [Moment] = []
    /// Newest first, the last 60 days, from the RecapStore.
    @Published private(set) var recaps: [DayRecap] = []
    /// `recaps.first` when its dayKey is today's.
    @Published private(set) var today: DayRecap?
    /// Newest first, one per recap.
    @Published private(set) var ledgers: [DayLedger] = []
    @Published private(set) var healthStatus: HealthStatus
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefresh: Date?
    /// Persisted; setting it reschedules the notification.
    @Published var recapSchedule: RecapNotification.Schedule {
        didSet {
            guard !isDemo, recapSchedule != oldValue else {
                return
            }
            let defaults = UserDefaults.standard
            defaults.set(recapSchedule.hour, forKey: Keys.recapHour)
            defaults.set(recapSchedule.minute, forKey: Keys.recapMinute)
            scheduleRecapNotification()
        }
    }
    /// Persisted, default true.
    @Published var lockEnabled: Bool {
        didSet {
            if !isDemo {
                UserDefaults.standard.set(lockEnabled, forKey: Keys.lockEnabled)
            }
        }
    }
    /// Calendar labels (RECAP 3): off until the user turns them on and iOS
    /// grants access. Persisted.
    @Published private(set) var calendarLabels = false
    /// Event titles in the recap need their own switch; counts don't.
    @Published var showEventTitles = false {
        didSet {
            guard !isDemo, showEventTitles != oldValue else {
                return
            }
            UserDefaults.standard.set(showEventTitles, forKey: Keys.showEventTitles)
            Task { await refreshRecap() }
        }
    }
    /// True until Face ID or the passcode succeeds, and again after the app
    /// has been in the background. Views stay mounted underneath; LockGate
    /// and the privacy covers hide them.
    @Published private(set) var isLocked = false
    @Published private(set) var isAuthenticating = false
    /// Set when a store could not be read or written. Views may show it and
    /// then clear it.
    @Published var storeError: String?
    /// Local-only reactions on feed posts until the social phase: post id -> kinds.
    @Published var reactions: [String: Set<ReactionKind>] = [:]
    /// Set by a notification tap; RootView switches to it and clears it.
    @Published var pendingTab: MainTab?

    private let momentStore: MomentStore
    private let recapStore: RecapStore
    private let health: HealthService?
    /// Where the two JSON files live; nil in demo mode.
    private let dataDirectory: URL?
    /// Seeds the copy variants (RECAP 6.1); a UUID made on first launch.
    private let userId: String
    /// Day keys whose recap the user opened, for the steady badge.
    private var openedDays: Set<String>
    /// The user's word on a spike, by spike id, applied to every regeneration.
    private var spikeTags: [String: String]
    private var loadFailed = false
    private var unlockPromptPending = true

    static let elevatedMargin = 25
    static let keptDays = 60
    static let refreshInterval: TimeInterval = 15 * 60
    /// A recap day runs 04:00 to 04:00 (RECAP 1).
    static let dayStartHour = 4

    private enum Keys {
        static let userId = "user.id"
        static let lockEnabled = "lock.enabled"
        static let recapHour = "recap.hour"
        static let recapMinute = "recap.minute"
        static let healthStatus = "health.status"
        static let openedDays = "recap.opened"
        static let spikeTags = "spike.tags"
        static let reactions = "feed.reactions"
        static let lastRefresh = "recap.lastRefresh"
        static let calendarLabels = "calendar.labels"
        static let showEventTitles = "calendar.titles"
    }

    private init(isDemo: Bool, momentStore: MomentStore, recapStore: RecapStore,
                 health: HealthService?, dataDirectory: URL?) {
        self.isDemo = isDemo
        self.calendar = Calendar.autoupdatingCurrent
        self.momentStore = momentStore
        self.recapStore = recapStore
        self.health = health
        self.dataDirectory = dataDirectory

        let defaults = UserDefaults.standard
        if isDemo {
            userId = "demo"
            lockEnabled = false
            recapSchedule = RecapNotification.Schedule()
            healthStatus = .authorized
            openedDays = []
            spikeTags = [:]
        } else {
            if let saved = defaults.string(forKey: Keys.userId) {
                userId = saved
            } else {
                let fresh = UUID().uuidString
                defaults.set(fresh, forKey: Keys.userId)
                userId = fresh
            }
            lockEnabled = defaults.object(forKey: Keys.lockEnabled) as? Bool ?? true
            let hour = defaults.object(forKey: Keys.recapHour) as? Int ?? RecapNotification.defaultHour
            let minute = defaults.object(forKey: Keys.recapMinute) as? Int ?? RecapNotification.defaultMinute
            recapSchedule = RecapNotification.Schedule(hour: hour, minute: minute)
            if health == nil {
                healthStatus = .unavailable
            } else {
                healthStatus = defaults.string(forKey: Keys.healthStatus).flatMap { HealthStatus(rawValue: $0) } ?? .unknown
            }
            openedDays = Set(defaults.stringArray(forKey: Keys.openedDays) ?? [])
            spikeTags = defaults.dictionary(forKey: Keys.spikeTags) as? [String: String] ?? [:]
            lastRefresh = defaults.object(forKey: Keys.lastRefresh) as? Date
            calendarLabels = defaults.bool(forKey: Keys.calendarLabels)
            showEventTitles = defaults.bool(forKey: Keys.showEventTitles)
            if let stored = defaults.dictionary(forKey: Keys.reactions) as? [String: [String]] {
                var out: [String: Set<ReactionKind>] = [:]
                for (post, names) in stored {
                    let kinds = Set(names.compactMap { ReactionKind(rawValue: $0) })
                    if !kinds.isEmpty {
                        out[post] = kinds
                    }
                }
                reactions = out
            }
        }
        isLocked = lockEnabled
        reload()
    }

    static func live() -> AppModel {
        let directory = AppModel.dataDirectoryURL()
        return AppModel(
            isDemo: false,
            momentStore: FileMomentStore(url: directory.appendingPathComponent("moments.json")),
            recapStore: FileRecapStore(url: directory.appendingPathComponent("recaps.json")),
            health: HealthService.isAvailable ? HealthService() : nil,
            dataDirectory: directory
        )
    }

    static func demo() -> AppModel {
        let calendar = Calendar.autoupdatingCurrent
        let now = Date()
        let recapStore = InMemoryRecapStore()
        for recap in DemoData.recaps(calendar: calendar, now: now) {
            try? recapStore.save(recap)
        }
        return AppModel(
            isDemo: true,
            momentStore: InMemoryMomentStore(moments: DemoData.moments(calendar: calendar, now: now)),
            recapStore: recapStore,
            health: nil,
            dataDirectory: nil
        )
    }

    /// Picks live or demo from the launch arguments.
    static func fromLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments) -> AppModel {
        return arguments.contains("-demo") ? demo() : live()
    }

    // Health data never goes into iCloud, and iCloud Backup counts (RECAP 8,
    // Guideline 5.1.3(ii)), so unlike Romp the folder is excluded from backup.
    private static func dataDirectoryURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var directory = base.appendingPathComponent("Frayed", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory
    }

    // MARK: Derived

    /// A fresh engine per read, so `now` is always the current time.
    var trophies: TrophyEngine {
        return TrophyEngine(calendar: calendar, now: Date())
    }

    /// "No. 118" on the recap header.
    var recapNumber: Int {
        return recaps.count
    }

    /// Ledgers follow `recaps` one to one, so today's is the first when
    /// `today` is set.
    var todayLedger: DayLedger? {
        return today == nil ? nil : ledgers.first
    }

    // MARK: Loading

    private func reload() {
        do {
            moments = try momentStore.load()
            let all = try recapStore.load()
            recaps = Array(all.prefix(AppModel.keptDays))
            loadFailed = false
        } catch {
            loadFailed = true
            storeError = "Your recaps could not be loaded. Unlock your iPhone and try again."
        }
        rebuildDerived()
    }

    private func rebuildDerived() {
        let todayDay = AppModel.recapDay(for: Date(), calendar: calendar)
        today = recaps.first.flatMap { recap -> DayRecap? in
            guard let day = AppModel.date(fromDayKey: recap.dayKey, calendar: calendar),
                  calendar.isDate(day, inSameDayAs: todayDay) else {
                return nil
            }
            return recap
        }
        ledgers = recaps.compactMap { recap -> DayLedger? in
            guard let day = AppModel.date(fromDayKey: recap.dayKey, calendar: calendar) else {
                return nil
            }
            return recap.ledger(day: calendar.startOfDay(for: day), recapOpened: openedDays.contains(recap.dayKey))
        }
    }

    // MARK: Health and the recap

    func requestHealthAccess() async {
        guard !isDemo, let health = health else {
            return
        }
        let status = await health.requestAuthorization()
        setHealthStatus(status)
        await refreshRecap()
    }

    private func setHealthStatus(_ status: HealthStatus) {
        healthStatus = status
        if !isDemo {
            UserDefaults.standard.set(status.rawValue, forKey: Keys.healthStatus)
        }
    }

    /// HealthService.recapInput -> RecapEngine.generate -> RecapStore.save,
    /// then the ledgers and a .recap Moment for the day.
    func refreshRecap() async {
        guard !isDemo, let health = health, healthStatus == .authorized, !isRefreshing else {
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let now = Date()
        let day = AppModel.recapDay(for: now, calendar: calendar)
        // `day` is already the recap day, so key `now`: dayKey(for:) shifts by 04:00 itself.
        let dayKey = AppModel.dayKey(for: now, calendar: calendar)
        let earlier = recaps.filter { $0.dayKey != dayKey }
        let previous = recaps.filter { $0.dayKey < dayKey }.compactMap { $0.suggestion?.rule }
        do {
            var input = try await health.recapInput(
                day: day, now: now, schedule: recapSchedule, userId: userId,
                elevatedMargin: AppModel.elevatedMargin, previousSuggestions: previous,
                recapDays: earlier.count, calendar: calendar
            )
            // The last 7 stored days feed the "vs your week" comparison.
            let lastWeek = Array(earlier.prefix(7))
            input.recoveryMedian7d = RecapEngine.median(lastWeek.compactMap { $0.recovery?.median })
            let known = lastWeek.compactMap { recap -> (dayKey: String, minutes: Double)? in
                guard let median = recap.recovery?.median else { return nil }
                return (recap.dayKey, median)
            }
            if let best = known.min(by: { $0.minutes < $1.minutes }),
               let bestDay = AppModel.date(fromDayKey: best.dayKey, calendar: calendar) {
                input.recoveryBest7d = RecapInput.RecoveryBest(
                    weekday: RecapCopy.weekday(of: bestDay, calendar: calendar),
                    minutes: Int(best.minutes.rounded())
                )
            }
            input.calendarAccess = CalendarService.access(from: input.dayStart, to: now,
                                                          enabled: calendarLabels, showTitles: showEventTitles)
            for index in input.runs.indices {
                if let tag = spikeTags[input.runs[index].id].flatMap({ SpikeTag(rawValue: $0) }) {
                    input.runs[index].tag = tag
                }
            }
            let recap = RecapEngine.generate(input, calendar: calendar)
            store(recap)
            lastRefresh = now
            UserDefaults.standard.set(now, forKey: Keys.lastRefresh)
        } catch HealthServiceError.notAuthorized {
            setHealthStatus(.denied)
        } catch HealthServiceError.unavailable {
            setHealthStatus(.unavailable)
        } catch HealthServiceError.protectedDataUnavailable {
            storeError = "Apple Health is locked until you unlock your iPhone."
        } catch {
            storeError = "The recap could not be written. Unlock your iPhone and try again."
        }
    }

    /// Saves the recap, replaces the same day's earlier one in memory,
    /// rebuilds the ledgers and writes the day's recap moment.
    private func store(_ recap: DayRecap) {
        do {
            try recapStore.save(recap)
            recaps = Array(try recapStore.load().prefix(AppModel.keptDays))
        } catch {
            storeError = "The recap could not be saved. Unlock your iPhone and try again."
            return
        }
        rebuildDerived()
        saveRecapMoment(for: recap)
    }

    private func saveRecapMoment(for recap: DayRecap) {
        guard let day = AppModel.date(fromDayKey: recap.dayKey, calendar: calendar),
              let start = calendar.date(bySettingHour: AppModel.dayStartHour, minute: 0, second: 0, of: day) else {
            return
        }
        let end = min(max(recap.generatedAt, start.addingTimeInterval(60)), start.addingTimeInterval(Moment.maxDuration))
        let existing = recapMoment(for: recap)

        var peaks = Array(repeating: 0, count: Moment.RecapSummary.stripLength)
        for spike in recap.spikes {
            let hour = Int(spike.peakAt.timeIntervalSince(start) / 3600)
            if hour >= 0 && hour < peaks.count {
                peaks[hour] = max(peaks[hour], spike.peak)
            }
        }
        let summary = Moment.RecapSummary(
            spikeCount: recap.counts.daytime,
            stillCount: recap.counts.still,
            movingCount: recap.counts.moving,
            workoutCount: recap.counts.workout,
            noticedCount: recap.counts.noticed,
            load: recap.load?.total,
            recoverySeconds: recap.recovery?.median.map { Int(($0 * 60).rounded()) },
            calmestBpm: recap.calmest?.bpm,
            dayType: recap.type?.rawValue,
            coverage: recap.coverage,
            hourlyPeaks: peaks
        )
        let night = recap.lastNight.map { n in
            Moment.NightSummary(
                asleepMinutes: n.asleepMinutes,
                awakeMinutes: n.awakeMinutes,
                awakenings: n.awakenings,
                lowestHR: n.lowHR,
                sleepScore: nil,
                awakeRises: recap.counts.inBedAwake,
                asleepRises: recap.counts.inBedAsleep,
                hrvNight: n.hrvNight,
                hrvBaseline: n.hrvBaseline
            )
        }
        do {
            let moment = try Moment(
                id: existing?.id ?? UUID(),
                start: start,
                end: end,
                kind: .recap,
                attribution: .still,
                peakHR: recap.spikes.map { $0.peak }.max(),
                restingHR: recap.restingHR,
                noticed: existing?.noticed,
                note: existing?.note ?? "",
                title: existing?.title,
                source: .health,
                visibility: existing?.visibility ?? .private,
                recap: summary,
                night: night
            )
            try momentStore.save(moment)
            moments = try momentStore.load()
        } catch {
            storeError = "The recap could not be saved. Unlock your iPhone and try again."
        }
    }

    /// Today's ledger.recapOpened = true (steady badge).
    func markRecapOpened() {
        guard let today = today, !openedDays.contains(today.dayKey) else {
            return
        }
        openedDays.insert(today.dayKey)
        if !isDemo {
            UserDefaults.standard.set(Array(openedDays).sorted(), forKey: Keys.openedDays)
        }
        rebuildDerived()
    }

    /// Re-renders today with the tag and persists it. The tag is kept by
    /// spike id and applied to every later regeneration through
    /// RecapInput.Run.tag, so the engine's copy catches up on the next
    /// refresh; the counts update at once.
    func setTag(_ tag: SpikeTag?, spikeId: String) {
        spikeTags[spikeId] = tag?.rawValue
        if !isDemo {
            UserDefaults.standard.set(spikeTags, forKey: Keys.spikeTags)
        }
        guard let current = today, current.spikes.contains(where: { $0.id == spikeId }) else {
            return
        }
        var updated = current
        for i in updated.spikes.indices where updated.spikes[i].id == spikeId {
            updated.spikes[i].tag = tag
        }
        updated.counts.noticed = updated.spikes.filter { $0.bucket == .still && $0.tag != nil }.count
        store(updated)
        if !isDemo && healthStatus == .authorized {
            Task { await refreshRecap() }
        }
    }

    func weekReceipt(for date: Date) -> WeekReceipt {
        let week = trophies.week(containing: date)
        var weeks = Set<Date>()
        for recap in recaps {
            if let day = AppModel.date(fromDayKey: recap.dayKey, calendar: calendar), day < week.end {
                weeks.insert(trophies.week(containing: day).start)
            }
        }
        return WeekReceipt.build(week: week, recaps: recaps, receiptCount: max(weeks.count, 1), calendar: calendar)
    }

    // MARK: Calendar labels

    /// Turning labels on asks iOS for calendar access; a refusal leaves
    /// them off. Either way today's recap is rewritten to match.
    func setCalendarLabels(_ on: Bool) async {
        guard !isDemo else {
            return
        }
        let granted = on ? await CalendarService.requestAccess() : false
        calendarLabels = granted
        UserDefaults.standard.set(granted, forKey: Keys.calendarLabels)
        if on && !granted {
            storeError = "Frayed can't read your calendar. Turn on Full Access for Frayed in Settings, Privacy, Calendars."
        }
        await refreshRecap()
    }

    // MARK: Posting

    /// The `.recap` moment saved for this recap's day, which is what gets posted.
    func recapMoment(for recap: DayRecap) -> Moment? {
        guard let day = AppModel.date(fromDayKey: recap.dayKey, calendar: calendar) else {
            return nil
        }
        return moments.first { $0.kind == .recap && calendar.isDate($0.start, inSameDayAs: day) }
    }

    /// Nothing reaches the feed on its own: a recap stays private until the
    /// user posts it, and taking it down sets it back to private.
    func setVisibility(_ visibility: MomentVisibility, momentId: UUID) {
        guard var moment = moments.first(where: { $0.id == momentId }), moment.visibility != visibility else {
            return
        }
        moment.visibility = visibility
        do {
            try momentStore.save(moment)
            moments = try momentStore.load()
        } catch {
            storeError = "That post could not be saved. Unlock your iPhone and try again."
        }
    }

    // MARK: Reactions

    func toggle(_ kind: ReactionKind, on postId: String) {
        var kinds = reactions[postId] ?? []
        if kinds.contains(kind) {
            kinds.remove(kind)
        } else {
            kinds.insert(kind)
        }
        if kinds.isEmpty {
            reactions.removeValue(forKey: postId)
        } else {
            reactions[postId] = kinds
        }
        if !isDemo {
            let stored = reactions.mapValues { $0.map { $0.rawValue }.sorted() }
            UserDefaults.standard.set(stored, forKey: Keys.reactions)
        }
    }

    // MARK: Delete

    /// Removes every recap and moment from this iPhone. Apple Health, the
    /// age gate, the lock setting and the UI mode are untouched.
    func deleteAllData() {
        if let directory = dataDirectory {
            for name in ["moments.json", "recaps.json"] {
                do {
                    try FileManager.default.removeItem(at: directory.appendingPathComponent(name))
                } catch CocoaError.fileNoSuchFile {
                    // Nothing was ever saved.
                } catch {
                    storeError = "Your data could not be deleted."
                    return
                }
            }
        } else {
            try? recapStore.deleteAll()
            for moment in moments {
                try? momentStore.delete(id: moment.id)
            }
        }
        moments = []
        recaps = []
        openedDays = []
        spikeTags = [:]
        reactions = [:]
        lastRefresh = nil
        if !isDemo {
            let defaults = UserDefaults.standard
            defaults.removeObject(forKey: Keys.openedDays)
            defaults.removeObject(forKey: Keys.spikeTags)
            defaults.removeObject(forKey: Keys.reactions)
            defaults.removeObject(forKey: Keys.lastRefresh)
        }
        rebuildDerived()
    }

    // MARK: Lock

    /// Called when the scene goes to the background. Only the background
    /// re-locks: the Face ID prompt itself makes the scene inactive, so
    /// locking on that would loop.
    func lockForBackground() {
        isLocked = lockEnabled
        unlockPromptPending = true
    }

    /// Shows the Face ID prompt once per launch or return from background,
    /// when the scene is active and the app is locked.
    func promptUnlockIfNeeded() {
        guard lockEnabled else {
            isLocked = false
            return
        }
        guard isLocked, unlockPromptPending else {
            return
        }
        unlockPromptPending = false
        Task { await unlock() }
    }

    func unlock() async {
        guard isLocked, !isAuthenticating else {
            return
        }
        let context = LAContext()
        var error: NSError?
        // No passcode set (or a simulator without one): there is nothing to
        // check against, and staying locked would make the app unusable.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            isLocked = false
            return
        }
        isAuthenticating = true
        let passed = (try? await context.evaluatePolicy(.deviceOwnerAuthentication,
                                                        localizedReason: "Unlock to see your recaps.")) ?? false
        isAuthenticating = false
        if passed {
            isLocked = false
        }
    }

    // MARK: Scene

    /// Retries a load that failed on a locked phone, re-derives `today`
    /// across the 04:00 boundary and refreshes when the last one is older
    /// than 15 minutes.
    func sceneBecameActive() {
        if loadFailed {
            storeError = nil
            reload()
        } else {
            rebuildDerived()
        }
        guard !isDemo, healthStatus == .authorized else {
            return
        }
        let stale = lastRefresh.map { Date().timeIntervalSince($0) >= AppModel.refreshInterval } ?? true
        if stale {
            Task { await refreshRecap() }
        }
    }

    // MARK: Notifications

    /// Asks once, then schedules the daily recap. Returns whether it was allowed.
    @discardableResult
    func requestNotificationPermission() async -> Bool {
        guard !isDemo else {
            return false
        }
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        scheduleRecapNotification()
        return granted
    }

    /// One repeating calendar trigger at the user's time (RECAP 8). The body
    /// is static and generic; the recap itself is generated on open.
    func scheduleRecapNotification() {
        guard !isDemo else {
            return
        }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [RecapNotification.identifier])
        let content = UNMutableNotificationContent()
        content.title = RecapNotification.title
        content.body = RecapNotification.bodies[0]
        content.threadIdentifier = RecapNotification.threadIdentifier
        content.relevanceScore = RecapNotification.relevanceScore
        let trigger = UNCalendarNotificationTrigger(dateMatching: recapSchedule.dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: RecapNotification.identifier, content: content, trigger: trigger)
        center.add(request) { _ in }
    }

    // MARK: Day keys

    /// "2026-09-22": the key the engine writes and the stores replace on.
    static func dayKey(for date: Date, calendar: Calendar) -> String {
        return keyFormatter(calendar).string(from: recapDay(for: date, calendar: calendar))
    }

    /// Local midnight of the key's day. Also reads the compact "20260922"
    /// form Trophies uses, in case a store was written with it.
    static func date(fromDayKey key: String, calendar: Calendar) -> Date? {
        if let date = keyFormatter(calendar).date(from: key) {
            return date
        }
        let compact = keyFormatter(calendar)
        compact.dateFormat = "yyyyMMdd"
        return compact.date(from: key)
    }

    /// Local midnight of the recap day containing `date`: before 04:00 the
    /// day is still yesterday's.
    static func recapDay(for date: Date, calendar: Calendar) -> Date {
        let shifted = date.addingTimeInterval(-Double(dayStartHour) * 3600)
        return calendar.startOfDay(for: shifted)
    }

    private static func keyFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
