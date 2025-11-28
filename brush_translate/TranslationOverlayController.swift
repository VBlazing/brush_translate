//
//  TranslationOverlayController.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import SwiftUI

final class TranslationOverlayController {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var isHovering = false

    func show(translation: TranslationResult, theme: ThemeOption) {
        show(view: AnyView(TranslationCardView(translation: translation, theme: theme) { [weak self] hovering in
            self?.handleHover(isHovering: hovering)
        }), theme: theme)
    }

    func showPlaceholder(message: String, theme: ThemeOption) {
        let placeholder = TranslationResult(
            originalText: "",
            translatedText: message,
            alternatives: [],
            detectedSource: "",
            target: ""
        )
        show(view: AnyView(TranslationCardView(translation: placeholder, theme: theme) { [weak self] hovering in
            self?.handleHover(isHovering: hovering)
        }), theme: theme)
    }

    private func show(view: AnyView, theme: ThemeOption) {
        DispatchQueue.main.async {
            self.dismissTask?.cancel()
            self.ensurePanel()
            self.panel?.backgroundColor = theme.panelBackgroundColor
            self.panel?.contentView = NSHostingView(rootView: view)
            if let hosting = self.panel?.contentView as? NSHostingView<AnyView> {
                let size = hosting.fittingSize
                self.panel?.setContentSize(size)
            }
            self.panel?.center()
            self.panel?.makeKeyAndOrderFront(nil)
            self.panel?.orderFrontRegardless()
            self.panel?.alphaValue = 0
            self.isHovering = false

            NSApp.activate(ignoringOtherApps: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                self.panel?.animator().alphaValue = 1
            }

            self.scheduleHide(after: 5)
        }
    }

    private func handleHover(isHovering: Bool) {
        self.isHovering = isHovering
        if isHovering {
            dismissTask?.cancel()
        } else {
            scheduleHide(after: 5)
        }
    }

    private func scheduleHide(after seconds: TimeInterval) {
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            let nanoseconds = UInt64(seconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            await MainActor.run {
                guard self?.isHovering == false else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            self.panel?.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            self?.panel?.orderOut(nil)
        }
    }

    private func ensurePanel() {
        guard panel == nil else { return }

        let style: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 320),
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]

        self.panel = panel
    }
}
