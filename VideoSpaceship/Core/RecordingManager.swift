import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine

@MainActor
class RecordingManager: ObservableObject {
    static let shared = RecordingManager()
    
    @Published var isRecording: Bool = false
    @Published var isPaused: Bool = false
    @Published var recordingDuration: TimeInterval = 0
    @Published var availableScreens: [SCDisplay] = []
    @Published var availableWindows: [SCWindow] = []
    @Published var availableCameras: [AVCaptureDevice] = []
    @Published var availableMicrophones: [AVCaptureDevice] = []
    @Published var availableAudioDevices: [AVCaptureDevice] = []
    
    private var screenRecorder: ScreenRecorder?
    private var cameraRecorder: CameraRecorder?
    private var audioRecorder: AudioRecorder?
    private var videoCompositor: VideoCompositor?
    private var recordingTimer: Timer?
    private var startTime: Date?
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        Task {
            await refreshAvailableDevices()
        }
    }
    
    // MARK: - Device Discovery
    
    func refreshAvailableDevices() async {
        // Get available screens and windows
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            
            self.availableScreens = content.displays
            self.availableWindows = content.windows.filter { window in
                window.title != nil && !window.title!.isEmpty
            }
        } catch {
            print("Failed to get shareable content: \(error)")
        }
        
        // Get available cameras
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        self.availableCameras = discoverySession.devices
        
        // Get available microphones
        let audioDiscoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        self.availableMicrophones = audioDiscoverySession.devices
        
        // Get system audio devices
        self.availableAudioDevices = AVCaptureDevice.devices(for: .audio)
    }
    
    // MARK: - Recording Control
    
    func startQuickRecord() async {
        let preferences = AppState.shared.preferences
        await startRecording(mode: preferences.lastRecordingMode)
    }
    
    func startRecording(mode: RecordingMode, screen: SCDisplay? = nil, window: SCWindow? = nil) async {
        guard !isRecording else { return }
        
        do {
            // Initialize recorders based on mode
            let preferences = AppState.shared.preferences
            
            // Screen recording
            if mode == .screenAndCamera || mode == .screenOnly {
                let targetScreen = screen ?? availableScreens.first
                guard let targetScreen = targetScreen else {
                    throw RecordingError.noScreenAvailable
                }
                
                screenRecorder = ScreenRecorder()
                try await screenRecorder?.start(display: targetScreen, window: window)
            }
            
            // Camera recording
            if mode == .screenAndCamera || mode == .cameraOnly {
                guard let camera = availableCameras.first(where: { $0.uniqueID == preferences.selectedCameraID }) ?? availableCameras.first else {
                    throw RecordingError.noCameraAvailable
                }
                
                cameraRecorder = CameraRecorder()
                try await cameraRecorder?.start(device: camera, backgroundEffect: preferences.pipBackgroundEffect)
            }
            
            // Audio recording
            if preferences.microphoneEnabled || preferences.systemAudioEnabled {
                audioRecorder = AudioRecorder()
                try await audioRecorder?.start(
                    microphone: preferences.microphoneEnabled ? availableMicrophones.first : nil,
                    systemAudio: preferences.systemAudioEnabled
                )
            }
            
            // Start compositor to combine streams
            videoCompositor = VideoCompositor(
                mode: mode,
                pipSettings: PiPSettings(from: preferences)
            )
            
            try await videoCompositor?.start(
                screenRecorder: screenRecorder,
                cameraRecorder: cameraRecorder,
                audioRecorder: audioRecorder
            )
            
            // Update state
            isRecording = true
            startTime = Date()
            startRecordingTimer()
            
        } catch {
            AppState.shared.showError("Failed to start recording: \(error.localizedDescription)")
            await cleanup()
        }
    }
    
    func stopRecording() async {
        guard isRecording else { return }
        
        stopRecordingTimer()
        isRecording = false
        isPaused = false
        
        do {
            // Stop all recorders
            await screenRecorder?.stop()
            await cameraRecorder?.stop()
            await audioRecorder?.stop()
            
            // Finalize video
            guard let outputURL = await videoCompositor?.finalize() else {
                throw RecordingError.compositionFailed
            }
            
            // Process video
            AppState.shared.setProcessing(true)
            let processedURL = try await processVideo(outputURL)
            AppState.shared.setProcessing(false)
            
            // Save or upload
            try await saveRecording(processedURL)
            
            // Cleanup
            await cleanup()
            
        } catch {
            AppState.shared.showError("Failed to stop recording: \(error.localizedDescription)")
            await cleanup()
        }
    }
    
    func togglePause() async {
        guard isRecording else { return }
        
        isPaused.toggle()
        
        if isPaused {
            await screenRecorder?.pause()
            await cameraRecorder?.pause()
            await audioRecorder?.pause()
            stopRecordingTimer()
        } else {
            await screenRecorder?.resume()
            await cameraRecorder?.resume()
            await audioRecorder?.resume()
            startRecordingTimer()
        }
    }
    
    // MARK: - Timer
    
    private func startRecordingTimer() {
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startTime = self.startTime else { return }
            Task { @MainActor in
                self.recordingDuration = Date().timeIntervalSince(startTime)
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
    }
    
    // MARK: - Video Processing
    
    private func processVideo(_ inputURL: URL) async throws -> URL {
        let preferences = AppState.shared.preferences
        
        guard preferences.autoCompress else {
            return inputURL
        }
        
        let processor = VideoProcessor()
        return try await processor.compress(
            inputURL: inputURL,
            quality: preferences.compressionQuality,
            progressHandler: { progress in
                Task { @MainActor in
                    AppState.shared.setProcessing(true, progress: progress)
                }
            }
        )
    }
    
    // MARK: - Save/Upload
    
    private func saveRecording(_ videoURL: URL) async throws {
        let preferences = AppState.shared.preferences
        let recording = Recording(
            id: UUID(),
            title: "Recording \(Date().formatted())",
            url: videoURL,
            duration: recordingDuration,
            createdAt: Date(),
            storageMode: preferences.storageMode
        )
        
        switch preferences.storageMode {
        case .local:
            try await RecordingStorage.shared.saveLocal(recording)
        case .cloud:
            try await RecordingStorage.shared.uploadToCloud(recording, saveBackup: preferences.saveLocalBackup)
        }
    }
    
    // MARK: - Cleanup
    
    func cleanup() async {
        screenRecorder = nil
        cameraRecorder = nil
        audioRecorder = nil
        videoCompositor = nil
        startTime = nil
        recordingDuration = 0
    }
}

