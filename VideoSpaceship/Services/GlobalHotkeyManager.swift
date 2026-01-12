import Foundation
import Carbon
import AppKit

class GlobalHotkeyManager {
    static let shared = GlobalHotkeyManager()
    
    private var hotkeys: [HotkeyAction: EventHotKeyRef?] = [:]
    private var eventHandler: EventHandlerRef?
    
    private init() {
        setupEventHandler()
    }
    
    deinit {
        cleanup()
    }
    
    // MARK: - Setup
    
    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (nextHandler, event, userData) -> OSStatus in
                var hotkeyID = EventHotKeyID()
                GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotkeyID
                )
                
                if let action = HotkeyAction(rawValue: Int(hotkeyID.id)) {
                    GlobalHotkeyManager.shared.handleHotkey(action)
                }
                
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }
    
    // MARK: - Registration
    
    func registerHotkey(_ action: HotkeyAction, keyCode: UInt32, modifiers: UInt32) {
        // Unregister existing hotkey for this action
        unregisterHotkey(action)
        
        var hotkeyRef: EventHotKeyRef?
        var hotkeyID = EventHotKeyID(signature: OSType(0x4D414E55), id: UInt32(action.rawValue)) // 'MANU'
        
        let status = RegisterEventHotKey(
            keyCode,
            modifiers,
            hotkeyID,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
        
        if status == noErr {
            hotkeys[action] = hotkeyRef
            print("Registered hotkey for \(action): keyCode=\(keyCode), modifiers=\(modifiers)")
        } else {
            print("Failed to register hotkey for \(action): \(status)")
        }
    }
    
    func unregisterHotkey(_ action: HotkeyAction) {
        if let hotkeyRef = hotkeys[action] {
            UnregisterEventHotKey(hotkeyRef)
            hotkeys[action] = nil
        }
    }
    
    func registerDefaultHotkeys() {
        // Cmd+Shift+R: Start/Stop Recording
        registerHotkey(.startStopRecording, keyCode: 15, modifiers: UInt32(cmdKey | shiftKey))
        
        // Cmd+Shift+P: Pause/Resume
        registerHotkey(.pauseResume, keyCode: 35, modifiers: UInt32(cmdKey | shiftKey))
        
        // Cmd+Shift+M: Mute/Unmute
        registerHotkey(.muteUnmute, keyCode: 46, modifiers: UInt32(cmdKey | shiftKey))
        
        // Cmd+Shift+W: Show/Hide Webcam
        registerHotkey(.toggleWebcam, keyCode: 13, modifiers: UInt32(cmdKey | shiftKey))
    }
    
    // MARK: - Handling
    
    private func handleHotkey(_ action: HotkeyAction) {
        Task { @MainActor in
            let recordingManager = RecordingManager.shared
            let appState = AppState.shared
            
            switch action {
            case .startStopRecording:
                if recordingManager.isRecording {
                    await recordingManager.stopRecording()
                } else {
                    await recordingManager.startQuickRecord()
                }
                
            case .pauseResume:
                if recordingManager.isRecording {
                    await recordingManager.togglePause()
                }
                
            case .muteUnmute:
                appState.preferences.microphoneEnabled.toggle()
                
            case .toggleWebcam:
                if recordingManager.isRecording {
                    recordingManager.toggleWebcam()
                }
            }
        }
    }
    
    // MARK: - Cleanup
    
    private func cleanup() {
        for (_, hotkeyRef) in hotkeys {
            if let ref = hotkeyRef {
                UnregisterEventHotKey(ref)
            }
        }
        hotkeys.removeAll()
        
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}

// MARK: - Hotkey Actions

enum HotkeyAction: Int, CaseIterable {
    case startStopRecording = 1
    case pauseResume = 2
    case muteUnmute = 3
    case toggleWebcam = 4
    
    var title: String {
        switch self {
        case .startStopRecording: return "Start/Stop Recording"
        case .pauseResume: return "Pause/Resume"
        case .muteUnmute: return "Mute/Unmute Microphone"
        case .toggleWebcam: return "Show/Hide Webcam"
        }
    }
    
    var defaultKeyCombo: String {
        switch self {
        case .startStopRecording: return "⌘⇧R"
        case .pauseResume: return "⌘⇧P"
        case .muteUnmute: return "⌘⇧M"
        case .toggleWebcam: return "⌘⇧W"
        }
    }
}

// MARK: - Hotkey Settings

struct HotkeySettings: Codable {
    var enabled: Bool = true
    var customBindings: [Int: KeyBinding] = [:]
}

struct KeyBinding: Codable {
    let keyCode: UInt32
    let modifiers: UInt32
    
    var displayString: String {
        var parts: [String] = []
        
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        
        // Map key code to character (simplified)
        let keyChar = keyCodeToChar(keyCode)
        parts.append(keyChar)
        
        return parts.joined()
    }
    
    private func keyCodeToChar(_ code: UInt32) -> String {
        let keyMap: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 31: "O", 32: "U", 34: "I", 35: "P",
            45: "N", 46: "M"
        ]
        return keyMap[code] ?? "?"
    }
}
