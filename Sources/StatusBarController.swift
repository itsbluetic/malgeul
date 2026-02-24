import AppKit
import UserNotifications
import Combine

final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem!
    private let audioRecorder = AudioRecorder()
    private let sonioxService = SonioxService()
    private let hotkeyManager = HotkeyManager()
    private let configManager = ConfigManager.shared
    private let soundManager = SoundManager.shared

    private var transcriptionHistory: [String] = []
    private var cancellables = Set<AnyCancellable>()

    private let langBadge: [String: String] = ["ko": "KR", "en": "EN"]
    private let langNames: [String: String] = ["ko": "한국어", "en": "English"]

    override init() {
        super.init()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusTitle()

        requestNotificationPermission()
        setupHotkeys()
        buildMenu()

        // Observe recording state
        audioRecorder.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.buildMenu()
            }
            .store(in: &cancellables)
    }

    // MARK: - Status Title

    private func updateStatusTitle() {
        let badge = langBadge[configManager.config.language] ?? configManager.config.language.uppercased()
        statusItem.button?.title = "🎤\(badge)"
    }

    private func setStatusTitle(_ emoji: String) {
        let badge = langBadge[configManager.config.language] ?? configManager.config.language.uppercased()
        statusItem.button?.title = "\(emoji)\(badge)"
    }

    // MARK: - Menu

    private func buildMenu() {
        let menu = NSMenu()

        let config = configManager.config
        let isRecording = audioRecorder.isRecording

        // Record toggle
        let recordTitle = isRecording ? "🔴 녹음 중지" : "🎤 녹음 시작"
        let hotkeyLabel = formatHotkey(config.recordHotkey)
        let recordItem = NSMenuItem(
            title: "\(recordTitle)       \(hotkeyLabel)",
            action: #selector(toggleRecording),
            keyEquivalent: ""
        )
        recordItem.target = self
        menu.addItem(recordItem)

        menu.addItem(.separator())

        // Language display
        let langName = langNames[config.language] ?? config.language
        let langHotkeyLabel = formatHotkey(config.langHotkey)
        let langItem = NSMenuItem(
            title: "전사 언어: \(langName)   \(langHotkeyLabel)",
            action: #selector(cycleLanguage),
            keyEquivalent: ""
        )
        langItem.target = self
        menu.addItem(langItem)

        // Auto paste toggle
        let autoPasteItem = NSMenuItem(
            title: "\(config.autoPaste ? "✓" : "  ") 자동 붙여넣기",
            action: #selector(toggleAutoPaste),
            keyEquivalent: ""
        )
        autoPasteItem.target = self
        menu.addItem(autoPasteItem)

        menu.addItem(.separator())

        // History submenu
        let historyItem = NSMenuItem(title: "최근 전사", action: nil, keyEquivalent: "")
        let historyMenu = NSMenu()
        if transcriptionHistory.isEmpty {
            let emptyItem = NSMenuItem(title: "(비어있음)", action: nil, keyEquivalent: "")
            historyMenu.addItem(emptyItem)
        } else {
            for (index, text) in transcriptionHistory.enumerated() {
                let display = text.count > 30 ? String(text.prefix(30)) + "..." : text
                let item = NSMenuItem(
                    title: display,
                    action: #selector(copyHistoryItem(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.tag = index
                historyMenu.addItem(item)
            }
        }
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)

        menu.addItem(.separator())

        // Settings submenu
        let settingsItem = NSMenuItem(title: "환경설정", action: nil, keyEquivalent: "")
        let settingsMenu = NSMenu()

        // Hotkey settings
        let hotkeyItem = NSMenuItem(title: "녹음 단축키 설정", action: nil, keyEquivalent: "")
        let hotkeyMenu = NSMenu()
        let hotkeys: [(String, String)] = [
            ("alt+s", "⌥S"), ("alt+r", "⌥R"), ("alt+m", "⌥M"),
            ("ctrl+s", "⌃S"), ("ctrl+r", "⌃R"),
        ]
        for (key, label) in hotkeys {
            let check = config.recordHotkey == key ? "✓ " : "   "
            let item = NSMenuItem(
                title: "\(check)\(label)",
                action: #selector(setRecordHotkey(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = key
            hotkeyMenu.addItem(item)
        }
        hotkeyItem.submenu = hotkeyMenu
        settingsMenu.addItem(hotkeyItem)

        // Language settings
        let langSettingItem = NSMenuItem(title: "전사 언어", action: nil, keyEquivalent: "")
        let langMenu = NSMenu()
        let languages: [(String, String)] = [("ko", "한국어"), ("en", "English")]
        for (code, name) in languages {
            let check = config.language == code ? "✓ " : "   "
            let item = NSMenuItem(
                title: "\(check)\(name)",
                action: #selector(setLanguage(_:)),
                keyEquivalent: ""
            )
            item.target = self
            item.representedObject = code
            langMenu.addItem(item)
        }
        langSettingItem.submenu = langMenu
        settingsMenu.addItem(langSettingItem)

        // Sound feedback
        let soundItem = NSMenuItem(
            title: "사운드 피드백 [\(config.soundFeedback ? "✓" : " ")]",
            action: #selector(toggleSoundFeedback),
            keyEquivalent: ""
        )
        soundItem.target = self
        settingsMenu.addItem(soundItem)

        settingsItem.submenu = settingsMenu
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Malgeul 종료",
            action: #selector(quitApp),
            keyEquivalent: ""
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    // MARK: - Hotkey Formatting

    private func formatHotkey(_ hotkey: String) -> String {
        guard !hotkey.isEmpty else { return "-" }
        var result = hotkey.lowercased()
        let replacements: [(String, String)] = [
            ("cmd", "⌘"), ("shift", "⇧"), ("alt", "⌥"),
            ("ctrl", "⌃"), ("space", "Space"), ("+", ""),
        ]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }
        return result
    }

    // MARK: - Hotkeys Setup

    private func setupHotkeys() {
        let config = configManager.config
        hotkeyManager.configure(recordHotkey: config.recordHotkey, langHotkey: config.langHotkey)

        hotkeyManager.onToggleRecord = { [weak self] in
            self?.toggleRecording()
        }

        hotkeyManager.onCycleLanguage = { [weak self] in
            self?.cycleLanguage()
        }

        hotkeyManager.onCancelRecord = { [weak self] in
            self?.cancelRecording()
        }

        hotkeyManager.start()
    }

    // MARK: - Recording Actions

    @objc private func toggleRecording() {
        if audioRecorder.isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        do {
            try audioRecorder.startRecording()
            setStatusTitle("🔴")
            soundManager.playRecordStart()
        } catch {
            showNotification(title: "오디오 오류", body: error.localizedDescription)
        }
    }

    private func stopRecording() {
        setStatusTitle("⏳")
        soundManager.playRecordStop()

        let audioData = audioRecorder.stopRecording()

        guard !audioData.isEmpty else {
            updateStatusTitle()
            return
        }

        let apiKey = configManager.config.sonioxApiKey
        let language = configManager.config.language

        Task {
            await transcribeAndPaste(audioData: audioData, apiKey: apiKey, language: language)
        }
    }

    @objc private func cancelRecording() {
        guard audioRecorder.isRecording else { return }
        audioRecorder.cancelRecording()
        soundManager.playCancel()
        updateStatusTitle()
        showNotification(title: "음성 인식", body: "녹음이 취소되었습니다.")
    }

    // MARK: - Transcription

    private func transcribeAndPaste(audioData: Data, apiKey: String, language: String) async {
        do {
            let text = try await sonioxService.transcribe(
                audioData: audioData,
                apiKey: apiKey,
                language: language
            )

            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

            await MainActor.run {
                if !trimmed.isEmpty {
                    // Add to history
                    transcriptionHistory.insert(trimmed, at: 0)
                    if transcriptionHistory.count > 10 {
                        transcriptionHistory = Array(transcriptionHistory.prefix(10))
                    }

                    // Copy to clipboard
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(trimmed, forType: .string)

                    // Auto paste
                    if configManager.config.autoPaste {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                            self?.simulatePaste()
                        }
                    }

                    soundManager.playTranscribeComplete()

                    // Show checkmark then revert
                    setStatusTitle("✅")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                        self?.updateStatusTitle()
                        self?.buildMenu()
                    }
                } else {
                    showNotification(title: "음성 인식", body: "인식된 텍스트가 없습니다.")
                    updateStatusTitle()
                    buildMenu()
                }
            }
        } catch {
            await MainActor.run {
                soundManager.playError()
                let message = String(error.localizedDescription.prefix(160))
                showNotification(title: "오류", body: message)
                updateStatusTitle()
                buildMenu()
            }
        }
    }

    // MARK: - Auto Paste (Cmd+V simulation)

    private func simulatePaste() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cghidEventTap)
    }

    // MARK: - Settings Actions

    @objc private func cycleLanguage() {
        let order = ["ko", "en"]
        let current = configManager.config.language
        let currentIndex = order.firstIndex(of: current) ?? 0
        let next = order[(currentIndex + 1) % order.count]

        configManager.update { $0.language = next }
        updateStatusTitle()
        buildMenu()
        let name = langNames[next] ?? next
        showNotification(title: "음성 인식", body: "전사 언어 전환: \(name)")
    }

    @objc private func toggleAutoPaste() {
        let current = configManager.config.autoPaste
        configManager.update { $0.autoPaste = !current }
        buildMenu()
        let status = configManager.config.autoPaste ? "활성화" : "비활성화"
        showNotification(title: "자동 붙여넣기", body: "\(status)되었습니다.")
    }

    @objc private func toggleSoundFeedback() {
        let current = configManager.config.soundFeedback
        configManager.update { $0.soundFeedback = !current }
        buildMenu()
        let status = configManager.config.soundFeedback ? "활성화" : "비활성화"
        showNotification(title: "사운드 피드백", body: "\(status)되었습니다.")
    }

    @objc private func setRecordHotkey(_ sender: NSMenuItem) {
        guard let hotkey = sender.representedObject as? String else { return }
        configManager.update { $0.recordHotkey = hotkey }
        hotkeyManager.configure(
            recordHotkey: configManager.config.recordHotkey,
            langHotkey: configManager.config.langHotkey
        )
        hotkeyManager.start()
        buildMenu()
        showNotification(title: "음성 인식", body: "녹음 단축키: \(formatHotkey(hotkey))")
    }

    @objc private func setLanguage(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? String else { return }
        configManager.update { $0.language = lang }
        updateStatusTitle()
        buildMenu()
        let name = langNames[lang] ?? lang
        showNotification(title: "음성 인식", body: "전사 언어: \(name)")
    }

    @objc private func copyHistoryItem(_ sender: NSMenuItem) {
        let index = sender.tag
        guard index < transcriptionHistory.count else { return }
        let text = transcriptionHistory[index]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        let preview = text.count > 30 ? String(text.prefix(30)) + "..." : text
        showNotification(title: "클립보드 복사", body: "복사됨: \(preview)")
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Quit

    @objc private func quitApp() {
        hotkeyManager.stop()
        NSApp.terminate(nil)
    }
}
