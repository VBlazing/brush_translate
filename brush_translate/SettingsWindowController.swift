//
//  SettingsWindowController.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import SwiftUI

final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?
    private weak var model: AppModel?

    private override init() {
        super.init()
    }

    func show(with model: AppModel) {
        self.model = model
        if window == nil {
            let content = ContentView().environmentObject(model)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "刷词翻译设置"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: content)
            window.center()
            window.delegate = self
            self.window = window
        }

        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        model?.enterAccessoryMode()
    }
}
