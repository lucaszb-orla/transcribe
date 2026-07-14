import SwiftUI

/// Shown while a meeting is being recorded: status, elapsed time, live transcript, and
/// pause/resume + stop controls.
struct RecordingView: View {
    @Environment(AppState.self) private var appState
    @State private var now = Date()

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            transcript
            Divider()
            controls
        }
        .onReceive(timer) { now = $0 }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.isPaused ? .orange : .red)
                    .frame(width: 10, height: 10)
                    .opacity(appState.isPaused ? 1 : pulse)
                    .animation(appState.isPaused ? nil : .easeInOut(duration: 0.8).repeatForever(), value: pulse)
                Text(appState.isPaused ? "Pausado" : "Gravando")
                    .font(.headline)
                Spacer()
                Text(elapsed)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Image(systemName: appState.isPaused ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(appState.isPaused ? .secondary : .primary)
                    .imageScale(.small)
                LevelMeter(level: appState.isPaused ? 0 : appState.micLevel)
                    .frame(height: 6)
            }
        }
        .padding()
        .background(.bar)
        .onAppear { pulse = 0.3 }
    }

    @State private var pulse = 1.0

    @ViewBuilder
    private var transcript: some View {
        if appState.liveText.isEmpty {
            ContentUnavailableView {
                Label("Ouvindo…", systemImage: "waveform")
            } description: {
                Text("Fale algo para ver a transcrição aparecer em tempo real.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    Text(appState.liveText)
                        .font(.body)
                        .frame(maxWidth: 640, alignment: .leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding()
                        .id("live")
                }
                .onChange(of: appState.liveText) {
                    withAnimation { proxy.scrollTo("live", anchor: .bottom) }
                }
            }
        }
    }

    private var controls: some View {
        HStack {
            if appState.isPaused {
                Button { appState.resumeMeeting() } label: {
                    Label("Retomar", systemImage: "play.fill")
                }
            } else {
                Button { appState.pauseMeeting() } label: {
                    Label("Pausar", systemImage: "pause.fill")
                }
            }

            Spacer()

            Button(role: .destructive) {
                Task { await appState.endMeeting() }
            } label: {
                Label("Encerrar", systemImage: "stop.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .keyboardShortcut(".", modifiers: .command)
        }
        .controlSize(.large)
        .padding()
        .background(.bar)
    }

    private var elapsed: String {
        guard let start = appState.recordingStartedAt else { return "00:00" }
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

/// Horizontal microphone level bar, green→yellow→red as the input gets louder.
private struct LevelMeter: View {
    var level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(min(max(level, 0), 1)))
                    .animation(.linear(duration: 0.08), value: level)
            }
        }
    }

    private var color: Color {
        switch level {
        case ..<0.6: .green
        case ..<0.85: .yellow
        default: .red
        }
    }
}
