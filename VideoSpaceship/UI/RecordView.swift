import SwiftUI
import AVFoundation
import ScreenCaptureKit

struct RecordView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var recordingManager: RecordingManager
    
    @State private var selectedMode: RecordingMode = .screenAndCamera
    @State private var selectedScreen: SCDisplay?
    @State private var selectedCamera: AVCaptureDevice?
    @State private var showCountdown = false
    @State private var countdownValue = 3
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.accentColor)
                    
                    Text("Record Your Screen")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Choose your recording mode and settings")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 40)
                
                // Recording Mode Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recording Mode")
                        .font(.headline)
                    
                    Picker("Mode", selection: $selectedMode) {
                        ForEach(RecordingMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 40)
                
                // Device Selection
                VStack(spacing: 16) {
                    if selectedMode == .screenAndCamera || selectedMode == .screenOnly {
                        ScreenSelectionView(selectedScreen: $selectedScreen)
                    }
                    
                    if selectedMode == .screenAndCamera || selectedMode == .cameraOnly {
                        CameraSelectionView(selectedCamera: $selectedCamera)
                    }
                }
                .padding(.horizontal, 40)
                
                // PiP Settings (if camera enabled)
                if selectedMode == .screenAndCamera {
                    PiPSettingsView()
                        .padding(.horizontal, 40)
                }
                
                // Audio Settings
                AudioSettingsView()
                    .padding(.horizontal, 40)
                
                // Record Button
                Button {
                    startRecordingWithCountdown()
                } label: {
                    HStack {
                        Image(systemName: "record.circle.fill")
                        Text("Start Recording")
                    }
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .cornerRadius(12)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 40)
                .padding(.bottom, 40)
                .disabled(recordingManager.isRecording)
            }
        }
        .sheet(isPresented: $showCountdown) {
            CountdownView(countdown: $countdownValue) {
                Task {
                    await recordingManager.startRecording(
                        mode: selectedMode,
                        screen: selectedScreen
                    )
                }
            }
        }
        .onAppear {
            Task {
                await recordingManager.refreshAvailableDevices()
                selectedScreen = recordingManager.availableScreens.first
                selectedCamera = recordingManager.availableCameras.first
            }
        }
    }
    
    private func startRecordingWithCountdown() {
        countdownValue = appState.preferences.countdownDuration
        if countdownValue > 0 {
            showCountdown = true
        } else {
            Task {
                await recordingManager.startRecording(mode: selectedMode, screen: selectedScreen)
            }
        }
    }
}

struct ScreenSelectionView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @Binding var selectedScreen: SCDisplay?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen")
                .font(.headline)
            
            if recordingManager.availableScreens.isEmpty {
                Text("No screens available")
                    .foregroundColor(.secondary)
            } else {
                Picker("Screen", selection: $selectedScreen) {
                    ForEach(recordingManager.availableScreens, id: \.displayID) { screen in
                        Text("Display \(screen.displayID)").tag(screen as SCDisplay?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

struct CameraSelectionView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @Binding var selectedCamera: AVCaptureDevice?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera")
                .font(.headline)
            
            if recordingManager.availableCameras.isEmpty {
                Text("No cameras available")
                    .foregroundColor(.secondary)
            } else {
                Picker("Camera", selection: $selectedCamera) {
                    ForEach(recordingManager.availableCameras, id: \.uniqueID) { camera in
                        Text(camera.localizedName).tag(camera as AVCaptureDevice?)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}

struct PiPSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        GroupBox("Picture-in-Picture Settings") {
            VStack(spacing: 16) {
                HStack {
                    Text("Position")
                    Spacer()
                    Picker("Position", selection: $appState.preferences.pipPosition) {
                        ForEach(PiPPosition.allCases, id: \.self) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 150)
                }
                
                HStack {
                    Text("Size")
                    Spacer()
                    Picker("Size", selection: $appState.preferences.pipSize) {
                        ForEach(PiPSize.allCases, id: \.self) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                
                HStack {
                    Text("Shape")
                    Spacer()
                    Picker("Shape", selection: $appState.preferences.pipShape) {
                        ForEach(PiPShape.allCases, id: \.self) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 250)
                }
                
                HStack {
                    Text("Background")
                    Spacer()
                    Picker("Background", selection: $appState.preferences.pipBackgroundEffect) {
                        ForEach(BackgroundEffect.allCases, id: \.self) { effect in
                            Text(effect.rawValue).tag(effect)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
            }
            .padding()
        }
    }
}

struct AudioSettingsView: View {
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        GroupBox("Audio Settings") {
            VStack(spacing: 12) {
                Toggle("Record Microphone", isOn: $appState.preferences.microphoneEnabled)
                Toggle("Record System Audio", isOn: $appState.preferences.systemAudioEnabled)
            }
            .padding()
        }
    }
}

struct CountdownView: View {
    @Binding var countdown: Int
    let onComplete: () -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.9)
                .ignoresSafeArea()
            
            VStack(spacing: 40) {
                Text("Recording starts in...")
                    .font(.title)
                    .foregroundColor(.white)
                
                Text("\(countdown)")
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .contentTransition(.numericText())
                
                Button("Cancel") {
                    dismiss()
                }
                .foregroundColor(.white)
            }
        }
        .frame(width: 400, height: 300)
        .onAppear {
            startCountdown()
        }
    }
    
    private func startCountdown() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if countdown > 1 {
                withAnimation {
                    countdown -= 1
                }
            } else {
                timer.invalidate()
                dismiss()
                onComplete()
            }
        }
    }
}
