import Foundation

/// The recap's rendered strings, in RECAP 6.1 block order. Every field is
/// final text; a nil or empty field is a skipped block, never "N/A".
struct RecapText: Codable, Hashable {
    struct LabelledLine: Codable, Hashable {
        let spikeId: String
        /// "a long stretch, 1 h 15 m" for a 45-min-plus spike, shown before the line.
        let stretch: String?
        let text: String
    }

    var headline = ""
    var attribution: String? = nil
    var labelled: [LabelledLine] = []
    var calendarHint: String? = nil
    var calmest: String? = nil
    var recovery: String? = nil
    var lastNight: String? = nil
    var load: String? = nil
    /// "so far", "partial", "first week", "estimated", joined with " · ".
    var loadLabel: String? = nil
    var loadNotes: [String] = []
    var typeLabel: String? = nil
    var typeOneLiner: String? = nil
    /// "· threshold +20" when the spike threshold is not Standard.
    var typeSuffix: String? = nil
    var addOns: [String] = []
    var suggestion: String? = nil
    var suggestionSource: String? = nil
    var footer = ""
    /// The user tagged Panic twice or more: the footer moves under the headline.
    var footerUnderHeadline = false
    var updated: String? = nil
    var shareLine1: String? = nil
    var shareLine2: String? = nil

    init() {}

    static let empty = RecapText()

    /// Every non-empty block in render order, footer placement applied.
    var blocks: [String] {
        var out: [String] = [headline]
        if footerUnderHeadline {
            out.append(footer)
        }
        if let a = attribution { out.append(a) }
        out.append(contentsOf: labelled.map { $0.text })
        if let h = calendarHint { out.append(h) }
        if let c = calmest { out.append(c) }
        if let r = recovery { out.append(r) }
        if let n = lastNight { out.append(n) }
        if let l = load { out.append(l) }
        out.append(contentsOf: loadNotes)
        if let t = typeLabel { out.append(t) }
        if let s = suggestion { out.append(s) }
        if !footerUnderHeadline {
            out.append(footer)
        }
        return out.filter { !$0.isEmpty }
    }
}

/// Every copy template block from RECAP 6, the seeded variant picker, and
/// the banned-word list the tests sweep every template against.
enum RecapCopy {
    enum Block: Int, CaseIterable {
        case headline, attribution, labelled, calmest, recovery, lastNight, load, type, suggestion, footer, share, notification
    }

    /// Variant index per block = (seed + block) mod count, seed = fnv1a(userId + dayKey).
    struct Picker: Hashable {
        let seed: UInt64
        /// When set, every block uses this variant: fixtures and previews.
        let fixedIndex: Int?

        static let first = Picker(seed: 0, fixedIndex: 0)

        static func fixed(_ index: Int) -> Picker {
            return Picker(seed: 0, fixedIndex: index)
        }

        static func seeded(userId: String, dayKey: String) -> Picker {
            return Picker(seed: RecapCopy.fnv1a(userId + dayKey), fixedIndex: nil)
        }

        func index(_ block: Block, count: Int) -> Int {
            guard count > 0 else {
                return 0
            }
            if let fixed = fixedIndex {
                return fixed % count
            }
            return Int((seed &+ UInt64(block.rawValue)) % UInt64(count))
        }

        /// The seeded variant, or the next one whose data exists.
        func pick<T>(_ block: Block, from variants: [T], eligible: (T) -> Bool) -> T? {
            guard !variants.isEmpty else {
                return nil
            }
            let start = index(block, count: variants.count)
            for offset in 0..<variants.count {
                let candidate = variants[(start + offset) % variants.count]
                if eligible(candidate) {
                    return candidate
                }
            }
            return nil
        }

        func pick<T>(_ block: Block, from variants: [T]) -> T? {
            return pick(block, from: variants, eligible: { _ in true })
        }
    }

    // MARK: Rules the engine must never break (RECAP 0.1)

    /// Never in any generated string, matched case-insensitively as substrings.
    static let bannedWords: [String] = [
        "panic attack", "anxiety attack", "anxiety", "anxious", "depression", "depressed",
        "burnout", "burned out", "burnt out", "disorder", "symptom", "diagnos", "stressed out", "unhealthy"
    ]

    /// Allowed only in fixed UI chrome (Settings), never in the recap body.
    static let chromeOnlyWords: [String] = ["stress"]

