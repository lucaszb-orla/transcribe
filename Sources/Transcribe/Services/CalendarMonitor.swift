import EventKit
import Foundation
import Observation

struct MeetingSuggestion: Identifiable, Equatable {
    let id: String // EKEvent.eventIdentifier
    let title: String
    let start: Date
    let participants: [String]
    let callURL: URL
}

/// Polls the Apple Calendar for events with a video-call link about to start.
/// This only ever *suggests* a recording — starting it is always a user action (see PRD risks).
@Observable
final class CalendarMonitor {
    private(set) var suggestion: MeetingSuggestion?
    private(set) var authorizationDenied = false

    private let store = EKEventStore()
    private var timer: Timer?
    private var dismissedEventIDs: Set<String> = []

    /// How far ahead of an event's start time we start suggesting it.
    private let lookahead: TimeInterval = 3 * 60
    private let pollInterval: TimeInterval = 30

    func start() async {
        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else {
                authorizationDenied = true
                return
            }
        } catch {
            authorizationDenied = true
            return
        }

        checkNow()
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkNow()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func dismissCurrentSuggestion() {
        if let id = suggestion?.id {
            dismissedEventIDs.insert(id)
        }
        suggestion = nil
    }

    private func checkNow() {
        let now = Date()
        let windowEnd = now.addingTimeInterval(lookahead)
        let predicate = store.predicateForEvents(withStart: now, end: windowEnd, calendars: nil)
        let events = store.events(matching: predicate)

        let candidate = events
            .filter { !dismissedEventIDs.contains($0.eventIdentifier) }
            .sorted { $0.startDate < $1.startDate }
            .first { CallLinkDetector.detect(url: $0.url, location: $0.location, notes: $0.notes) != nil }

        guard let event = candidate,
              let callURL = CallLinkDetector.detect(url: event.url, location: event.location, notes: event.notes) else {
            suggestion = nil
            return
        }

        suggestion = MeetingSuggestion(
            id: event.eventIdentifier,
            title: event.title ?? "Reunião sem título",
            start: event.startDate,
            participants: event.attendees?.compactMap(\.name) ?? [],
            callURL: callURL
        )
    }
}
