import Foundation

final class AnthropicService {

    static let shared = AnthropicService()

    private let session = URLSession.shared
    private let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    func generateHTML(description: String, imageData: Data? = nil, completion: @escaping (Result<String, Error>) -> Void) {
        let userContent: Any
        if let imageData {
            let base64 = imageData.base64EncodedString()
            userContent = [
                ["type": "image",
                 "source": ["type": "base64",
                            "media_type": "image/jpeg",
                            "data": base64] as [String: Any]] as [String: Any],
                ["type": "text",
                 "text": "Create a self-contained mobile HTML app that: \(description)"] as [String: Any]
            ]
        } else {
            userContent = "Create a self-contained mobile HTML app that: \(description)"
        }

        let requestBody: [String: Any] = [
            "model": "claude-haiku-4-5-20251001",
            "max_tokens": 4000,
            "system": "You output ONLY raw HTML. Your entire response must start with <!DOCTYPE html> and end with </html>. No explanations, no markdown, no code fences, nothing before or after the HTML.",
            "messages": [
                ["role": "user", "content": userContent]
            ]
        ]

        do {
            let payload = try JSONSerialization.data(withJSONObject: requestBody, options: [])
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue(Config.anthropicAPIKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = payload

            let task = session.dataTask(with: request) { data, response, error in
                if let error = error {
                    completion(.failure(error))
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, !(200..<300).contains(httpResponse.statusCode) {
                    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "<no body>"
                    let message = "Anthropic API error: \(httpResponse.statusCode) - \(body)"
                    completion(.failure(NSError(domain: "AnthropicService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: message])))
                    return
                }

                guard let data = data else {
                    completion(.failure(NSError(domain: "AnthropicService", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data received"])))
                    return
                }

                do {
                    if let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                       let content = json["content"] as? [[String: Any]],
                       let first = content.first,
                       let text = first["text"] as? String {
                        var html = text
                        if let start = html.range(of: "<!DOCTYPE html>", options: .caseInsensitive) {
                            html = String(html[start.lowerBound...])
                        }
                        if let end = html.range(of: "</html>", options: .caseInsensitive) {
                            html = String(html[..<end.upperBound])
                        }
                        completion(.success(html))
                    } else {
                        completion(.failure(NSError(domain: "AnthropicService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format"])))
                    }
                } catch {
                    completion(.failure(error))
                }
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
}