    /// The user's own words; the app repeats them verbatim and never adds to them.
    static let allowedUserWords: [String] = SpikeTag.allCases.map { $0.label }

    /// The first banned or chrome-only word found in the text, or nil.
    static func bannedWord(in text: String) -> String? {
        let lowered = text.lowercased()
        for word in bannedWords + chromeOnlyWords where lowered.contains(word) {
            return word
        }
        return nil
    }

    // MARK: Templates

    static let headlineVariants = [
        "Your heart spiked {n} {n:time|times} {when}. {Of} of them while you were sitting still.",
        "{n} {n:spike|spikes}. {of} of them from a chair, which is harder than it sounds.",
        "Your heart went up {n} {n:time|times} {when}. You put a name on {named} of them.",
        "{n} {n:spike|spikes} {when}, {of} of them on your own time."
    ]
    static let headlineAllStill = "Your heart spiked {n} times {when}. {All} of them sitting still."
    static let headlineNone = "Nothing to report. Your heart kept to itself {when}."
    static let headlineOneOnPurpose = "One spike, on purpose."
    static let headlineAllOnPurpose = "{n} spikes, all of them on purpose."
    static let headlineOneStill = "Your heart spiked once {when}, sitting still."
    static let headlineThin = "Your heart spiked {n} {n:time|times} in the {hours} hours the Watch was on."
    static let headlineThinNone = "Nothing to report in the {hours} hours the Watch was on."

    /// Segments in fixed order; a zero count drops its segment.
    static let attributionVariants: [(segments: [String], separator: String)] = [
        (["{workout} in workouts", "{moving} while moving", "{still} sitting still"], " · "),
        (["Workouts {workout}", "moving {moving}", "sitting still {still}"], " · "),
        (["{still} sitting still", "{moving} on the move", "{workout} in a workout"], ", ")
    ]

    /// Picked by the timing relation, never by seed.
    static let labelledCalendar: [DayRecap.Relation: String] = [
        .leftBefore: "{who}: peak {peak} bpm. Your body left {m} min before you did.",
        .inItBefore: "{who}: {mag} at {time}. Your body was in it {m} min before it started.",
        .stayedAfter: "{who}: peak {peak} bpm, hung around {m} min after it ended.",
        .cameDownWithIt: "{who}: peak {peak} bpm, and came down about when it ended."
    ]
    static let labelledNoCalendar = [
        "About {clock}: peak {peak} bpm, {dur}. You'd know better than us what that was.",
        "{Time}, {mag}, {dur}. Sitting still the whole time.",
        "Peak {peak} bpm at {time}. Not a walk, not a workout. Just you and something."
    ]
    static let labelledTag = "You called it {tag}."
    static let labelledStretch = "a long stretch, {h} h {m} m"
    static let calendarHint = "Turn on calendar labels to see which of these had an invite."

    static let calmestVariants = [
        "Calmest: {time}, {bpm} bpm. Whatever that was, do it again.",
        "Low point of the day, in a good way: {bpm} bpm at {time}.",
        "{Time} was the calmest you got, {bpm} bpm. Noted."
    ]

    static let recoveryVariants = [
        "Bounced back in {median} on average; {bestDay} was {best}.",
        "{Median} from peak back to normal. Your week says {median7d}.",
        "Took {median} to come down, typical for your week."
    ]
    static let recoveryFirstWeek = "{Median} from peak back to normal. We'll have a comparison in a few days."
    static let recoveryUnknown = "Came down: couldn't tell, you moved each time. Fair."
    static let recoveryOverAnHour = "over an hour"

    static let lastNightVariants = [
        "Last night: {asleep} asleep, {awakenings} {awakenings:wake-up|wake-ups} the Watch caught, {low}.",
        "{asleep} of sleep, {low}. HRV {hrvState}.",
        "Slept {asleep}. {awakenings} {awakenings:wake-up|wake-ups}, {low}. That's the whole report."
    ]
    static let lastNightLow = "lowest {lowHR} bpm"
    static let lastNightNoLow = "no lowest reading"
    static let lastNightAwake = "Your heart went up {times} while you were awake in bed, around {clock}."
    static let lastNightAsleepOne = "One rise around {clock} while you were asleep. Dreams do that too."
    static let lastNightAsleepMany = "{k} rises while you were asleep, the first around {clock}. Dreams do that too."
    static let lastNightShort = "Short one."
    static let noSleepData = "No sleep data: the Watch was off the wrist or under 30 % (Apple's rule, not ours)."

