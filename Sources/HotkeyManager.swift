import Carbon
import Cocoa
import CoreGraphics

final class HotkeyManager {
    var onToggleRecord: (() -> Void)?
    var onCycleLanguage: (() -> Void)?
    var onCancelRecord: (() -> Void)?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    // nil key code = modifier-only hotkey (keyCode 0 is "a", so it can't be a sentinel)
    fileprivate var recordKeyCode: CGKeyCode?
    fileprivate var recordModifiers: CGEventFlags = []
    fileprivate var langKeyCode: CGKeyCode?
    fileprivate var langModifiers: CGEventFlags = []
    private var recordArmed = false
    private var langArmed = false

    private static let relevantFlags: CGEventFlags = [.maskAlternate, .maskShift, .maskCommand, .maskControl]

    // macOS virtual key codes
    private static let keycodeMap: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26,
        "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38,
        "k": 40, "n": 45, "m": 46,
        "space": 49, "escape": 53,
    ]

    private static let modifierMap: [String: CGEventFlags] = [
        "alt": .maskAlternate,
        "shift": .maskShift,
        "cmd": .maskCommand,
        "ctrl": .maskControl,
    ]

    private func log(_ msg: String) {
        let line = "[\(Date())] \(msg)\n"
        let path = "/tmp/malgeul.log"
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(line.data(using: .utf8)!)
            handle.closeFile()
        } else {
            FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
        }
    }

    init() {}

    func configure(recordHotkey: String, langHotkey: String) {
        let (rKey, rMod) = Self.parseHotkey(recordHotkey)
        let (lKey, lMod) = Self.parseHotkey(langHotkey)
        recordKeyCode = rKey
        recordModifiers = rMod
        langKeyCode = lKey
        langModifiers = lMod
        recordArmed = false
        langArmed = false
    }

    func start() {
        stop()

        let trusted = checkAccessibilityPermission()
        log("Accessibility trusted: \(trusted)")

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)

        // Use Unmanaged to pass self to C callback
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: hotkeyCallback,
            userInfo: selfPointer
        ) else {
            log("defaultTap failed, trying listenOnly")
            // If event tap fails, try listen-only mode
            guard let listenTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,
                eventsOfInterest: mask,
                callback: hotkeyCallback,
                userInfo: selfPointer
            ) else {
                log("listenOnly tap also failed!")
                return
            }
            log("listenOnly tap created successfully")
            eventTap = listenTap
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, listenTap, 0)
            runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: listenTap, enable: true)
            return
        }
        log("defaultTap created successfully")

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
    }

    func checkAccessibilityPermission() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeRetainedValue(): true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        return trusted
    }

    /// Returns true if the event was consumed (should not reach the focused app).
    fileprivate func handleKeyEvent(_ keyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        let maskedFlags = flags.intersection(Self.relevantFlags)

        // Any key press while a modifier-only hotkey is armed cancels it (e.g. ⌃⌥+X shortcuts)
        recordArmed = false
        langArmed = false

        // Escape cancels recording (not swallowed)
        if keyCode == 53 {
            DispatchQueue.main.async { [weak self] in
                self?.onCancelRecord?()
            }
            return false
        }

        // Record hotkey
        if let key = recordKeyCode, keyCode == key && maskedFlags == recordModifiers {
            DispatchQueue.main.async { [weak self] in
                self?.onToggleRecord?()
            }
            return true
        }

        // Language hotkey
        if let key = langKeyCode, keyCode == key && maskedFlags == langModifiers {
            DispatchQueue.main.async { [weak self] in
                self?.onCycleLanguage?()
            }
            return true
        }
        return false
    }

    fileprivate func handleFlagsChanged(flags: CGEventFlags) {
        let maskedFlags = flags.intersection(Self.relevantFlags)

        if recordKeyCode == nil, Self.updateModifierOnly(maskedFlags, hotkey: recordModifiers, armed: &recordArmed) {
            DispatchQueue.main.async { [weak self] in
                self?.onToggleRecord?()
            }
        }
        if langKeyCode == nil, Self.updateModifierOnly(maskedFlags, hotkey: langModifiers, armed: &langArmed) {
            DispatchQueue.main.async { [weak self] in
                self?.onCycleLanguage?()
            }
        }
    }

    /// Arm when flags equal the hotkey modifiers; fire when all are released while armed.
    private static func updateModifierOnly(_ flags: CGEventFlags, hotkey: CGEventFlags, armed: inout Bool) -> Bool {
        guard !hotkey.isEmpty else { return false }
        if armed {
            if flags.isEmpty {
                armed = false
                return true
            }
            // Partial release of the hotkey modifiers keeps it armed; anything else disarms
            if flags != hotkey && !(flags.isSubset(of: hotkey)) {
                armed = false
            }
            return false
        }
        if flags == hotkey { armed = true }
        return false
    }

    private static func parseHotkey(_ hotkey: String) -> (CGKeyCode?, CGEventFlags) {
        let parts = hotkey.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var modifiers: CGEventFlags = []
        var keyCode: CGKeyCode?

        for part in parts {
            if let mod = modifierMap[part] {
                modifiers.insert(mod)
            } else if let code = keycodeMap[part] {
                keyCode = code
            }
        }
        return (keyCode, modifiers)
    }
}

// C callback for CGEvent tap
private func hotkeyCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passRetained(event) }

    // Re-enable tap if it gets disabled
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
        if let tap = manager.eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
        return Unmanaged.passRetained(event)
    }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()

    if type == .flagsChanged {
        manager.handleFlagsChanged(flags: event.flags)
        return Unmanaged.passRetained(event)
    }

    guard type == .keyDown else { return Unmanaged.passRetained(event) }

    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    // Swallow matched hotkeys (no effect for the listen-only fallback tap)
    if manager.handleKeyEvent(keyCode, flags: flags) {
        return nil
    }

    return Unmanaged.passRetained(event)
}
