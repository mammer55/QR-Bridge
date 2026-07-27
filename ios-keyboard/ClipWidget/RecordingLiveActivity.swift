import ActivityKit
import SwiftUI
import WidgetKit

/// The Live Activity: shown on the Lock Screen and in the Dynamic Island across
/// the whole flow — recording → transcribing → done/failed. Long-press the
/// Island to expand it; while recording, the red Stop button is there.
struct RecordingLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            lockScreen(context.state)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)

        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(s.headline, systemImage: s.icon)
                        .foregroundStyle(s.color)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Group {
                        if s.phase == .recording {
                            Text(s.startedAt, style: .timer)
                                .font(.system(.headline, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                        } else if s.phase == .transcribing {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: s.icon).foregroundStyle(s.color).font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    bottom(s)
                        .padding(.horizontal, 6)
                        .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: s.icon).foregroundStyle(s.color)
            } compactTrailing: {
                if s.phase == .recording {
                    Text(s.startedAt, style: .timer)
                        .font(.system(.caption2, design: .monospaced))
                        .frame(width: 44, alignment: .trailing)
                        .multilineTextAlignment(.trailing)
                } else if s.phase == .transcribing {
                    ProgressView().tint(.white).scaleEffect(0.7)
                }
            } minimal: {
                Image(systemName: s.icon).foregroundStyle(s.color)
            }
        }
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func lockScreen(_ s: RecordingActivityAttributes.ContentState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(s.headline, systemImage: s.icon)
                    .foregroundStyle(s.color)
                    .font(.headline)
                Spacer()
                if s.phase == .recording {
                    Text(s.startedAt, style: .timer)
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else if s.phase == .transcribing {
                    ProgressView().tint(.white)
                }
            }
            bottom(s)
        }
    }

    // MARK: - Bottom (button or result), shared by lock screen + expanded island

    @ViewBuilder
    private func bottom(_ s: RecordingActivityAttributes.ContentState) -> some View {
        switch s.phase {
        case .recording:
            Button(intent: StopRecordingIntent()) {
                Label("Stop", systemImage: "stop.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
            .buttonStyle(.borderedProminent)

        case .transcribing:
            Text("Transcribing your memo…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .done:
            Text(s.transcript?.isEmpty == false ? s.transcript! : "No speech detected.")
                .font(.subheadline)
                .foregroundStyle(.white)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .failed:
            Text(s.message ?? "Transcription failed.")
                .font(.subheadline)
                .foregroundStyle(.orange)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Phase → presentation

private extension RecordingActivityAttributes.ContentState {
    var headline: String {
        switch phase {
        case .recording:    return "Recording"
        case .transcribing: return "Transcribing"
        case .done:         return "Done"
        case .failed:       return "Failed"
        }
    }

    var icon: String {
        switch phase {
        case .recording:    return "mic.fill"
        case .transcribing: return "waveform"
        case .done:         return "checkmark.circle.fill"
        case .failed:       return "exclamationmark.triangle.fill"
        }
    }

    var color: Color {
        switch phase {
        case .recording:    return .red
        case .transcribing: return .yellow
        case .done:         return .green
        case .failed:       return .orange
        }
    }
}
