import Foundation
import AVFoundation

final class AudioRecorderService {
    private var audioEngine: AVAudioEngine?
    private var inputNode: AVAudioInputNode?
    private var levelHandler: ((Float) -> Void)?
    private var isRecording = false

    func start(levelHandler: @escaping (Float) -> Void) {
        guard !isRecording else { return }
        isRecording = true
        self.levelHandler = levelHandler

        audioEngine = AVAudioEngine()
        guard let engine = audioEngine else { return }
        inputNode = engine.inputNode

        let format = inputNode?.outputFormat(forBus: 0)

        inputNode?.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    func stop() {
        guard isRecording else { return }
        isRecording = false
        inputNode?.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        inputNode = nil
        levelHandler = nil
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        // Normalize to 0-1 range (assuming microphone input)
        // RMS values from microphone typically range from 0.0001 to 0.5
        let normalizedLevel = min(1.0, max(0.0, (rms - 0.0001) / 0.1))

        levelHandler?(normalizedLevel)
    }
}