// MARK: - Errors

enum RecordingError: LocalizedError {
    case noScreenAvailable
    case noCameraAvailable
    case noMicrophoneAvailable
    case compositionFailed
    case processingFailed
    
    var errorDescription: String? {
        switch self {
        case .noScreenAvailable:
            return "No screen available for recording"
        case .noCameraAvailable:
            return "No camera available for recording"
        case .noMicrophoneAvailable:
            return "No microphone available for recording"
        case .compositionFailed:
            return "Failed to compose video"
        case .processingFailed:
            return "Failed to process video"
        }
    }
}

// MARK: - PiP Settings Helper

struct PiPSettings {
    let position: PiPPosition
    let size: PiPSize
    let shape: PiPShape
    let borderWidth: Double
    let borderColor: NSColor
    let glowEnabled: Bool
    let glowColor: NSColor
    let shadowEnabled: Bool
    let cornerRadius: Double
    let aspectRatio: Double
    let backgroundEffect: BackgroundEffect
    
    init(from preferences: UserPreferences) {
        self.position = preferences.pipPosition
        self.size = preferences.pipSize
        self.shape = preferences.pipShape
        self.borderWidth = preferences.pipBorderWidth
        self.borderColor = preferences.pipBorderColor.nsColor
        self.glowEnabled = preferences.pipGlowEnabled
        self.glowColor = preferences.pipGlowColor.nsColor
        self.shadowEnabled = preferences.pipShadowEnabled
        self.cornerRadius = preferences.pipCornerRadius
        self.aspectRatio = preferences.pipAspectRatio
        self.backgroundEffect = preferences.pipBackgroundEffect
    }
}
