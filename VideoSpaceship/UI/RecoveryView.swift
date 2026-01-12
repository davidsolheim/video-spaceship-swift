import SwiftUI

struct RecoveryView: View {
    @StateObject private var recoveryManager = RecordingRecoveryManager.shared
    @State private var isRecovering = false
    @State private var recoveryProgress: Double = 0
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Image(systemName: "arrow.clockwise.circle.fill")
                    .font(.largeTitle)
                    .foregroundColor(.orange)
                
                VStack(alignment: .leading) {
                    Text("Recover Recordings")
                        .font(.title)
                        .fontWeight(.bold)
                    
                    Text("Found \(recoveryManager.recoverableRecordings.count) interrupted recording(s)")
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            
            if recoveryManager.recoverableRecordings.isEmpty {
                EmptyRecoveryView()
            } else {
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(recoveryManager.recoverableRecordings) { recording in
                            RecoverableRecordingCard(recording: recording) {
                                await recoverRecording(recording)
                            } onDiscard: {
                                recoveryManager.discardRecording(recording)
                            }
                        }
                    }
                    .padding()
                }
            }
            
            // Actions
            HStack {
                Button("Clean Old Sessions") {
                    recoveryManager.cleanOldSessions()
                    Task {
                        await recoveryManager.scanForRecoverableRecordings()
                    }
                }
                
                Spacer()
                
                Button("Discard All") {
                    for recording in recoveryManager.recoverableRecordings {
                        recoveryManager.discardRecording(recording)
                    }
                }
                .disabled(recoveryManager.recoverableRecordings.isEmpty)
            }
            .padding()
        }
        .overlay {
            if isRecovering {
                RecoveryProgressOverlay(progress: recoveryProgress)
            }
        }
    }
    
    private func recoverRecording(_ recording: RecoverableRecording) async {
        isRecovering = true
        recoveryProgress = 0
        
        do {
            let recoveredURL = try await recoveryManager.recoverRecording(recording)
            
            // Save to storage
            let rec = Recording(
                id: recording.metadata.id,
                title: "Recovered Recording \(recording.formattedDate)",
                url: recoveredURL,
                duration: recording.estimatedDuration,
                createdAt: recording.metadata.startTime,
                storageMode: .local
            )
            
            try await RecordingStorage.shared.saveLocal(rec)
            
            // Remove from recoverable list
            recoveryManager.discardRecording(recording)
            
        } catch {
            AppState.shared.showError("Failed to recover recording: \(error.localizedDescription)")
        }
        
        isRecovering = false
    }
}

struct EmptyRecoveryView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 64))
                .foregroundColor(.green)
            
            Text("No Recordings to Recover")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("All your recordings completed successfully")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RecoverableRecordingCard: View {
    let recording: RecoverableRecording
    let onRecover: () async -> Void
    let onDiscard: () -> Void
    
    @State private var isRecovering = false
    
    var body: some View {
        HStack(spacing: 16) {
            // Icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title)
                .foregroundColor(.orange)
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text("Recording from \(recording.formattedDate)")
                    .font(.headline)
                
                HStack(spacing: 16) {
                    Label(recording.formattedDuration, systemImage: "clock")
                    Label(recording.formattedFileSize, systemImage: "doc")
                    Label("\(recording.chunkCount) chunks", systemImage: "square.stack.3d.up")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 8) {
                Button {
                    Task {
                        isRecovering = true
                        await onRecover()
                        isRecovering = false
                    }
                } label: {
                    if isRecovering {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Label("Recover", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRecovering)
                
                Button(role: .destructive) {
                    onDiscard()
                } label: {
                    Label("Discard", systemImage: "trash")
                }
                .disabled(isRecovering)
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
    }
}

struct RecoveryProgressOverlay: View {
    let progress: Double
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView(value: progress) {
                    Text("Recovering Recording...")
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
