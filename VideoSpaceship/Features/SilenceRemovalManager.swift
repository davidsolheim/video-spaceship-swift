import Foundation
import AVFoundation

class SilenceRemovalManager: ObservableObject {
    static let shared = SilenceRemovalManager()
    
    @Published var isProcessing = false
    @Published var processingProgress: Double = 0
    
    private init() {}
    
    // MARK: - Silence Detection
    
    func detectSilentSegments(
        videoURL: URL,
        threshold: Float = 0.01,
        minDuration: TimeInterval = 1.0
    ) async throws -> [SilentSegment] {
        let asset = AVAsset(url: videoURL)
        
        guard let audioTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw SilenceRemovalError.noAudioTrack
        }
        
        let reader = try AVAssetReader(asset: asset)
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]
        
        let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
        reader.add(output)
        reader.startReading()
        
        var silentSegments: [SilentSegment] = []
        var currentTime: Double = 0
        var silenceStart: Double?
        let sampleRate: Double = 44100.0
        
        while let sampleBuffer = output.copyNextSampleBuffer() {
            if let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) {
                let length = CMBlockBufferGetDataLength(blockBuffer)
                var data = Data(count: length)
                
                data.withUnsafeMutableBytes { ptr in
                    CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: ptr.baseAddress!)
                }
                
                let samples = data.withUnsafeBytes { $0.bindMemory(to: Int16.self) }
                let avgLevel = calculateAverageLevel(samples: Array(samples))
                
                if avgLevel < threshold {
                    if silenceStart == nil {
                        silenceStart = currentTime
                    }
                } else {
                    if let start = silenceStart {
                        let duration = currentTime - start
                        if duration >= minDuration {
                            silentSegments.append(SilentSegment(
                                startTime: start,
                                endTime: currentTime,
                                averageLevel: avgLevel
                            ))
                        }
                        silenceStart = nil
                    }
                }
                
                currentTime += Double(samples.count) / sampleRate
            }
        }
        
        // Handle silence at the end
        if let start = silenceStart {
            let duration = currentTime - start
            if duration >= minDuration {
                silentSegments.append(SilentSegment(
                    startTime: start,
                    endTime: currentTime,
                    averageLevel: 0
                ))
            }
        }
        
        return silentSegments
    }
    
    // MARK: - Silence Removal
    
    func removeSilence(
        from videoURL: URL,
        silentSegments: [SilentSegment],
        keepPadding: TimeInterval = 0.3
    ) async throws -> URL {
        isProcessing = true
        processingProgress = 0
        
        defer {
            isProcessing = false
        }
        
        let asset = AVAsset(url: videoURL)
        let duration = try await asset.load(.duration)
        
        // Create segments to keep (inverse of silent segments)
        let keepSegments = createKeepSegments(
            totalDuration: duration.seconds,
            silentSegments: silentSegments,
            padding: keepPadding
        )
        
        // Build composition
        let composition = AVMutableComposition()
        var insertTime = CMTime.zero
        
        for (index, segment) in keepSegments.enumerated() {
            // Add video track
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: segment.start, preferredTimescale: 600),
                    end: CMTime(seconds: segment.end, preferredTimescale: 600)
                )
                
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
                
                let timeRange = CMTimeRange(
                    start: CMTime(seconds: segment.start, preferredTimescale: 600),
                    end: CMTime(seconds: segment.end, preferredTimescale: 600)
                )
                
                try compositionAudioTrack?.insertTimeRange(
                    timeRange,
                    of: audioTrack,
                    at: insertTime
                )
            }
            
            let segmentDuration = CMTime(seconds: segment.end - segment.start, preferredTimescale: 600)
            insertTime = CMTimeAdd(insertTime, segmentDuration)
            
            processingProgress = Double(index + 1) / Double(keepSegments.count)
        }
        
        // Export
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("silence_removed_\(UUID().uuidString).mp4")
        
        try? FileManager.default.removeItem(at: outputURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw SilenceRemovalError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw exportSession.error ?? SilenceRemovalError.exportFailed
        }
        
        return outputURL
    }
    
    // MARK: - Helper Methods
    
    private func calculateAverageLevel(samples: [Int16]) -> Float {
        let sum = samples.reduce(0.0) { $0 + abs(Float($1)) }
        return sum / Float(samples.count) / Float(Int16.max)
    }
    
    private func createKeepSegments(
        totalDuration: TimeInterval,
        silentSegments: [SilentSegment],
        padding: TimeInterval
    ) -> [TimeSegment] {
        var keepSegments: [TimeSegment] = []
        var currentTime: TimeInterval = 0
        
        for silentSegment in silentSegments.sorted(by: { $0.startTime < $1.startTime }) {
            // Add segment before silence (with padding)
            let segmentEnd = max(currentTime, silentSegment.startTime - padding)
            if segmentEnd > currentTime {
                keepSegments.append(TimeSegment(start: currentTime, end: segmentEnd))
            }
            
            // Skip to end of silence (with padding)
            currentTime = min(totalDuration, silentSegment.endTime + padding)
        }
        
        // Add final segment
        if currentTime < totalDuration {
            keepSegments.append(TimeSegment(start: currentTime, end: totalDuration))
        }
        
        return keepSegments
    }
    
    // MARK: - Statistics
    
    func calculateStatistics(
        originalDuration: TimeInterval,
        silentSegments: [SilentSegment]
    ) -> RemovalStatistics {
        let totalSilence = silentSegments.reduce(0) { $0 + ($1.endTime - $1.startTime) }
        let newDuration = originalDuration - totalSilence
        let percentageRemoved = (totalSilence / originalDuration) * 100
        
        return RemovalStatistics(
            originalDuration: originalDuration,
            newDuration: newDuration,
            silenceRemoved: totalSilence,
            percentageRemoved: percentageRemoved,
            segmentCount: silentSegments.count
        )
    }
}

