import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                HStack {
                    Text("Settings")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top)
                
                // Storage Settings
                GroupBox("Storage") {
                    VStack(alignment: .leading, spacing: 16) {
                        Picker("Storage Mode", selection: $appState.preferences.storageMode) {
                            ForEach(StorageMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        
                        if appState.preferences.storageMode == .local {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Save Location")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack {
                                    Text(appState.preferences.localSavePath)
                                        .font(.system(.body, design: .monospaced))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    
                                    Button("Choose...") {
                                        chooseFolder()
                                    }
                                }
                            }
                        }
                        
                        if appState.preferences.storageMode == .cloud {
                            Toggle("Save Local Backup", isOn: $appState.preferences.saveLocalBackup)
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // Recording Settings
                GroupBox("Recording") {
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle("Auto-compress after recording", isOn: $appState.preferences.autoCompress)
                        
                        if appState.preferences.autoCompress {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Compression Quality")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Picker("Quality", selection: $appState.preferences.compressionQuality) {
                                    ForEach(CompressionQuality.allCases, id: \.self) { quality in
                                        Text(quality.rawValue).tag(quality)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }
                        }
                        
                        HStack {
                            Text("Countdown Duration")
                            Spacer()
                            Stepper("\(appState.preferences.countdownDuration)s", value: $appState.preferences.countdownDuration, in: 0...10)
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // API Settings
                GroupBox("API Configuration") {
                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Base URL")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            TextField("https://videospaceship.com", text: $appState.preferences.apiBaseURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Button("Reset to Default") {
                            appState.preferences.apiBaseURL = "https://videospaceship.com"
                        }
                    }
                    .padding()
                }
                .padding(.horizontal)
                
                // About
                GroupBox("About") {
                    VStack(spacing: 12) {
                        Image(systemName: "video.circle.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        
                        Text("Video Spaceship")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Version 1.0.0")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Native Swift macOS App")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
        }
    }
    
    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            appState.preferences.localSavePath = url.path
        }
    }
}
