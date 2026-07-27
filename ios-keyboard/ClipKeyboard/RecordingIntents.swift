import AppIntents

/// Starts recording. iOS forbids activating the mic from a purely background
/// intent (we confirmed this — the audio session refuses to go active), so this
/// brings the app to the foreground for the split second it takes to start.
/// Once recording, you can swipe away and it keeps going in the background.
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Starts an audio memo, then keeps recording in the background.")

    // Foreground is required to *begin* mic capture; continuation afterwards
    // is what runs in the background.
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        // Retry briefly: perform() can fire a hair before the app is fully
        // active, when the session still can't go active.
        for attempt in 0..<10 {
            if await AudioRecorder.shared.startFromIntent() {
                return .result(dialog: "Recording started.")
            }
            if attempt < 9 { try? await Task.sleep(nanoseconds: 150_000_000) }
        }
        let why = AudioRecorder.shared.lastError ?? "unknown error"
        return .result(dialog: "Couldn't start: \(why)")
    }
}

/// (StopRecordingIntent lives in Shared/ so the Dynamic Island can use it too.)

/// Makes both actions show up in Shortcuts / Siri and assignable to the
/// Action Button, without the user having to build a shortcut by hand.
struct ClipShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start a memo in \(.applicationName)",
                "Start recording in \(.applicationName)",
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: StopRecordingIntent(),
            phrases: [
                "Stop the memo in \(.applicationName)",
                "Stop recording in \(.applicationName)",
            ],
            shortTitle: "Stop Recording",
            systemImageName: "stop.fill"
        )
    }
}
