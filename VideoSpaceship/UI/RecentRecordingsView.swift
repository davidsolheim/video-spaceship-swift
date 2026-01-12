import SwiftUI

struct RecentRecordingsView: View {
    @StateObject private var storage = RecordingStorage.shared
    @State private var selectedRecording: Recording?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Recent Recordings")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    Task {
                        await RecordingManager.shared.refreshAvailableDevices()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .padding()
            
            Divider()
            
            // Recordings list
            if storage.recordings.isEmpty {
                EmptyRecordingsView()
            } else {
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.adaptive(minimum: 300), spacing: 16)
                    ], spacing: 16) {
                        ForEach(storage.recordings) { recording in
                            RecordingCard(recording: recording)
                                .onTapGesture {
                                    selectedRecording = recording
                                }
                        }
                    }
                    .padding()
                }
            }
        }
        .sheet(item: $selectedRecording) { recording in
            RecordingDetailView(recording: recording)
        }
    }
}

struct EmptyRecordingsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "video.slash")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Recordings Yet")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Start recording to see your videos here")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct RecordingCard: View {
    let recording: Recording
    @StateObject private var storage = RecordingStorage.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Thumbnail placeholder
            ZStack {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(16/9, contentMode: .fit)
                
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.white)
            }
            .cornerRadius(8)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.headline)
                    .lineLimit(2)
                
                HStack {
                    Label(recording.formattedDuration, systemImage: "clock")
                    Spacer()
                    Label(recording.formattedFileSize, systemImage: "doc")
                }
                .font(.caption)
                .foregroundColor(.secondary)
                
                Text(recording.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                // Storage indicator
                HStack {
                    Image(systemName: recording.storageMode == .cloud ? "icloud.fill" : "internaldrive")
                    Text(recording.storageMode.rawValue)
                }
                .font(.caption2)
                .foregroundColor(recording.storageMode == .cloud ? .blue : .green)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct RecordingDetailView: View {
    let recording: Recording
    @Environment(\.dismiss) var dismiss
    @StateObject private var storage = RecordingStorage.shared
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            HStack {
                Text(recording.title)
                    .font(.title)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
            
            // Details
            VStack(alignment: .leading, spacing: 12) {
                DetailRow(label: "Duration", value: recording.formattedDuration)
                DetailRow(label: "File Size", value: recording.formattedFileSize)
                DetailRow(label: "Created", value: recording.formattedDate)
                DetailRow(label: "Storage", value: recording.storageMode.rawValue)
            }
            
            Spacer()
            
            // Actions
            HStack(spacing: 12) {
                Button {
                    openRecording()
                } label: {
                    Label("Open", systemImage: "play.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                
                Button {
                    revealInFinder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                
                Button(role: .destructive) {
                    deleteRecording()
                } label: {
                    Label("Delete", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .frame(width: 500, height: 400)
    }
    
    private func openRecording() {
        NSWorkspace.shared.open(recording.url)
    }
    
    private func revealInFinder() {
        NSWorkspace.shared.selectFile(recording.url.path, inFileViewerRootedAtPath: "")
    }
    
    private func deleteRecording() {
        Task {
            try? await storage.deleteLocal(recording)
            dismiss()
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}
