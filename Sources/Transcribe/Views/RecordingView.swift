import SwiftUI

/// Shown while a meeting is being recorded: status, elapsed time, live transcript, and
/// pause/resume + stop controls.
struct RecordingView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
        .animation(.smooth, value: appState.isPaused)
        .animation(.smooth, value: appState.liveText.isEmpty)
        .onReceive(timer) { date in
            withAnimation(.snappy(duration: 0.3)) { now = date }
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(appState.isPaused ? .orange : .red)
                    .frame(width: 10, height: 10)
                    .opacity(appState.isPaused || reduceMotion ? 1 : pulse)
                    .animation(appState.isPaused || reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(), value: pulse)
                Text(appState.isPaused ? "Pausado" : "Gravando")
                    .font(.headline)
                    .contentTransition(.numericText())
                Spacer()
                Text(elapsed)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            HStack(spacing: 8) {
                Image(systemName: appState.isPaused ? "mic.slash.fill" : "mic.fill")
                    .foregroundStyle(appState.isPaused ? .secondary : .primary)
                    .imageScale(.small)
                    .contentTransition(.symbolEffect(.replace))
                LevelMeter(level: appState.isPaused ? 0 : appState.micLevel)
                    .frame(height: 6)
            }

            if appState.isContinuing {
                Label("Continuando uma transcrição existente", systemImage: "arrow.uturn.left")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding()
        .background(.bar)
        .onAppear { if !reduceMotion { pulse = 0.3 } }
    }

    @State private var pulse = 1.0

    @ViewBuilder
    private var transcript: some View {
        if appState.liveText.isEmpty {
            ContentUnavailableView {
                Label("Ouvindo…", systemImage: "waveform")
                    .symbolEffect(.variableColor.iterative, isActive: !reduceMotion)
            } description: {
                Text("Fale algo para ver a transcrição aparecer em tempo real.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
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
            .transition(.opacity)
        }
    }

    private var controls: some View {
        HStack {
            Button {
                if appState.isPaused { appState.resumeMeeting() } else { appState.pauseMeeting() }
            } label: {
                Label(appState.isPaused ? "Retomar" : "Pausar",
                      systemImage: appState.isPaused ? "play.fill" : "pause.fill")
                    .contentTransition(.symbolEffect(.replace))
            }

            Spacer()

            Button(role: .destructive) {
                confirmEnd = true
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
        .endMeetingConfirmation(isPresented: $confirmEnd) {
            Task { await appState.endMeeting() }
        }
    }

    @State private var confirmEnd = false

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
        .accessibilityElement()
        .accessibilityLabel("Nível do microfone")
        .accessibilityValue("\(Int(min(max(level, 0), 1) * 100)) por cento")
    }

    private var color: Color {
        switch level {
        case ..<0.6: .green
        case ..<0.85: .yellow
        default: .red
        }
    }
}
