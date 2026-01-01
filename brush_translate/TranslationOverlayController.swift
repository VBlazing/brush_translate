//
//  TranslationOverlayController.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import SwiftUI
import QuartzCore

@MainActor
final class TranslationOverlayController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var dismissTask: Task<Void, Never>?
    private var isHovering = false
    private var trackingArea: NSTrackingArea?
    var onDidHide: (() -> Void)?
    private let baseCollectionBehavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]

    var isVisible: Bool {
        panel?.isVisible == true
    }

    func showSuccess(
        translation: TranslationResult,
        analysis: SentenceAnalysis? = nil,
        analysisType: AnalysisTextType? = nil,
        wordParts: [WordPart] = [],
        selectedComponentIDs: Set<SentenceComponentID>? = nil,
        theme: ThemeOption,
        isAnalyzing: Bool = false,
        toast: ToastData? = nil,
        onAnalyze: (() -> Void)? = nil,
        onToggleComponent: ((SentenceComponentID) -> Void)? = nil,
        showAnalyzeButton: Bool = true
    ) {
        let data = TranslationCardData(
            sourceText: translation.originalText,
            translatedText: translation.translatedText,
            analysisType: analysisType,
            wordParts: wordParts,
            analysis: analysis,
            selectedComponentIDs: selectedComponentIDs ?? [],
            status: .success,
            onRetry: nil,
            onSpeak: { [weak self] in self?.speak(text: translation.originalText) },
            onSaveNote: { [weak self] in self?.saveNote(source: translation.originalText, translated: translation.translatedText) },
            onAnalyze: onAnalyze,
            onToggleComponent: onToggleComponent,
            showAnalyzeButton: showAnalyzeButton,
            isAnalyzing: isAnalyzing,
            toast: toast,
            inlineToast: nil,
            showLanguagePicker: false,
            detectedLanguageDisplayName: nil,
            selectedSourceLanguage: .auto,
            onChangeSourceLanguage: nil
        )
        show(view: AnyView(TranslationCardView(data: data, theme: theme, onHoverChange: { [weak self] hovering in
            self?.handleHover(isHovering: hovering)
        }, onSpeak: data.onSpeak, onSaveNote: data.onSaveNote, onAnalyze: data.onAnalyze)), theme: theme)
    }

    func showPlaceholder(theme: ThemeOption) {
        let data = TranslationCardData(
            sourceText: "",
            translatedText: "",
            analysisType: nil,
            wordParts: [],
            analysis: nil,
            selectedComponentIDs: [],
            status: .placeholder,
            onRetry: nil,
            onSpeak: nil,
            onSaveNote: nil,
            onAnalyze: nil,
            onToggleComponent: nil,
            showAnalyzeButton: false,
            isAnalyzing: false,
            toast: nil,
            inlineToast: nil,
            showLanguagePicker: false,
            detectedLanguageDisplayName: nil,
            selectedSourceLanguage: .auto,
            onChangeSourceLanguage: nil
        )
        show(view: AnyView(TranslationCardView(data: data, theme: theme, onHoverChange: { [weak self] hovering in
            self?.handleHover(isHovering: hovering)
        }, onSpeak: nil, onSaveNote: nil, onAnalyze: nil)), theme: theme)
    }

    func showLoading(sourceText: String, theme: ThemeOption) {
        let data = TranslationCardData(
            sourceText: sourceText,
            translatedText: "",
            analysisType: nil,
            wordParts: [],
            analysis: nil,
            selectedComponentIDs: [],
            status: .loading,
            onRetry: nil,
            onSpeak: nil,
            onSaveNote: nil,
            onAnalyze: nil,
            onToggleComponent: nil,
            showAnalyzeButton: false,
            isAnalyzing: false,
            toast: nil,
            inlineToast: nil,
            showLanguagePicker: false,
            detectedLanguageDisplayName: nil,
            selectedSourceLanguage: .auto,
            onChangeSourceLanguage: nil
        )
        show(view: AnyView(TranslationCardView(data: data, theme: theme, onHoverChange: { [weak self] hovering in
            self?.handleHover(isHovering: hovering)
        }, onSpeak: nil, onSaveNote: nil, onAnalyze: nil)), theme: theme)
    }

    func showFailure(
        sourceText: String,
        message: String,
        theme: ThemeOption,
        showLanguagePicker: Bool = false,
        detectedLanguageDisplayName: String? = nil,
        selectedSourceLanguage: LanguageOption,
        onChangeSourceLanguage: ((LanguageOption) -> Void)? = nil,
        inlineToast: ToastData? = nil,
        retry: @escaping () -> Void
    ) {
        let data = TranslationCardData(
            sourceText: sourceText,
            translatedText: message,
            analysisType: nil,
            wordParts: [],
            analysis: nil,
            selectedComponentIDs: [],
            status: .failure,
            onRetry: retry,
            onSpeak: { [weak self] in self?.speak(text: sourceText) },
            onSaveNote: nil,
            onAnalyze: nil,
            onToggleComponent: nil,
            showAnalyzeButton: false,
            isAnalyzing: false,
            toast: nil,
            inlineToast: inlineToast,
            showLanguagePicker: showLanguagePicker,
            detectedLanguageDisplayName: detectedLanguageDisplayName,
            selectedSourceLanguage: selectedSourceLanguage,
            onChangeSourceLanguage: onChangeSourceLanguage
        )
        show(view: AnyView(TranslationCardView(data: data, theme: theme, onHoverChange: { [weak self] hovering in
            self?.handleHover(isHovering: hovering)
        }, onSpeak: data.onSpeak, onSaveNote: data.onSaveNote, onAnalyze: data.onAnalyze)), theme: theme)
    }

    private func speak(text: String) {
        SpeechSynthesizer.shared.speak(text: text)
    }

    private func saveNote(source: String, translated: String) {
        NoteStore.shared.add(source: source, translated: translated)
    }

    private func show(view: AnyView, theme: ThemeOption) {
        DispatchQueue.main.async {
            self.dismissTask?.cancel()
            self.ensurePanel()
            guard let panel = self.panel else { return }
            let wasVisible = panel.isVisible
            let previousFrame = panel.frame
            let resizeAnimationDuration: TimeInterval = 0.28

            panel.backgroundColor = theme.panelBackgroundColor
            panel.appearance = NSAppearance(named: theme == .night ? .darkAqua : .aqua)
            if let hosting = panel.contentView as? NSHostingView<AnyView> {
                hosting.rootView = view
            } else {
                panel.contentView = NSHostingView(rootView: view)
            }

            if let hosting = panel.contentView as? NSHostingView<AnyView> {
                let size = hosting.fittingSize
                if wasVisible {
                    let oldMidX = previousFrame.midX
                    let oldTopY = previousFrame.maxY
                    var newFrame = previousFrame
                    newFrame.size = size
                    // Keep the card visually "pinned" in place when height changes:
                    // preserve top edge and horizontal center, expand downwards.
                    newFrame.origin = NSPoint(x: oldMidX - size.width / 2, y: oldTopY - size.height)
                    NSAnimationContext.runAnimationGroup { context in
                        context.duration = resizeAnimationDuration
                        context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                        panel.animator().setFrame(newFrame, display: true)
                    }
                } else {
                    panel.setContentSize(size)
                }
            }

            self.ensureCloseGestureInstalled()

            if !wasVisible {
                self.preparePanelForPresentation()
                self.repositionPanelToMouseCenter()
                panel.makeKeyAndOrderFront(nil)
                panel.orderFrontRegardless()
                self.lockPanelToCurrentSpace()
                panel.alphaValue = 0
                self.isHovering = false

                if !SettingsWindowController.shared.isVisible {
                    NSApp.activate(ignoringOtherApps: true)
                }
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.1
                    panel.animator().alphaValue = 1
                }
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
        onDidHide?()
        let panel = self.panel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            panel?.animator().alphaValue = 0
        } completionHandler: {
            panel?.orderOut(nil)
        }
    }

    func hideImmediately() {
        onDidHide?()
        panel?.alphaValue = 0
        panel?.orderOut(nil)
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
        panel.titlebarSeparatorStyle = .none
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = baseCollectionBehavior.union(.stationary)
        panel.ignoresMouseEvents = false
        panel.delegate = self

        self.panel = panel
    }

    private func preparePanelForPresentation() {
        panel?.collectionBehavior = baseCollectionBehavior.union(.moveToActiveSpace)
    }

    private func lockPanelToCurrentSpace() {
        panel?.collectionBehavior = baseCollectionBehavior.union(.stationary)
    }

    private func ensureCloseGestureInstalled() {
        guard let panel, let contentView = panel.contentView else { return }

        panel.acceptsMouseMovedEvents = true
        panel.level = .screenSaver

        let alreadyInstalled = contentView.gestureRecognizers.contains { recognizer in
            guard let click = recognizer as? NSClickGestureRecognizer else { return false }
            return click.numberOfClicksRequired == 2 && click.buttonMask == 0x1
        }
        if alreadyInstalled { return }

        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(handleDoubleClick(_:)))
        doubleClick.numberOfClicksRequired = 2
        doubleClick.buttonMask = 0x1
        contentView.addGestureRecognizer(doubleClick)
    }

    @objc private func handleDoubleClick(_ sender: NSGestureRecognizer) {
        hide()
    }

    func windowDidResignKey(_ notification: Notification) {
        // Keep the card visible; it should only be dismissed by double-click.
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
