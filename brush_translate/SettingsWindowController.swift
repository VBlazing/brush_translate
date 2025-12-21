//
//  SettingsWindowController.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import SwiftUI

final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    var isVisible: Bool {
        window?.isVisible == true
    }

    private override init() {
        super.init()
    }

    func show(with model: AppModel) {
        if window == nil {
            let content = ContentView().environmentObject(model)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "刷词翻译设置"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.moveToActiveSpace]
            window.contentView = NSHostingView(rootView: content)
            window.center()
            self.window = window
        }

        if let window {
            window.collectionBehavior = [.moveToActiveSpace]
            if let screen = SettingsWindowController.activeScreen() {
                let frame = SettingsWindowController.centeredFrame(
                    size: window.frame.size,
                    in: screen.visibleFrame
                )
                window.setFrame(frame, display: false)
            }
        }
        window?.makeKeyAndOrderFront(nil)
        if let window {
            DispatchQueue.main.async {
                window.collectionBehavior = [.stationary]
            }
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

private extension SettingsWindowController {
    static func activeScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            return screen
        }
        return NSScreen.main ?? NSScreen.screens.first
    }

    static func centeredFrame(size: CGSize, in bounds: CGRect) -> CGRect {
        let origin = CGPoint(
            x: bounds.origin.x + (bounds.size.width - size.width) / 2,
            y: bounds.origin.y + (bounds.size.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }
}
