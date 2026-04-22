import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    convenience init() {
        let settingsView = LLMSettingsView()
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = "LLM Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 480, height: 280))
        window.center()

        self.init(window: window)
    }
}

struct LLMSettingsView: View {
    @State private var apiBase: String = SettingsManager.shared.llmAPIBase ?? ""
    @State private var apiKey: String = SettingsManager.shared.llmAPIKey ?? ""
    @State private var model: String = SettingsManager.shared.llmModel ?? "gpt-3.5-turbo"
    @State private var testStatus: String = ""
    @State private var isTesting: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("LLM Refinement Settings")
                .font(.headline)
                .padding(.bottom, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("API Base URL")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("https://api.openai.com/v1", text: $apiBase)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("API Key")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        apiKey = ""
                        SettingsManager.shared.clearLLMAPIKey()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.red)
                    .font(.caption)
                }
                SecureField("sk-...", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Model")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("gpt-3.5-turbo", text: $model)
                    .textFieldStyle(.roundedBorder)
            }

            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(isTesting || apiBase.isEmpty || apiKey.isEmpty)

                if isTesting {
                    ProgressView()
                        .scaleEffect(0.6)
                }

                Text(testStatus)
                    .font(.caption)
                    .foregroundColor(testStatus.contains("Success") ? .green : (testStatus.contains("Failed") ? .red : .secondary))

                Spacer()

                Button("Save") {
                    save()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(20)
        .frame(width: 480, height: 280)
    }

    private func testConnection() {
        isTesting = true
        testStatus = "Testing..."

        guard let url = URL(string: "\(apiBase.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/models") else {
            testStatus = "Failed: Invalid URL"
            isTesting = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 10

        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                isTesting = false
                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 || httpResponse.statusCode == 401 {
                        testStatus = "Success: Connection OK (auth status: \(httpResponse.statusCode))"
                    } else {
                        testStatus = "Failed: HTTP \(httpResponse.statusCode)"
                    }
                } else if error != nil {
                    testStatus = "Failed: \(error!.localizedDescription)"
                } else {
                    testStatus = "Failed: Unknown error"
                }
            }
        }.resume()
    }

    private func save() {
        SettingsManager.shared.llmAPIBase = apiBase
        SettingsManager.shared.llmAPIKey = apiKey
        SettingsManager.shared.llmModel = model
        testStatus = "Saved!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if testStatus == "Saved!" {
                testStatus = ""
            }
        }
    }
}
