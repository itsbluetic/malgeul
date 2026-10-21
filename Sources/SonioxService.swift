import Foundation

final class SonioxService: NSObject, URLSessionWebSocketDelegate {
    private let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!

    func transcribe(audioData: Data, apiKey: String, language: String) async throws -> String {
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let task = session.webSocketTask(with: url)
        task.resume()

        // 1. Send config
        let langHints = language == "ko" ? ["ko", "en"] : ["en", "ko"]
        let config: [String: Any] = [
            "api_key": apiKey,
            "model": "stt-rt-v4",
            "audio_format": "pcm_s16le",
            "sample_rate": 16000,
            "num_channels": 1,
            "language_hints": langHints
        ]
        let configData = try JSONSerialization.data(withJSONObject: config)
        let configString = String(data: configData, encoding: .utf8)!
        try await task.send(.string(configString))

        // 2. Send audio data in chunks
        let chunkSize = 32000 // ~1 second of 16kHz 16-bit mono
        var offset = 0
        while offset < audioData.count {
            let end = min(offset + chunkSize, audioData.count)
            let chunk = audioData.subdata(in: offset..<end)
            try await task.send(.data(chunk))
            offset = end
        }

        // 3. Send finish signal (empty string)
        try await task.send(.string(""))

        // 4. Receive responses and collect final tokens
        var finalTokens: [String] = []
        var finished = false

        while !finished {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                // Connection closed by server
                break
            }

            switch message {
            case .string(let text):
                guard let data = text.data(using: .utf8),
                      let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                if let tokens = response["tokens"] as? [[String: Any]] {
                    for token in tokens {
                        if let isFinal = token["is_final"] as? Bool, isFinal,
                           let tokenText = token["text"] as? String {
                            finalTokens.append(tokenText)
                        }
                    }
                }

                if let isFinished = response["finished"] as? Bool, isFinished {
                    finished = true
                }

            case .data:
                // Binary responses not expected, skip
                break

            @unknown default:
                break
            }
        }

        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
        return finalTokens.joined()
    }

    // URLSessionWebSocketDelegate - allow connection
    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {}

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {}
}

// MARK: - Streaming Session

/// Streams audio to Soniox while recording so the transcript is ready right after stop.
/// All mutable state is confined to `queue`; sends are issued one at a time to preserve order.
final class SonioxStreamingSession {
    private let url = URL(string: "wss://stt-rt.soniox.com/transcribe-websocket")!
    private let chunkBytes = 3200 // ~100ms of 16kHz 16-bit mono
    private let finishTimeout: TimeInterval = 15

    private let apiKey: String
    private let language: String
    private let queue = DispatchQueue(label: "com.anmen.malgeul.soniox-stream")

    // Queue-confined state
    private var urlSession: URLSession?
    private var task: URLSessionWebSocketTask?
    private var pendingAudio = Data()
    private var outbox: [URLSessionWebSocketTask.Message] = []
    private var isSending = false
    private var isFinishing = false
    private var isClosed = false
    private var isServerFinished = false
    private var finalTokens: [String] = []
    private var failure: StreamingError?
    private var continuation: CheckedContinuation<String, Error>?

    init(apiKey: String, language: String) {
        self.apiKey = apiKey
        self.language = language
    }

    /// Opens the WebSocket and queues the config message as the first message.
    func start() {
        queue.async { [self] in
            guard task == nil, !isClosed else { return }

            let langHints = language == "ko" ? ["ko", "en"] : ["en", "ko"]
            let config: [String: Any] = [
                "api_key": apiKey,
                "model": "stt-rt-v4",
                "audio_format": "pcm_s16le",
                "sample_rate": 16000,
                "num_channels": 1,
                "language_hints": langHints
            ]
            guard let configData = try? JSONSerialization.data(withJSONObject: config),
                  let configString = String(data: configData, encoding: .utf8) else {
                fail(.connectionFailed("설정 메시지를 만들 수 없습니다."))
                return
            }

            let session = URLSession(configuration: .default)
            let webSocketTask = session.webSocketTask(with: url)
            urlSession = session
            task = webSocketTask
            webSocketTask.resume()

            outbox.append(.string(configString))
            pumpSend()
            receiveNext()
        }
    }