// MARK: - Models

struct SilentSegment: Identifiable {
    let id = UUID()
    let startTime: TimeInterval
    let endTime: TimeInterval
    let averageLevel: Float
    
    var duration: TimeInterval {
        endTime - startTime
    }
    
    var formattedDuration: String {
        String(format: "%.1fs", duration)
    }
}

struct TimeSegment {
    let start: TimeInterval
    let end: TimeInterval
}

struct RemovalStatistics {
    let originalDuration: TimeInterval
    let newDuration: TimeInterval
    let silenceRemoved: TimeInterval
    let percentageRemoved: Double
    let segmentCount: Int
    
    var timeSaved: String {
        let minutes = Int(silenceRemoved) / 60
        let seconds = Int(silenceRemoved) % 60
        return "\(minutes)m \(seconds)s"
    }
}

enum SilenceRemovalError: LocalizedError {
    case noAudioTrack
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "No audio track found in video"
        case .exportFailed:
            return "Failed to export processed video"
        }
    }
}

// MARK: - Silence Removal View

import SwiftUI

struct SilenceRemovalView: View {
    let recording: Recording
    
    @StateObject private var manager = SilenceRemovalManager.shared
    @State private var silentSegments: [SilentSegment] = []
    @State private var statistics: RemovalStatistics?
    @State private var isAnalyzing = false
    @State private var threshold: Float = 0.01
    @State private var minDuration: Double = 1.0
    @State private var keepPadding: Double = 0.3
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Silence Removal")
                .font(.title2)
                .fontWeight(.bold)
            
            // Settings
            GroupBox("Detection Settings") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Threshold:")
                        Slider(value: $threshold, in: 0.001...0.1)
                        Text(String(format: "%.3f", threshold))
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Text("Min Duration:")
                        Slider(value: $minDuration, in: 0.5...5.0)
                        Text(String(format: "%.1fs", minDuration))
                            .monospacedDigit()
                    }
                    
                    HStack {
                        Text("Keep Padding:")
                        Slider(value: $keepPadding, in: 0...1.0)
                        Text(String(format: "%.1fs", keepPadding))
                            .monospacedDigit()
                    }
                }
                .padding()
            }
            
            // Analyze button
            Button {
                analyzeSilence()
            } label: {
                if isAnalyzing {
                    ProgressView()
                } else {
                    Text("Analyze Silence")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isAnalyzing)
            
            // Results
            if let stats = statistics {
                GroupBox("Statistics") {
                    VStack(alignment: .leading, spacing: 8) {
                        StatRow(label: "Original Duration", value: formatDuration(stats.originalDuration))
                        StatRow(label: "New Duration", value: formatDuration(stats.newDuration))
                        StatRow(label: "Time Saved", value: stats.timeSaved)
                        StatRow(label: "Percentage Removed", value: String(format: "%.1f%%", stats.percentageRemoved))
                        StatRow(label: "Silent Segments", value: "\(stats.segmentCount)")
                    }
                    .padding()
                }
            }
            
            // Segments list
            if !silentSegments.isEmpty {
                Text("Silent Segments")
                    .font(.headline)
                
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(silentSegments) { segment in
                            SilentSegmentRow(segment: segment)
                        }
                    }
                }
                
                Button {
                    removeSilence()
                } label: {
                    if manager.isProcessing {
                        ProgressView(value: manager.processingProgress)
                            .frame(width: 200)
                    } else {
                        Text("Remove Silence")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.isProcessing)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func analyzeSilence() {
        isAnalyzing = true
        
        Task {
            do {
                silentSegments = try await manager.detectSilentSegments(
                    videoURL: recording.url,
                    threshold: threshold,
                    minDuration: minDuration
                )
                
                statistics = manager.calculateStatistics(
                    originalDuration: recording.duration,
                    silentSegments: silentSegments
                )
            } catch {
                AppState.shared.showError("Failed to analyze: \(error.localizedDescription)")
            }
            
            isAnalyzing = false
        }
    }
    
    private func removeSilence() {
        Task {
            do {
                let outputURL = try await manager.removeSilence(
                    from: recording.url,
                    silentSegments: silentSegments,
                    keepPadding: keepPadding
                )
                
                // Save as new recording
                let newRecording = Recording(
                    id: UUID(),
                    title: "\(recording.title) (Silence Removed)",
                    url: outputURL,
                    duration: statistics?.newDuration ?? recording.duration,
                    createdAt: Date(),
                    storageMode: .local
                )
                
                try await RecordingStorage.shared.saveLocal(newRecording)
                
                AppState.shared.showSuccess("Silence removed successfully!")
                
            } catch {
                AppState.shared.showError("Failed to remove silence: \(error.localizedDescription)")
            }
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

struct StatRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

struct SilentSegmentRow: View {
    let segment: SilentSegment
    
    var body: some View {
        HStack {
            Text(formatTime(segment.startTime))
                .font(.caption)
                .monospacedDigit()
            
            Text("→")
                .foregroundColor(.secondary)
            
            Text(formatTime(segment.endTime))
                .font(.caption)
                .monospacedDigit()
            
            Spacer()
            
            Text(segment.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(4)
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
