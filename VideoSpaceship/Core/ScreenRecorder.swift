import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

class ScreenRecorder: NSObject {
    private var stream: SCStream?
    private var streamOutput: ScreenRecorderOutput?
    private var isCapturing = false
    private var isPaused = false
    
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var audioWriterInput: AVAssetWriterInput?
    
    private let outputURL: URL
    private var startTime: CMTime?
    
    init() {
        // Create temporary output file
        let tempDir = FileManager.default.temporaryDirectory
        self.outputURL = tempDir.appendingPathComponent("screen_\(UUID().uuidString).mov")
        super.init()
    }
    
    func start(display: SCDisplay, window: SCWindow? = nil) async throws {
        // Create content filter
        let filter: SCContentFilter
        if let window = window {
            filter = SCContentFilter(desktopIndependentWindow: window)
        } else {
            filter = SCContentFilter(display: display, excludingWindows: [])
        }
        
        // Configure stream
        let configuration = SCStreamConfiguration()
        configuration.width = Int(display.width) * 2  // Retina resolution
        configuration.height = Int(display.height) * 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)  // 60 FPS
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.showsCursor = true
        configuration.capturesAudio = true
        configuration.sampleRate = 48000
        configuration.channelCount = 2
        
        // Create stream
        stream = SCStream(filter: filter, configuration: configuration, delegate: nil)
        
        // Create output handler
        streamOutput = ScreenRecorderOutput(recorder: self)
        
        // Add stream output
        try stream?.addStreamOutput(streamOutput!, type: .screen, sampleHandlerQueue: .global(qos: .userInitiated))
        try stream?.addStreamOutput(streamOutput!, type: .audio, sampleHandlerQueue: .global(qos: .userInitiated))
        
        // Setup video writer
        try setupVideoWriter(width: configuration.width, height: configuration.height)
        
        // Start capture
        try await stream?.startCapture()
        isCapturing = true
    }
    
    func stop() async {
        guard isCapturing else { return }
        
        isCapturing = false
        
        // Stop stream
        try? await stream?.stopCapture()
        
        // Finalize video writer
        await finishWriting()
    }
    
    func pause() async {
        isPaused = true
    }
    
    func resume() async {
        isPaused = false
    }
    
    func getOutputURL() -> URL {
        return outputURL
    }
    
    // MARK: - Video Writer Setup
    
    private func setupVideoWriter(width: Int, height: Int) throws {
        // Create asset writer
        videoWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mov)
        
        // Video input settings
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 20_000_000,  // 20 Mbps for high quality
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoExpectedSourceFrameRateKey: 60,
            ]
        ]
        
        videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput?.expectsMediaDataInRealTime = true
        
        if let videoWriterInput = videoWriterInput, videoWriter?.canAdd(videoWriterInput) == true {
            videoWriter?.add(videoWriterInput)
        }
        
        // Audio input settings
        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 192000
        ]
        
        audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        audioWriterInput?.expectsMediaDataInRealTime = true
        
        if let audioWriterInput = audioWriterInput, videoWriter?.canAdd(audioWriterInput) == true {
            videoWriter?.add(audioWriterInput)
        }
        
        // Start writing session
        videoWriter?.startWriting()
    }
    
    // MARK: - Sample Buffer Handling
    
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, type: SCStreamOutputType) {
        guard isCapturing, !isPaused else { return }
        guard let videoWriter = videoWriter else { return }
        
        // Start session with first sample
        if startTime == nil {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            startTime = timestamp
            videoWriter.startSession(atSourceTime: timestamp)
        }
        
        switch type {
        case .screen:
            if let videoWriterInput = videoWriterInput, videoWriterInput.isReadyForMoreMediaData {
                videoWriterInput.append(sampleBuffer)
            }
        case .audio:
            if let audioWriterInput = audioWriterInput, audioWriterInput.isReadyForMoreMediaData {
                audioWriterInput.append(sampleBuffer)
            }
        @unknown default:
            break
        }
    }
    
    private func finishWriting() async {
        guard let videoWriter = videoWriter else { return }
        
        videoWriterInput?.markAsFinished()
        audioWriterInput?.markAsFinished()
        
        await videoWriter.finishWriting()
        
        self.videoWriter = nil
        self.videoWriterInput = nil
        self.audioWriterInput = nil
    }
}

// MARK: - Stream Output Handler

class ScreenRecorderOutput: NSObject, SCStreamOutput {
    weak var recorder: ScreenRecorder?
    
    init(recorder: ScreenRecorder) {
        self.recorder = recorder
    }
    
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        recorder?.processSampleBuffer(sampleBuffer, type: type)
    }
}
