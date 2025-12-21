//
//  HotKeyManager.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import Carbon
import Foundation

final class HotKeyManager {
    static let shared = HotKeyManager()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handler: (() -> Void)?
    private var registeredKeyCode: UInt32?
    private var registeredModifiers: UInt32?

    private init() {}

    func register(handler: @escaping () -> Void) {
        self.handler = handler
        installHandlerIfNeeded()
    }

    func updateHotKey(keyCode: UInt32, modifiers: UInt32) {
        installHandlerIfNeeded()
        guard registeredKeyCode != keyCode || registeredModifiers != modifiers else { return }
        registerHotKey(keyCode: keyCode, modifiers: modifiers)
    }

    func unregister() {
        unregisterHotKey()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }

        handler = nil
        hotKeyRef = nil
        eventHandler = nil
        registeredKeyCode = nil
        registeredModifiers = nil
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData = userData else { return noErr }
                let hotKeyManager = Unmanaged<HotKeyManager>.fromOpaque(userData).takeUnretainedValue()
                hotKeyManager.handler?()
                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandler
        )
    }

    private func registerHotKey(keyCode: UInt32, modifiers: UInt32) {
        unregisterHotKey()
        let hotKeyID = EventHotKeyID(signature: OSType(UInt32(bigEndian: 0x42525348)), id: 1) // "BRSH"
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetEventDispatcherTarget(), 0, &hotKeyRef)
        registeredKeyCode = keyCode
        registeredModifiers = modifiers
    }

    private func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil
    }
}

struct HotKeyDefinition: Equatable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let `default` = HotKeyDefinition(keyCode: 17, modifiers: UInt32(optionKey))

    var displayKeys: [String] {
        var keys: [String] = []
        if modifiers & UInt32(controlKey) != 0 { keys.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { keys.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { keys.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { keys.append("⌘") }
        keys.append(HotKeyDefinition.keyLabel(for: keyCode))
        return keys
    }

    static func from(event: NSEvent) -> HotKeyDefinition? {
        let modifiers = carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else { return nil }
        return HotKeyDefinition(keyCode: UInt32(event.keyCode), modifiers: modifiers)
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        return modifiers
    }

    private static func keyLabel(for keyCode: UInt32) -> String {
        if let label = keyDisplayMap[keyCode] {
            return label
        }
        return "Key\(keyCode)"
    }

    private static let keyDisplayMap: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩︎",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
        45: "N", 46: "M", 47: ".", 48: "⇥", 49: "␣", 50: "`", 51: "⌫",
        53: "⎋", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}
