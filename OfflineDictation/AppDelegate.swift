import Cocoa
import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static var shared: AppDelegate?

    var statusItem: NSStatusItem?
    var popover = NSPopover()
    var hotkeyMonitor: Any?
    var isCurrentlyRecording = false
    var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        ProcessInfo.processInfo.disableAutomaticTermination("Menu bar app has no regular windows and must keep running")

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
        guard let button = statusItem?.button else { return }
        button.title = ""

        let symbol = recording ? "mic.fill.badge.plus" : "mic.fill"
        let description = recording ? "Recording" : "Dictation"
        guard let base = NSImage(systemSymbolName: symbol, accessibilityDescription: description) else { return }

        if recording {
            let config = NSImage.SymbolConfiguration(paletteColors: [.systemRed, .systemRed])
            let colored = base.withSymbolConfiguration(config) ?? base
            colored.isTemplate = false
            button.image = colored
        } else {
            base.isTemplate = true
            button.image = base
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


    @objc func openSettings() {
        print("openSettings called")

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 320, height: 220),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView())
        settingsWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow, closedWindow === settingsWindow else { return }
        settingsWindow = nil
    }
}

extension Notification.Name {
    static let toggleRecording = Notification.Name("toggleRecording")
}
