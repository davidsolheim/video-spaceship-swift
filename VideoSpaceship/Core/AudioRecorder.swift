import Foundation
import AVFoundation
import CoreAudio

class AudioRecorder: NSObject {
    private var microphoneSession: AVCaptureSession?
    private var audioOutput: AVCaptureAudioDataOutput?
    private var sampleBufferDelegate: AudioSampleBufferDelegate?
    
    private var isCapturing = false
    private var isPaused = false
    
    // Audio mixing
    private var audioMixer: AVAudioMixerNode?
    private var audioEngine: AVAudioEngine?
    
    // Sample buffer callback
    var onSampleBuffer: ((CMSampleBuffer) -> Void)?
    
    func start(microphone: AVCaptureDevice?, systemAudio: Bool) async throws {
        if let microphone = microphone {
            try await startMicrophoneCapture(device: microphone)
        }
        
        if systemAudio {
            try await startSystemAudioCapture()
        }
        
        isCapturing = true
    }
    
    func stop() async {
        guard isCapturing else { return }
        
        isCapturing = false
        
        microphoneSession?.stopRunning()
        microphoneSession = nil
        
        audioEngine?.stop()
        audioEngine = nil
    }
    
    func pause() async {
        isPaused = true
    }
    
    func resume() async {
        isPaused = false
    }
    
    // MARK: - Microphone Capture
    
    private func startMicrophoneCapture(device: AVCaptureDevice) async throws {
        microphoneSession = AVCaptureSession()
        guard let microphoneSession = microphoneSession else { return }
        
        microphoneSession.beginConfiguration()
        
        // Add audio input
        let audioInput = try AVCaptureDeviceInput(device: device)
        if microphoneSession.canAddInput(audioInput) {
            microphoneSession.addInput(audioInput)
        }
        
        // Add audio output
        audioOutput = AVCaptureAudioDataOutput()
        let queue = DispatchQueue(label: "com.videospaceship.audio", qos: .userInitiated)
        sampleBufferDelegate = AudioSampleBufferDelegate(recorder: self)
        audioOutput?.setSampleBufferDelegate(sampleBufferDelegate, queue: queue)
        
        if let audioOutput = audioOutput, microphoneSession.canAddOutput(audioOutput) {
            microphoneSession.addOutput(audioOutput)
        }
        
        microphoneSession.commitConfiguration()
        microphoneSession.startRunning()
    }
    
    // MARK: - System Audio Capture
    
    private func startSystemAudioCapture() async throws {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        // Get system audio tap
        // Note: This requires screen recording permission on macOS
        // System audio is captured through ScreenCaptureKit's audio stream
        // This is a placeholder for additional audio processing if needed
        
        audioMixer = audioEngine.mainMixerNode
        
        try audioEngine.start()
    }
    
    // MARK: - Sample Buffer Processing
    
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard isCapturing, !isPaused else { return }
        
        // Send to compositor
        onSampleBuffer?(sampleBuffer)
    }
}

// MARK: - Sample Buffer Delegate

class AudioSampleBufferDelegate: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    weak var recorder: AudioRecorder?
    
    init(recorder: AudioRecorder) {
        self.recorder = recorder
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        recorder?.processSampleBuffer(sampleBuffer)
    }
}

// MARK: - Audio Mixer

class AudioMixer {
    private let audioEngine = AVAudioEngine()
    private var playerNodes: [String: AVAudioPlayerNode] = [:]
    private var volumeNodes: [String: AVAudioMixerNode] = [:]
    
    func addSource(id: String, audioFile: AVAudioFile) {
        let playerNode = AVAudioPlayerNode()
        let volumeNode = AVAudioMixerNode()
        
        audioEngine.attach(playerNode)
        audioEngine.attach(volumeNode)
        
        audioEngine.connect(playerNode, to: volumeNode, format: audioFile.processingFormat)
        audioEngine.connect(volumeNode, to: audioEngine.mainMixerNode, format: audioFile.processingFormat)
        
        playerNodes[id] = playerNode
        volumeNodes[id] = volumeNode
        
        playerNode.scheduleFile(audioFile, at: nil)
    }
    
    func setVolume(id: String, volume: Float) {
        volumeNodes[id]?.outputVolume = volume
    }
    
    func setMuted(id: String, muted: Bool) {
        volumeNodes[id]?.outputVolume = muted ? 0.0 : 1.0
    }
    
    func start() throws {
        try audioEngine.start()
        playerNodes.values.forEach { $0.play() }
    }
    
    func stop() {
        playerNodes.values.forEach { $0.stop() }
        audioEngine.stop()
    }
}
