import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?
    var popover = NSPopover()
    var hotkeyMonitor: Any?
    var isCurrentlyRecording = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        AXIsProcessTrustedWithOptions(options as CFDictionary)
        print("AppDelegate launched successfully")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Dictation")
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover.contentSize = NSSize(width: 400, height: 200)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: ContentView())

        var lastOptionPressTime: Date?

        hotkeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { event in
            let optionIsDown = event.modifierFlags.contains(.option)
            guard optionIsDown else { return }

            let now = Date()
            if let last = lastOptionPressTime, now.timeIntervalSince(last) < 0.4 {
                NotificationCenter.default.post(name: .toggleRecording, object: nil)
                lastOptionPressTime = nil
            } else {
                lastOptionPressTime = now
            }
        }
    }

    func updateMenuBarIcon(recording: Bool) {
        print("updateMenuBarIcon fired, recording is \(recording)")
        statusItem?.button?.image = nil
        statusItem?.button?.title = recording ? "RECORDING" : "idle"
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
