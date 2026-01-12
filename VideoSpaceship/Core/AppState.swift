import Foundation
import Combine

@MainActor
class AppState: ObservableObject {
    static let shared = AppState()
    
    @Published var currentView: AppView = .record
    @Published var isProcessing: Bool = false
    @Published var processingProgress: Double = 0.0
    @Published var errorMessage: String?
    @Published var showError: Bool = false
    
    // User preferences
    @Published var preferences: UserPreferences
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        // Load preferences from UserDefaults
        self.preferences = UserPreferences.load()
        
        // Auto-save preferences when they change
        $preferences
            .debounce(for: 0.5, scheduler: DispatchQueue.main)
            .sink { preferences in
                preferences.save()
            }
            .store(in: &cancellables)
    }
    
    func showError(_ message: String) {
        self.errorMessage = message
        self.showError = true
    }
    
    func clearError() {
        self.errorMessage = nil
        self.showError = false
    }
    
    func setProcessing(_ isProcessing: Bool, progress: Double = 0.0) {
        self.isProcessing = isProcessing
        self.processingProgress = progress
    }
}

enum AppView {
    case record
    case recent
    case settings
}
