import EventKit
import Foundation
import Observation

struct MeetingSuggestion: Identifiable, Equatable {
    let id: String // EKEvent.eventIdentifier
    let title: String
    let start: Date
    let end: Date
    let participants: [String]
    let callURL: URL
}

/// Polls the Apple Calendar for events with a video-call link about to start. The monitor surfaces
/// suggestions; AppState owns the separate, opt-in auto-recording policy.
@Observable
final class CalendarMonitor {
    private(set) var suggestion: MeetingSuggestion?
    private(set) var authorizationDenied = false

    /// Called once per newly-detected candidate event (used for opt-in auto-recording).
    var onNewCandidate: ((MeetingSuggestion) -> Void)?

    private let store = EKEventStore()
    private var timer: Timer?
    private var dismissedEventIDs: Set<String> = []
    private var lastNotifiedID: String?

    /// How far ahead of an event's start time we start suggesting it.
    private let lookahead: TimeInterval = 3 * 60
    private let pollInterval: TimeInterval = 30

    func start() {
        let status = EKEventStore.authorizationStatus(for: .event)
        guard status == .fullAccess else {
            authorizationDenied = status == .denied || status == .restricted
            stop()
            return
        }

        authorizationDenied = false
        checkNow()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.checkNow()
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        suggestion = nil
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

        let newSuggestion = MeetingSuggestion(
            id: event.eventIdentifier,
            title: event.title ?? "Reunião sem título",
            start: event.startDate,
            end: event.endDate,
            participants: event.attendees?.compactMap(\.name) ?? [],
            callURL: callURL
        )
        suggestion = newSuggestion

        // Fire the callback once per distinct event so auto-record doesn't re-trigger each poll.
        if newSuggestion.id != lastNotifiedID {
            lastNotifiedID = newSuggestion.id
            onNewCandidate?(newSuggestion)
        }
    }
}
