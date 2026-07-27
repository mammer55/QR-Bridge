import ActivityKit
import Foundation

/// Drives the recording Live Activity through its whole lifecycle:
/// recording → transcribing → done/failed.
@MainActor
enum LiveActivityManager {
    private static var activity: Activity<RecordingActivityAttributes>?

    static func start() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        if let existing = Activity<RecordingActivityAttributes>.activities.first {
            activity = existing
            return
        }
        let attributes = RecordingActivityAttributes(title: "Clip Recorder")
        let state = RecordingActivityAttributes.ContentState(phase: .recording, startedAt: Date())
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil)
            )
        } catch {
            print("Live Activity start failed: \(error)")
        }
    }

    static func setTranscribing() async {
        await update { $0.phase = .transcribing }
    }

    /// Show "Done" briefly (with the transcript), then dismiss.
    static func finish(transcript: String) async {
        guard let activity else { return }
        var state = activity.content.state
        state.phase = .done
        state.transcript = transcript
        await activity.end(.init(state: state, staleDate: nil),
                           dismissalPolicy: .after(.now + 30))
        self.activity = nil
    }

    static func fail(message: String) async {
        guard let activity else { return }
        var state = activity.content.state
        state.phase = .failed
        state.message = message
        await activity.end(.init(state: state, staleDate: nil),
                           dismissalPolicy: .after(.now + 30))
        self.activity = nil
    }

    /// End immediately with no result view (e.g. stop with nothing to transcribe).
    static func endNow() {
        let current = activity
        activity = nil
        Task {
            if let current {
                await current.end(nil, dismissalPolicy: .immediate)
            }
            for stray in Activity<RecordingActivityAttributes>.activities {
                await stray.end(nil, dismissalPolicy: .immediate)
            }
        }
    }

    private static func update(_ mutate: (inout RecordingActivityAttributes.ContentState) -> Void) async {
        guard let activity else { return }
        var state = activity.content.state
        mutate(&state)
        await activity.update(.init(state: state, staleDate: nil))
    }
}
