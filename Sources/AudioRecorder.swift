import AVFoundation
import Combine

final class AudioRecorder: ObservableObject {
    @Published private(set) var isRecording = false

    private var audioEngine: AVAudioEngine?
    private var audioData = Data()
    private let lock = NSLock()

    func startRecording() throws {
        guard !isRecording else { return }

        // Request microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                semaphore.signal()
            }
            semaphore.wait()
            guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
                throw RecorderError.microphonePermissionDenied
            }
        case .denied, .restricted:
            throw RecorderError.microphonePermissionDenied
        case .authorized:
            break
        @unknown default:
            break
        }

        lock.lock()
        audioData = Data()
        lock.unlock()

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // Target format: 16kHz, mono, Int16
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        ) else {
            throw RecorderError.formatError
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.formatError
        }

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCount = AVAudioFrameCount(
                Double(buffer.frameLength) * 16000.0 / inputFormat.sampleRate
            )
            guard frameCount > 0 else { return }

            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: frameCount
            ) else { return }

            var error: NSError?
            let status = converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            guard status != .error, error == nil else { return }

            if let channelData = convertedBuffer.int16ChannelData {
                let byteCount = Int(convertedBuffer.frameLength) * MemoryLayout<Int16>.size
                let bytes = Data(bytes: channelData[0], count: byteCount)
                self.lock.lock()
                self.audioData.append(bytes)
                self.lock.unlock()
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
        isRecording = true
    }

    func stopRecording() -> Data {
        guard isRecording else { return Data() }
        isRecording = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        lock.lock()
        let result = audioData
        audioData = Data()
        lock.unlock()
        return result
    }

    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        lock.lock()
        audioData = Data()
        lock.unlock()
    }

    enum RecorderError: LocalizedError {
        case microphonePermissionDenied
        case formatError

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "마이크 접근 권한이 거부되었습니다. 시스템 설정에서 허용해주세요."
            case .formatError:
                return "오디오 포맷을 설정할 수 없습니다."
            }
        }
    }
}