    static let loadLine = "Load {total} · {band}"
    static let loadSoFar = "so far"
    static let loadPartial = "partial"
    static let loadFirstWeek = "first week"
    static let loadEstimated = "estimated"
    static let firstWeekNote = "First week: baselines fill in as we go."
    static let restingNote = "A full day on the wrist and Apple hands over a resting rate."

    static let typeNames: [DayType: String] = [
        .frayed: "Frayed", .nightShift: "Night shift", .meetingSurvivor: "Meeting survivor",
        .slowBurner: "Slow burner", .runningOnFumes: "Running on fumes", .bouncedBack: "Bounced back",
        .zenMaster: "Zen master", .cardioOnly: "Cardio only", .quietDay: "Quiet day", .justAWeekday: "Just a {weekday}"
    ]
    static let typeOneLiners: [DayType: String] = [
        .frayed: "Everything, all at once. Tomorrow is allowed to be smaller.",
        .nightShift: "Your heart worked a night shift. Nobody asked it to.",
        .meetingSurvivor: "Attended everything. Survived everything. Calendar has receipts.",
        .slowBurner: "Nothing dramatic. Just on, for a while. Like a porch light.",
        .runningOnFumes: "Ran the whole day on {asleep}. Impressive. The night owes you one.",
        .bouncedBack: "Spiked, sure. Never stayed.",
        .zenMaster: "A full day of readings and not one spike. We checked twice.",
        .cardioOnly: "Your heart only went up when you told it to.",
        .quietDay: "One spike, or none. Nothing happened. That was the good part.",
        .justAWeekday: "{n} spikes, none of them a story."
    ]
    static let typePending = "Type at {recapClock}"
    static let typeThin = "Not enough Watch time for a type today"
    static let typeThreshold = "· threshold +{margin}"
    static let addOnCaffeine = "+ Caffeine curve"

    static let suggestionVariants: [RecapSuggestion.Rule: [String]] = [
        .breathing: [
            "Five minutes of cyclic sighing: breathe in through the nose, a second small sip in, long slow breath out. Repeat. In a month-long trial it edged out mindfulness on mood.",
            "Two-minute version if five is too many: long exhales, that's the whole trick."
        ],
        .brokenNight: ["Bed when you're actually sleepy, not earlier. Your night is already doing enough."],
        .earlierBed: [
            "Bed {gap} min earlier tonight would put you over 7 hours. That's the whole plan, and it's optional.",
            "An earlier bed tonight, if it's on offer. Not a target, just the one thing on the list."
        ],
        .walk: ["A short walk after the next one. One bout of movement takes the edge off a little, on average. A little is fine."],
        .meetingSurvivor: ["Leave the last meeting five minutes early tomorrow. Your body already does."],
        .cardioOnly: ["Same again tomorrow, if you like."],
        .noNotes: ["No notes. Keep whatever that was."],
        .nothingToFix: ["Nothing to fix. Read it, close it, go do something else."]
    ]
    static let suggestionSources: [RecapSuggestion.Rule: RecapSuggestion.Source] = [
        .breathing: .balban2023, .brokenNight: .espie2006, .earlierBed: .watson2015, .walk: .ensari2015
    ]

    static let footerWithNumber = "If today was heavier than a recap can hold: call or text {number}, any time. It's for anyone, not only emergencies."
    static let footerNoNumber = "If today was heavier than a recap can hold: tap here for a crisis line, any time. It's for anyone, not only emergencies."
    static let notWorn = "No Watch data today. Nothing to recap, nothing to read into it."
    static let updatedLine = "updated {clock}"

    static let shareLine1 = "{type}. {oneLiner}"
    static let shareLine2Variants = [
        "{n} {n:spike|spikes} · {median} to come down",
        "{still} sitting still · calmest {calmestBpm} bpm",
        "Load {load} · slept {asleep}",
        "Load {load}"
    ]

