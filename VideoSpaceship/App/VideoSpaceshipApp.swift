import SwiftUI
import ScreenCaptureKit

@main
struct VideoSpaceshipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared
    @StateObject private var recordingManager = RecordingManager.shared
    @StateObject private var authManager = AuthenticationManager.shared
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .environmentObject(recordingManager)
                .environmentObject(authManager)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    Task {
                        await checkPermissions()
                    }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Recording") {
                Button("Start Quick Record") {
                    Task {
                        await recordingManager.startQuickRecord()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                
                Button("Stop Recording") {
                    Task {
                        await recordingManager.stopRecording()
                    }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(!recordingManager.isRecording)
                
                Divider()
                
                Button("Pause/Resume") {
                    Task {
                        await recordingManager.togglePause()
                    }
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(!recordingManager.isRecording)
            }
        }
        
        // Menu bar extra for quick access
        MenuBarExtra("Video Spaceship", systemImage: "video.circle.fill") {
            MenuBarView()
                .environmentObject(recordingManager)
                .environmentObject(authManager)
        }
        .menuBarExtraStyle(.window)
    }
    
    private func checkPermissions() async {
        // Check screen recording permission
        let canRecord = CGPreflightScreenCaptureAccess()
        if !canRecord {
            CGRequestScreenCaptureAccess()
        }
        
        // Check camera permission
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        default:
            break
        }
        
        // Check microphone permission
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .audio)
        default:
            break
        }
    }
}
