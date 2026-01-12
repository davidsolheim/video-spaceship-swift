import SwiftUI
import AppKit

class FloatingControlBarWindow: NSWindow {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.collectionBehavior = [.canJoinAllSpaces, .stationary]
        self.isMovableByWindowBackground = true
        
        // Position at top center of screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.midX - frame.width / 2
            let y = screenFrame.maxY - frame.height - 20
            self.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

class FloatingControlBarController: ObservableObject {
    private var window: FloatingControlBarWindow?
    
    func show(recordingManager: RecordingManager, appState: AppState) {
        guard window == nil else { return }
        
        let window = FloatingControlBarWindow()
        let contentView = FloatingControlBarView()
            .environmentObject(recordingManager)
            .environmentObject(appState)
        
        window.contentView = NSHostingView(rootView: contentView)
        window.orderFront(nil)
        
        self.window = window
    }
    
    func hide() {
        window?.close()
        window = nil
    }
}

struct FloatingControlBarView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @EnvironmentObject var appState: AppState
    
    var body: some View {
        HStack(spacing: 20) {
            // Timer
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 12, height: 12)
                    .opacity(recordingManager.isPaused ? 0.3 : 1.0)
                
                Text(formatDuration(recordingManager.recordingDuration))
                    .font(.system(.title3, design: .monospaced))
                    .fontWeight(.semibold)
            }
            
            Divider()
                .frame(height: 40)
            
            // Controls
            HStack(spacing: 12) {
                // Pause/Resume
                Button {
                    Task {
                        await recordingManager.togglePause()
                    }
                } label: {
                    Image(systemName: recordingManager.isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help(recordingManager.isPaused ? "Resume Recording" : "Pause Recording")
                
                // Microphone
                Button {
                    appState.preferences.microphoneEnabled.toggle()
                } label: {
                    Image(systemName: appState.preferences.microphoneEnabled ? "mic.fill" : "mic.slash.fill")
                        .font(.title2)
                        .foregroundColor(appState.preferences.microphoneEnabled ? .primary : .red)
                }
                .buttonStyle(.plain)
                .help("Toggle Microphone")
                
                // Webcam
                Button {
                    recordingManager.toggleWebcam()
                } label: {
                    Image(systemName: recordingManager.isWebcamVisible ? "video.fill" : "video.slash.fill")
                        .font(.title2)
                        .foregroundColor(recordingManager.isWebcamVisible ? .primary : .red)
                }
                .buttonStyle(.plain)
                .help("Toggle Webcam")
                
                // PiP Settings
                Menu {
                    Picker("Position", selection: $appState.preferences.pipPosition) {
                        ForEach(PiPPosition.allCases, id: \.self) { position in
                            Text(position.rawValue).tag(position)
                        }
                    }
                    
                    Picker("Size", selection: $appState.preferences.pipSize) {
                        ForEach(PiPSize.allCases, id: \.self) { size in
                            Text(size.rawValue).tag(size)
                        }
                    }
                    
                    Picker("Shape", selection: $appState.preferences.pipShape) {
                        ForEach(PiPShape.allCases, id: \.self) { shape in
                            Text(shape.rawValue).tag(shape)
                        }
                    }
                    
                    Picker("Background", selection: $appState.preferences.pipBackgroundEffect) {
                        ForEach(BackgroundEffect.allCases, id: \.self) { effect in
                            Text(effect.rawValue).tag(effect)
                        }
                    }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.title2)
                }
                .buttonStyle(.plain)
                .help("PiP Settings")
            }
            
            Divider()
                .frame(height: 40)
            
            // Stop Recording
            Button {
                Task {
                    await recordingManager.stopRecording()
                }
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                    Text("Finish")
                }
                .font(.headline)
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.red)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
            .help("Stop Recording")
        }
        .padding(16)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(12)
        )
        .shadow(radius: 10)
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

// Visual Effect Blur for macOS
struct VisualEffectBlur: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

// Extension to RecordingManager for webcam visibility
extension RecordingManager {
    @Published var isWebcamVisible: Bool = true
    
    func toggleWebcam() {
        isWebcamVisible.toggle()
        // This would be implemented in the VideoCompositor to show/hide the PiP overlay
    }
}
