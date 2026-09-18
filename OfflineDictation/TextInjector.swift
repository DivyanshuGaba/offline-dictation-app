import Cocoa

struct TextInjector {
    static func paste(_ text: String) {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: AnyObject?
        let result = AXUIElementCopyAttributeValue(systemWideElement, kAXFocusedUIElementAttribute as CFString, &focusedElement)

        guard result == .success, let element = focusedElement else {
            pasteViaClipboard(text)
            return
        }

        let axElement = element as! AXUIElement
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &settable)

        if settable.boolValue {
            var currentValue: AnyObject?
            AXUIElementCopyAttributeValue(axElement, kAXValueAttribute as CFString, &currentValue)
            let existingText = (currentValue as? String) ?? ""

            var selectedRange: AnyObject?
            AXUIElementCopyAttributeValue(axElement, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

            let newValue = existingText + text
            AXUIElementSetAttributeValue(axElement, kAXValueAttribute as CFString, newValue as CFString)
        } else {
            pasteViaClipboard(text)
        }
    }

    static func pasteViaClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgSessionEventTap)
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
