import SwiftUI

struct ContentView: View {
    private let accent = Color(red: 0.760, green: 0.965, blue: 0.898)
    @ObservedObject private var recorder = AudioRecorder.shared
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    recordControls
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                }

                if let err = recorder.lastError {
                    Section {
                        Text(err).font(.caption).foregroundStyle(.red)
                    }
                }

                Section("Recordings") {
                    if recorder.recordings.isEmpty {
                        Text("No recordings yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(recorder.recordings, id: \.self) { url in
                            row(for: url)
                        }
                        .onDelete(perform: deleteRows)
                    }
                }
            }
            .navigationTitle("Clip Recorder")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
            }
        }
    }

    // MARK: - Record button + timer

    private var recordControls: some View {
        VStack(spacing: 12) {
            Button(action: recorder.toggle) {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording ? Color.red : accent)
                        .frame(width: 108, height: 108)
                        .shadow(radius: 5)
                    Image(systemName: recorder.isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(recorder.isRecording ? .white : .black)
                }
            }
            .buttonStyle(.plain)

            if recorder.isRecording {
                Text(timeString(recorder.elapsed))
                    .font(.system(size: 30, weight: .semibold, design: .monospaced))
                Text("Recording. Switch apps freely and it keeps going.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Tap to record. When you stop, it is transcribed to your clipboard.")
                    .font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Recording row

    private func row(for url: URL) -> some View {
        let isThisPlaying = recorder.currentlyPlaying == url
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button {
                    recorder.togglePlay(url)
                } label: {
                    Image(systemName: isThisPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(recorder.displayTitle(for: url)).font(.subheadline)
                    Text(sizeString(url)).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()

                if recorder.processing.contains(url) {
                    ProgressView()
                } else {
                    Button {
                        recorder.retranscribe(url)
                    } label: {
                        Label("Transcribe again", systemImage: "arrow.clockwise")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .buttonStyle(.plain)
                }
            }

            if let text = recorder.transcript(for: url), !text.isEmpty {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private func deleteRows(_ offsets: IndexSet) {
        offsets.map { recorder.recordings[$0] }.forEach(recorder.delete)
    }

    // MARK: - Helpers

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private func sizeString(_ url: URL) -> String {
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

// MARK: - Settings sheet (Groq API key)

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = KeychainStore.groqKey ?? ""
    @State private var keyRevealed = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Group {
                            if keyRevealed {
                                TextField("gsk_…", text: $apiKey)
                            } else {
                                SecureField("gsk_…", text: $apiKey)
                            }
                        }
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .font(.system(.footnote, design: .monospaced))

                        Button {
                            keyRevealed.toggle()
                        } label: {
                            Image(systemName: keyRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }
                    Button("Paste from clipboard") {
                        if let s = UIPasteboard.general.string { apiKey = s }
                    }
                    .font(.footnote)
                } header: {
                    Text("Groq API key")
                } footer: {
                    Text("Used to transcribe your recordings with Groq Whisper. Stored securely in the Keychain on this device.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        KeychainStore.groqKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
