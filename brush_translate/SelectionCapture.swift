//
//  SelectionCapture.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import ApplicationServices
import CoreGraphics

enum SelectionCapture {
    static func captureSelectedText() async -> String? {
        // Prefer Accessibility path
        if requestAccessibilityPermissionIfNeeded() {
            let copied = await copyFromPasteboardSelection()
            return copied
//            if let focusedElement = focusedUIElement(),
//               let selected = selectedText(from: focusedElement),
//               selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
//                return selected.trimmingCharacters(in: .whitespacesAndNewlines)
//            }
        }

        return nil
    }

    private static func focusedUIElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var app: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &app) == .success,
              let focusedApp = app else { return nil }

        var element: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedApp as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &element) == .success,
              let focusedElement = element else { return nil }

        return (focusedElement as! AXUIElement)
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        var selected: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selected) == .success,
           let text = selected as? String {
            return text
        }

        if let fromRange = selectedTextViaRange(from: element) {
            return fromRange
        }

        var value: AnyObject?
        if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
           let text = value as? String,
           !text.isEmpty {
            return text
        }

        return nil
    }

    private static func selectedTextViaRange(from element: AXUIElement) -> String? {
        var rangeObj: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeObj) == .success,
              let rangeValue = rangeObj,
              CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              AXValueGetType(rangeValue as! AXValue) == .cfRange else {
            return nil
        }

        var cfRange = CFRange()
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &cfRange) else { return nil }

        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let fullText = value as? String else { return nil }

        let nsRange = NSRange(location: cfRange.location, length: cfRange.length)
        guard let swiftRange = Range(nsRange, in: fullText) else { return nil }
        let substring = fullText[swiftRange]
        return String(substring)
    }

    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    private static func requestAccessibilityPermissionIfNeeded() -> Bool {
        let trusted = AXIsProcessTrusted()
        if !trusted {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
        return trusted
    }

    private static func copyFromPasteboardSelection() async -> String? {
        let pasteboard = NSPasteboard.general
        let initialChangeCount = pasteboard.changeCount
        let previousData = pasteboard.data(forType: .string)
        let previousString = pasteboard.string(forType: .string)

        sendCopyShortcut()

        // Poll for a short time to avoid a fixed wait while still handling slow apps.
        let pollIntervalNs: UInt64 = 20_000_000
        let maxWaitNs: UInt64 = 200_000_000
        var waited: UInt64 = 0
        while pasteboard.changeCount == initialChangeCount, waited < maxWaitNs {
            try? await Task.sleep(nanoseconds: pollIntervalNs)
            waited += pollIntervalNs
        }

        // If the pasteboard didn't change, no selection was copied; return empty string
        guard pasteboard.changeCount != initialChangeCount else {
            return nil
        }

        var copied: String?
        if let data = pasteboard.data(forType: .string), let str = String(data: data, encoding: .utf8) {
            copied = str.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let str = pasteboard.string(forType: .string) {
            copied = str.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if let previousData {
            pasteboard.clearContents()
            pasteboard.setData(previousData, forType: .string)
        } else if let previousString {
            pasteboard.clearContents()
            pasteboard.setString(previousString, forType: .string)
        }

        return copied
    }

    private static func sendCopyShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let cKeyCode: CGKeyCode = 8

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: true)
        keyDown?.flags = .maskCommand
        keyDown?.post(tap: .cgSessionEventTap)

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: cKeyCode, keyDown: false)
        keyUp?.flags = .maskCommand
        keyUp?.post(tap: .cgSessionEventTap)
    }
}
