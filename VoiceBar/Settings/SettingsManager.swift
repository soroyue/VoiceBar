import Foundation

final class SettingsManager {
    static let shared = SettingsManager()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let speechLanguage = "VoiceBar.SpeechLanguage"
        static let llmEnabled = "VoiceBar.LLMEnabled"
        static let llmAPIBase = "VoiceBar.LLMAPIBase"
        static let llmAPIKey = "VoiceBar.LLMAPIKey"
        static let llmModel = "VoiceBar.LLMModel"
        static let triggerKey = "VoiceBar.TriggerKey"
        static let urbanPlanningEnabled = "VoiceBar.UrbanPlanningEnabled"
    }

    private init() {
        // Set defaults
        if defaults.object(forKey: Keys.speechLanguage) == nil {
            defaults.set("zh-CN", forKey: Keys.speechLanguage)
        }
        if defaults.object(forKey: Keys.llmEnabled) == nil {
            defaults.set(false, forKey: Keys.llmEnabled)
        }
        if defaults.object(forKey: Keys.llmModel) == nil {
            defaults.set("gpt-3.5-turbo", forKey: Keys.llmModel)
        }
        if defaults.object(forKey: Keys.urbanPlanningEnabled) == nil {
            defaults.set(true, forKey: Keys.urbanPlanningEnabled)
        }
    }

    var speechLanguage: String {
        get { defaults.string(forKey: Keys.speechLanguage) ?? "zh-CN" }
        set { defaults.set(newValue, forKey: Keys.speechLanguage) }
    }

    var llmEnabled: Bool {
        get { defaults.bool(forKey: Keys.llmEnabled) }
        set { defaults.set(newValue, forKey: Keys.llmEnabled) }
    }

    var llmAPIBase: String? {
        get { defaults.string(forKey: Keys.llmAPIBase) }
        set { defaults.set(newValue, forKey: Keys.llmAPIBase) }
    }

    var llmAPIKey: String? {
        get { defaults.string(forKey: Keys.llmAPIKey) }
        set { defaults.set(newValue, forKey: Keys.llmAPIKey) }
    }

    var llmModel: String? {
        get { defaults.string(forKey: Keys.llmModel) }
        set { defaults.set(newValue, forKey: Keys.llmModel) }
    }

    var isLLMConfigured: Bool {
        guard let apiBase = llmAPIBase, !apiBase.isEmpty,
              let apiKey = llmAPIKey, !apiKey.isEmpty else {
            return false
        }
        return true
    }

    var triggerKey: String? {
        get { defaults.string(forKey: Keys.triggerKey) }
        set { defaults.set(newValue, forKey: Keys.triggerKey) }
    }

    var urbanPlanningEnabled: Bool {
        get { defaults.bool(forKey: Keys.urbanPlanningEnabled) }
        set { defaults.set(newValue, forKey: Keys.urbanPlanningEnabled) }
    }

    func clearLLMAPIKey() {
        defaults.removeObject(forKey: Keys.llmAPIKey)
    }
}
