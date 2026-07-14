import AVFoundation
import CoreMedia

extension CMSampleBuffer {
    /// Converts a ScreenCaptureKit audio sample buffer into an `AVAudioPCMBuffer`
    /// so it can be scheduled on an `AVAudioEngine` node alongside the microphone signal.
    var asPCMBuffer: AVAudioPCMBuffer? {
        guard let formatDescription = CMSampleBufferGetFormatDescription(self),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
              let format = AVAudioFormat(streamDescription: streamDescription) else {
            return nil
        }

        let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(self))
        guard frameCount > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        buffer.frameLength = frameCount

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )
        return status == noErr ? buffer : nil
    }
}
