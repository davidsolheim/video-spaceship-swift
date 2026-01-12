import Foundation

@MainActor
class RecordingStorage: ObservableObject {
    static let shared = RecordingStorage()
    
    @Published var recordings: [Recording] = []
    @Published var uploadProgress: [UUID: Double] = [:]
    
    private let recordingsKey = "SavedRecordings"
    
    private init() {
        loadRecordings()
    }
    
    // MARK: - Local Storage
    
    func saveLocal(_ recording: Recording) async throws {
        let preferences = AppState.shared.preferences
        let savePath = URL(fileURLWithPath: preferences.localSavePath)
        
        // Ensure directory exists
        try FileManager.default.createDirectory(at: savePath, withIntermediateDirectories: true)
        
        // Copy file to save location
        let fileName = "\(recording.title)_\(recording.id.uuidString).mp4"
        let destinationURL = savePath.appendingPathComponent(fileName)
        
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        
        try FileManager.default.copyItem(at: recording.url, to: destinationURL)
        
        // Update recording with new URL
        var updatedRecording = recording
        updatedRecording.url = destinationURL
        
        // Get file size
        let attributes = try FileManager.default.attributesOfItem(atPath: destinationURL.path)
        updatedRecording.fileSize = attributes[.size] as? Int64
        
        // Save to list
        recordings.append(updatedRecording)
        saveRecordings()
        
        // Clean up temp file
        try? FileManager.default.removeItem(at: recording.url)
    }
    
    func deleteLocal(_ recording: Recording) async throws {
        // Remove file
        if FileManager.default.fileExists(atPath: recording.url.path) {
            try FileManager.default.removeItem(at: recording.url)
        }
        
        // Remove from list
        recordings.removeAll { $0.id == recording.id }
        saveRecordings()
    }
    
    // MARK: - Cloud Storage
    
    func uploadToCloud(_ recording: Recording, saveBackup: Bool) async throws {
        guard let authToken = AuthenticationManager.shared.authToken else {
            throw StorageError.notAuthenticated
        }
        
        let apiBaseURL = AppState.shared.preferences.apiBaseURL
        
        // Step 1: Request presigned URL
        guard let presignedURL = try await requestPresignedURL(apiBaseURL: apiBaseURL, token: authToken, recording: recording) else {
            throw StorageError.uploadFailed
        }
        
        // Step 2: Upload file
        try await uploadFile(recording.url, to: presignedURL, recordingID: recording.id)
        
        // Step 3: Confirm upload
        let cloudURL = try await confirmUpload(apiBaseURL: apiBaseURL, token: authToken, recording: recording)
        
        // Update recording
        var updatedRecording = recording
        updatedRecording.cloudURL = cloudURL
        
        if saveBackup {
            // Save local copy
            try await saveLocal(updatedRecording)
        } else {
            // Just add to list
            recordings.append(updatedRecording)
            saveRecordings()
            
            // Clean up temp file
            try? FileManager.default.removeItem(at: recording.url)
        }
    }
    
    private func requestPresignedURL(apiBaseURL: String, token: String, recording: Recording) async throws -> URL? {
        guard let url = URL(string: "\(apiBaseURL)/api/recordings/upload/presign") else { return nil }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "title": recording.title,
            "duration": recording.duration,
            "fileSize": recording.fileSize ?? 0
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StorageError.uploadFailed
        }
        
        let result = try JSONDecoder().decode([String: String].self, from: data)
        return result["presignedURL"].flatMap { URL(string: $0) }
    }
    
    private func uploadFile(_ fileURL: URL, to presignedURL: URL, recordingID: UUID) async throws {
        let fileData = try Data(contentsOf: fileURL)
        
        var request = URLRequest(url: presignedURL)
        request.httpMethod = "PUT"
        request.setValue("video/mp4", forHTTPHeaderField: "Content-Type")
        
        // Upload with progress tracking
        let session = URLSession.shared
        
        let (_, response) = try await session.upload(for: request, from: fileData, delegate: UploadDelegate(recordingID: recordingID, storage: self))
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw StorageError.uploadFailed
        }
    }
    
    private func confirmUpload(apiBaseURL: String, token: String, recording: Recording) async throws -> URL {
        guard let url = URL(string: "\(apiBaseURL)/api/recordings/upload/confirm") else {
            throw StorageError.uploadFailed
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "recordingId": recording.id.uuidString,
            "title": recording.title
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw StorageError.uploadFailed
        }
        
        let result = try JSONDecoder().decode([String: String].self, from: data)
        guard let urlString = result["url"], let cloudURL = URL(string: urlString) else {
            throw StorageError.uploadFailed
        }
        
        return cloudURL
    }
    
    // MARK: - Persistence
    
    private func loadRecordings() {
        guard let data = UserDefaults.standard.data(forKey: recordingsKey),
              let recordings = try? JSONDecoder().decode([Recording].self, from: data) else {
            return
        }
        self.recordings = recordings
    }
    
    private func saveRecordings() {
        if let data = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(data, forKey: recordingsKey)
        }
    }
}

// MARK: - Upload Delegate

class UploadDelegate: NSObject, URLSessionTaskDelegate {
    let recordingID: UUID
    weak var storage: RecordingStorage?
    
    init(recordingID: UUID, storage: RecordingStorage) {
        self.recordingID = recordingID
        self.storage = storage
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        Task { @MainActor in
            storage?.uploadProgress[recordingID] = progress
        }
    }
}

// MARK: - Errors

enum StorageError: LocalizedError {
    case notAuthenticated
    case uploadFailed
    case downloadFailed
    case fileNotFound
    
    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "You must be signed in to upload to cloud"
        case .uploadFailed:
            return "Failed to upload recording to cloud"
        case .downloadFailed:
            return "Failed to download recording from cloud"
        case .fileNotFound:
            return "Recording file not found"
        }
    }
}
