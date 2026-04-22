import Foundation
import Speech
import AVFoundation

final class SpeechRecognitionService {
    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?
    private var currentLanguage: Locale
    private var levelHandler: ((Float) -> Void)?
    private var lastTranscription: String = ""

    init(language: String) {
        self.currentLanguage = Locale(identifier: language)
        self.speechRecognizer = SFSpeechRecognizer(locale: currentLanguage)
    }

    func updateLanguage(_ languageCode: String) {
        stopStreamingInternal()
        currentLanguage = Locale(identifier: languageCode)
        speechRecognizer = SFSpeechRecognizer(locale: currentLanguage)
    }

    func startStreaming(onResult: @escaping (String) -> Void, onLevel: @escaping (Float) -> Void) {
        self.levelHandler = onLevel

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("Speech recognizer unavailable")
            return
        }

        // Request authorization
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard status == .authorized else {
                print("Speech recognition not authorized")
                return
            }

            DispatchQueue.main.async {
                self?.startRecognitionInternal(onResult: onResult)
            }
        }
    }

    private func startRecognitionInternal(onResult: @escaping (String) -> Void) {
        recognitionTask?.cancel()
        recognitionTask = nil

        audioEngine = AVAudioEngine()

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let request = recognitionRequest else { return }
        request.shouldReportPartialResults = true

        if #available(macOS 13.0, *) {
            request.addsPunctuation = true
        }

        guard let engine = audioEngine else { return }
        let inputNode = engine.inputNode

        recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
            var isFinal = false
            if let result = result {
                let text = result.bestTranscription.formattedString
                self?.lastTranscription = text
                onResult(text)
                isFinal = result.isFinal
            }
            if error != nil || isFinal {
                self?.stopStreamingInternal()
            }
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
            self?.calculateRMS(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            print("Audio engine failed to start: \(error)")
        }
    }

    private func calculateRMS(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))
        // Typical speech RMS: 0.005–0.05. Map 0→0, 0.03→1 for good visual range
        let normalizedLevel = min(1.0, max(0.0, rms / 0.03))

        DispatchQueue.main.async { [weak self] in
            self?.levelHandler?(normalizedLevel)
        }
    }

    func stopStreaming(completion: @escaping (String) -> Void) {
        let finalText = lastTranscription
        lastTranscription = ""
        stopStreamingInternal()
        completion(finalText)
    }

    private func stopStreamingInternal() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        levelHandler = nil
        lastTranscription = ""
    }
}
