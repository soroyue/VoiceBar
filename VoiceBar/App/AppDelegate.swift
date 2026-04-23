import AppKit
import SwiftUI
import ServiceManagement
import Carbon.HIToolbox

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var keyboardMonitor: KeyboardMonitor!
    private var speechRecognizer: SpeechRecognitionService!
    private var floatingPanelController: FloatingPanelController!
    private var autoTypeService: AutoTypeService!
    private var llmService: LLMRefinementService!
    private var settingsWindowController: SettingsWindowController?

    private var isRecording = false
    private var transcriptionText = ""
    private var currentLanguage: String
    private var currentTriggerKey: TriggerKey
    /// Captured before any VoiceBar window takes focus, used for Cmd+V paste target
    private var targetPID: pid_t = 0
    /// Saved clipboard content for restoration after paste
    private var savedClipboard: String?

    override init() {
        self.currentLanguage = SettingsManager.shared.speechLanguage
        self.currentTriggerKey = {
            if let saved = SettingsManager.shared.triggerKey,
               let key = TriggerKey(rawValue: saved) {
                return key
            }
            return .rightCommand
        }()
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupServices()
        setupFloatingPanel()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "waveform.circle.fill", accessibilityDescription: "VoiceBar")
            button.image?.isTemplate = true
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            button.sendAction(on: .leftMouseUp)
        }
        statusItem.menu = buildMenu()

        let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("voicebar.log")
        let logMsg = "[VoiceBar] App started at \(Date())\n"
        try? logMsg.write(to: logPath, atomically: true, encoding: .utf8)
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        showDiagnostics(nil)
    }

    @objc private func showDiagnostics(_ sender: Any?) {
        let trigger = keyboardMonitor?.currentTriggerKey.menuLabel ?? "unknown"
        let tapStatus = keyboardMonitor?.hasCGEventTap == true ? "CGEvent ✅" : "NSEvent ⚠️"

        let alert = NSAlert()
        alert.messageText = "🔧 VoiceBar 状态"
        alert.informativeText = """
        当前触发键: \(trigger)
        录音状态: \(isRecording ? "🔴 录音中" : "⚪ 待机")
        键盘监控: \(tapStatus)

        使用方法：按住触发键说话，松开自动粘贴。

        提示：如需在登录时自动启动，请在菜单栏启用 "Start at Login"。
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let triggerMenu = NSMenu()
        for key in TriggerKey.allCases {
            let item = NSMenuItem(title: key.menuLabel, action: #selector(selectTriggerKey(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = (key == currentTriggerKey) ? .on : .off
            triggerMenu.addItem(item)
        }
        let triggerItem = NSMenuItem(title: "Trigger Key / 触发键", action: nil, keyEquivalent: "")
        triggerItem.submenu = triggerMenu
        menu.addItem(triggerItem)

        let diagItem = NSMenuItem(title: "🔧 Diagnostics / 诊断", action: #selector(showDiagnostics(_:)), keyEquivalent: "")
        diagItem.target = self
        menu.addItem(diagItem)

        let langMenu = NSMenu()
        let languages: [(String, String)] = [
            ("zh-CN", "简体中文"),
            ("en-US", "English"),
            ("zh-TW", "繁體中文"),
            ("ja-JP", "日本語"),
            ("ko-KR", "한국어")
        ]
        for (code, name) in languages {
            let item = NSMenuItem(title: name, action: #selector(selectLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = (code == currentLanguage) ? .on : .off
            langMenu.addItem(item)
        }
        let langItem = NSMenuItem(title: "Language / 语言", action: nil, keyEquivalent: "")
        langItem.submenu = langMenu
        menu.addItem(langItem)

        // Urban planning vocabulary toggle
        let urbanVocabItem = NSMenuItem(title: "城市规划专业词库", action: #selector(toggleUrbanPlanning(_:)), keyEquivalent: "")
        urbanVocabItem.target = self
        urbanVocabItem.state = SettingsManager.shared.urbanPlanningEnabled ? .on : .off
        menu.addItem(urbanVocabItem)

        let llmMenu = NSMenu()
        let llmEnabledItem = NSMenuItem(title: "Enable LLM Refinement", action: #selector(toggleLLMEnabled(_:)), keyEquivalent: "")
        llmEnabledItem.target = self
        llmEnabledItem.state = SettingsManager.shared.llmEnabled ? .on : .off
        llmMenu.addItem(llmEnabledItem)
        llmMenu.addItem(NSMenuItem.separator())
        let llmSettingsItem = NSMenuItem(title: "LLM Settings...", action: #selector(openLLMSettings(_:)), keyEquivalent: "")
        llmSettingsItem.target = self
        llmMenu.addItem(llmSettingsItem)
        let llmItem = NSMenuItem(title: "LLM Refinement", action: nil, keyEquivalent: "")
        llmItem.submenu = llmMenu
        menu.addItem(llmItem)

        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: "Start at Login", action: #selector(toggleLoginItem(_:)), keyEquivalent: "")
        loginItem.target = self
        if #available(macOS 13.0, *) {
            loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        } else {
            loginItem.isHidden = true
        }
        menu.addItem(loginItem)

        menu.addItem(NSMenuItem(title: "Quit VoiceBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        return menu
    }

    private func setupServices() {
        autoTypeService = AutoTypeService()
        llmService = LLMRefinementService()
        speechRecognizer = SpeechRecognitionService(language: currentLanguage)
        keyboardMonitor = KeyboardMonitor(onKeyDown: { [weak self] in
            self?.startRecording()
        }, onKeyUp: { [weak self] in
            self?.stopRecording()
        })
        keyboardMonitor.start()
        autoTypeService.configure(keyboardMonitor: keyboardMonitor)
    }

    private func setupFloatingPanel() {
        floatingPanelController = FloatingPanelController()
    }

    private func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        transcriptionText = ""

        // CRITICAL: capture target PID BEFORE showing any VoiceBar window
        targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0

        floatingPanelController.show()
        floatingPanelController.updateTranscription("")
        floatingPanelController.setWaveformLevel(0)

        speechRecognizer.startStreaming(
            onResult: { [weak self] partialText in
                DispatchQueue.main.async {
                    self?.transcriptionText = partialText
                    self?.floatingPanelController.updateTranscription(partialText)
                    vblog("[delegate] onResult: '\(partialText.prefix(20)))...' len=\(partialText.count)")
                }
            },
            onLevel: { [weak self] rmsLevel in
                DispatchQueue.main.async {
                    self?.floatingPanelController.setWaveformLevel(rmsLevel)
                }
            }
        )
    }

    private func stopRecording() {
        guard isRecording else { return }
        isRecording = false

        speechRecognizer.stopStreaming { [weak self] finalText in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.transcriptionText = finalText
                self.floatingPanelController.updateTranscription(finalText)
                self.handleTranscriptionComplete(finalText)
            }
        }
    }

    private func handleTranscriptionComplete(_ text: String) {
        guard !text.isEmpty else {
            floatingPanelController.hide()
            return
        }

        let textToPaste: String
        if SettingsManager.shared.llmEnabled && SettingsManager.shared.isLLMConfigured {
            floatingPanelController.updateTranscription("Refining...")
            let pid = targetPID  // capture before async
            llmService.refine(text: text) { [weak self] refinedText in
                DispatchQueue.main.async {
                    self?.targetPID = pid
                    let final = refinedText ?? text
                    self?.floatingPanelController.hide()
                    self?.pasteViaClipboard(final)
                }
            }
            return
        } else {
            textToPaste = text
        }

        floatingPanelController.hide()
        pasteViaClipboard(textToPaste)
    }

    /// Pastes text by copying to clipboard then simulating Cmd+V.
    private func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard content
        savedClipboard = pasteboard.string(forType: .string)

        // Write text to clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Wait for clipboard to be fully ready, then paste
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.simulateCmdV()

            // Restore clipboard after paste (give plenty of time for paste to complete)
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                pasteboard.clearContents()
                if let saved = self?.savedClipboard {
                    pasteboard.setString(saved, forType: .string)
                    self?.savedClipboard = nil
                }
            }
        }
    }

    /// Simulates Cmd+V keystroke via CGEvent, posted to the target PID captured
    /// before any VoiceBar window took focus.
    private func simulateCmdV() {
        guard targetPID > 0 else {
            vblog("[paste] ERROR: targetPID is 0")
            return
        }

        // Use .hidSystemState + .cgAnnotatedSessionEventTap — same as successful repos
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            vblog("[paste] CGEventSource(hidSystemState) FAILED")
            return
        }

        let vKey: CGKeyCode = 9  // V key

        guard let kd = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let ku = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else {
            vblog("[paste] CGEvent(vKey) FAILED")
            return
        }

        kd.flags = .maskCommand
        ku.flags = .maskCommand

        kd.post(tap: .cgAnnotatedSessionEventTap)
        ku.post(tap: .cgAnnotatedSessionEventTap)

        vblog("[paste] Cmd+V posted to PID=\(targetPID)")
    }

    @objc private func selectTriggerKey(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? TriggerKey else { return }
        currentTriggerKey = key
        keyboardMonitor.setTriggerKey(key)

        if let triggerSubmenu = sender.menu {
            for item in triggerSubmenu.items {
                item.state = (item.representedObject as? TriggerKey == key) ? .on : .off
            }
        }
    }

    @objc private func selectLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        currentLanguage = code
        SettingsManager.shared.speechLanguage = code

        if let langSubmenu = sender.menu {
            for item in langSubmenu.items {
                item.state = (item.representedObject as? String == code) ? .on : .off
            }
        }

        speechRecognizer.updateLanguage(code)
    }

    @objc private func toggleUrbanPlanning(_ sender: NSMenuItem) {
        let newState = !SettingsManager.shared.urbanPlanningEnabled
        SettingsManager.shared.urbanPlanningEnabled = newState
        sender.state = newState ? .on : .off
    }

    @objc private func toggleLLMEnabled(_ sender: NSMenuItem) {
        let newState = !SettingsManager.shared.llmEnabled
        SettingsManager.shared.llmEnabled = newState
        sender.state = newState ? .on : .off
    }

    @objc private func openLLMSettings(_ sender: Any?) {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController()
        }
        settingsWindowController?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleLoginItem(_ sender: NSMenuItem) {
        if #available(macOS 13.0, *) {
            do {
                let service = SMAppService.mainApp
                if service.status == .enabled {
                    try service.unregister()
                    sender.state = .off
                } else {
                    try service.register()
                    sender.state = .on
                }
            } catch {
                let alert = NSAlert()
                alert.messageText = "Login Item Error"
                alert.informativeText = "Could not update login item: \(error.localizedDescription)"
                alert.runModal()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        keyboardMonitor.stop()
    }
}

private func vblog(_ msg: String) {
    let line = "[delegate] [\(Date())] \(msg)\n"
    let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("voicebar.log")
    try? line.appendToFile(logPath)
}

private extension String {
    func appendToFile(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        if let data = self.data(using: .utf8) { handle.write(data) }
        handle.closeFile()
    }
}
