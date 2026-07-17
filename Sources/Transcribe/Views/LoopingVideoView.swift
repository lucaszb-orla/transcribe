import AVFoundation
import SwiftUI

/// Silent, seamlessly looping playback for the animated onboarding logo — no controls, no audio,
/// no user interaction. `AVPlayerLooper` (not just `player.actionAtItemEnd`) is what makes the loop
/// gapless instead of flashing black between plays.
struct LoopingVideoView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PlayerLayerView {
        PlayerLayerView(url: url)
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {}

    final class PlayerLayerView: NSView {
        private let player = AVQueuePlayer()
        private var looper: AVPlayerLooper?
        private let videoLayer = AVPlayerLayer()

        init(url: URL) {
            super.init(frame: .zero)
            wantsLayer = true
            videoLayer.videoGravity = .resizeAspect
            videoLayer.backgroundColor = .clear
            videoLayer.player = player
            layer = videoLayer

            player.isMuted = true
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.play()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        // `layer` was set directly to `videoLayer` instead of using it as a sublayer, so nothing
        // keeps its frame in sync with the view's bounds automatically — without this, the layer
        // stays at its initial `.zero` frame and the view's own background shows through as a
        // visible box around the (tiny/misplaced) video.
        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            videoLayer.frame = bounds
            CATransaction.commit()
        }
    }
}
