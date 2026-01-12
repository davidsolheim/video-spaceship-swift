import SwiftUI
import AppKit
import ScreenCaptureKit

class RegionSelectorWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = .clear
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}

class RegionSelectorController: ObservableObject {
    @Published var selectedRegion: CGRect?
    @Published var isSelecting = false
    
    private var window: RegionSelectorWindow?
    private var completion: ((CGRect?) -> Void)?
    
    func show(on screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        self.completion = completion
        self.isSelecting = true
        
        let window = RegionSelectorWindow(screen: screen)
        let contentView = RegionSelectorView(controller: self, screenFrame: screen.frame)
        
        window.contentView = NSHostingView(rootView: contentView)
        window.makeKeyAndOrderFront(nil)
        
        self.window = window
    }
    
    func hide(with region: CGRect?) {
        window?.close()
        window = nil
        isSelecting = false
        completion?(region)
        completion = nil
    }
}

struct RegionSelectorView: View {
    @ObservedObject var controller: RegionSelectorController
    let screenFrame: CGRect
    
    @State private var startPoint: CGPoint?
    @State private var currentPoint: CGPoint?
    @State private var savedRegions: [SavedRegion] = []
    @State private var showSavedRegions = false
    
    var selectionRect: CGRect? {
        guard let start = startPoint, let current = currentPoint else { return nil }
        
        let x = min(start.x, current.x)
        let y = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)
        
        return CGRect(x: x, y: y, width: width, height: height)
    }
    
    var body: some View {
        ZStack {
            // Semi-transparent overlay
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            // Selection rectangle
            if let rect = selectionRect {
                Rectangle()
                    .stroke(Color.blue, lineWidth: 2)
                    .background(Color.blue.opacity(0.1))
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                
                // Dimensions label
                Text("\(Int(rect.width)) × \(Int(rect.height))")
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                    .position(x: rect.midX, y: rect.minY - 20)
            }
            
            // Instructions
            VStack {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Select Recording Area")
                            .font(.title2)
                            .fontWeight(.bold)
                        
                        Text("Click and drag to select a region")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 16) {
                            Button("Cancel") {
                                controller.hide(with: nil)
                            }
                            .keyboardShortcut(.escape, modifiers: [])
                            
                            if selectionRect != nil {
                                Button("Confirm") {
                                    controller.hide(with: selectionRect)
                                }
                                .keyboardShortcut(.return, modifiers: [])
                                .buttonStyle(.borderedProminent)
                            }
                            
                            Button("Saved Regions") {
                                showSavedRegions.toggle()
                            }
                        }
                    }
                    .padding()
                    .background(
                        VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                            .cornerRadius(12)
                    )
                    
                    Spacer()
                }
                .padding()
                
                Spacer()
            }
            
            // Saved regions panel
            if showSavedRegions {
                SavedRegionsPanel(
                    regions: $savedRegions,
                    onSelect: { region in
                        controller.hide(with: region.rect)
                    },
                    onClose: {
                        showSavedRegions = false
                    }
                )
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if startPoint == nil {
                        startPoint = value.startLocation
                    }
                    currentPoint = value.location
                }
                .onEnded { value in
                    if let rect = selectionRect, rect.width > 10 && rect.height > 10 {
                        // Optionally save the region
                        // controller.hide(with: rect)
                    }
                }
        )
        .onAppear {
            loadSavedRegions()
        }
    }
    
    private func loadSavedRegions() {
        if let data = UserDefaults.standard.data(forKey: "SavedRegions"),
           let regions = try? JSONDecoder().decode([SavedRegion].self, from: data) {
            savedRegions = regions
        }
    }
    
    private func saveRegion(_ rect: CGRect, name: String) {
        let region = SavedRegion(name: name, rect: rect)
        savedRegions.append(region)
        
        if let data = try? JSONEncoder().encode(savedRegions) {
            UserDefaults.standard.set(data, forKey: "SavedRegions")
        }
    }
}

struct SavedRegionsPanel: View {
    @Binding var regions: [SavedRegion]
    let onSelect: (SavedRegion) -> Void
    let onClose: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saved Regions")
                    .font(.headline)
                
                Spacer()
                
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
            }
            
            if regions.isEmpty {
                Text("No saved regions")
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(regions) { region in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(region.name)
                                        .font(.subheadline)
                                    Text("\(Int(region.rect.width)) × \(Int(region.rect.height))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Button("Use") {
                                    onSelect(region)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                            .padding(8)
                            .background(Color(NSColor.controlBackgroundColor))
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(width: 300)
        .background(
            VisualEffectBlur(material: .hudWindow, blendingMode: .behindWindow)
                .cornerRadius(12)
        )
        .shadow(radius: 10)
        .position(x: 200, y: 200)
    }
}

struct SavedRegion: Identifiable, Codable {
    let id: UUID
    let name: String
    let rect: CGRect
    
    init(id: UUID = UUID(), name: String, rect: CGRect) {
        self.id = id
        self.name = name
        self.rect = rect
    }
}

// CGRect Codable extension
extension CGRect: Codable {
    enum CodingKeys: String, CodingKey {
        case x, y, width, height
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let x = try container.decode(CGFloat.self, forKey: .x)
        let y = try container.decode(CGFloat.self, forKey: .y)
        let width = try container.decode(CGFloat.self, forKey: .width)
        let height = try container.decode(CGFloat.self, forKey: .height)
        self.init(x: x, y: y, width: width, height: height)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(origin.x, forKey: .x)
        try container.encode(origin.y, forKey: .y)
        try container.encode(size.width, forKey: .width)
        try container.encode(size.height, forKey: .height)
    }
}