    /// Every template, for the banned-word sweep.
    static var allTemplates: [String] {
        var all = headlineVariants
        all += [headlineAllStill, headlineNone, headlineOneOnPurpose, headlineAllOnPurpose, headlineOneStill, headlineThin, headlineThinNone]
        all += attributionVariants.flatMap { $0.segments }
        all += labelledCalendar.values
        all += labelledNoCalendar
        all += [labelledTag, labelledStretch, calendarHint]
        all += calmestVariants
        all += recoveryVariants
        all += [recoveryFirstWeek, recoveryUnknown, recoveryOverAnHour]
        all += lastNightVariants
        all += [lastNightLow, lastNightNoLow, lastNightAwake, lastNightAsleepOne, lastNightAsleepMany, lastNightShort, noSleepData]
        all += [loadLine, loadSoFar, loadPartial, loadFirstWeek, loadEstimated, firstWeekNote, restingNote]
        all += typeNames.values
        all += typeOneLiners.values
        all += [typePending, typeThin, typeThreshold, addOnCaffeine]
        all += suggestionVariants.values.flatMap { $0 }
        all += suggestionSources.values.map { $0.citation }
        all += [footerWithNumber, footerNoNumber, notWorn, updatedLine, shareLine1]
        all += shareLine2Variants
        all += DayRecap.LoadBand.allCases.map { $0.label }
        all += [DayRecap.HRVState.aboutUsual, .lower, .higher, .noBaseline].map { $0.label }
        all += RecapNotification.bodies
        all += [RecapNotification.notWornBody, RecapNotification.sundayNudgeBody, RecapNotification.title]
        return all
    }

    // MARK: Placeholders

    /// Fills {key}, {key:singular|plural} (by the value of key) and a
    /// capitalised {Key} (first letter upper-cased).
    static func fill(_ template: String, _ values: [String: String]) -> String {
        var out = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{") {
            out.append(contentsOf: rest[rest.startIndex..<open])
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}") else {
                out.append(contentsOf: rest[open...])
                rest = ""
                break
            }
            let token = rest[afterOpen..<close]
            if let colon = token.firstIndex(of: ":") {
                let key = String(token[token.startIndex..<colon])
                let forms = token[token.index(after: colon)...].split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map { String($0) }
                let value = values[key] ?? ""
                out += value == "1" ? (forms.first ?? "") : (forms.last ?? "")
            } else {
                out += lookup(String(token), values)
            }
            rest = rest[rest.index(after: close)...]
        }
        out.append(contentsOf: rest)
        return out
    }

    private static func lookup(_ key: String, _ values: [String: String]) -> String {
        if let value = values[key] {
            return value
        }
        if let first = key.first, first.isUppercase {
            let lower = first.lowercased() + String(key.dropFirst())
            if let value = values[lower] {
                return capitalised(value)
            }
        }
        return "{" + key + "}"
    }

    static func capitalised(_ s: String) -> String {
        guard let first = s.first else {
            return s
        }
        return first.uppercased() + String(s.dropFirst())
    }

    static let weekdays = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static func weekday(of date: Date, calendar: Calendar) -> String {
        let index = calendar.component(.weekday, from: date)
        return weekdays[(index - 1 + 7) % 7]
    }

    /// "2:40 pm", floored to 5 min: background readings are 5 min apart.
    static func clock(_ date: Date, calendar: Calendar, roundToFive: Bool = true) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 0
        var minute = parts.minute ?? 0
        if roundToFive {
            minute -= minute % 5
        }
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(hour12):\(twoDigits(minute)) \(hour < 12 ? "am" : "pm")"
    }

    static func about(_ date: Date, calendar: Calendar) -> String {
        return "about " + clock(date, calendar: calendar)
    }

    /// "8 pm" or "8:30 pm", the recap time without rounding.
    static func hourClock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        let hour = parts.hour ?? 20
        let minute = parts.minute ?? 0
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let suffix = hour < 12 ? "am" : "pm"
        return minute == 0 ? "\(hour12) \(suffix)" : "\(hour12):\(twoDigits(minute)) \(suffix)"
    }

    /// Minutes: exact under 15, rounded to 5 from 15 up; 0 is "a moment".
    static func duration(_ minutes: Int) -> String {
        if minutes <= 0 {
            return "a moment"
        }
        if minutes < 15 {
            return "\(minutes) min"
        }
        return "\(Int((Double(minutes) / 5).rounded()) * 5) min"
    }

    /// "7 h 05 m".
    static func hoursMinutes(_ minutes: Int) -> String {
        return "\(minutes / 60) h \(twoDigits(minutes % 60)) m"
    }

    static func signed(_ magnitude: Int) -> String {
        return magnitude >= 0 ? "+\(magnitude)" : "\(magnitude)"
    }

    /// "about 17 min" or "over an hour".
    static func recoveryText(_ minutes: Double) -> String {
        if minutes >= 60 {
            return recoveryOverAnHour
        }
        return "about \(Int(minutes.rounded())) min"
    }

    static func twoDigits(_ n: Int) -> String {
        return n < 10 ? "0\(n)" : "\(n)"
    }

    static func fnv1a(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}

