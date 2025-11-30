//
//  TranslationOverlayController.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import SwiftUI

final class TranslationOverlayController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var isHovering = false
    private var trackingArea: NSTrackingArea?
    private var eventMonitor: Any?

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
            self.repositionPanelToMouseCenter()
            self.panel?.makeKeyAndOrderFront(nil)
            self.panel?.orderFrontRegardless()
            self.panel?.alphaValue = 0
            self.isHovering = false
            self.addClickAwayRecognizer()

            NSApp.activate(ignoringOtherApps: true)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.1
                self.panel?.animator().alphaValue = 1
            }

        }
    }

    private func handleHover(isHovering: Bool) {
        self.isHovering = isHovering
        if isHovering {
//            dismissTask?.cancel()
        } else {
            // no auto-hide; will hide on click-away/double-click
        }
    }

    func hide() {
        clearMonitor()
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
        panel.ignoresMouseEvents = false
        panel.delegate = self

        self.panel = panel
    }

    private func addClickAwayRecognizer() {
        guard let panel else { return }
        panel.acceptsMouseMovedEvents = true
        panel.level = .screenSaver

        let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(handleClickOutside(_:)))
        clickRecognizer.buttonMask = 0x1 // left click
        clickRecognizer.numberOfClicksRequired = 1
        clickRecognizer.delaysPrimaryMouseButtonEvents = false
        panel.contentView?.addGestureRecognizer(clickRecognizer)

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.buttonMask = 0x1
        panel.contentView?.addGestureRecognizer(doubleClick)

        // Track clicks outside the panel
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self, let panel = self.panel else { return event }
            // Convert click to panel content coordinates to decide outside/inside
            let screenPoint: NSPoint
            if let win = event.window {
                screenPoint = win.convertToScreen(NSRect(origin: event.locationInWindow, size: .zero)).origin
            } else {
                screenPoint = event.locationInWindow
            }
            let panelPoint = panel.convertPoint(fromScreen: screenPoint)
            if let contentView = panel.contentView {
                let localPoint = contentView.convert(panelPoint, from: nil)
                if !contentView.bounds.contains(localPoint) {
                    self.hide()
                    return nil
                }
            } else {
                self.hide()
                return nil
            }
            return event
        }
    }

    @objc private func handleClickOutside(_ sender: NSGestureRecognizer) {
        // gesture handled in local monitor
    }

    @objc private func handleDoubleClick(_ sender: NSGestureRecognizer) {
        hide()
    }

    private func clearMonitor() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        hide()
    }

    private func repositionPanelToMouseCenter() {
        guard let panel = panel else { return }
        let mouseLocation = NSEvent.mouseLocation
        var frame = panel.frame

        frame.origin = NSPoint(x: mouseLocation.x - frame.width / 2,
                               y: mouseLocation.y - frame.height / 2)

        if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouseLocation) }) {
            let maxX = screen.visibleFrame.maxX - frame.width
            let maxY = screen.visibleFrame.maxY - frame.height
            frame.origin.x = max(screen.visibleFrame.minX, min(frame.origin.x, maxX))
            frame.origin.y = max(screen.visibleFrame.minY, min(frame.origin.y, maxY))
        }

        panel.setFrame(frame, display: true, animate: false)
    }
}
