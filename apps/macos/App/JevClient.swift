import Foundation

enum JevClient {
    static let model = "~typesafe/jev-latest"
    static let decisionsURL = URL(string: "https://openrouter.ai/api/alpha/decisions")!

    struct FileJudgment: Equatable, Sendable {
        var kind: String
        var scene: String
        var keep: Double
        var sensitive: Double
    }

    static func labelFile(state: String, apiKey: String) throws -> FileJudgment {
        let payload = try decide(state: state, questions: fileQuestions, apiKey: apiKey)
        return FileJudgment(
            kind: choice(payload, "kind") ?? "other",
            scene: choice(payload, "scene") ?? "other",
            keep: noul(payload, "keep"),
            sensitive: noul(payload, "sensitive")
        )
    }

    static func interpretSearch(query: String, apiKey: String) throws -> String {
        let payload = try decide(state: "search query: \(query)", questions: searchQuestions, apiKey: apiKey)
        return choice(payload, "intent") ?? "all"
    }

    private static func decide(state: String, questions: [String: Any], apiKey: String) throws -> [String: Any] {
        var request = URLRequest(url: decisionsURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Brand.site, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(Brand.name, forHTTPHeaderField: "X-OpenRouter-Title")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "state": state,
            "questions": questions,
        ])
        let (data, response) = try URLSession.shared.synchronousData(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        guard (200..<300).contains(status) else {
            let message = (json["error"] as? [String: Any])?["message"] as? String
                ?? json["message"] as? String
                ?? "OpenRouter returned \(status)"
            throw JevError.http(status, message)
        }
        return json
    }

    private static func choice(_ payload: [String: Any], _ name: String) -> String? {
        guard let answers = payload["answers"] as? [String: Any],
              let answer = answers[name] as? [String: Any] else { return nil }
        return answer["choice"] as? String
    }

    private static func noul(_ payload: [String: Any], _ name: String) -> Double {
        guard let answers = payload["answers"] as? [String: Any],
              let answer = answers[name] as? [String: Any],
              let value = answer["noul"] as? Double else { return 0.5 }
        return value
    }

    private static let fileQuestions: [String: Any] = [
        "kind": [
            "type": "choice",
            "instructions": "What kind of file is this, from the name, type, folder, and size?",
            "criteria": [
                "photo": "A camera photo or still image",
                "video": "A video clip",
                "screenshot": "A screen capture or UI shot",
                "document": "A PDF, text, spreadsheet, slide, or similar",
                "other": "Anything else",
            ],
        ],
        "scene": [
            "type": "choice",
            "instructions": "What is this mainly of?",
            "criteria": [
                "people": "People or portraits",
                "indoor": "Indoor place or room",
                "outdoor": "Outdoor place or nature",
                "product": "An object or product",
                "food": "Food or drink",
                "document": "Paper, slide, or text on screen",
                "other": "Unclear or mixed",
            ],
        ],
        "keep": [
            "type": "noul",
            "instructions": "Is this worth keeping in a featured library, not junk, a temp export, or a duplicate-looking filename?",
        ],
        "sensitive": [
            "type": "noul",
            "instructions": "Does the name or type suggest this is private or sensitive?",
        ],
    ]

    private static let searchQuestions: [String: Any] = [
        "intent": [
            "type": "choice",
            "instructions": "What is this search trying to find in a photo drive?",
            "criteria": [
                "all": "No specific type, match names and labels",
                "photos": "Looking for photos or images",
                "videos": "Looking for videos",
                "people": "Looking for people or portraits",
                "screenshots": "Looking for screenshots",
                "documents": "Looking for documents",
                "other": "Something else",
            ],
        ],
    ]
}

enum JevError: Error, CustomStringConvertible {
    case http(Int, String)
    case missingKey
    var description: String {
        switch self {
        case .http(let code, let body): return "Jev HTTP \(code) \(body.prefix(160))"
        case .missingKey: return "Add an OpenRouter key in Settings → Advanced."
        }
    }
}

private extension URLSession {
    func synchronousData(for request: URLRequest) throws -> (Data, URLResponse) {
        var collected: (Data, URLResponse)?
        var collectedError: Error?
        let lock = DispatchSemaphore(value: 0)
        let task = dataTask(with: request) { data, response, error in
            if let error {
                collectedError = error
            } else if let data, let response {
                collected = (data, response)
            } else {
                collectedError = URLError(.badServerResponse)
            }
            lock.signal()
        }
        task.resume()
        lock.wait()
        if let collectedError { throw collectedError }
        guard let collected else { throw URLError(.badServerResponse) }
        return collected
    }
}
