import Foundation

struct UserPreferences: Codable {
    // Recording preferences
    var lastRecordingMode: RecordingMode = .screenAndCamera
    var selectedCameraID: String?
    var selectedMicrophoneID: String?
    var selectedScreenID: UInt32?
    
    // PiP preferences
    var pipPosition: PiPPosition = .bottomRight
    var pipSize: PiPSize = .medium
    var pipShape: PiPShape = .circle
    var pipBorderWidth: Double = 3.0
    var pipBorderColor: CodableColor = CodableColor(.white)
    var pipGlowEnabled: Bool = false
    var pipGlowColor: CodableColor = CodableColor(.blue)
    var pipShadowEnabled: Bool = true
    var pipBackgroundEffect: BackgroundEffect = .none
    var pipCornerRadius: Double = 20.0
    var pipAspectRatio: Double = 1.0
    
    // Audio preferences
    var systemAudioEnabled: Bool = true
    var microphoneEnabled: Bool = true
    var audioMixerSettings: [String: AudioChannelSettings] = [:]
    
    // Storage preferences
    var storageMode: StorageMode = .local
    var localSavePath: String = NSSearchPathForDirectoriesInDomains(.moviesDirectory, .userDomainMask, true).first ?? ""
    var saveLocalBackup: Bool = true
    
    // Processing preferences
    var compressionQuality: CompressionQuality = .high
    var autoCompress: Bool = true
    
    // API configuration
    var apiBaseURL: String = "https://videospaceship.com"
    
    // UI preferences
    var countdownDuration: Int = 3
    var showFloatingControls: Bool = true
    
    static func load() -> UserPreferences {
        guard let data = UserDefaults.standard.data(forKey: "UserPreferences"),
              let preferences = try? JSONDecoder().decode(UserPreferences.self, from: data) else {
            return UserPreferences()
        }
        return preferences
    }
    
    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: "UserPreferences")
        }
    }
}

// MARK: - Enums

enum RecordingMode: String, Codable, CaseIterable {
    case screenAndCamera = "Screen + Camera"
    case screenOnly = "Screen Only"
    case cameraOnly = "Camera Only"
}

enum PiPPosition: String, Codable, CaseIterable {
    case topLeft = "Top Left"
    case topRight = "Top Right"
    case bottomLeft = "Bottom Left"
    case bottomRight = "Bottom Right"
}

enum PiPSize: String, Codable, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    
    var scale: Double {
        switch self {
        case .small: return 0.15
        case .medium: return 0.20
        case .large: return 0.25
        }
    }
}

enum PiPShape: String, Codable, CaseIterable {
    case circle = "Circle"
    case roundedRectangle = "Rounded Rectangle"
    case square = "Square"
}

enum BackgroundEffect: String, Codable, CaseIterable {
    case none = "None"
    case blur = "Blur"
    case remove = "Remove"
}

enum StorageMode: String, Codable, CaseIterable {
    case local = "Local"
    case cloud = "Cloud"
}

enum CompressionQuality: String, Codable, CaseIterable {
    case low = "Low"
    case medium = "Medium"
    case high = "High"
    case lossless = "Lossless"
    
    var bitrate: Int {
        switch self {
        case .low: return 2_000_000      // 2 Mbps
        case .medium: return 5_000_000   // 5 Mbps
        case .high: return 10_000_000    // 10 Mbps
        case .lossless: return 0         // Use lossless codec
        }
    }
}

struct AudioChannelSettings: Codable {
    var volume: Float = 1.0
    var isMuted: Bool = false
    var isSolo: Bool = false
}

// Helper for encoding/decoding Color
struct CodableColor: Codable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double
    
    init(_ nsColor: NSColor) {
        let color = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
        self.red = color.redComponent
        self.green = color.greenComponent
        self.blue = color.blueComponent
        self.alpha = color.alphaComponent
    }
    
    var nsColor: NSColor {
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }
}

import AppKit
