import Foundation

class TeamManager: ObservableObject {
    static let shared = TeamManager()
    
    @Published var currentWorkspace: Workspace?
    @Published var workspaces: [Workspace] = []
    @Published var teamMembers: [TeamMember] = []
    
    private let baseURL: String
    private let apiClient: APIClient
    
    private init() {
        self.baseURL = UserDefaults.standard.string(forKey: "BackendURL") ?? "https://api.videospaceship.com"
        self.apiClient = APIClient.shared
        
        loadWorkspaces()
    }
    
    // MARK: - Workspaces
    
    func createWorkspace(name: String, description: String?) async throws -> Workspace {
        let endpoint = "\(baseURL)/api/v1/workspaces/create"
        
        let requestBody: [String: Any] = [
            "name": name,
            "description": description as Any
        ]
        
        let response = try await apiClient.post(endpoint, body: requestBody)
        
        guard let data = response["data"] as? [String: Any] else {
            throw TeamError.invalidResponse
        }
        
        let workspace = try parseWorkspace(from: data)
        workspaces.append(workspace)
        saveWorkspaces()
        
        return workspace
    }
    
    func fetchWorkspaces() async throws {
        let endpoint = "\(baseURL)/api/v1/workspaces"
        
        let response = try await apiClient.get(endpoint)
        
        guard let data = response["data"] as? [[String: Any]] else {
            throw TeamError.invalidResponse
        }
        
        workspaces = try data.compactMap { try? parseWorkspace(from: $0) }
        saveWorkspaces()
    }
    
    func switchWorkspace(_ workspace: Workspace) {
        currentWorkspace = workspace
        UserDefaults.standard.set(workspace.id.uuidString, forKey: "CurrentWorkspaceID")
        
        Task {
            try? await fetchTeamMembers(for: workspace)
        }
    }
    
    // MARK: - Team Members
    
    func fetchTeamMembers(for workspace: Workspace) async throws {
        let endpoint = "\(baseURL)/api/v1/workspaces/\(workspace.id.uuidString)/members"
        
        let response = try await apiClient.get(endpoint)
        
        guard let data = response["data"] as? [[String: Any]] else {
            throw TeamError.invalidResponse
        }
        
        teamMembers = try data.compactMap { try? parseTeamMember(from: $0) }
    }
    
    func inviteMember(
        to workspace: Workspace,
        email: String,
        role: TeamRole
    ) async throws {
        let endpoint = "\(baseURL)/api/v1/workspaces/\(workspace.id.uuidString)/invite"
        
        let requestBody: [String: Any] = [
            "email": email,
            "role": role.rawValue
        ]
        
        _ = try await apiClient.post(endpoint, body: requestBody)
    }
    
    func removeMember(_ member: TeamMember, from workspace: Workspace) async throws {
        let endpoint = "\(baseURL)/api/v1/workspaces/\(workspace.id.uuidString)/members/\(member.id.uuidString)/remove"
        
        _ = try await apiClient.post(endpoint, body: [:])
        
        teamMembers.removeAll { $0.id == member.id }
    }
    
    func updateMemberRole(_ member: TeamMember, role: TeamRole, in workspace: Workspace) async throws {
        let endpoint = "\(baseURL)/api/v1/workspaces/\(workspace.id.uuidString)/members/\(member.id.uuidString)/role"
        
        let requestBody: [String: Any] = [
            "role": role.rawValue
        ]
        
        _ = try await apiClient.post(endpoint, body: requestBody)
        
        if let index = teamMembers.firstIndex(where: { $0.id == member.id }) {
            teamMembers[index].role = role
        }
    }
    
    // MARK: - Shared Folders
    
    func createSharedFolder(
        in workspace: Workspace,
        name: String,
        permissions: FolderPermissions
    ) async throws -> SharedFolder {
        let endpoint = "\(baseURL)/api/v1/workspaces/\(workspace.id.uuidString)/folders/create"
        
        let requestBody: [String: Any] = [
            "name": name,
            "permissions": [
                "viewer_can_download": permissions.viewerCanDownload,
                "editor_can_delete": permissions.editorCanDelete
            ]
        ]
        
        let response = try await apiClient.post(endpoint, body: requestBody)
        
        guard let data = response["data"] as? [String: Any] else {
            throw TeamError.invalidResponse
        }
        
        return try parseSharedFolder(from: data)
    }
    