    /// Accepts converted PCM from the audio tap thread. Order is preserved by the serial queue.
    func append(_ data: Data) {
        guard !data.isEmpty else { return }
        queue.async { [self] in
            guard !isClosed, !isFinishing else { return }
            pendingAudio.append(data)
            while pendingAudio.count >= chunkBytes {
                outbox.append(.data(pendingAudio.prefix(chunkBytes)))
                pendingAudio = Data(pendingAudio.dropFirst(chunkBytes))
            }
            pumpSend()
        }
    }

    /// Flushes remaining audio, signals end of stream and waits for the final transcript.
    func finish() async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            queue.async { [self] in
                if let failure {
                    close()
                    cont.resume(throwing: failure)
                    return
                }
                guard !isClosed, !isFinishing else {
                    cont.resume(throwing: StreamingError.closed)
                    return
                }
                isFinishing = true
                continuation = cont

                if !pendingAudio.isEmpty {
                    outbox.append(.data(pendingAudio))
                    pendingAudio = Data()
                }
                outbox.append(.string(""))
                pumpSend()

                queue.asyncAfter(deadline: .now() + finishTimeout) { [weak self] in
                    self?.fail(.timeout)
                }
            }
        }
    }

    /// Closes the socket immediately and discards everything.
    func cancel() {
        queue.async { [self] in
            failure = failure ?? .closed
            if let cont = continuation {
                continuation = nil
                cont.resume(throwing: StreamingError.closed)
            }
            close()
        }
    }

    // MARK: - Private (queue-confined)

    private func pumpSend() {
        guard !isSending, !isClosed, failure == nil, let task, !outbox.isEmpty else { return }
        let message = outbox.removeFirst()
        isSending = true
        task.send(message) { [weak self] error in
            guard let self else { return }
            self.queue.async {
                self.isSending = false
                if let error {
                    self.fail(.connectionFailed(error.localizedDescription))
                    return
                }
                self.pumpSend()
            }
        }
    }

    private func receiveNext() {
        guard !isClosed, let task else { return }
        task.receive { [weak self] result in
            guard let self else { return }
            self.queue.async {
                guard !self.isClosed else { return }
                switch result {
                case .success(let message):
                    if case .string(let text) = message {
                        self.handle(text: text)
                    }
                    if !self.isServerFinished, self.failure == nil {
                        self.receiveNext()
                    }
                case .failure(let error):
                    self.fail(.connectionFailed(error.localizedDescription))
                }
            }
        }
    }

    private func handle(text: String) {
        guard let data = text.data(using: .utf8),
              let response = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if response["error_code"] != nil || response["error_message"] != nil {
            let code = response["error_code"].map { "\($0)" } ?? "-"
            let message = response["error_message"] as? String ?? ""
            fail(.server("\(code) \(message)"))
            return
        }

        if let tokens = response["tokens"] as? [[String: Any]] {
            for token in tokens {
                guard let isFinal = token["is_final"] as? Bool, isFinal,
                      let tokenText = token["text"] as? String else { continue }
                // Skip special control tokens such as <fin> / <end>
                if tokenText.hasPrefix("<"), tokenText.hasSuffix(">") { continue }
                finalTokens.append(tokenText)
            }
        }

        if let isFinished = response["finished"] as? Bool, isFinished {
            isServerFinished = true
            let result = finalTokens.joined()
            if let cont = continuation {
                continuation = nil
                cont.resume(returning: result)
            }
            close()
        }
    }

    private func fail(_ error: StreamingError) {
        guard !isClosed, !isServerFinished else { return }
        if failure == nil { failure = error }
        if let cont = continuation {
            continuation = nil
            cont.resume(throwing: failure ?? error)
            close()
        } else if case .timeout = error {
            close()
        }
        // Without a waiting continuation the error is kept and reported by finish().
    }

    private func close() {
        guard !isClosed else { return }
        isClosed = true
        outbox.removeAll()
        pendingAudio = Data()
        task?.cancel(with: .normalClosure, reason: nil)
        urlSession?.invalidateAndCancel()
        task = nil
        urlSession = nil
    }

    enum StreamingError: LocalizedError {
        case connectionFailed(String)
        case server(String)
        case timeout
        case closed

        var errorDescription: String? {
            switch self {
            case .connectionFailed(let detail):
                return "음성 인식 서버 연결에 실패했습니다: \(detail)"
            case .server(let detail):
                return "음성 인식 서버 오류: \(detail)"
            case .timeout:
                return "음성 인식 응답 시간이 초과되었습니다."
            case .closed:
                return "음성 인식 세션이 종료되었습니다."
            }
        }
    }
}
