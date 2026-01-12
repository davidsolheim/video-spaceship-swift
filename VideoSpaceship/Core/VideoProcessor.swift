import Foundation
import AVFoundation
import VideoToolbox

class VideoProcessor {
    
    /// Compress video with optimal quality and speed balance
    func compress(
        inputURL: URL,
        quality: CompressionQuality,
        progressHandler: @escaping (Double) -> Void
    ) async throws -> URL {
        let asset = AVAsset(url: inputURL)
        
        // Get video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw VideoProcessingError.noVideoTrack
        }
        
        // Get audio tracks
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        
        // Create output URL
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("compressed_\(UUID().uuidString).mp4")
        
        // Remove existing file if present
        try? FileManager.default.removeItem(at: outputURL)
        
        // Create asset reader
        let assetReader = try AVAssetReader(asset: asset)
        
        // Video reader output
        let videoReaderOutput = AVAssetReaderTrackOutput(
            track: videoTrack,
            outputSettings: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            ]
        )
        assetReader.add(videoReaderOutput)
        
        // Audio reader output
        var audioReaderOutput: AVAssetReaderTrackOutput?
        if let audioTrack = audioTracks.first {
            audioReaderOutput = AVAssetReaderTrackOutput(
                track: audioTrack,
                outputSettings: nil  // Pass through
            )
            assetReader.add(audioReaderOutput!)
        }
        
        // Create asset writer
        let assetWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        
        // Video writer input - use hardware encoding
        let videoSettings = try await createVideoSettings(for: videoTrack, quality: quality)
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoWriterInput.expectsMediaDataInRealTime = false
        assetWriter.add(videoWriterInput)
        
        // Audio writer input
        var audioWriterInput: AVAssetWriterInput?
        if audioTracks.first != nil {
            let audioSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 192000
            ]
            audioWriterInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioWriterInput?.expectsMediaDataInRealTime = false
            assetWriter.add(audioWriterInput!)
        }
        
        // Start reading and writing
        assetReader.startReading()
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)
        
        // Get duration for progress tracking
        let duration = try await asset.load(.duration)
        let durationSeconds = CMTimeGetSeconds(duration)
        
        // Process video
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            videoWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "video.processing")) {
                while videoWriterInput.isReadyForMoreMediaData {
                    if let sampleBuffer = videoReaderOutput.copyNextSampleBuffer() {
                        videoWriterInput.append(sampleBuffer)
                        
                        // Update progress
                        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                        let progress = CMTimeGetSeconds(timestamp) / durationSeconds
                        progressHandler(progress * 0.8)  // 80% for video processing
                    } else {
                        videoWriterInput.markAsFinished()
                        break
                    }
                }
                
                if assetReader.status == .completed || assetReader.status == .failed {
                    continuation.resume()
                }
            }
        }
        
        // Process audio
        if let audioWriterInput = audioWriterInput, let audioReaderOutput = audioReaderOutput {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                audioWriterInput.requestMediaDataWhenReady(on: DispatchQueue(label: "audio.processing")) {
                    while audioWriterInput.isReadyForMoreMediaData {
                        if let sampleBuffer = audioReaderOutput.copyNextSampleBuffer() {
                            audioWriterInput.append(sampleBuffer)
                            progressHandler(0.8 + 0.1)  // 90% total
                        } else {
                            audioWriterInput.markAsFinished()
                            break
                        }
                    }
                    continuation.resume()
                }
            }
        }
        
        // Finish writing
        await assetWriter.finishWriting()
        progressHandler(1.0)
        
        if assetWriter.status == .completed {
            return outputURL
        } else if let error = assetWriter.error {
            throw error
        } else {
            throw VideoProcessingError.compressionFailed
        }
    }
    
    private func createVideoSettings(for track: AVAssetTrack, quality: CompressionQuality) async throws -> [String: Any] {
        let naturalSize = try await track.load(.naturalSize)
        let width = Int(naturalSize.width)
        let height = Int(naturalSize.height)
        
        var compressionProperties: [String: Any] = [
            AVVideoExpectedSourceFrameRateKey: 60,
            AVVideoMaxKeyFrameIntervalKey: 60,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ]
        
        // Set bitrate based on quality
        if quality != .lossless {
            compressionProperties[AVVideoAverageBitRateKey] = quality.bitrate
        }
        
        // Use hardware acceleration when available
        let codec: AVVideoCodecType
        if quality == .lossless {
            codec = .hevc  // HEVC supports lossless
        } else {
            codec = .h264  // H.264 for compatibility
        }
        
        return [
            AVVideoCodecKey: codec,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
    }
    
    /// Merge multiple video files
    func merge(videos: [URL], outputURL: URL) async throws {
        let composition = AVMutableComposition()
        
        var insertTime = CMTime.zero
        
        for videoURL in videos {
            let asset = AVAsset(url: videoURL)
            let duration = try await asset.load(.duration)
            
            // Add video track
            if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
                let compositionVideoTrack = composition.addMutableTrack(
                    withMediaType: .video,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                )
                try compositionVideoTrack?.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
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
                try compositionAudioTrack?.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: audioTrack,
                    at: insertTime
                )
            }
            
            insertTime = CMTimeAdd(insertTime, duration)
        }
        
        // Export
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw VideoProcessingError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw exportSession.error ?? VideoProcessingError.exportFailed
        }
    }
    
    /// Extract thumbnail from video
    func extractThumbnail(from videoURL: URL, at time: CMTime = .zero) async throws -> NSImage {
        let asset = AVAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.requestedTimeToleranceAfter = .zero
        imageGenerator.requestedTimeToleranceBefore = .zero
        
        let cgImage = try await imageGenerator.image(at: time).image
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

// MARK: - Errors

enum VideoProcessingError: LocalizedError {
    case noVideoTrack
    case compressionFailed
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "No video track found in input file"
        case .compressionFailed:
            return "Video compression failed"
        case .exportFailed:
            return "Video export failed"
        }
    }
}
