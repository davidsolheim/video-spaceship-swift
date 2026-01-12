import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        NavigationSplitView {
            // Sidebar
            SidebarView(selectedView: $appState.currentView)
        } detail: {
            // Main content
            ZStack {
                switch appState.currentView {
                case .record:
                    RecordView()
                case .recent:
                    RecentRecordingsView()
                case .settings:
                    SettingsView()
                }
                
                // Processing overlay
                if appState.isProcessing {
                    ProcessingOverlay(progress: appState.processingProgress)
                }
            }
        }
        .alert("Error", isPresented: $appState.showError) {
            Button("OK") {
                appState.clearError()
            }
        } message: {
            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
            }
        }
    }
}

struct SidebarView: View {
    @Binding var selectedView: AppView
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        List(selection: $selectedView) {
            NavigationLink(value: AppView.record) {
                Label("Record", systemImage: "record.circle")
            }
            
            NavigationLink(value: AppView.recent) {
                Label("Recent", systemImage: "clock")
            }
            
            NavigationLink(value: AppView.settings) {
                Label("Settings", systemImage: "gear")
            }
            
            Divider()
            
            Section {
                if authManager.isAuthenticated {
                    HStack {
                        Image(systemName: "person.circle.fill")
                        VStack(alignment: .leading) {
                            Text(authManager.user?.email ?? "User")
                                .font(.caption)
                            Button("Sign Out") {
                                Task {
                                    await authManager.signOut()
                                }
                            }
                            .font(.caption2)
                        }
                    }
                } else {
                    Button {
                        Task {
                            await authManager.signIn()
                        }
                    } label: {
                        Label("Sign In", systemImage: "person.circle")
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
    }
}

struct ProcessingOverlay: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView(value: progress) {
                    Text("Processing Video...")
                        .font(.headline)
                }
                .progressViewStyle(.linear)
                .frame(width: 300)
                
                Text("\(Int(progress * 100))%")
                    .font(.title2)
                    .monospacedDigit()
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(NSColor.windowBackgroundColor))
            )
            .shadow(radius: 20)
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var authManager: AuthenticationManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if recordingManager.isRecording {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Recording...")
                        .font(.headline)
                    
                    Text(formatDuration(recordingManager.recordingDuration))
                        .font(.system(.body, design: .monospaced))
                    
                    Divider()
                    
                    Button {
                        Task {
                            await recordingManager.stopRecording()
                        }
                    } label: {
                        Label("Stop Recording", systemImage: "stop.fill")
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    
                    Button {
                        Task {
                            await recordingManager.togglePause()
                        }
                    } label: {
                        Label(
                            recordingManager.isPaused ? "Resume" : "Pause",
                            systemImage: recordingManager.isPaused ? "play.fill" : "pause.fill"
                        )
                    }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                }
            } else {
                Button {
                    Task {
                        await recordingManager.startQuickRecord()
                    }
                } label: {
                    Label("Quick Record", systemImage: "record.circle")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }
            
            Divider()
            
            Button("Show App") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
        .padding()
        .frame(width: 250)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}
