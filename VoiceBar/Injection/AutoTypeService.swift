import Foundation
import AppKit
import Carbon.HIToolbox

/// Types text using CGEvent postToPid, similar to IME direct input.
/// Disables VoiceBar's keyboard monitoring during typing so CGEvents
/// are not intercepted, then re-enables it after.
final class AutoTypeService {
    private var lastCommittedLength: Int = 0
    private var targetPID: pid_t = 0
    private var isTyping = false
    /// Safety timeout - if typing stalls, re-enable monitoring
    private var typingTimeoutTimer: Timer?

    /// Weak reference to keyboard monitor for enabling/disabling during typing.
    private weak var keyboardMonitor: KeyboardMonitor?

    private let logPath: URL = {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("voicebar.log")
    }()

    func configure(keyboardMonitor: KeyboardMonitor) {
        self.keyboardMonitor = keyboardMonitor
    }

    /// Allow AppDelegate to set the target PID explicitly before any VoiceBar
    /// windows take focus (which would make frontmostApplication return VoiceBar).
    func setTargetPID(_ pid: pid_t) {
        targetPID = pid
        vblog("setTargetPID: \(pid)")
    }

    func reset() {
        lastCommittedLength = 0
        isTyping = false
        typingTimeoutTimer?.invalidate()
        typingTimeoutTimer = nil
        // If explicit PID was set, keep using it; otherwise capture frontmost
        if targetPID == 0 {
            targetPID = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
        }
        vblog("reset: targetPID=\(targetPID)")
    }

    func typeIncremental(newText: String) {
        if newText.count < lastCommittedLength {
            lastCommittedLength = 0
        }

        let newPortion = String(newText.dropFirst(lastCommittedLength))
        guard !newPortion.isEmpty else { return }
        guard targetPID > 0 else { return }

        if isTyping {
            vblog("typeInc: skipped (isTyping=true, pending chars)")
            return
        }

        isTyping = true
        scheduleTimeout()
        typeString(newPortion) {
            self.lastCommittedLength += newPortion.count
            self.isTyping = false
            self.typingTimeoutTimer?.invalidate()
            self.typingTimeoutTimer = nil
        }
    }

    func commitRemaining(newText: String) {
        let remaining = String(newText.dropFirst(lastCommittedLength))
        guard !remaining.isEmpty else {
            lastCommittedLength = 0
            return
        }
        if isTyping {
            // Wait for in-progress typing to finish first
            vblog("commitRemaining: waiting for isTyping to clear")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                self.commitRemaining(newText: newText)
            }
            return
        }
        typeString(remaining) {
            self.lastCommittedLength = 0
        }
    }

    // MARK: - Core

    private func scheduleTimeout() {
        typingTimeoutTimer?.invalidate()
        typingTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: false) { [weak self] _ in
            self?.vblog("TYPING TIMEOUT: forcing re-enable")
            self?.isTyping = false
            self?.keyboardMonitor?.setDisabled(false)
        }
    }

    private func typeString(_ text: String, completion: @escaping () -> Void) {
        guard !text.isEmpty else { completion(); return }
        let pid = targetPID
        guard pid > 0 else { completion(); return }

        vblog("typeString START: len=\(text.count) pid=\(pid)")

        // Disable VoiceBar's keyboard monitoring
        DispatchQueue.main.async {
            self.keyboardMonitor?.setDisabled(true)
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Give target app time to fully activate
            self.activateTarget(pid: pid)
            Thread.sleep(forTimeInterval: 0.5)  // Wait for app to stabilize

            // Verify frontmost state
            let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0
            self.vblog("typeString: frontmost=\(frontmost) targetPID=\(pid)")

            // Post to .cgAnnotatedSessionEventTap in batches of 20 UTF-16 code units,
            // matching the approach used by VoiceInput-Patch / StreamDictate
            let batchSize = 20
            let utf16 = Array(text.utf16)
            var offset = 0

            while offset < utf16.count {
                let end = min(offset + batchSize, utf16.count)
                let batch = Array(utf16[offset..<end])

                self.postUnicodeBatch(batch)

                // Delay between batches (800 microseconds, per VoiceInput-Patch)
                Thread.sleep(forTimeInterval: 0.0008)

                offset = end
            }

            self.vblog("typeString DONE")

            // Re-enable VoiceBar's keyboard monitoring
            DispatchQueue.main.async {
                self.keyboardMonitor?.setDisabled(false)
                completion()
            }
        }
    }

    private func activateTarget(pid: pid_t) {
        // AppleScript activation - most reliable
        var error: NSDictionary?
        let script = NSAppleScript(source: """
            tell application "System Events"
                set frontmost of every process whose unix id is \(pid) to true
            end tell
            """)
        script?.executeAndReturnError(&error)
        if let err = error {
            vblog("activateTarget error: \(err)")
        }
    }

    /// Post a batch of UTF-16 characters using CGEvent.
    /// Uses .hidSystemState (as all working voice-input projects do) and
    /// .cgAnnotatedSessionEventTap (bypasses tap interference in protected apps).
    private func postUnicodeBatch(_ utf16: [UInt16]) {
        guard !utf16.isEmpty else { return }

        // .hidSystemState — used by all working implementations (VoiceInput-Patch, StreamDictate, etc.)
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            vblog("postUnicodeBatch: CGEventSource(hidSystemState) FAILED")
            return
        }

        guard let kd = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0), keyDown: true),
              let ku = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(0), keyDown: false) else {
            vblog("postUnicodeBatch: CGEvent creation FAILED")
            return
        }

        kd.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
        ku.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)

        // .cgAnnotatedSessionEventTap bypasses tap interference — critical for Notes.app
        kd.post(tap: .cgAnnotatedSessionEventTap)
        ku.post(tap: .cgAnnotatedSessionEventTap)
    }

    private func isCJK(_ char: Character) -> Bool {
        guard let s = char.unicodeScalars.first else { return false }
        let v = s.value
        return (0x4E00...0x9FFF).contains(v) ||
               (0x3000...0x303F).contains(v) ||
               (0x3040...0x309F).contains(v) ||
               (0x30A0...0x30FF).contains(v) ||
               (0xAC00...0xD7AF).contains(v)
    }

    private func vblog(_ msg: String) {
        let line = "[autotype] \(msg)\n"
        try? line.appendToFile(logPath)
    }
}

private extension String {
    func appendToFile(_ url: URL) throws {
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()
        if let data = self.data(using: .utf8) { handle.write(data) }
        handle.closeFile()
    }
}
