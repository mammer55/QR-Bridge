import AppIntents

/// Stops the current recording and kicks off transcription. Lives in Shared/
/// because the Dynamic Island's Stop button (in the widget extension) needs to
/// reference it, while the real work runs in the app process.
///
/// In the widget target (WIDGET_EXT) it's a stub — the button only needs the
/// type. When the button is tapped, iOS runs the *app's* copy, which has the
/// full implementation below.
/// Conforms to `LiveActivityIntent` (not just `AppIntent`) so that when the
/// Dynamic Island's Stop button is tapped, iOS runs it in the *app's* process —
/// where AudioRecorder.shared actually holds the live recording.
struct StopRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description = IntentDescription("Stops and saves the current memo, then transcribes it.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if WIDGET_EXT
        return .result(dialog: "Stopping…")
        #else
        guard AudioRecorder.shared.isRecording else {
            return .result(dialog: "Nothing was recording.")
        }
        await AudioRecorder.shared.stopAndProcess()
        return .result(dialog: "Stopped. Transcribing now…")
        #endif
    }
}
