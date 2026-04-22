import Foundation
import AppKit
import Carbon.HIToolbox
import IOKit.hid

enum TriggerKey: String, CaseIterable {
    case rightCommand = "Right ⌘"
    case rightOption = "Right ⌥"
    case fn = "Fn"

    var menuLabel: String { rawValue }

    var keyCode: Int32 {
        switch self {
        case .rightCommand: return 54
        case .rightOption: return 61
        case .fn: return 63
        }
    }
}

// MARK: - IOKit HID C Callbacks

private func hidDeviceMatchedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
    guard let ctx = context else { return }
    vblog("VoiceBar: HID device matched")
    IOHIDDeviceRegisterInputValueCallback(device, hidValueCallback, ctx)
}

private func hidDeviceRemovedCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    device: IOHIDDevice
) {
}

private func hidValueCallback(
    context: UnsafeMutableRawPointer?,
    result: IOReturn,
    sender: UnsafeMutableRawPointer?,
    value: IOHIDValue
) {
    guard let ctx = context else { return }
    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(ctx).takeUnretainedValue()
    monitor.handleHIDValue(value)
}

// MARK: - KeyboardMonitor

final class KeyboardMonitor {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var hiddenWindow: NSWindow?
    private let onKeyDown: () -> Void
    private let onKeyUp: () -> Void

    private(set) var currentTriggerKey: TriggerKey = .fn
    private(set) var hasCGEventTap = false

    // IOKit HID
    private var hidManager: IOHIDManager?

    // CGEvent tap
    private var cgEventTap: CFMachPort?

    // Track trigger key pressed state — used to prevent duplicate onKeyDown/onKeyUp
    // calls when both CGEvent tap and IOKit HID fire for the same physical key press.
    private var isTriggerKeyDown = false

    // Re-entrancy guard — ensures onKeyDown/onKeyUp fire at most once per callback chain
    private var isCallbackInFlight = false

    // When true, keyboard monitoring is temporarily paused (during typing)
    private var isDisabled = false

    init(onKeyDown: @escaping () -> Void, onKeyUp: @escaping () -> Void) {
        self.onKeyDown = onKeyDown
        self.onKeyUp = onKeyUp
        loadSavedTriggerKey()
    }

    private func loadSavedTriggerKey() {
        if let saved = UserDefaults.standard.string(forKey: "VoiceBar.TriggerKey"),
           let key = TriggerKey(rawValue: saved) {
            currentTriggerKey = key
        }
    }

    func setTriggerKey(_ key: TriggerKey) {
        currentTriggerKey = key
        UserDefaults.standard.set(key.rawValue, forKey: "VoiceBar.TriggerKey")
    }

    /// Temporarily disable all keyboard monitoring (used during typing to prevent
    /// VoiceBar's monitors from intercepting CGEvents meant for the target app).
    func setDisabled(_ disabled: Bool) {
        isDisabled = disabled
        vblog("VoiceBar: monitor setDisabled=\(disabled)")
    }

    /// Allow AppDelegate to explicitly set the target PID before the hidden window
    /// takes focus (which would cause frontmostApplication to return VoiceBar).
    private var _explicitTargetPID: pid_t = 0
    var targetPID: pid_t {
        return _explicitTargetPID > 0 ? _explicitTargetPID : (NSWorkspace.shared.frontmostApplication?.processIdentifier ?? 0)
    }

    func setTargetPID(_ pid: pid_t) {
        _explicitTargetPID = pid
        vblog("VoiceBar: explicit targetPID set to \(pid)")
    }

    func start() {
        stop()

        vblog("VoiceBar: Starting with trigger: \(currentTriggerKey.menuLabel)")

        // Try CGEvent session tap (needs Input Monitoring, not Accessibility)

        // Try CGEvent session tap
        startCGEventTap()

        // Also set up IOKit HID (needs Input Monitoring)
        startIOKitHID()

        // Hidden window + local monitor
        setupHiddenWindow()

        // Only set up NSEvent global monitor if CGEvent tap is not active
        // (to avoid race conditions where both fire for the same event)
        if !hasCGEventTap {
            setupGlobalMonitor()
        } else {
            vblog("VoiceBar: Skipping NSEvent global monitor (CGEvent tap active)")
        }
    }

    // MARK: - IOKit HID

