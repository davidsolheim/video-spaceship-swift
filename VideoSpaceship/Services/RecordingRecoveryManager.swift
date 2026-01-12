import Foundation
import AVFoundation

@MainActor
class RecordingRecoveryManager: ObservableObject {
    static let shared = RecordingRecoveryManager()
    
    @Published var recoverableRecordings: [RecoverableRecording] = []
    
    private let recoveryDirectory: URL
    private let chunkInterval: TimeInterval = 30.0 // Save chunks every 30 seconds
    
    private init() {
        let tempDir = FileManager.default.temporaryDirectory
        self.recoveryDirectory = tempDir.appendingPathComponent("VideoSpaceshipRecovery", isDirectory: true)
        
        // Create recovery directory
        try? FileManager.default.createDirectory(at: recoveryDirectory, withIntermediateDirectories: true)
        
        // Scan for recoverable recordings on init
        Task {
            await scanForRecoverableRecordings()
        }
    }
    
    // MARK: - Recording Session Management
    
    func createRecordingSession() -> RecordingSession {
        let sessionID = UUID()
        let sessionDir = recoveryDirectory.appendingPathComponent(sessionID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        
        let metadata = RecordingSessionMetadata(
            id: sessionID,
            startTime: Date(),
            lastChunkIndex: 0,
            isComplete: false
        )
        
        saveMetadata(metadata, to: sessionDir)
        
        return RecordingSession(id: sessionID, directory: sessionDir, metadata: metadata)
    }
    
    func saveChunk(session: RecordingSession, chunkURL: URL, chunkIndex: Int) {
        let chunkDestination = session.directory.appendingPathComponent("chunk_\(chunkIndex).mov")
        
        do {
            if FileManager.default.fileExists(atPath: chunkDestination.path) {
                try FileManager.default.removeItem(at: chunkDestination)
            }
            try FileManager.default.copyItem(at: chunkURL, to: chunkDestination)
            
            // Update metadata
            var metadata = session.metadata
            metadata.lastChunkIndex = chunkIndex
            metadata.lastUpdateTime = Date()
            saveMetadata(metadata, to: session.directory)
            
        } catch {
            print("Failed to save chunk: \(error)")
        }
    }
    
    func markSessionComplete(session: RecordingSession) {
        var metadata = session.metadata
        metadata.isComplete = true
        metadata.endTime = Date()
        saveMetadata(metadata, to: session.directory)
    }
    
    func deleteSession(session: RecordingSession) {
        try? FileManager.default.removeItem(at: session.directory)
    }
    
    // MARK: - Recovery
    
    func scanForRecoverableRecordings() async {
        var recoverable: [RecoverableRecording] = []
        
        guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        
        for sessionDir in sessionDirs {
            guard let metadata = loadMetadata(from: sessionDir) else { continue }
            
            // Skip completed sessions
            if metadata.isComplete { continue }
            
            // Check if session is older than 1 hour (likely crashed)
            let age = Date().timeIntervalSince(metadata.lastUpdateTime ?? metadata.startTime)
            if age < 3600 { continue } // Skip recent sessions
            
            // Count chunks
            let chunks = try? FileManager.default.contentsOfDirectory(at: sessionDir, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "mov" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            guard let chunks = chunks, !chunks.isEmpty else { continue }
            
            let duration = Double(chunks.count) * chunkInterval
            let fileSize = chunks.reduce(0) { size, url in
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                return size + (attrs?[.size] as? Int64 ?? 0)
            }
            
            recoverable.append(RecoverableRecording(
                metadata: metadata,
                directory: sessionDir,
                chunkCount: chunks.count,
                estimatedDuration: duration,
                fileSize: fileSize
            ))
        }
        
        self.recoverableRecordings = recoverable
    }
    
    func recoverRecording(_ recording: RecoverableRecording) async throws -> URL {
        let chunks = try FileManager.default.contentsOfDirectory(at: recording.directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "mov" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        
        guard !chunks.isEmpty else {
            throw RecoveryError.noChunksFound
        }
        
        // If only one chunk, just return it
        if chunks.count == 1 {
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("recovered_\(recording.metadata.id.uuidString).mov")
            try FileManager.default.copyItem(at: chunks[0], to: outputURL)
            return outputURL
        }
        
        // Merge multiple chunks
        return try await mergeChunks(chunks, recordingID: recording.metadata.id)
    }
    
    func discardRecording(_ recording: RecoverableRecording) {
        try? FileManager.default.removeItem(at: recording.directory)
        recoverableRecordings.removeAll { $0.metadata.id == recording.metadata.id }
    }
    
    func cleanOldSessions(olderThan days: Int = 7) {
        guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
            at: recoveryDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        
        let cutoffDate = Date().addingTimeInterval(-Double(days) * 24 * 3600)
        
        for sessionDir in sessionDirs {
            guard let metadata = loadMetadata(from: sessionDir) else { continue }
            
            if metadata.startTime < cutoffDate {
                try? FileManager.default.removeItem(at: sessionDir)
            }
        }
    }
    
    // MARK: - Chunk Merging
    
    private func mergeChunks(_ chunks: [URL], recordingID: UUID) async throws -> URL {
        let composition = AVMutableComposition()
        
        var insertTime = CMTime.zero
        
        for chunkURL in chunks {
            let asset = AVAsset(url: chunkURL)
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
        
        // Export merged composition
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recovered_\(recordingID.uuidString).mov")
        
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        
        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw RecoveryError.exportFailed
        }
        
        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mov
        
        await exportSession.export()
        
        if exportSession.status != .completed {
            throw exportSession.error ?? RecoveryError.exportFailed
        }
        
        return outputURL
    }
    
    // MARK: - Metadata Management
    
    private func saveMetadata(_ metadata: RecordingSessionMetadata, to directory: URL) {
        let metadataURL = directory.appendingPathComponent("metadata.json")
        if let data = try? JSONEncoder().encode(metadata) {
            try? data.write(to: metadataURL)
        }
    }
    
    private func loadMetadata(from directory: URL) -> RecordingSessionMetadata? {
        let metadataURL = directory.appendingPathComponent("metadata.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONDecoder().decode(RecordingSessionMetadata.self, from: data) else {
            return nil
        }
        return metadata
    }
}

// MARK: - Models

struct RecordingSession {
    let id: UUID
    let directory: URL
    var metadata: RecordingSessionMetadata
}

struct RecordingSessionMetadata: Codable {
    let id: UUID
    let startTime: Date
    var lastChunkIndex: Int
    var lastUpdateTime: Date?
    var endTime: Date?
    var isComplete: Bool
}

struct RecoverableRecording: Identifiable {
    let metadata: RecordingSessionMetadata
    let directory: URL
    let chunkCount: Int
    let estimatedDuration: TimeInterval
    let fileSize: Int64
    
    var id: UUID { metadata.id }
    
    var formattedDuration: String {
        let minutes = Int(estimatedDuration) / 60
        let seconds = Int(estimatedDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    var formattedFileSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: metadata.startTime)
    }
}

enum RecoveryError: LocalizedError {
    case noChunksFound
    case exportFailed
    
    var errorDescription: String? {
        switch self {
        case .noChunksFound:
            return "No recording chunks found"
        case .exportFailed:
            return "Failed to merge recording chunks"
        }
    }
}
