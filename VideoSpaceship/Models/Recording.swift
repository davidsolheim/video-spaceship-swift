import Foundation

struct Recording: Identifiable, Codable {
    let id: UUID
    var title: String
    let url: URL
    let duration: TimeInterval
    let createdAt: Date
    let storageMode: StorageMode
    var cloudURL: URL?
    var thumbnailURL: URL?
    var fileSize: Int64?
    
    var formattedDuration: String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
    
    var formattedFileSize: String {
        guard let fileSize = fileSize else { return "Unknown" }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}

// MARK: - User Model

struct User: Codable {
    let id: String
    let email: String
    let name: String?
    let isPremium: Bool
}

// MARK: - Upload Progress

struct UploadProgress: Identifiable {
    let id: UUID
    let recordingID: UUID
    var progress: Double
    var isComplete: Bool
    var error: String?
}
