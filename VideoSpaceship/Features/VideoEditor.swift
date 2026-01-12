import Foundation
import AVFoundation
import SwiftUI

class VideoEditor: ObservableObject {
    @Published var isEditing = false
    @Published var editProgress: Double = 0
    
    // MARK: - Trim
    
    func trim(
        videoURL: URL,
        startTime: CMTime,
        endTime: CMTime
    ) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed_\(UUID().uuidString).mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoEditorError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = CMTimeRange(start: startTime, end: endTime)
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw exportSession.error ?? VideoEditorError.exportFailed
        }
        
        return outputURL
    }
    
    // MARK: - Split and Cut
    
    func splitAndCut(
        videoURL: URL,
        segments: [TimeRange]
    ) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        let composition = AVMutableComposition()
        
        var insertTime = CMTime.zero
        
        for segment in segments {
            // Add video track
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                
                let timeRange = CMTimeRange(start: segment.start, end: segment.end)
                try compositionVideoTrack?.insertTimeRange(
                    timeRange,
                    of: videoTrack,
                    at: insertTime
                )
            }
            
            // Add audio track
            if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
                let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                
                let timeRange = CMTimeRange(start: segment.start, end: segment.end)
                try compositionAudioTrack?.insertTimeRange(
                    timeRange,
                    of: audioTrack,
                    at: insertTime
                )
            }
            
            let duration = CMTimeSubtract(segment.end, segment.start)
            insertTime = CMTimeAdd(insertTime, duration)
        }
        
        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("edited_\(UUID().uuidString).mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoEditorError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw exportSession.error ?? VideoEditorError.exportFailed
        }
        
        return outputURL
    }
    
    // MARK: - Add Watermark
    
    func addWatermark(
        videoURL: URL,
        watermarkImage: NSImage,
        position: WatermarkPosition,
        opacity: Float
    ) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        let composition = AVMutableComposition()
        
        // Add video and audio tracks
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoEditorError.noVideoTrack
        }
        
        let compositionVideoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        )
        
        let duration = try await asset.load(.duration)
        try compositionVideoTrack?.insertTimeRange(
            CMTimeRange(start: .zero, duration: duration),
            of: videoTrack,
            at: .zero
        )
        
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            let compositionAudioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
            try compositionAudioTrack?.insertTimeRange(
                CMTimeRange(start: .zero, duration: duration),
                of: audioTrack,
                at: .zero
            )
        }
        
        // Create video composition with watermark
        let videoComposition = AVMutableVideoComposition()
        let naturalSize = try await videoTrack.load(.naturalSize)
        videoComposition.renderSize = naturalSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: 30)
        
        // Create instruction
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: duration)
        
        let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack!)
        instruction.layerInstructions = [layerInstruction]
        
        videoComposition.instructions = [instruction]
        
        // Add watermark layer
        let watermarkLayer = CALayer()
        watermarkLayer.contents = watermarkImage
        watermarkLayer.opacity = opacity
        
        let watermarkSize = CGSize(width: 100, height: 100)
        let watermarkPosition = calculateWatermarkPosition(
            position: position,
            videoSize: naturalSize,
            watermarkSize: watermarkSize
        )
        
        watermarkLayer.frame = CGRect(origin: watermarkPosition, size: watermarkSize)
        
        let parentLayer = CALayer()
        let videoLayer = CALayer()
        parentLayer.frame = CGRect(origin: .zero, size: naturalSize)
        videoLayer.frame = CGRect(origin: .zero, size: naturalSize)
        parentLayer.addSublayer(videoLayer)
        parentLayer.addSublayer(watermarkLayer)
        
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: parentLayer
        )
        
        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("watermarked_\(UUID().uuidString).mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoEditorError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.videoComposition = videoComposition
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw exportSession.error ?? VideoEditorError.exportFailed
        }
        
        return outputURL
    }
    
    private func calculateWatermarkPosition(
        position: WatermarkPosition,
        videoSize: CGSize,
        watermarkSize: CGSize
    ) -> CGPoint {
        let padding: CGFloat = 20
        
        switch position {
        case .topLeft:
            return CGPoint(x: padding, y: videoSize.height - watermarkSize.height - padding)
        case .topRight:
            return CGPoint(x: videoSize.width - watermarkSize.width - padding, y: videoSize.height - watermarkSize.height - padding)
        case .bottomLeft:
            return CGPoint(x: padding, y: padding)
        case .bottomRight:
            return CGPoint(x: videoSize.width - watermarkSize.width - padding, y: padding)
        case .center:
            return CGPoint(
                x: (videoSize.width - watermarkSize.width) / 2,
                y: (videoSize.height - watermarkSize.height) / 2
            )
        }
    }
}

