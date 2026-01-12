import Foundation
import AppKit

class PlatformIntegrationManager: ObservableObject {
    static let shared = PlatformIntegrationManager()
    
    @Published var connectedPlatforms: Set<Platform> = []
    @Published var uploadProgress: [UUID: Double] = [:]
    
    private var platformTokens: [Platform: String] = [:]
    
    private init() {
        loadConnectedPlatforms()
    }
    
    // MARK: - Authentication
    
    func connect(to platform: Platform) async throws {
        let authURL = try getAuthURL(for: platform)
        
        // Open browser for OAuth
        if let url = URL(string: authURL) {
            NSWorkspace.shared.open(url)
        }
        
        // Wait for callback (would be handled by URL scheme handler)
        // For now, this is a placeholder
    }
    
    func disconnect(from platform: Platform) {
        platformTokens.removeValue(forKey: platform)
        connectedPlatforms.remove(platform)
        saveConnectedPlatforms()
    }
    
    func isConnected(to platform: Platform) -> Bool {
        return connectedPlatforms.contains(platform)
    }
    
    // MARK: - Upload
    
    func upload(
        recording: Recording,
        to platform: Platform,
        metadata: UploadMetadata
    ) async throws -> String {
        guard isConnected(to: platform) else {
            throw PlatformError.notConnected
        }
        
        guard let token = platformTokens[platform] else {
            throw PlatformError.noToken
        }
        
        switch platform {
        case .youtube:
            return try await uploadToYouTube(recording, token: token, metadata: metadata)
        case .vimeo:
            return try await uploadToVimeo(recording, token: token, metadata: metadata)
        case .googleDrive:
            return try await uploadToGoogleDrive(recording, token: token, metadata: metadata)
        case .dropbox:
            return try await uploadToDropbox(recording, token: token, metadata: metadata)
        }
    }
    
    // MARK: - YouTube Upload
    