    private func startIOKitHID() {
        hidManager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        guard let manager = hidManager else {
            vblog("VoiceBar: IOKit HID: IOHIDManagerCreate returned nil")
            return
        }

        // Match ONLY keyboard devices (usage page 0x07) to avoid seizing mouse/trackpad.
        // Also include Fn key via Generic Desktop page (0x01) usage 0x05.
        let keyboardMatching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_KeyboardOrKeypad
        ]
        IOHIDManagerSetDeviceMatching(manager, keyboardMatching as CFDictionary)

        // Also add Fn key matching (Generic Desktop 0x01, usage 0x05) separately
        let fnMatching: [String: Any] = [
            kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
            kIOHIDDeviceUsageKey: 0x05  // SystemControl / Fn key
        ]
        let matchList: [CFDictionary] = [
            keyboardMatching as CFDictionary,
            fnMatching as CFDictionary
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matchList as CFArray)

        let context = Unmanaged.passUnretained(self).toOpaque()

        IOHIDManagerRegisterDeviceRemovalCallback(manager, hidDeviceRemovedCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, hidDeviceMatchedCallback, context)

        // NEVER use SeizeDevice — it would grab all matched devices (including mouse/trackpad)
        // and break user input. Non-exclusive mode still gives us input callbacks.
        let openResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        if openResult == kIOReturnSuccess {
            vblog("VoiceBar: IOKit HID opened (keyboard-only, non-exclusive)")
        } else {
            vblog("VoiceBar: IOKit HID open failed: \(openResult)")
            hidManager = nil
        }
    }

    fileprivate func handleHIDValue(_ value: IOHIDValue) {
        if isDisabled { return }
        let element = IOHIDValueGetElement(value)
        let usage: UInt32 = IOHIDElementGetUsage(element)
        let usagePage: UInt32 = IOHIDElementGetUsagePage(element)
        let intValue: Int = IOHIDValueGetIntegerValue(value)

        vblog("VoiceBar: HID val page=0x\(String(usagePage, radix:16)) usage=\(usage) val=\(intValue)")

        guard usagePage == kHIDPage_KeyboardOrKeypad || usagePage == kHIDPage_GenericDesktop else { return }

        // IOKit HID reports raw USB HID usage values; CGEvent uses keycodes (0-127).
        // Map the common modifier/function usage ranges to their keycode equivalents.
        let keyCode: Int32
        if usagePage == kHIDPage_KeyboardOrKeypad {
            // Modifier keys: 0xE0-0xE7 map to keycodes 0x00-0x07 (left to right)
            if (0xE0...0xE7).contains(usage) {
                keyCode = Int32(usage - 0xE0)
            } else {
                keyCode = Int32(truncatingIfNeeded: usage)
            }
        } else {
            // Generic Desktop page: Fn is usage 0x05 → keycode 63 (macOS convention)
            if usage == 0x05 {
                keyCode = 63
            } else {
                keyCode = Int32(truncatingIfNeeded: usage)
            }
        }

        if keyCode == currentTriggerKey.keyCode {
            if intValue == 1 {
                if isCallbackInFlight { return }
                let alreadyDown = isTriggerKeyDown
                isTriggerKeyDown = true
                if !alreadyDown {
                    DispatchQueue.main.async { [weak self] in self?.onKeyDown() }
                }
            } else {
                let alreadyUp = !isTriggerKeyDown
                isTriggerKeyDown = false
                if !alreadyUp {
                    DispatchQueue.main.async { [weak self] in self?.onKeyUp() }
                }
            }
        }
    }

    // MARK: - CGEvent Tap

    private func startCGEventTap() {
        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()

        for tapLocRaw in [1, 0, 2] {
            cgEventTap = CGEvent.tapCreate(
                tap: CGEventTapLocation(rawValue: UInt32(tapLocRaw))!,
                place: .headInsertEventTap,
                options: CGEventTapOptions(rawValue: 0)!,
                eventsOfInterest: eventMask,
                callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                    guard let refcon = refcon else { return Unmanaged.passRetained(event) }
                    let monitor = Unmanaged<KeyboardMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    monitor.handleCGEvent(proxy: proxy, type: type, event: event)
                    return Unmanaged.passRetained(event)
                },
                userInfo: context
            )
            if let tap = cgEventTap {
                vblog("VoiceBar: CGEventTap SUCCESS at loc=\(tapLocRaw)")
                let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
                CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
                CGEvent.tapEnable(tap: tap, enable: true)
                hasCGEventTap = true
                return
            }
        }
        vblog("VoiceBar: CGEventTap FAILED - tapCreate returned nil")
    }

    fileprivate func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) {
        if isDisabled { return }
        let keyCode = Int32(event.getIntegerValueField(.keyboardEventKeycode))

        if keyCode == currentTriggerKey.keyCode {
            if type == .flagsChanged {
                // Re-entrancy guard: flagsChanged can fire rapidly multiple times per press
                if isCallbackInFlight { return }
                isCallbackInFlight = true

                if !isTriggerKeyDown {
                    isTriggerKeyDown = true
                    DispatchQueue.main.async { [weak self] in
                        self?.onKeyDown()
                        self?.isCallbackInFlight = false
                    }
                } else {
                    isTriggerKeyDown = false
                    DispatchQueue.main.async { [weak self] in
                        self?.onKeyUp()
                        self?.isCallbackInFlight = false
                    }
                }
            } else if type == .keyDown {
                if isCallbackInFlight { return }
                isCallbackInFlight = true
                let alreadyDown = isTriggerKeyDown
                isTriggerKeyDown = true
                if !alreadyDown {
                    DispatchQueue.main.async { [weak self] in
                        self?.onKeyDown()
                        self?.isCallbackInFlight = false
                    }
                } else {
                    isCallbackInFlight = false
                }
            } else if type == .keyUp {
                let alreadyUp = !isTriggerKeyDown
                isTriggerKeyDown = false
                if !alreadyUp {
                    DispatchQueue.main.async { [weak self] in self?.onKeyUp() }
                }
            }
        }
    }

    // MARK: - Hidden Window

    private func setupHiddenWindow() {
        // Use NSPanel with nonactivating style so it never steals focus
        let window = NSPanel(
            contentRect: NSRect(x: -10000, y: -10000, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.level = .floating
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(nil)
        window.acceptsMouseMovedEvents = false
        self.hiddenWindow = window

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handleNSEvent(event)
            return event
        }

        vblog("VoiceBar: Hidden window + local monitor set up")
    }

    // MARK: - Global NSEvent Monitor

    private func setupGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] event in
            self?.handleNSEvent(event)
        }

        if globalMonitor != nil {
            vblog("VoiceBar: Global monitor started OK")
        } else {
            vblog("VoiceBar: Global monitor FAILED")
        }
    }

    private func handleNSEvent(_ event: NSEvent) {
        if isDisabled { return }
        let keyCode = Int32(event.keyCode)
        let type = event.type

        if keyCode == currentTriggerKey.keyCode {
            if type == .flagsChanged {
                if isCallbackInFlight { return }
                isCallbackInFlight = true

                if !isTriggerKeyDown {
                    isTriggerKeyDown = true
                    onKeyDown()
                    isCallbackInFlight = false
                } else {
                    isTriggerKeyDown = false
                    onKeyUp()
                    isCallbackInFlight = false
                }
            } else if type == .keyDown {
                if isCallbackInFlight { return }
                isCallbackInFlight = true
                let alreadyDown = isTriggerKeyDown
                isTriggerKeyDown = true
                if !alreadyDown {
                    onKeyDown()
                    isCallbackInFlight = false
                } else {
                    isCallbackInFlight = false
                }
            } else if type == .keyUp {
                let alreadyUp = !isTriggerKeyDown
                isTriggerKeyDown = false
                if !alreadyUp {
                    onKeyUp()
                }
            }
        }
    }

    func stop() {
        if let tap = cgEventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            cgEventTap = nil
        }

        if let m = globalMonitor {
            NSEvent.removeMonitor(m)
            globalMonitor = nil
        }

        if let m = localMonitor {
            NSEvent.removeMonitor(m)
            localMonitor = nil
        }

        hiddenWindow?.close()
        hiddenWindow = nil

        if let manager = hidManager {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            hidManager = nil
        }
    }
}

private let vbLogPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("voicebar.log")

private func vblog(_ msg: String) {
    let line = "[\(Date())] \(msg)\n"
    do {
        let handle = try FileHandle(forWritingTo: vbLogPath)
        handle.seekToEndOfFile()
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
        handle.closeFile()
    } catch {
        try? line.write(to: vbLogPath, atomically: true, encoding: .utf8)
    }
}