// MARK: Rendering

extension RecapCopy {
    static func render(_ r: DayRecap, input: RecapInput, calendar: Calendar, picker: Picker) -> RecapText {
        var t = RecapText()
        t.footer = footer(number: input.crisisNumber)
        if r.isNotWorn {
            t.headline = notWorn
            t.lastNight = noSleepData
            return t
        }

        let n = r.counts.daytime
        let still = r.counts.still
        let when = r.isSoFar ? "so far" : "today"
        t.headline = headline(n: n, still: still, noticed: r.counts.noticed, when: when,
                              thinHours: r.coverage < DayType.minimumCoverage ? Int(r.awakeTrackedHours.rounded()) : nil,
                              picker: picker)
        t.footerUnderHeadline = r.spikes.filter { $0.tag == .panic }.count >= 2
        if n > 0 {
            t.attribution = attribution(r.counts, picker: picker)
        }

        let top = r.stillSpikes
            .sorted { a, b in a.magnitude != b.magnitude ? a.magnitude > b.magnitude : a.start < b.start }
            .prefix(3)
        t.labelled = top.map { labelledLine($0, calendar: calendar, picker: picker) }
        if !input.calendarAccess.access && !input.calendarAccess.hintDismissed && !top.isEmpty {
            t.calendarHint = calendarHint
        }

        if let c = r.calmest, let template = picker.pick(.calmest, from: calmestVariants) {
            t.calmest = fill(template, ["time": about(c.at, calendar: calendar), "bpm": "\(c.bpm)"])
        }
        if let rec = r.recovery {
            t.recovery = recoveryLine(rec, picker: picker)
        }
        t.lastNight = r.lastNight.map { lastNightLine($0, calendar: calendar, picker: picker) } ?? noSleepData

        if let load = r.load {
            t.load = fill(loadLine, ["total": "\(load.total)", "band": load.band.label])
            var labels: [String] = []
            if r.isSoFar { labels.append(loadSoFar) }
            if r.coverage < DayType.minimumCoverage {
                labels.append(loadPartial)
            } else if load.firstWeek {
                labels.append(loadFirstWeek)
            } else if load.partial {
                labels.append(loadPartial)
            }
            if load.estimated { labels.append(loadEstimated) }
            t.loadLabel = labels.isEmpty ? nil : labels.joined(separator: " · ")
            if load.firstWeek { t.loadNotes.append(firstWeekNote) }
            if load.estimated { t.loadNotes.append(restingNote) }
        }

        let typeValues = typePlaceholders(r, dayStart: input.dayStart, calendar: calendar)
        switch r.typeStatus {
        case .awarded:
            if let type = r.type {
                t.typeLabel = typeName(type, values: typeValues)
                t.typeOneLiner = fill(typeOneLiners[type] ?? "", typeValues)
            }
        case .pending:
            t.typeLabel = fill(typePending, ["recapClock": hourClock(input.recapTime, calendar: calendar)])
        case .thinCoverage, .notWorn:
            t.typeLabel = typeThin
        }
        if r.elevatedMargin != 25 {
            t.typeSuffix = fill(typeThreshold, ["margin": "\(r.elevatedMargin)"])
        }
        t.addOns = r.addOns.map { _ in addOnCaffeine }

        t.suggestion = r.suggestion?.text
        t.suggestionSource = r.suggestion?.source?.citation
        if !r.isSoFar {
            t.updated = fill(updatedLine, ["clock": clock(r.generatedAt, calendar: calendar, roundToFive: false)])
        }

        if let type = r.type, r.typeStatus == .awarded {
            let line1 = fill(shareLine1, ["type": typeName(type, values: typeValues),
                                          "oneLiner": fill(typeOneLiners[type] ?? "", typeValues)])
            t.shareLine1 = line1
            t.shareLine2 = shareLine2(r, line1: line1)
        }
        return t
    }

    // MARK: Headline (6.2)

