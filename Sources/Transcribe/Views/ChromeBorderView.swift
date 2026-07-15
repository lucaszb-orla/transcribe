import SwiftUI

struct ChromeBorderView: View {
    var progress: Double

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.appearsActive) private var appearsActive
    @State private var shaderIsReady = false
    @State private var startDate = Date()

    var body: some View {
        // Source: https://developer.apple.com/documentation/swiftui/timelineschedule/animation(minimuminterval:paused:)
        TimelineView(.animation(
            minimumInterval: 1.0 / 60.0,
            paused: reduceMotion || !appearsActive || !shaderIsReady
        )) { context in
            ChromeBorderStroke(
                progress: progress,
                time: reduceMotion ? 0 : context.date.timeIntervalSince(startDate),
                lineWidth: colorSchemeContrast == .increased ? 3 : 2.5,
                useShader: shaderIsReady && !reduceMotion
            )
        }
        .task { await compileShader() }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func compileShader() async {
        let shader = ShaderLibrary.chromeBorder(
            .float2(820, 560),
            .float(0),
            .float(0)
        )
        do {
            // Source: https://developer.apple.com/documentation/swiftui/shader/compile(as:)
            try await shader.compile(as: .shapeStyle)
            shaderIsReady = true
        } catch {
            shaderIsReady = false
        }
    }
}

private struct ChromeBorderStroke: View, Animatable {
    var progress: Double
    var time: TimeInterval
    var lineWidth: CGFloat
    var useShader: Bool

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GeometryReader { geometry in
            let border = RoundedRectangle(cornerRadius: 28, style: .continuous)
            if useShader {
                border.strokeBorder(
                    ShaderLibrary.chromeBorder(
                        .float2(geometry.size.width, geometry.size.height),
                        .float(time),
                        .float(progress)
                    ),
                    lineWidth: lineWidth
                )
            } else {
                border.strokeBorder(staticChrome, lineWidth: lineWidth)
            }
        }
    }

    private var staticChrome: AngularGradient {
        AngularGradient(
            stops: [
                .init(color: Color(red: 0.28, green: 0.30, blue: 0.34), location: 0.00),
                .init(color: Color(red: 0.96, green: 0.97, blue: 0.98), location: 0.16),
                .init(color: Color(red: 0.45, green: 0.48, blue: 0.53), location: 0.35),
                .init(color: Color(red: 0.94, green: 0.76, blue: 0.52), location: 0.48),
                .init(color: Color(red: 0.52, green: 0.88, blue: 0.98), location: 0.55),
                .init(color: Color(red: 0.95, green: 0.96, blue: 0.98), location: 0.67),
                .init(color: Color(red: 0.26, green: 0.28, blue: 0.32), location: 0.86),
                .init(color: Color(red: 0.82, green: 0.84, blue: 0.88), location: 1.00)
            ],
            center: .center
        )
    }
}
