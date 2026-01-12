import Foundation
import AVFoundation

struct QualityPreset: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String
    let codec: VideoCodec
    let bitrate: Int // in kbps
    let resolution: Resolution?
    let frameRate: Int?
    let audioQuality: AudioQuality
    
    init(
        id: UUID = UUID(),
        name: String,
        description: String,
        codec: VideoCodec,
        bitrate: Int,
        resolution: Resolution? = nil,
        frameRate: Int? = nil,
        audioQuality: AudioQuality = .high
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.codec = codec
        self.bitrate = bitrate
        self.resolution = resolution
        self.frameRate = frameRate
        self.audioQuality = audioQuality
    }
    
    var estimatedFileSize: String {
        // Rough estimate: bitrate * duration / 8 (to convert to bytes)
        // For 1 minute of video
        let bytesPerMinute = (bitrate * 1000 * 60) / 8
        let mbPerMinute = Double(bytesPerMinute) / (1024 * 1024)
        return String(format: "~%.1f MB/min", mbPerMinute)
    }
}

enum VideoCodec: String, Codable, CaseIterable {
    case h264 = "H.264"
    case hevc = "HEVC (H.265)"
    case prores = "ProRes"
    
    var avCodec: AVVideoCodecType {
        switch self {
        case .h264: return .h264
        case .hevc: return .hevc
        case .prores: return .proRes422
        }
    }
    
    var fileExtension: String {
        switch self {
        case .h264, .hevc: return "mp4"
        case .prores: return "mov"
        }
    }
}

struct Resolution: Codable, Equatable {
    let width: Int
    let height: Int
    
    var displayName: String {
        switch (width, height) {
        case (3840, 2160): return "4K (3840×2160)"
        case (2560, 1440): return "2K (2560×1440)"
        case (1920, 1080): return "1080p (1920×1080)"
        case (1280, 720): return "720p (1280×720)"
        case (854, 480): return "480p (854×480)"
        default: return "\(width)×\(height)"
        }
    }
    
    static let uhd4k = Resolution(width: 3840, height: 2160)
    static let qhd = Resolution(width: 2560, height: 1440)
    static let fullHD = Resolution(width: 1920, height: 1080)
    static let hd = Resolution(width: 1280, height: 720)
    static let sd = Resolution(width: 854, height: 480)
}

enum AudioQuality: String, Codable, CaseIterable {
    case low = "Low (64 kbps)"
    case medium = "Medium (128 kbps)"
    case high = "High (192 kbps)"
    case veryHigh = "Very High (256 kbps)"
    
    var bitrate: Int {
        switch self {
        case .low: return 64000
        case .medium: return 128000
        case .high: return 192000
        case .veryHigh: return 256000
        }
    }
}

// MARK: - Built-in Presets

extension QualityPreset {
    static let web = QualityPreset(
        name: "Web",
        description: "Optimized for web sharing (small file size)",
        codec: .h264,
        bitrate: 2000,
        resolution: .hd,
        frameRate: 30,
        audioQuality: .medium
    )
    
    static let standard = QualityPreset(
        name: "Standard",
        description: "Balanced quality and file size",
        codec: .h264,
        bitrate: 5000,
        resolution: .fullHD,
        frameRate: 30,
        audioQuality: .high
    )
    
    static let high = QualityPreset(
        name: "High",
        description: "High quality for presentations",
        codec: .h264,
        bitrate: 10000,
        resolution: .fullHD,
        frameRate: 60,
        audioQuality: .veryHigh
    )
    
    static let ultra = QualityPreset(
        name: "Ultra",
        description: "Maximum quality with HEVC compression",
        codec: .hevc,
        bitrate: 15000,
        resolution: .qhd,
        frameRate: 60,
        audioQuality: .veryHigh
    )
    
    static let fourK = QualityPreset(
        name: "4K",
        description: "4K resolution with HEVC",
        codec: .hevc,
        bitrate: 25000,
        resolution: .uhd4k,
        frameRate: 60,
        audioQuality: .veryHigh
    )
    
    static let lossless = QualityPreset(
        name: "Lossless",
        description: "ProRes for editing (very large files)",
        codec: .prores,
        bitrate: 100000,
        audioQuality: .veryHigh
    )
    