// MARK: - Models

struct TimeRange {
    let start: CMTime
    let end: CMTime
}

enum WatermarkPosition {
    case topLeft
    case topRight
    case bottomLeft
    case bottomRight
    case center
}

enum VideoEditorError: LocalizedError {
    case noVideoTrack
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found"
        case .exportFailed:
            return "Failed to export edited video"
        }
    }
}

// MARK: - Timeline Editor View

struct TimelineEditorView: View {
    let recording: Recording
    @StateObject private var editor = VideoEditor()
    @StateObject private var player = VideoPlayerController()
    
    @State private var trimStart: Double = 0
    @State private var trimEnd: Double = 100
    @State private var isExporting = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Video player
            VideoPlayerView(controller: player, videoURL: recording.url)
                .frame(height: 400)
            
            // Timeline
            VStack(spacing: 16) {
                // Playback controls
                HStack {
                    Button {
                        player.togglePlayPause()
                    } label: {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    }
                    
                    Text(formatTime(player.currentTime))
                        .font(.system(.body, design: .monospaced))
                    
                    Slider(value: $player.currentTime, in: 0...recording.duration)
                    
                    Text(formatTime(recording.duration))
                        .font(.system(.body, design: .monospaced))
                }
                .padding()
                
                // Trim controls
                VStack(alignment: .leading, spacing: 8) {
                    Text("Trim")
                        .font(.headline)
                    
                    HStack {
                        Text("Start:")
                        Slider(value: $trimStart, in: 0...100)
                        Text(formatTime(recording.duration * trimStart / 100))
                            .font(.caption)
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Text("End:")
                        Slider(value: $trimEnd, in: 0...100)
                        Text(formatTime(recording.duration * trimEnd / 100))
                            .font(.caption)
                            .monospacedDigit()
                    }
                }
                .padding()
                
                // Export button
                Button {
                    exportTrimmedVideo()
                } label: {
                    if isExporting {
                        ProgressView()
                    } else {
                        Text("Export Trimmed Video")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isExporting)
                .padding()
            }
        }
        .onAppear {
            player.load(url: recording.url)
        }
    }
    
    private func exportTrimmedVideo() {
        isExporting = true
        
        Task {
            do {
                let startTime = CMTime(seconds: recording.duration * trimStart / 100, preferredTimescale: 600)
                let endTime = CMTime(seconds: recording.duration * trimEnd / 100, preferredTimescale: 600)
                
                let outputURL = try await editor.trim(
                    videoURL: recording.url,
                    startTime: startTime,
                    endTime: endTime
                )
                
                // Save trimmed video
                let trimmedRecording = Recording(
                    id: UUID(),
                    title: "\(recording.title) (Trimmed)",
                    url: outputURL,
                    duration: recording.duration * (trimEnd - trimStart) / 100,
                    createdAt: Date(),
                    storageMode: .local
                )
                
                try await RecordingStorage.shared.saveLocal(trimmedRecording)
                
            } catch {
                AppState.shared.showError("Failed to export: \(error.localizedDescription)")
            }
            
            isExporting = false
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Video Player Controller

class VideoPlayerController: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var isPlaying = false
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    
    func load(url: URL) {
        player = AVPlayer(url: url)
        
        // Observe playback time
        timeObserver = player?.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.1, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.currentTime = time.seconds
        }
    }
    
    func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
    }
    
    func seek(to time: Double) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
    
    deinit {
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
        }
    }
}

// MARK: - Video Player View

struct VideoPlayerView: NSViewRepresentable {
    let controller: VideoPlayerController
    let videoURL: URL
    
    func makeNSView(context: Context) -> AVPlayerView {
        let playerView = AVPlayerView()
        playerView.player = controller.player
        playerView.controlsStyle = .none
        return playerView
    }
    
    func updateNSView(_ nsView: AVPlayerView, context: Context) {}
}

import AVKit
