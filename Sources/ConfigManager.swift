import Foundation

struct AppConfig: Codable {
    var recordHotkey: String
    var langHotkey: String
    var language: String
    var model: String
    var sttEngine: String
    var sonioxApiKey: String
    var autoPaste: Bool
    var soundFeedback: Bool

    enum CodingKeys: String, CodingKey {
        case recordHotkey = "record_hotkey"
        case langHotkey = "lang_hotkey"
        case language
        case model
        case sttEngine = "stt_engine"
        case sonioxApiKey = "soniox_api_key"
        case autoPaste = "auto_paste"
        case soundFeedback = "sound_feedback"
    }

    static let defaultConfig = AppConfig(
        recordHotkey: "alt+s",
        langHotkey: "alt+l",
        language: "ko",
        model: "mlx-community/whisper-large-v3-turbo",
        sttEngine: "soniox",
        sonioxApiKey: "",
        autoPaste: true,
        soundFeedback: true
    )
}

final class ConfigManager {
    static let shared = ConfigManager()

    private let configPath: URL
    private(set) var config: AppConfig

    private init() {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configDir = homeDir.appendingPathComponent(".config/voice-recorder")
        self.configPath = configDir.appendingPathComponent("config.json")
        self.config = AppConfig.defaultConfig
        load()
    }

    func load() {
        guard FileManager.default.fileExists(atPath: configPath.path) else {
            save()
            return
        }
        do {
            let data = try Data(contentsOf: configPath)
            // Decode into a dictionary first to merge with defaults
            let decoder = JSONDecoder()
            var loaded = try decoder.decode(AppConfig.self, from: data)

            // Handle legacy "hotkey" key
            if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if dict["record_hotkey"] == nil, let legacy = dict["hotkey"] as? String {
                    loaded.recordHotkey = legacy
                }
            }

            config = loaded
        } catch {
            // If decoding fails, try partial merge with defaults
            if let data = try? Data(contentsOf: configPath),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let defaults = AppConfig.defaultConfig
                config = AppConfig(
                    recordHotkey: dict["record_hotkey"] as? String ?? dict["hotkey"] as? String ?? defaults.recordHotkey,
                    langHotkey: dict["lang_hotkey"] as? String ?? defaults.langHotkey,
                    language: dict["language"] as? String ?? defaults.language,
                    model: dict["model"] as? String ?? defaults.model,
                    sttEngine: dict["stt_engine"] as? String ?? defaults.sttEngine,
                    sonioxApiKey: dict["soniox_api_key"] as? String ?? defaults.sonioxApiKey,
                    autoPaste: dict["auto_paste"] as? Bool ?? defaults.autoPaste,
                    soundFeedback: dict["sound_feedback"] as? Bool ?? defaults.soundFeedback
                )
            }
            save()
        }

        // Ensure required fields are not empty
        if config.recordHotkey.isEmpty {
            config.recordHotkey = AppConfig.defaultConfig.recordHotkey
        }
        if config.langHotkey.isEmpty {
            config.langHotkey = AppConfig.defaultConfig.langHotkey
        }
    }

    func save() {
        let dir = configPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configPath)
        }
    }

    func update(_ modify: (inout AppConfig) -> Void) {
        modify(&config)
        save()
    }
}