    static func headline(n: Int, still: Int, noticed: Int, when: String, thinHours: Int?, picker: Picker) -> String {
        if let hours = thinHours {
            let template = n == 0 ? headlineThinNone : headlineThin
            return fill(template, ["n": "\(n)", "hours": "\(hours)"])
        }
        if n == 0 {
            return fill(headlineNone, ["when": when])
        }
        if n == 1 && still == 0 {
            return headlineOneOnPurpose
        }
        if still == 0 {
            return fill(headlineAllOnPurpose, ["n": "\(n)"])
        }
        if n == 1 && still == 1 {
            return fill(headlineOneStill, ["when": when])
        }
        let index = picker.index(.headline, count: headlineVariants.count)
        let variant = index == 2 && noticed == 0 ? 3 : index
        var of = "\(still)"
        if still == 1 {
            of = "one"
        } else if still == n {
            of = n == 2 ? "both" : "all"
        }
        if variant == 0 && still == n {
            return fill(headlineAllStill, ["n": "\(n)", "when": when, "all": of])
        }
        var named = "\(noticed)"
        if noticed == n {
            named = "every one"
        }
        return fill(headlineVariants[variant], ["n": "\(n)", "when": when, "of": of, "named": named])
    }

    // MARK: Attribution (6.3)

    static func attribution(_ counts: DayRecap.Counts, picker: Picker) -> String {
        let index = picker.index(.attribution, count: attributionVariants.count)
        let variant = attributionVariants[index]
        let values = ["workout": counts.workout, "moving": counts.moving, "still": counts.still]
        let segments = variant.segments.compactMap { segment -> String? in
            for (key, count) in values where segment.contains("{\(key)}") {
                return count == 0 ? nil : fill(segment, [key: "\(count)"])
            }
            return nil
        }
        return segments.joined(separator: variant.separator)
    }

    // MARK: Labelled moments (6.4)

    static func labelledLine(_ spike: DayRecap.Spike, calendar: Calendar, picker: Picker) -> RecapText.LabelledLine {
        var values: [String: String] = [
            "peak": "\(spike.peak)",
            "mag": signed(spike.magnitude),
            "dur": duration(spike.elevatedMinutes),
            "clock": clock(spike.peakAt, calendar: calendar),
            "time": about(spike.peakAt, calendar: calendar)
        ]
        var text: String
        if let label = spike.label {
            values["time"] = about(spike.start, calendar: calendar)
            values["who"] = who(label, time: values["time"] ?? "")
            values["m"] = "\(label.relationMinutes)"
            let relation: DayRecap.Relation = spike.isLongStretch ? .cameDownWithIt : label.relation
            text = fill(labelledCalendar[relation] ?? "", values)
        } else {
            let template = picker.pick(.labelled, from: labelledNoCalendar) ?? labelledNoCalendar[0]
            text = fill(template, values)
        }
        if let tag = spike.tag {
            text += " " + fill(labelledTag, ["tag": tag.label])
        }
        var stretch: String? = nil
        if spike.isLongStretch {
            stretch = fill(labelledStretch, ["h": "\(spike.elevatedMinutes / 60)", "m": twoDigits(spike.elevatedMinutes % 60)])
        }
        return RecapText.LabelledLine(spikeId: spike.id, stretch: stretch, text: text)
    }

    /// "'Design review' (8 people)", "(one-to-one)", "(solo)"; without titles
    /// "A 6-person meeting at about 11:00 am", "A one-to-one at ...", "A solo calendar block at ...".
    static func who(_ label: DayRecap.Label, time: String) -> String {
        if let title = label.title {
            let people: String
            switch label.people {
            case 0: people = "solo"
            case 1: people = "one-to-one"
            default: people = "\(label.people) people"
            }
            return "'\(title)' (\(people))"
        }
        switch label.people {
        case 0: return "A solo calendar block at \(time)"
        case 1: return "A one-to-one at \(time)"
        default: return "A \(label.people)-person meeting at \(time)"
        }
    }

    // MARK: Recovery (6.6)

    static func recoveryLine(_ rec: DayRecap.Recovery, picker: Picker) -> String {
        guard let median = rec.median else {
            return recoveryUnknown
        }
        var values = ["median": recoveryText(median)]
        if let week = rec.median7d {
            values["median7d"] = "\(Int(week.rounded()))"
        }
        if let best = rec.best7d {
            values["bestDay"] = best.weekday
            values["best"] = "\(best.minutes)"
        }
        let eligible: (String) -> Bool = { template in
            if template.contains("{best") {
                return rec.best7d != nil
            }
            if template.contains("typical") {
                return rec.median7d != nil && rec.vsWeek == .aboutTheSame
            }
            return rec.median7d != nil
        }
        guard let template = picker.pick(.recovery, from: recoveryVariants, eligible: eligible) else {
            return fill(recoveryFirstWeek, values)
        }
        return fill(template, values)
    }

