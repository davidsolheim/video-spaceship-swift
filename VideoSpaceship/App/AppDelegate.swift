import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Setup menu bar icon
        setupMenuBar()
        
        // Configure app to stay running when windows are closed
        NSApp.setActivationPolicy(.regular)
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        // Cleanup: Stop any ongoing recordings
        Task {
            await RecordingManager.shared.cleanup()
        }
    }
    
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "video.circle.fill", accessibilityDescription: "Video Spaceship")
            button.action = #selector(statusBarButtonClicked)
            button.target = self
        }
    }
    
    @objc private func statusBarButtonClicked() {
        // Show main window or menu
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