    func shareRecording(
        _ recording: Recording,
        to folder: SharedFolder,
        in workspace: Workspace
    ) async throws {
        let endpoint = "\(baseURL)/api/v1/workspaces/\(workspace.id.uuidString)/folders/\(folder.id.uuidString)/recordings/add"
        
        let requestBody: [String: Any] = [
            "recording_id": recording.id.uuidString
        ]
        
        _ = try await apiClient.post(endpoint, body: requestBody)
    }
    
    // MARK: - Parsing
    
    private func parseWorkspace(from data: [String: Any]) throws -> Workspace {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = data["name"] as? String,
              let ownerIDString = data["owner_id"] as? String,
              let ownerID = UUID(uuidString: ownerIDString),
              let createdAtString = data["created_at"] as? String else {
            throw TeamError.invalidResponse
        }
        
        let description = data["description"] as? String
        let createdAt = ISO8601DateFormatter().date(from: createdAtString) ?? Date()
        
        return Workspace(
            id: id,
            name: name,
            description: description,
            ownerID: ownerID,
            createdAt: createdAt
        )
    }
    
    private func parseTeamMember(from data: [String: Any]) throws -> TeamMember {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = data["name"] as? String,
              let email = data["email"] as? String,
              let roleString = data["role"] as? String,
              let role = TeamRole(rawValue: roleString) else {
            throw TeamError.invalidResponse
        }
        
        let avatarURL = data["avatar_url"] as? String
        
        return TeamMember(
            id: id,
            name: name,
            email: email,
            avatarURL: avatarURL,
            role: role
        )
    }
    
    private func parseSharedFolder(from data: [String: Any]) throws -> SharedFolder {
        guard let idString = data["id"] as? String,
              let id = UUID(uuidString: idString),
              let name = data["name"] as? String else {
            throw TeamError.invalidResponse
        }
        
        return SharedFolder(
            id: id,
            name: name,
            recordingCount: data["recording_count"] as? Int ?? 0,
            permissions: FolderPermissions()
        )
    }
    
    // MARK: - Persistence
    
    private func loadWorkspaces() {
        if let data = UserDefaults.standard.data(forKey: "Workspaces"),
           let workspaces = try? JSONDecoder().decode([Workspace].self, from: data) {
            self.workspaces = workspaces
        }
        
        if let workspaceIDString = UserDefaults.standard.string(forKey: "CurrentWorkspaceID"),
           let workspaceID = UUID(uuidString: workspaceIDString) {
            currentWorkspace = workspaces.first { $0.id == workspaceID }
        }
    }
    
    private func saveWorkspaces() {
        if let data = try? JSONEncoder().encode(workspaces) {
            UserDefaults.standard.set(data, forKey: "Workspaces")
        }
    }
}

// MARK: - Models

struct Workspace: Identifiable, Codable {
    let id: UUID
    let name: String
    let description: String?
    let ownerID: UUID
    let createdAt: Date
}

struct TeamMember: Identifiable, Codable {
    let id: UUID
    let name: String
    let email: String
    let avatarURL: String?
    var role: TeamRole
}

enum TeamRole: String, Codable, CaseIterable {
    case owner = "owner"
    case admin = "admin"
    case editor = "editor"
    case viewer = "viewer"
    
    var displayName: String {
        switch self {
        case .owner: return "Owner"
        case .admin: return "Admin"
        case .editor: return "Editor"
        case .viewer: return "Viewer"
        }
    }
    
    var permissions: [Permission] {
        switch self {
        case .owner, .admin:
            return [.view, .edit, .delete, .share, .invite]
        case .editor:
            return [.view, .edit, .share]
        case .viewer:
            return [.view]
        }
    }
    
    func hasPermission(_ permission: Permission) -> Bool {
        return permissions.contains(permission)
    }
}

enum Permission {
    case view
    case edit
    case delete
    case share
    case invite
}

struct SharedFolder: Identifiable, Codable {
    let id: UUID
    let name: String
    var recordingCount: Int
    var permissions: FolderPermissions
}

struct FolderPermissions: Codable {
    var viewerCanDownload: Bool = true
    var editorCanDelete: Bool = false
}

enum TeamError: LocalizedError {
    case invalidResponse
    case unauthorized
    case notFound
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Unauthorized access"
        case .notFound:
            return "Resource not found"
        }
    }
}
