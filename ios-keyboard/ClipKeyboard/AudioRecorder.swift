import AVFoundation
import Foundation
import UIKit

/// Records audio to the app's Documents folder. Recording starts in the
/// foreground and — because the app declares the `audio` background mode and
/// keeps an active AVAudioSession — continues while you switch to other apps.
/// When you stop, the memo is auto-sent to Groq Whisper: the transcript is
/// copied to the clipboard, saved as a sidecar .txt, and you get a notification.
@MainActor
final class AudioRecorder: NSObject, ObservableObject {

    /// Shared instance so a background App Intent (which has no SwiftUI view)
    /// and the in-app UI drive the exact same recording engine.
    static let shared = AudioRecorder()

    /// Recordings this old (or older) are swept on launch and after each stop.
    private let maxAge: TimeInterval = 7 * 24 * 60 * 60

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var recordings: [URL] = []
    /// Keyed by file name (not full URL) so lookups stay reliable even if the
    /// URL representation differs between where it was written and read.
    @Published private(set) var transcripts: [String: String] = [:]
    @Published private(set) var processing: Set<URL> = []
    @Published private(set) var playingURL: URL?
    @Published private(set) var isPlaying = false
    @Published var lastError: String?

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var player: AVAudioPlayer?

    override init() {
        super.init()
        cleanupOldFiles()
        loadRecordings()
    }

    private var docsURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private func transcriptURL(for audio: URL) -> URL {
        audio.deletingPathExtension().appendingPathExtension("txt")
    }

    // MARK: - Start / stop

    func toggle() {
        if isRecording {
            Task { await stopAndProcess() }
        } else {
            start()
        }
    }

    func start() {
        Task { _ = await startFromIntent() }
    }

    // MARK: - Intent-facing API (usable with no UI present)

    /// Requests permission then starts recording. Returns whether the mic
    /// actually began capturing.
    @discardableResult
    func startFromIntent() async -> Bool {
        guard !isRecording else { return true }
        let granted = await requestPermission()
        guard granted else {
            lastError = "Microphone permission not granted. Open Clip once and allow the mic."
            return false
        }
        return beginRecording()
    }