    private func uploadToYouTube(
        _ recording: Recording,
        token: String,
        metadata: UploadMetadata
    ) async throws -> String {
        let uploadURL = "https://www.googleapis.com/upload/youtube/v3/videos"
        
        // Create multipart request
        var request = URLRequest(url: URL(string: uploadURL + "?uploadType=multipart&part=snippet,status")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // Build multipart body
        var body = Data()
        
        // Part 1: JSON metadata
        let snippet: [String: Any] = [
            "snippet": [
                "title": metadata.title,
                "description": metadata.description ?? "",
                "categoryId": "22" // People & Blogs
            ],
            "status": [
                "privacyStatus": metadata.isPrivate ? "private" : "public"
            ]
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: snippet)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(jsonData)
        body.append("\r\n".data(using: .utf8)!)
        
        // Part 2: Video file
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        
        let videoData = try Data(contentsOf: recording.url)
        body.append(videoData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw PlatformError.uploadFailed
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let videoID = json["id"] as? String else {
            throw PlatformError.invalidResponse
        }
        
        return "https://youtube.com/watch?v=\(videoID)"
    }
    
    // MARK: - Vimeo Upload
    
    private func uploadToVimeo(
        _ recording: Recording,
        token: String,
        metadata: UploadMetadata
    ) async throws -> String {
        // Step 1: Create video
        let createURL = "https://api.vimeo.com/me/videos"
        var createRequest = URLRequest(url: URL(string: createURL)!)
        createRequest.httpMethod = "POST"
        createRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        createRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let fileSize = try FileManager.default.attributesOfItem(atPath: recording.url.path)[.size] as! Int
        
        let createBody: [String: Any] = [
            "upload": [
                "approach": "tus",
                "size": fileSize
            ],
            "name": metadata.title,
            "description": metadata.description ?? "",
            "privacy": [
                "view": metadata.isPrivate ? "nobody" : "anybody"
            ]
        ]
        
        createRequest.httpBody = try JSONSerialization.data(withJSONObject: createBody)
        
        let (createData, _) = try await URLSession.shared.data(for: createRequest)
        
        guard let createJSON = try? JSONSerialization.jsonObject(with: createData) as? [String: Any],
              let uploadDict = createJSON["upload"] as? [String: Any],
              let uploadLink = uploadDict["upload_link"] as? String,
              let videoURI = createJSON["uri"] as? String else {
            throw PlatformError.invalidResponse
        }
        
        // Step 2: Upload video using TUS protocol
        try await uploadWithTUS(fileURL: recording.url, uploadURL: uploadLink, recordingID: recording.id)
        
        return "https://vimeo.com\(videoURI)"
    }
    
    // MARK: - Google Drive Upload
    
    private func uploadToGoogleDrive(
        _ recording: Recording,
        token: String,
        metadata: UploadMetadata
    ) async throws -> String {
        let uploadURL = "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart"
        
        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        let boundary = UUID().uuidString
        request.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Metadata
        let fileMetadata: [String: Any] = [
            "name": metadata.title,
            "description": metadata.description ?? ""
        ]
        
        let jsonData = try JSONSerialization.data(withJSONObject: fileMetadata)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n".data(using: .utf8)!)
        body.append(jsonData)
        body.append("\r\n".data(using: .utf8)!)
        
        // File
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Type: video/mp4\r\n\r\n".data(using: .utf8)!)
        
        let videoData = try Data(contentsOf: recording.url)
        body.append(videoData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fileID = json["id"] as? String else {
            throw PlatformError.invalidResponse
        }
        
        return "https://drive.google.com/file/d/\(fileID)/view"
    }
    
    // MARK: - Dropbox Upload
    
    private func uploadToDropbox(
        _ recording: Recording,
        token: String,
        metadata: UploadMetadata
    ) async throws -> String {
        let uploadURL = "https://content.dropboxapi.com/2/files/upload"
        
        var request = URLRequest(url: URL(string: uploadURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        
        let dropboxArgs: [String: Any] = [
            "path": "/\(metadata.title).mp4",
            "mode": "add",
            "autorename": true
        ]
        
        let argsJSON = try JSONSerialization.data(withJSONObject: dropboxArgs)
        request.setValue(String(data: argsJSON, encoding: .utf8), forHTTPHeaderField: "Dropbox-API-Arg")
        
        request.httpBody = try Data(contentsOf: recording.url)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let pathDisplay = json["path_display"] as? String else {
            throw PlatformError.invalidResponse
        }
        
        // Create shared link
        return try await createDropboxSharedLink(path: pathDisplay, token: token)
    }
    
    private func createDropboxSharedLink(path: String, token: String) async throws -> String {
        let linkURL = "https://api.dropboxapi.com/2/sharing/create_shared_link_with_settings"
        
        var request = URLRequest(url: URL(string: linkURL)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["path": path]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = json["url"] as? String else {
            throw PlatformError.invalidResponse
        }
        
        return url
    }
    
    // MARK: - TUS Upload (for Vimeo)
    
    private func uploadWithTUS(fileURL: URL, uploadURL: String, recordingID: UUID) async throws {
        let fileData = try Data(contentsOf: fileURL)
        let chunkSize = 5 * 1024 * 1024 // 5 MB chunks
        var offset = 0
        
        while offset < fileData.count {
            let end = min(offset + chunkSize, fileData.count)
            let chunk = fileData[offset..<end]
            
            var request = URLRequest(url: URL(string: uploadURL)!)
            request.httpMethod = "PATCH"
            request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("\(offset)", forHTTPHeaderField: "Upload-Offset")
            request.httpBody = chunk
            
            let (_, _) = try await URLSession.shared.data(for: request)
            
            offset = end
            
            // Update progress
            let progress = Double(offset) / Double(fileData.count)
            await MainActor.run {
                uploadProgress[recordingID] = progress
            }
        }
    }
    
    // MARK: - OAuth URLs
    
    private func getAuthURL(for platform: Platform) throws -> String {
        switch platform {
        case .youtube:
            return "https://accounts.google.com/o/oauth2/v2/auth?client_id=YOUR_CLIENT_ID&redirect_uri=videospaceship://oauth&response_type=code&scope=https://www.googleapis.com/auth/youtube.upload"
        case .vimeo:
            return "https://api.vimeo.com/oauth/authorize?client_id=YOUR_CLIENT_ID&redirect_uri=videospaceship://oauth&response_type=code&scope=upload"
        case .googleDrive:
            return "https://accounts.google.com/o/oauth2/v2/auth?client_id=YOUR_CLIENT_ID&redirect_uri=videospaceship://oauth&response_type=code&scope=https://www.googleapis.com/auth/drive.file"
        case .dropbox:
            return "https://www.dropbox.com/oauth2/authorize?client_id=YOUR_CLIENT_ID&redirect_uri=videospaceship://oauth&response_type=code"
        }
    }
    
    // MARK: - Persistence
    
    private func loadConnectedPlatforms() {
        if let data = UserDefaults.standard.data(forKey: "ConnectedPlatforms"),
           let platforms = try? JSONDecoder().decode(Set<Platform>.self, from: data) {
            connectedPlatforms = platforms
        }
    }
    
    private func saveConnectedPlatforms() {
        if let data = try? JSONEncoder().encode(connectedPlatforms) {
            UserDefaults.standard.set(data, forKey: "ConnectedPlatforms")
        }
    }
}

// MARK: - Models

enum Platform: String, Codable, CaseIterable {
    case youtube = "YouTube"
    case vimeo = "Vimeo"
    case googleDrive = "Google Drive"
    case dropbox = "Dropbox"
    
    var iconName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .vimeo: return "v.circle.fill"
        case .googleDrive: return "folder.fill"
        case .dropbox: return "square.and.arrow.down.fill"
        }
    }
}

struct UploadMetadata {
    let title: String
    let description: String?
    let isPrivate: Bool
    let tags: [String]?
}

enum PlatformError: LocalizedError {
    case notConnected
    case noToken
    case uploadFailed
    case invalidResponse
    
    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Platform not connected"
        case .noToken:
            return "No authentication token found"
        case .uploadFailed:
            return "Upload failed"
        case .invalidResponse:
            return "Invalid response from platform"
        }
    }
}
