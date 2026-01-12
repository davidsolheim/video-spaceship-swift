import Foundation

class ShareLinkManager: ObservableObject {
    static let shared = ShareLinkManager()
    
    @Published var shareLinks: [ShareLink] = []
    
    private let baseURL: String
    private let apiClient: APIClient
    
    private init() {
        self.baseURL = UserDefaults.standard.string(forKey: "BackendURL") ?? "https://api.videospaceship.com"
        self.apiClient = APIClient.shared
        
        loadShareLinks()
    }
    
    // MARK: - Create Share Link
    
    func createShareLink(
        for recording: Recording,
        options: ShareLinkOptions
    ) async throws -> ShareLink {
        let endpoint = "\(baseURL)/api/v1/share/create"
        
        let requestBody: [String: Any] = [
            "recording_id": recording.id.uuidString,
            "password": options.password as Any,
            "expires_at": options.expiresAt?.iso8601String as Any,
            "max_views": options.maxViews as Any,
            "allow_download": options.allowDownload
        ]
        
        let response = try await apiClient.post(endpoint, body: requestBody)
        
        guard let data = response["data"] as? [String: Any],
              let linkID = data["id"] as? String,
              let token = data["token"] as? String else {
            throw ShareLinkError.invalidResponse
        }
        
        let shareURL = "\(baseURL)/watch/\(token)"
        
        let shareLink = ShareLink(
            id: UUID(uuidString: linkID) ?? UUID(),
            recordingID: recording.id,
            url: shareURL,
            token: token,
            password: options.password,
            expiresAt: options.expiresAt,
            maxViews: options.maxViews,
            viewCount: 0,
            allowDownload: options.allowDownload,
            createdAt: Date()
        )
        
        shareLinks.append(shareLink)
        saveShareLinks()
        
        return shareLink
    }
    
    // MARK: - Manage Share Links
    
    func revokeShareLink(_ link: ShareLink) async throws {
        let endpoint = "\(baseURL)/api/v1/share/\(link.id.uuidString)/revoke"
        
        _ = try await apiClient.post(endpoint, body: [:])
        
        shareLinks.removeAll { $0.id == link.id }
        saveShareLinks()
    }
    
    func updateShareLink(_ link: ShareLink, options: ShareLinkOptions) async throws {
        let endpoint = "\(baseURL)/api/v1/share/\(link.id.uuidString)/update"
        
        let requestBody: [String: Any] = [
            "password": options.password as Any,
            "expires_at": options.expiresAt?.iso8601String as Any,
            "max_views": options.maxViews as Any,
            "allow_download": options.allowDownload
        ]
        
        _ = try await apiClient.post(endpoint, body: requestBody)
        
        if let index = shareLinks.firstIndex(where: { $0.id == link.id }) {
            shareLinks[index].password = options.password
            shareLinks[index].expiresAt = options.expiresAt
            shareLinks[index].maxViews = options.maxViews
            shareLinks[index].allowDownload = options.allowDownload
            saveShareLinks()
        }
    }
    
    func refreshViewCount(_ link: ShareLink) async throws -> Int {
        let endpoint = "\(baseURL)/api/v1/share/\(link.id.uuidString)/stats"
        
        let response = try await apiClient.get(endpoint)
        
        guard let data = response["data"] as? [String: Any],
              let viewCount = data["view_count"] as? Int else {
            throw ShareLinkError.invalidResponse
        }
        
        if let index = shareLinks.firstIndex(where: { $0.id == link.id }) {
            shareLinks[index].viewCount = viewCount
            saveShareLinks()
        }
        
        return viewCount
    }
    
    // MARK: - Persistence
    
    private func loadShareLinks() {
        if let data = UserDefaults.standard.data(forKey: "ShareLinks"),
           let links = try? JSONDecoder().decode([ShareLink].self, from: data) {
            shareLinks = links
        }
    }
    
    private func saveShareLinks() {
        if let data = try? JSONEncoder().encode(shareLinks) {
            UserDefaults.standard.set(data, forKey: "ShareLinks")
        }
    }
}

// MARK: - Models

struct ShareLink: Identifiable, Codable {
    let id: UUID
    let recordingID: UUID
    let url: String
    let token: String
    var password: String?
    var expiresAt: Date?
    var maxViews: Int?
    var viewCount: Int
    var allowDownload: Bool
    let createdAt: Date
    
    var isExpired: Bool {
        if let expiresAt = expiresAt {
            return Date() > expiresAt
        }
        return false
    }
    
    var isMaxViewsReached: Bool {
        if let maxViews = maxViews {
            return viewCount >= maxViews
        }
        return false
    }
    
    var isActive: Bool {
        return !isExpired && !isMaxViewsReached
    }
}

struct ShareLinkOptions {
    var password: String?
    var expiresAt: Date?
    var maxViews: Int?
    var allowDownload: Bool = true
}

enum ShareLinkError: LocalizedError {
    case invalidResponse
    case networkError
    case unauthorized
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .networkError:
            return "Network error occurred"
        case .unauthorized:
            return "Unauthorized access"
        }
    }
}

// MARK: - API Client

class APIClient {
    static let shared = APIClient()
    
    private init() {}
    
    func get(_ url: String) async throws -> [String: Any] {
        guard let url = URL(string: url) else {
            throw ShareLinkError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = AuthenticationManager.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ShareLinkError.networkError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ShareLinkError.invalidResponse
        }
        
        return json
    }
    
    func post(_ url: String, body: [String: Any]) async throws -> [String: Any] {
        guard let url = URL(string: url) else {
            throw ShareLinkError.invalidResponse
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        if let token = AuthenticationManager.shared.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw ShareLinkError.networkError
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ShareLinkError.invalidResponse
        }
        
        return json
    }
}

// MARK: - Date Extension

extension Date {
    var iso8601String: String {
        let formatter = ISO8601DateFormatter()
        return formatter.string(from: self)
    }
}
