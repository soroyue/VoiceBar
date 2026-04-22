import Foundation
import AppKit
import Carbon.HIToolbox

final class TextInjectionService {
    private var previousPasteboardItems: [NSPasteboardItem]?
    private var hasAccessibilityPermission: Bool = false

    init() {
        checkAccessibility()
    }

    private func checkAccessibility() {
        // Check if we have accessibility permissions
        let checkOptPrompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [checkOptPrompt: false] as CFDictionary
        hasAccessibilityPermission = AXIsProcessTrustedWithOptions(options)
        vbinject("Accessibility permission: \(hasAccessibilityPermission)")
    }

    func inject(text: String) {
        vbinject("TextInjectionService: injecting '\(text.prefix(30))...'")
        let pasteboard = NSPasteboard.general
        previousPasteboardItems = pasteboard.pasteboardItems
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let wasCJK = isCurrentSourceCJK()

        if wasCJK {
            vbinject("CJK input source detected, switching...")
            _ = switchToASCIIInputSource()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.simulatePaste()
        }

        if wasCJK {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.restoreInputSource()
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.restoreClipboard()
        }
    }

    private func simulatePaste() {
        if hasAccessibilityPermission {
            // Try CGEvent posting first (most reliable with accessibility)
            let eventSource = CGEventSource(stateID: .combinedSessionState)
            let vKey: CGKeyCode = 0x09 // V key

            guard let keyDown = CGEvent(keyboardEventSource: eventSource, virtualKey: vKey, keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: eventSource, virtualKey: vKey, keyDown: false) else {
                vbinject("CGEvent: failed to create key events")
                fallbackPaste()
                return
            }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand

            // Try session tap first, then HID tap
            keyDown.post(tap: .cgSessionEventTap)
            keyUp.post(tap: .cgSessionEventTap)
            vbinject("CGEvent posted via session tap")
        } else {
            vbinject("No accessibility - using NSPasteboard fallback")
            fallbackPaste()
        }
    }

    private func fallbackPaste() {
        // Best effort: just copy to clipboard and show notification
        // User can Cmd+V manually
        let alert = NSAlert()
        alert.messageText = "文字已复制到剪贴板"
        alert.informativeText = "请手动 Cmd+V 粘贴"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "好")
        alert.runModal()
    }

    private func isCurrentSourceCJK() -> Bool {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue() else { return false }
        guard let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
        let cfStr = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue()
        let bundleID = cfStr as String

        let cjkPatterns = [
            "SimplifiedChinese", "TraditionalChinese", "Pinyin", "ShuangPin", "Wubi",
            "com.google.inputmethod.Japanese", "com.google.inputmethod.Chinese",
            "com.rime.inputmethod.Rime", "moe.jy.IME"
        ]
        return cjkPatterns.contains { bundleID.contains($0) }
    }

    private var originalInputSource: TISInputSource? {
        didSet {
            // Store reference when switching
        }
    }

    private func switchToASCIIInputSource() -> Bool {
        guard let current = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue() else { return false }
        originalInputSource = current

        for _ in 0..<10 {
            let src = CGEventSource(stateID: .combinedSessionState)
            let spaceKey: CGKeyCode = 49 // Space

            guard let kd = CGEvent(keyboardEventSource: src, virtualKey: spaceKey, keyDown: true),
                  let ku = CGEvent(keyboardEventSource: src, virtualKey: spaceKey, keyDown: false) else { continue }
            kd.flags = .maskControl
            ku.flags = .maskControl
            kd.post(tap: .cgSessionEventTap)
            ku.post(tap: .cgSessionEventTap)

            Thread.sleep(forTimeInterval: 0.15)

            if let next = TISCopyCurrentKeyboardInputSource()?.takeUnretainedValue(),
               let idPtr = TISGetInputSourceProperty(next, kTISPropertyInputSourceID) {
                let cfStr = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue()
                let bundleID = cfStr as String
                if !isCJKBundleID(bundleID) {
                    vbinject("Switched to ASCII source: \(bundleID)")
                    return true
                }
            }
        }
        return false
    }

    private func restoreInputSource() {
        guard let src = originalInputSource else { return }
        TISSelectInputSource(src)
        vbinject("Restored original input source")
    }

    private func isCJKBundleID(_ id: String) -> Bool {
        let cjkPatterns = [
            "SimplifiedChinese", "TraditionalChinese", "Pinyin", "ShuangPin", "Wubi",
            "com.google.inputmethod.Japanese", "com.google.inputmethod.Chinese",
            "com.rime.inputmethod.Rime", "moe.jy.IME"
        ]
        return cjkPatterns.contains { id.contains($0) }
    }

    private func restoreClipboard() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if let items = previousPasteboardItems {
            for item in items {
                pasteboard.writeObjects([item])
            }
        }
        previousPasteboardItems = nil
        vbinject("Clipboard restored")
    }
}

private func vbinject(_ msg: String) {
    let line = "[inject] [\(Date())] \(msg)\n"
    let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("voicebar.log")
    try? line.appendToFile(logPath)
}

private extension String {
    func appendToFile(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        if let data = self.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    }
}