    private func requestPermission() async -> Bool {
        if AVAudioApplication.shared.recordPermission == .granted { return true }
        return await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { cont.resume(returning: $0) }
        }
    }

    @discardableResult
    private func beginRecording() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord,
                                    mode: .default,
                                    options: [.defaultToSpeaker, .allowBluetooth])
            try session.setActive(true)
        } catch {
            lastError = "Couldn't start audio session: \(error.localizedDescription)"
            return false
        }

        let url = docsURL.appendingPathComponent("memo-\(Self.stamp()).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            guard rec.record() else {
                lastError = "Recorder refused to start."
                return false
            }
            recorder = rec
            isRecording = true
            elapsed = 0
            lastError = nil
            startTimer()
            LiveActivityManager.start()
            return true
        } catch {
            lastError = "Couldn't create recorder: \(error.localizedDescription)"
            return false
        }
    }

    /// Stops recording (fast). Does not transcribe — use stopAndProcess for that.
    func stop() {
        recorder?.stop()
        recorder = nil
        stopTimer()
        isRecording = false
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
        cleanupOldFiles()
        loadRecordings()
    }

    /// Stops and then transcribes the just-finished memo. This is the path both
    /// the in-app Stop button and the Stop App Intent take.
    func stopAndProcess() async {
        let url = recorder?.url
        stop()
        guard let url else {
            LiveActivityManager.endNow()
            return
        }
        await process(url, live: true)
    }

    // MARK: - Transcription

    /// Re-run an existing recording through Groq.
    func retranscribe(_ url: URL) {
        Task { await process(url, live: false) }
    }

    /// - Parameter live: whether to drive the recording Live Activity through
    ///   its transcribing/done/failed phases (true for a just-finished memo).
    private func process(_ url: URL, live: Bool) async {
        guard !processing.contains(url) else { return }
        processing.insert(url)
        lastError = nil

        if live { await LiveActivityManager.setTranscribing() }
        let startedAt = Date()

        // Keep running briefly if the app gets backgrounded (e.g. stopped from
        // the Dynamic Island while you're in another app).
        let bgTask = UIApplication.shared.beginBackgroundTask(withName: "transcribe")
        defer {
            processing.remove(url)
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask) }
        }

        do {
            let text = try await Transcriber.shared.transcribe(url)
            try? Data(text.utf8).write(to: transcriptURL(for: url))
            transcripts[url.lastPathComponent] = text
            if !text.isEmpty {
                UIPasteboard.general.string = text
            }
            Notifier.post(title: text.isEmpty ? "No speech detected" : "Here's your transcript (copied)",
                          body: text.isEmpty ? "The recording had no detectable speech." : text)
            if live {
                // Groq's turbo model is fast — make sure the "Transcribing"
                // state is actually visible before flipping to the result.
                await Self.ensureMinimumVisible(since: startedAt)
                await LiveActivityManager.finish(transcript: text)
            }
        } catch {
            let message = error.localizedDescription
            lastError = message
            Notifier.post(title: "Transcription failed", body: message)
            if live {
                await Self.ensureMinimumVisible(since: startedAt)
                await LiveActivityManager.fail(message: message)
            }
        }
    }

    /// Ensures the "Transcribing" phase is on screen for at least ~1.5s so it
    /// doesn't flash by when transcription returns almost instantly.
    private static func ensureMinimumVisible(since start: Date) async {
        let minimum: TimeInterval = 1.5
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minimum {
            try? await Task.sleep(nanoseconds: UInt64((minimum - elapsed) * 1_000_000_000))
        }
    }

    // MARK: - Playback / delete

    var currentlyPlaying: URL? { isPlaying ? playingURL : nil }

    /// Play, pause, or resume. Tapping the same memo toggles pause/resume;
    /// tapping a different one starts it from the beginning.
    func togglePlay(_ url: URL) {
        if playingURL == url, let player {
            if player.isPlaying {
                player.pause()
                isPlaying = false
            } else {
                player.play()
                isPlaying = true
            }
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            player = p
            playingURL = url
            p.play()
            isPlaying = true
        } catch {
            lastError = "Couldn't play: \(error.localizedDescription)"
        }
    }

    func delete(_ url: URL) {
        if playingURL == url {
            player?.stop()
            player = nil
            playingURL = nil
            isPlaying = false
        }
        try? FileManager.default.removeItem(at: url)
        try? FileManager.default.removeItem(at: transcriptURL(for: url))
        transcripts[url.lastPathComponent] = nil
        loadRecordings()
    }

    // MARK: - Files

    func transcript(for url: URL) -> String? {
        transcripts[url.lastPathComponent]
    }

    /// Human title, e.g. "July 26, 2026 at 7:45 PM".
    func displayTitle(for url: URL) -> String {
        Self.titleFormatter.string(from: modified(url))
    }

    private func loadRecordings() {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: docsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        recordings = items
            .filter { $0.pathExtension == "m4a" }
            .sorted { modified($0) > modified($1) }

        var loaded: [String: String] = [:]
        for url in recordings {
            if let text = try? String(contentsOf: transcriptURL(for: url), encoding: .utf8) {
                loaded[url.lastPathComponent] = text
            }
        }
        transcripts = loaded
    }

    /// Delete recordings (and their transcripts) older than 7 days.
    private func cleanupOldFiles() {
        let cutoff = Date().addingTimeInterval(-maxAge)
        let items = (try? FileManager.default.contentsOfDirectory(
            at: docsURL,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])) ?? []
        for url in items where ["m4a", "txt"].contains(url.pathExtension) {
            if modified(url) < cutoff {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func modified(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let rec = self.recorder else { return }
                self.elapsed = rec.currentTime
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return f.string(from: Date())
    }

    private static let titleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy 'at' h:mm a"
        return f
    }()
}

extension AudioRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in self.loadRecordings() }
    }
}

extension AudioRecorder: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.playingURL = nil
        }
    }
}
