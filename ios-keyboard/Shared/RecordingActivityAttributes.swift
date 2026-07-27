import ActivityKit
import Foundation

/// Shared between the app (which starts/updates/ends the Live Activity) and the
/// widget extension (which renders it in the Dynamic Island / Lock Screen).
struct RecordingActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Phase: String, Codable, Hashable {
            case recording, transcribing, done, failed
        }

        var phase: Phase
        /// When recording began — the Live Activity counts up from this.
        var startedAt: Date
        /// Filled in on `.done`; the actual transcript text.
        var transcript: String?
        /// Filled in on `.failed`.
        var message: String?
    }

    var title: String
}
