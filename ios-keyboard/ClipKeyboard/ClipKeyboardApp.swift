import SwiftUI

/// Minimal container app. iOS won't install a keyboard extension on its own,
/// so this shell exists only to carry the ClipKeyboardExtension onto the phone.
/// Everything interesting lives in the extension's KeyboardViewController.
@main
struct ClipKeyboardApp: App {
    init() {
        Notifier.requestAuthorization()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
