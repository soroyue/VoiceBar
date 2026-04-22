import Foundation

final class LLMRefinementService {
    private let systemPrompt = """
You are a conservative speech-to-text post-processor. Your ONLY job is to fix obvious speech recognition errors.

RULES (strictly follow these):
1. ONLY fix Chinese homophone errors (e.g., 配森→Python, 杰森→JSON, 埃森→AI, 弟→的, 蓝后→然后)
2. ONLY fix English technical terms mistakenly converted to Chinese (e.g., OK→OK, PDF→PDF, API→API, URL→URL, HTTP→HTTP)
3. NEVER rewrite, polish, or improve grammatically correct text
4. NEVER add or remove content
5. NEVER change correct Chinese text
6. If the input looks correct, return it EXACTLY as-is with no changes
7. If you're unsure whether something is an error, leave it unchanged
8. Preserve ALL punctuation exactly as given
9. Return ONLY the corrected text, nothing else

Common fixes reference:
- 配森→Python, 杰森/杰明/皆可能→JSON, 挨/埃/爱→AI, 弟/滴→的, 蓝后→然后, 克心→可心, 卡死→卡死, 跑男→跑男 (if referring to a person/show)
- 维恩图→Venn图, 哎呦→哎呦, 奥德彪/奥迪表→奥德赛 (context dependent - leave as-is if unclear)
"""

    func refine(text: String, completion: @escaping (String?) -> Void) {
        guard let apiBase = SettingsManager.shared.llmAPIBase,
              !apiBase.isEmpty,
              let apiKey = SettingsManager.shared.llmAPIKey,
              !apiKey.isEmpty else {
            completion(text)
            return
        }

        let model = SettingsManager.shared.llmModel ?? "gpt-3.5-turbo"

        guard let url = URL(string: "\(apiBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/chat/completions") else {
            completion(text)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        let payload: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ],
            "max_tokens": 1024,
            "temperature": 0.1
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            completion(text)
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data = data,
                  error == nil else {
                completion(text)
                return
            }

            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first,
                   let message = firstChoice["message"] as? [String: Any],
                   let refinedText = message["content"] as? String {
                    completion(refinedText.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    completion(text)
                }
            } catch {
                completion(text)
            }
        }.resume()
    }
}
