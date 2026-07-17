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

        init(url: URL) {
            super.init(frame: .zero)
            wantsLayer = true
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.videoGravity = .resizeAspect
            layer = playerLayer

            player.isMuted = true
            let item = AVPlayerItem(url: url)
            looper = AVPlayerLooper(player: player, templateItem: item)
            player.play()
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}
