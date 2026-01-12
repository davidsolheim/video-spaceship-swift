import SwiftUI
import ScreenCaptureKit
import AppKit

struct MultiMonitorPicker: View {
    @Binding var selectedDisplay: SCDisplay?
    let displays: [SCDisplay]
    
    @State private var displayThumbnails: [UInt32: NSImage] = [:]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Select Display")
                .font(.headline)
            
            if displays.isEmpty {
                Text("No displays available")
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(displays, id: \.displayID) { display in
                            DisplayCard(
                                display: display,
                                thumbnail: displayThumbnails[display.displayID],
                                isSelected: selectedDisplay?.displayID == display.displayID
                            )
                            .onTapGesture {
                                selectedDisplay = display
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .onAppear {
            generateThumbnails()
        }
    }
    
    private func generateThumbnails() {
        Task {
            for display in displays {
                if let thumbnail = await captureThumbnail(for: display) {
                    await MainActor.run {
                        displayThumbnails[display.displayID] = thumbnail
                    }
                }
            }
        }
    }
    
    private func captureThumbnail(for display: SCDisplay) async -> NSImage? {
        // Use CGDisplayCreateImage to capture display thumbnail
        guard let cgImage = CGDisplayCreateImage(display.displayID) else {
            return nil
        }
        
        // Scale down for thumbnail
        let targetWidth: CGFloat = 320
        let scale = targetWidth / CGFloat(cgImage.width)
        let targetHeight = CGFloat(cgImage.height) * scale
        
        let size = NSSize(width: targetWidth, height: targetHeight)
        let image = NSImage(cgImage: cgImage, size: size)
        
        return image
    }
}

struct DisplayCard: View {
    let display: SCDisplay
    let thumbnail: NSImage?
    let isSelected: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Thumbnail
            ZStack {
                if let thumbnail = thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 320, height: 180)
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .frame(width: 320, height: 180)
                        .cornerRadius(8)
                        .overlay {
                            ProgressView()
                        }
                }
                
                // Primary badge
                if isPrimaryDisplay(display) {
                    VStack {
                        HStack {
                            Text("Primary")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                            
                            Spacer()
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
            
            // Display info
            VStack(alignment: .leading, spacing: 4) {
                Text("Display \(display.displayID)")
                    .font(.headline)
                
                Text("\(display.width) × \(display.height)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 3)
                )
        )
        .shadow(radius: isSelected ? 8 : 2)
    }
    
    private func isPrimaryDisplay(_ display: SCDisplay) -> Bool {
        return display.displayID == CGMainDisplayID()
    }
}

// Enhanced screen selection view for RecordView
struct EnhancedScreenSelectionView: View {
    @EnvironmentObject var recordingManager: RecordingManager
    @Binding var selectedScreen: SCDisplay?
    @State private var showRegionSelector = false
    @State private var selectedRegion: CGRect?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Screen Source")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    showRegionSelector = true
                } label: {
                    Label("Select Region", systemImage: "crop")
                }
            }
            
            MultiMonitorPicker(
                selectedDisplay: $selectedScreen,
                displays: recordingManager.availableScreens
            )
            
            if let region = selectedRegion {
                HStack {
                    Image(systemName: "crop")
                    Text("Custom region: \(Int(region.width)) × \(Int(region.height))")
                        .font(.caption)
                    
                    Button {
                        selectedRegion = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .sheet(isPresented: $showRegionSelector) {
            if let screen = selectedScreen,
               let nsScreen = NSScreen.screens.first(where: { $0.displayID == screen.displayID }) {
                RegionSelectorSheet(screen: nsScreen) { region in
                    selectedRegion = region
                    showRegionSelector = false
                }
            }
        }
    }
}

struct RegionSelectorSheet: View {
    let screen: NSScreen
    let onComplete: (CGRect?) -> Void
    
    @StateObject private var controller = RegionSelectorController()
    
    var body: some View {
        VStack {
            Text("Region selector will open in a new window")
                .padding()
        }
        .onAppear {
            controller.show(on: screen) { region in
                onComplete(region)
            }
        }
    }
}

// Extension to get display ID from NSScreen
extension NSScreen {
    var displayID: UInt32 {
        return deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
    }
}
