import Foundation

/// Pure, EventKit-free logic for spotting a video-call link inside event text.
/// Kept separate from `CalendarMonitor` so it can be unit tested without calendar access.
enum CallLinkDetector {
    private static let knownHosts = [
        "zoom.us",
        "meet.google.com",
        "teams.microsoft.com",
        "teams.live.com",
    ]

    /// Looks at the event's URL, location and notes (in that order) and returns the first
    /// recognizable video-call link, if any.
    static func detect(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isCallLink(url) {
            return url
        }
        for text in [location, notes].compactMap({ $0 }) {
            if let found = firstCallLink(in: text) {
                return found
            }
        }
        return nil
    }

    private static func isCallLink(_ url: URL) -> Bool {
        if url.scheme == "facetime" || url.scheme == "facetime-audio" {
            return true
        }
        guard let host = url.host?.lowercased() else { return false }
        return knownHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func firstCallLink(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return nil
        }
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let url = match.url, isCallLink(url) else { continue }
            return url
        }
        return nil
    }
}
