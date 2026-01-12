import Foundation
import CoreGraphics
import AppKit

class VisualEnhancementsManager {
    static let shared = VisualEnhancementsManager()
    
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    
    // Event tracking
    private var mouseEvents: [MouseEvent] = []
    private var keyEvents: [KeyEvent] = []
    
    // Settings
    var cursorHighlightEnabled = false
    var clickEffectsEnabled = false
    var keystrokeDisplayEnabled = false
    
    private init() {}
    
    // MARK: - Start/Stop Monitoring
    
    func startMonitoring() {
        guard eventTap == nil else { return }
        
        let eventMask = (1 << CGEventType.leftMouseDown.rawValue) |
                       (1 << CGEventType.rightMouseDown.rawValue) |
                       (1 << CGEventType.mouseMoved.rawValue) |
                       (1 << CGEventType.keyDown.rawValue)
        
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(eventMask),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                let manager = Unmanaged<VisualEnhancementsManager>.fromOpaque(refcon!).takeUnretainedValue()
                manager.handleEvent(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            print("Failed to create event tap")
            return
        }
        
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        
        eventTap = tap
    }
    
    func stopMonitoring() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            eventTap = nil
            runLoopSource = nil
        }
        
        mouseEvents.removeAll()
        keyEvents.removeAll()
    }
    
    // MARK: - Event Handling
    
    private func handleEvent(type: CGEventType, event: CGEvent) {
        let timestamp = Date()
        
        switch type {
        case .leftMouseDown, .rightMouseDown:
            if clickEffectsEnabled {
                let location = event.location
                let mouseEvent = MouseEvent(
                    timestamp: timestamp,
                    location: location,
                    type: type == .leftMouseDown ? .leftClick : .rightClick
                )
                mouseEvents.append(mouseEvent)
                
                // Keep only recent events (last 5 seconds)
                mouseEvents.removeAll { timestamp.timeIntervalSince($0.timestamp) > 5 }
            }
            
        case .mouseMoved:
            if cursorHighlightEnabled {
                // Track mouse position for cursor highlighting
                // This would be used during video composition
            }
            
        case .keyDown:
            if keystrokeDisplayEnabled {
                if let characters = event.characters {
                    let keyEvent = KeyEvent(
                        timestamp: timestamp,
                        key: characters,
                        modifiers: event.flags
                    )
                    keyEvents.append(keyEvent)
                    
                    // Keep only recent events (last 3 seconds)
                    keyEvents.removeAll { timestamp.timeIntervalSince($0.timestamp) > 3 }
                }
            }
            
        default:
            break
        }
    }
    
    // MARK: - Rendering Effects
    
    func renderCursorHighlight(at point: CGPoint, in context: CGContext, size: CGSize) {
        guard cursorHighlightEnabled else { return }
        
        // Draw spotlight effect around cursor
        let radius: CGFloat = 100
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                NSColor.yellow.withAlphaComponent(0.3).cgColor,
                NSColor.clear.cgColor
            ] as CFArray,
            locations: [0, 1]
        )
        
        if let gradient = gradient {
            context.drawRadialGradient(
                gradient,
                startCenter: point,
                startRadius: 0,
                endCenter: point,
                endRadius: radius,
                options: []
            )
        }
    }
    
    func renderClickEffects(in context: CGContext, size: CGSize, currentTime: Date) {
        guard clickEffectsEnabled else { return }
        
        for event in mouseEvents {
            let age = currentTime.timeIntervalSince(event.timestamp)
            guard age < 1.0 else { continue } // Show effect for 1 second
            
            // Animate ripple effect
            let progress = CGFloat(age)
            let radius = 20 + (progress * 30)
            let alpha = 1.0 - progress
            
            context.setStrokeColor(NSColor.blue.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(3)
            context.strokeEllipse(in: CGRect(
                x: event.location.x - radius,
                y: event.location.y - radius,
                width: radius * 2,
                height: radius * 2
            ))
        }
    }
    
    func renderKeystrokeDisplay(in context: CGContext, size: CGSize, currentTime: Date) {
        guard keystrokeDisplayEnabled else { return }
        
        // Display recent keystrokes at bottom of screen
        let displayY: CGFloat = 50
        var displayX: CGFloat = size.width / 2 - 200
        
        for event in keyEvents.suffix(10) {
            let age = currentTime.timeIntervalSince(event.timestamp)
            guard age < 3.0 else { continue }
            
            let alpha = 1.0 - (age / 3.0)
            
            // Draw key background
            let keyWidth: CGFloat = 40
            let keyHeight: CGFloat = 40
            let rect = CGRect(x: displayX, y: displayY, width: keyWidth, height: keyHeight)
            
            context.setFillColor(NSColor.black.withAlphaComponent(alpha * 0.7).cgColor)
            context.fill(rect)
            
            context.setStrokeColor(NSColor.white.withAlphaComponent(alpha).cgColor)
            context.setLineWidth(2)
            context.stroke(rect)
            
            // Draw key text
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 16, weight: .bold),
                .foregroundColor: NSColor.white.withAlphaComponent(alpha)
            ]
            
            let text = event.key.uppercased()
            let textSize = text.size(withAttributes: attributes)
            let textRect = CGRect(
                x: displayX + (keyWidth - textSize.width) / 2,
                y: displayY + (keyHeight - textSize.height) / 2,
                width: textSize.width,
                height: textSize.height
            )
            
            text.draw(in: textRect, withAttributes: attributes)
            
            displayX += keyWidth + 5
        }
    }
}

// MARK: - Event Models

struct MouseEvent {
    let timestamp: Date
    let location: CGPoint
    let type: MouseEventType
}

enum MouseEventType {
    case leftClick
    case rightClick
}

struct KeyEvent {
    let timestamp: Date
    let key: String
    let modifiers: CGEventFlags
}

// MARK: - Visual Enhancements Settings

struct VisualEnhancementsSettings: Codable {
    var cursorHighlightEnabled: Bool = false
    var cursorHighlightColor: CodableColor = CodableColor(.yellow)
    var cursorHighlightRadius: Double = 100
    
    var clickEffectsEnabled: Bool = false
    var clickEffectColor: CodableColor = CodableColor(.blue)
    var clickEffectDuration: Double = 1.0
    
    var keystrokeDisplayEnabled: Bool = false
    var keystrokeDisplayPosition: KeystrokePosition = .bottom
    var keystrokeDisplayDuration: Double = 3.0
}

enum KeystrokePosition: String, Codable, CaseIterable {
    case top = "Top"
    case bottom = "Bottom"
    case left = "Left"
    case right = "Right"
}
