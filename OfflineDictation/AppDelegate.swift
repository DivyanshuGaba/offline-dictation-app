import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    var hotkeyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictation")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentSize = NSSize(width: 400, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())

        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.modifierFlags.contains(.option) && event.keyCode == 49 {
                NotificationCenter.default.post(name: .toggleRecording, object: nil)
            }
        }
    }

    @objc func togglePopover() {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
}