    // MARK: Last night (6.7)

    static func lastNightLine(_ night: DayRecap.LastNight, calendar: Calendar, picker: Picker) -> String {
        let low = night.lowHR.map { fill(lastNightLow, ["lowHR": "\($0)"]) } ?? lastNightNoLow
        let values = [
            "asleep": hoursMinutes(night.asleepMinutes),
            "awakenings": "\(night.awakenings)",
            "low": low,
            "hrvState": night.hrvState.label
        ]
        var lines = [fill(picker.pick(.lastNight, from: lastNightVariants) ?? lastNightVariants[0], values)]

        let awake = night.inBed.filter { $0.inBedKind == .awake }.sorted { $0.start < $1.start }
        if let first = awake.first {
            let times = awake.count == 1 ? "once" : "\(awake.count) times"
            lines.append(fill(lastNightAwake, ["times": times, "clock": clock(first.peakAt, calendar: calendar)]))
        }
        let asleep = night.inBed.filter { $0.inBedKind == .asleep }.sorted { $0.start < $1.start }
        if let first = asleep.first {
            let template = asleep.count == 1 ? lastNightAsleepOne : lastNightAsleepMany
            lines.append(fill(template, ["k": "\(asleep.count)", "clock": clock(first.peakAt, calendar: calendar)]))
        }
        if night.isShort {
            lines.append(lastNightShort)
        }
        return lines.joined(separator: " ")
    }

    // MARK: Type and share card (5, 6.11)

    static func typePlaceholders(_ r: DayRecap, dayStart: Date, calendar: Calendar) -> [String: String] {
        var values = ["n": "\(r.counts.daytime)", "weekday": weekday(of: dayStart, calendar: calendar)]
        if let night = r.lastNight {
            values["asleep"] = hoursMinutes(night.asleepMinutes)
        }
        return values
    }

    static func typeName(_ type: DayType, values: [String: String]) -> String {
        return fill(typeNames[type] ?? type.rawValue, values)
    }

    /// The first variant whose numbers exist and which repeats nothing on line 1.
    static func shareLine2(_ r: DayRecap, line1: String) -> String? {
        let n = r.counts.daytime
        var values = ["n": "\(n)", "still": "\(r.counts.still)"]
        if let median = r.recovery?.median {
            values["median"] = recoveryText(median)
        }
        if let calmest = r.calmest {
            values["calmestBpm"] = "\(calmest.bpm)"
        }
        if let load = r.load {
            values["load"] = "\(load.total)"
        }
        if let night = r.lastNight {
            values["asleep"] = hoursMinutes(night.asleepMinutes)
        }
        for template in shareLine2Variants {
            if template.contains("{median}") {
                guard values["median"] != nil, !line1.contains("\(n) spike") else { continue }
            }
            if template.contains("{calmestBpm}") {
                guard r.counts.still >= 1, values["calmestBpm"] != nil,
                      !line1.contains("\(r.counts.still) sitting still"), !line1.contains("\(values["calmestBpm"] ?? "") bpm") else { continue }
            }
            if template.contains("{load}") {
                guard values["load"] != nil else { continue }
            }
            if template.contains("{asleep}") {
                guard let asleep = values["asleep"], !line1.contains(asleep) else { continue }
            }
            return fill(template, values)
        }
        return nil
    }

    // MARK: Suggestion and footer (6.8, 6.9)

    static func suggestion(rule: RecapSuggestion.Rule, gapMinutes: Int?, picker: Picker) -> RecapSuggestion {
        let variants = suggestionVariants[rule] ?? []
        let picked = picker.pick(.suggestion, from: variants, eligible: { template in
            if template.contains("{gap}") {
                guard let gap = gapMinutes else { return false }
                return gap <= 60
            }
            return true
        })
        let text = fill(picked ?? "", ["gap": "\(gapMinutes ?? 0)"])
        return RecapSuggestion(rule: rule, text: text, source: suggestionSources[rule])
    }

    static func footer(number: String?) -> String {
        guard let number = number, !number.isEmpty else {
            return footerNoNumber
        }
        return fill(footerWithNumber, ["number": number])
    }
}
