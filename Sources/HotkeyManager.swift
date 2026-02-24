import Carbon
import Cocoa
import CoreGraphics

final class HotkeyManager {
    var onToggleRecord: (() -> Void)?
    var onCycleLanguage: (() -> Void)?
    var onCancelRecord: (() -> Void)?

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    fileprivate var recordKeyCode: CGKeyCode = 0
    fileprivate var recordModifiers: CGEventFlags = []
    fileprivate var langKeyCode: CGKeyCode = 0
    fileprivate var langModifiers: CGEventFlags = []

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
        let path = "/tmp/myspeak-swift.log"
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
    }

    func start() {
        stop()

        let trusted = checkAccessibilityPermission()
        log("Accessibility trusted: \(trusted)")

        let mask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

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

    fileprivate func handleKeyEvent(_ keyCode: CGKeyCode, flags: CGEventFlags) {
        // Mask to only modifier keys we care about
        let relevantFlags: CGEventFlags = [.maskAlternate, .maskShift, .maskCommand, .maskControl]
        let maskedFlags = flags.intersection(relevantFlags)

        // Escape cancels recording
        if keyCode == 53 {
            DispatchQueue.main.async { [weak self] in
                self?.onCancelRecord?()
            }
            return
        }

        // Record hotkey
        if keyCode == recordKeyCode && maskedFlags == recordModifiers {
            DispatchQueue.main.async { [weak self] in
                self?.onToggleRecord?()
            }
            return
        }

        // Language hotkey
        if keyCode == langKeyCode && maskedFlags == langModifiers {
            DispatchQueue.main.async { [weak self] in
                self?.onCycleLanguage?()
            }
            return
        }
    }

    private static func parseHotkey(_ hotkey: String) -> (CGKeyCode, CGEventFlags) {
        let parts = hotkey.lowercased().split(separator: "+").map { $0.trimmingCharacters(in: .whitespaces) }
        var modifiers: CGEventFlags = []
        var keyCode: CGKeyCode = 0

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

    guard type == .keyDown else { return Unmanaged.passRetained(event) }

    let manager = Unmanaged<HotkeyManager>.fromOpaque(userInfo).takeUnretainedValue()
    let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
    let flags = event.flags

    manager.handleKeyEvent(keyCode, flags: flags)

    return Unmanaged.passRetained(event)
}
