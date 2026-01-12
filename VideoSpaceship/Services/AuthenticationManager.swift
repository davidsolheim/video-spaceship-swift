import Foundation
import Security

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated: Bool = false
    @Published var user: User?
    @Published var authToken: String?
    
    private let keychainService = "com.videospaceship.auth"
    private let tokenKey = "authToken"
    
    private init() {
        // Load saved token from keychain
        if let token = loadTokenFromKeychain() {
            self.authToken = token
            Task {
                await validateToken()
            }
        }
    }
    
    // MARK: - Authentication
    
    func signIn() async {
        let apiBaseURL = AppState.shared.preferences.apiBaseURL
        
        // Open browser for authentication
        guard let authURL = URL(string: "\(apiBaseURL)/auth/signin?redirect=videospaceship://auth") else {
            return
        }
        
        NSWorkspace.shared.open(authURL)
        
        // Wait for deep link callback
        // In a real implementation, this would be handled by the deep link handler
    }
    
    func handleAuthCallback(token: String) async {
        self.authToken = token
        saveTokenToKeychain(token)
        await validateToken()
    }
    
    func signOut() async {
        self.isAuthenticated = false
        self.user = nil
        self.authToken = nil
        deleteTokenFromKeychain()
    }
    
    private func validateToken() async {
        guard let token = authToken else {
            isAuthenticated = false
            return
        }
        
        do {
            let apiBaseURL = AppState.shared.preferences.apiBaseURL
            guard let url = URL(string: "\(apiBaseURL)/api/auth/session") else { return }
            
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                await signOut()
                return
            }
            
            let user = try JSONDecoder().decode(User.self, from: data)
            self.user = user
            self.isAuthenticated = true
            
        } catch {
            print("Token validation failed: \(error)")
            await signOut()
        }
    }
    
    // MARK: - Keychain
    
    private func saveTokenToKeychain(_ token: String) {
        guard let data = token.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecValueData as String: data
        ]
        
        // Delete existing item
        SecItemDelete(query as CFDictionary)
        
        // Add new item
        SecItemAdd(query as CFDictionary, nil)
    }
    
    private func loadTokenFromKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return token
    }
    
    private func deleteTokenFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}
