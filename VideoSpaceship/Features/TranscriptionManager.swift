import Foundation
import Speech
import AVFoundation

class TranscriptionManager: ObservableObject {
    static let shared = TranscriptionManager()
    
    @Published var isTranscribing = false
    @Published var transcriptionProgress: Double = 0
    
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    private init() {
        requestAuthorization()
    }
    
    // MARK: - Authorization
    
    func requestAuthorization() {
        SFSpeechRecognizer.requestAuthorization { status in
            switch status {
            case .authorized:
                print("Speech recognition authorized")
            case .denied, .restricted, .notDetermined:
                print("Speech recognition not authorized: \(status)")
            @unknown default:
                break
            }
        }
    }
    
    // MARK: - Transcription
    
    func transcribe(recording: Recording) async throws -> Transcription {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerUnavailable
        }
        
        isTranscribing = true
        transcriptionProgress = 0
        
        defer {
            isTranscribing = false
        }
        
        // Extract audio from video
        let audioURL = try await extractAudio(from: recording.url)
        
        // Perform recognition
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                if let result = result, result.isFinal {
                    let segments = self.createSegments(from: result)
                    let transcription = Transcription(
                        id: UUID(),
                        recordingID: recording.id,
                        text: result.bestTranscription.formattedString,
                        segments: segments,
                        createdAt: Date()
                    )
                    continuation.resume(returning: transcription)
                }
            }
        }
    }
    
    private func createSegments(from result: SFSpeechRecognitionResult) -> [TranscriptionSegment] {
        let transcription = result.bestTranscription
        var segments: [TranscriptionSegment] = []
        
        for segment in transcription.segments {
            let transcriptSegment = TranscriptionSegment(
                text: segment.substring,
                startTime: segment.timestamp,
                duration: segment.duration,
                confidence: segment.confidence
            )
            segments.append(transcriptSegment)
        }
        
        return segments
    }
    
    // MARK: - Audio Extraction
    
    private func extractAudio(from videoURL: URL) async throws -> URL {
        let asset = AVAsset(url: videoURL)
        
        let audioURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("audio_\(UUID().uuidString).m4a")
        
        try? FileManager.default.removeItem(at: audioURL)
        
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw TranscriptionError.audioExtractionFailed
        }
        
        exportSession.outputURL = audioURL
        exportSession.outputFileType = .m4a
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw exportSession.error ?? TranscriptionError.audioExtractionFailed
        }
        
        return audioURL
    }
    
    // MARK: - Export
    
    func exportSRT(transcription: Transcription) throws -> URL {
        let srtURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript_\(transcription.id.uuidString).srt")
        
        var srtContent = ""
        
        for (index, segment) in transcription.segments.enumerated() {
            let startTime = formatSRTTime(segment.startTime)
            let endTime = formatSRTTime(segment.startTime + segment.duration)
            
            srtContent += "\(index + 1)\n"
            srtContent += "\(startTime) --> \(endTime)\n"
            srtContent += "\(segment.text)\n\n"
        }
        
        try srtContent.write(to: srtURL, atomically: true, encoding: .utf8)
        
        return srtURL
    }
    
    func exportVTT(transcription: Transcription) throws -> URL {
        let vttURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript_\(transcription.id.uuidString).vtt")
        
        var vttContent = "WEBVTT\n\n"
        
        for segment in transcription.segments {
            let startTime = formatVTTTime(segment.startTime)
            let endTime = formatVTTTime(segment.startTime + segment.duration)
            
            vttContent += "\(startTime) --> \(endTime)\n"
            vttContent += "\(segment.text)\n\n"
        }
        
        try vttContent.write(to: vttURL, atomically: true, encoding: .utf8)
        
        return vttURL
    }
    
    func exportPlainText(transcription: Transcription) throws -> URL {
        let txtURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("transcript_\(transcription.id.uuidString).txt")
        
        try transcription.text.write(to: txtURL, atomically: true, encoding: .utf8)
        
        return txtURL
    }
    
    // MARK: - Time Formatting
    
    private func formatSRTTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, milliseconds)
    }
    
    private func formatVTTTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 1000)
        
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, seconds, milliseconds)
    }
}

// MARK: - Models

struct Transcription: Identifiable, Codable {
    let id: UUID
    let recordingID: UUID
    let text: String
    let segments: [TranscriptionSegment]
    let createdAt: Date
}

struct TranscriptionSegment: Codable {
    let text: String
    let startTime: TimeInterval
    let duration: TimeInterval
    let confidence: Float
}

enum TranscriptionError: LocalizedError {
    case recognizerUnavailable
    case audioExtractionFailed
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .recognizerUnavailable:
            return "Speech recognizer is not available"
        case .audioExtractionFailed:
            return "Failed to extract audio from video"
        case .exportFailed:
            return "Failed to export transcription"
        }
    }
}
