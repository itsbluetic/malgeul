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