    static let builtInPresets: [QualityPreset] = [
        .web, .standard, .high, .ultra, .fourK, .lossless
    ]
}

// MARK: - Custom Preset Builder

struct CustomPresetBuilder {
    var name: String = "Custom"
    var codec: VideoCodec = .h264
    var bitrate: Int = 5000
    var resolution: Resolution? = nil
    var frameRate: Int? = nil
    var audioQuality: AudioQuality = .high
    
    func build() -> QualityPreset {
        let description = buildDescription()
        return QualityPreset(
            name: name,
            description: description,
            codec: codec,
            bitrate: bitrate,
            resolution: resolution,
            frameRate: frameRate,
            audioQuality: audioQuality
        )
    }
    
    private func buildDescription() -> String {
        var parts: [String] = []
        
        if let resolution = resolution {
            parts.append(resolution.displayName)
        }
        
        if let frameRate = frameRate {
            parts.append("\(frameRate) fps")
        }
        
        parts.append("\(bitrate / 1000) Mbps")
        parts.append(codec.rawValue)
        
        return parts.joined(separator: ", ")
    }
}

// MARK: - Quality Preset Manager

class QualityPresetManager: ObservableObject {
    static let shared = QualityPresetManager()
    
    @Published var customPresets: [QualityPreset] = []
    
    var allPresets: [QualityPreset] {
        QualityPreset.builtInPresets + customPresets
    }
    
    private init() {
        loadCustomPresets()
    }
    
    func addCustomPreset(_ preset: QualityPreset) {
        customPresets.append(preset)
        saveCustomPresets()
    }
    
    func removeCustomPreset(_ preset: QualityPreset) {
        customPresets.removeAll { $0.id == preset.id }
        saveCustomPresets()
    }
    
    private func loadCustomPresets() {
        if let data = UserDefaults.standard.data(forKey: "CustomQualityPresets"),
           let presets = try? JSONDecoder().decode([QualityPreset].self, from: data) {
            customPresets = presets
        }
    }
    
    private func saveCustomPresets() {
        if let data = try? JSONEncoder().encode(customPresets) {
            UserDefaults.standard.set(data, forKey: "CustomQualityPresets")
        }
    }
}

// MARK: - Quality Preset Picker View

struct QualityPresetPicker: View {
    @Binding var selectedPreset: QualityPreset
    @StateObject private var manager = QualityPresetManager.shared
    @State private var showCustomBuilder = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Quality Preset")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showCustomBuilder = true
                } label: {
                    Label("Custom", systemImage: "plus.circle")
                }
            }
            
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(manager.allPresets) { preset in
                        PresetCard(
                            preset: preset,
                            isSelected: selectedPreset.id == preset.id
                        )
                        .onTapGesture {
                            selectedPreset = preset
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCustomBuilder) {
            CustomPresetBuilderView { preset in
                manager.addCustomPreset(preset)
                selectedPreset = preset
                showCustomBuilder = false
            }
        }
    }
}

struct PresetCard: View {
    let preset: QualityPreset
    let isSelected: Bool
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(preset.name)
                    .font(.headline)
                
                Text(preset.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(preset.estimatedFileSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
                )
        )
    }
}

struct CustomPresetBuilderView: View {
    let onSave: (QualityPreset) -> Void
    
    @State private var builder = CustomPresetBuilder()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Create Custom Preset")
                .font(.title2)
                .fontWeight(.bold)
            
            Form {
                TextField("Name", text: $builder.name)
                
                Picker("Codec", selection: $builder.codec) {
                    ForEach(VideoCodec.allCases, id: \.self) { codec in
                        Text(codec.rawValue).tag(codec)
                    }
                }
                
                HStack {
                    Text("Bitrate (Mbps)")
                    Slider(value: Binding(
                        get: { Double(builder.bitrate) / 1000 },
                        set: { builder.bitrate = Int($0 * 1000) }
                    ), in: 1...50)
                    Text("\(builder.bitrate / 1000)")
                        .monospacedDigit()
                }
                
                Picker("Audio Quality", selection: $builder.audioQuality) {
                    ForEach(AudioQuality.allCases, id: \.self) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
            }
            .padding()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                
                Spacer()
                
                Button("Save") {
                    onSave(builder.build())
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 400)
        .padding()
    }
}
