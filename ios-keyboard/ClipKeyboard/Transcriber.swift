import Foundation

enum TranscriptionError: LocalizedError {
    case noKey
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .noKey:
            return "No Groq API key. Paste it in the app first."
        case .http(let code, let body):
            let snippet = body.prefix(200)
            return "Groq error \(code): \(snippet)"
        case .badResponse:
            return "Couldn't read Groq's response."
        }
    }
}

/// Uploads an audio file to Groq's Whisper endpoint (OpenAI-compatible) and
/// returns the transcript text. Uses the Groq key from the Keychain.
struct Transcriber {
    static let shared = Transcriber()

    private let endpoint = URL(string: "https://api.groq.com/openai/v1/audio/transcriptions")!
    private let model = "whisper-large-v3-turbo"

    func transcribe(_ fileURL: URL) async throws -> String {
        guard let key = KeychainStore.groqKey, !key.isEmpty else {
            throw TranscriptionError.noKey
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 120
        req.httpBody = try makeBody(fileURL: fileURL, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw TranscriptionError.badResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TranscriptionError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let text = obj?["text"] as? String else {
            throw TranscriptionError.badResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func makeBody(fileURL: URL, boundary: String) throws -> Data {
        let fileData = try Data(contentsOf: fileURL)
        var body = Data()

        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        field("model", model)
        field("response_format", "json")

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(fileURL.lastPathComponent)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/m4a\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        return body
    }
}
