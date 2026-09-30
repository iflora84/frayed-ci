import EventKit
import Foundation

/// Today's events for calendar labels (RECAP 3). Read on this iPhone only:
/// titles go into the recap only with "Show event titles" on, and nothing
/// from the calendar is ever posted.
enum CalendarService {
    static var isAuthorized: Bool {
        return EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    /// Shows the system prompt the first time; false if the user declines.
    static func requestAccess() async -> Bool {
        return (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    /// What RecapEngine gets: the events in [start, end] when labels are on
    /// and iOS allows it, otherwise access off so the recap offers the hint.
    static func access(from start: Date, to end: Date, enabled: Bool, showTitles: Bool) -> RecapInput.CalendarAccess {
        guard enabled, isAuthorized, end > start else {
            return RecapInput.CalendarAccess()
        }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate).map { event -> RecapInput.Event in
            let attendees = event.attendees ?? []
            let me = attendees.first { $0.isCurrentUser }
            return RecapInput.Event(
                id: event.calendarItemIdentifier,
                title: showTitles ? event.title : nil,
                start: event.startDate,
                end: event.endDate,
                people: attendees.filter { !$0.isCurrentUser }.count,
                isAllDay: event.isAllDay,
                isCanceled: event.status == .canceled,
                isDeclined: me?.participantStatus == .declined
            )
        }
        return RecapInput.CalendarAccess(access: true, showTitles: showTitles, events: events)
    }
}
