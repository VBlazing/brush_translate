//
//  ContentView.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel
    @State private var revealedProviders = Set<TranslationProvider>()
    @State private var expandedProviders = Set<TranslationProvider>()
    @State private var hoveredProvider: TranslationProvider?
    @State private var verifyingProviders = Set<TranslationProvider>()
    @State private var verificationResults: [TranslationProvider: VerificationResult] = [:]
    @State private var isEditingShortcut = false
    @State private var pendingHotKey: HotKeyDefinition?
    @State private var keyCaptureMonitor = KeyCaptureMonitor()
    @State private var saveButtonFrame: CGRect = .zero

    private var theme: ThemeOption { model.theme }
    private var themeBinding: Binding<ThemeOption> {
        Binding(
            get: { model.theme },
            set: { newValue in
                guard model.theme != newValue else { return }
                DispatchQueue.main.async {
                    model.theme = newValue
                }
            }
        )
    }

    var body: some View {
        ZStack {
            theme.background
                .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 14) {
                    translationSection
                    modelSection
                    featureSection
                    themeSection
                }
            }
            .padding(24)
            .frame(minWidth: 720, minHeight: 560)
        }
        .environment(\.colorScheme, theme == .night ? .dark : .light)
        .onDisappear {
            cancelShortcutEditing()
        }
        .coordinateSpace(name: "settingsRoot")
        .onPreferenceChange(SaveButtonFrameKey.self) { frame in
            saveButtonFrame = frame
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onEnded { value in
                    guard isEditingShortcut else { return }
                    if !saveButtonFrame.contains(value.location) {
                        cancelShortcutEditing()
                    }
                }
        )
    }

    private var translationSection: some View {
        SettingSection(theme: theme, title: "翻译", subtitle: nil) {
            SettingField(theme: theme, title: "原文语言", caption: "待翻译语种") {
                Picker("源语言", selection: $model.sourceLanguage) {
                    ForEach(LanguageOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .controlSize(.regular)
                .formFieldBackground(theme)
            }

            SettingField(theme: theme, title: "译文语言", caption: "翻译的目标语言") {
                Picker("目标语言", selection: $model.targetLanguage) {
                    ForEach(LanguageOption.allCases.filter { $0 != .auto }) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .controlSize(.regular)
                .formFieldBackground(theme)
            }

            if model.sourceLanguage == model.targetLanguage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(Color.orange)
                    Text("源语言与目标语言相同，可能导致翻译无变化。")
                        .foregroundColor(theme.translateText)
                        .font(.footnote)
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.divider.opacity(0.4))
                )
            }
        }
    }

    private var modelSection: some View {
        let providers = TranslationProvider.allCases
        return SettingSection(theme: theme, title: "服务", subtitle: nil) {
            VStack(spacing: 10) {
                ForEach(providers) { provider in
                    modelProviderRow(for: provider)
                }
            }
        }
    }

    private var featureSection: some View {
        SettingSection(theme: theme, title: "功能", subtitle: nil) {
            SettingField(theme: theme, title: "翻译快捷键", caption: "选中文字后触发翻译，弹出卡片显示内容") {
                HStack(spacing: 10) {
                    Spacer()
                    HStack(spacing: 8) {
                        ShortcutPill(keys: currentHotKeyKeys, theme: theme)
                        VStack(alignment: .trailing, spacing: 6) {
                            Button(action: handleShortcutAction) {
                                Text(isEditingShortcut ? "保存" : "修改")
                            }
                            .background(
                                GeometryReader { proxy in
                                    Color.clear.preference(
                                        key: SaveButtonFrameKey.self,
                                        value: proxy.frame(in: .named("settingsRoot"))
                                    )
                                }
                            )
                            if isEditingShortcut {
                                Text("按下新的快捷键")
                                    .font(.footnote)
                                    .foregroundColor(theme.translateText)
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isEditingShortcut && pendingHotKey == nil)
                    }
                }
            }
        }
    }

    private var themeSection: some View {
        SettingSection(theme: theme, title: "样式", subtitle: nil) {
            SettingField(theme: theme, title: "主题配置", caption: nil) {
                Picker("主题", selection: themeBinding) {
                    ForEach(ThemeOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .formFieldBackground(theme)
            }
        }
    }

    @ViewBuilder
    private func modelProviderRow(for provider: TranslationProvider) -> some View {
        let isExpanded = expandedProviders.contains(provider)
        let isHovered = hoveredProvider == provider
        let showActions = isExpanded || isHovered
        let isSelected = model.selectedProvider == provider
        let apiKeyMissing = trimmedAPIKey(for: provider).isEmpty
        let hoverOpacity: CGFloat = theme == .night ? 0.35 : 0.32
        let hoverBackground = theme == .night
            ? theme.divider.opacity(hoverOpacity)
            : Color.black.opacity(0.05)
        let rowCornerRadius: CGFloat = 14
        let fieldWidth: CGFloat = 240
        let actionOpacity = showActions ? 1.0 : 0.0

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .foregroundColor(theme.translateText)

                Image(systemName: provider.iconName)
                    .foregroundColor(theme.sourceText)

                HStack(spacing: 6) {
                    Text(provider.displayName)
                        .font(.headline.weight(.semibold))
                        .foregroundColor(theme.sourceText)
                    if isSelected {
                        Text("已选择")
                            .font(.footnote)
                            .foregroundColor(theme.translateText)
                    }
                }

                Spacer()

                HStack(spacing: 10) {
                    if apiKeyMissing {
                        Text("未填写 API Key")
                            .font(.footnote)
                            .foregroundColor(theme.errorText)
                    }
                    Button(action: { applyProvider(provider) }) {
                        Text("应用")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.sourceText)
                    .disabled(apiKeyMissing)
                }
                .opacity(actionOpacity)
                .allowsHitTesting(showActions)
            }
            .frame(height: 48)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering {
                    hoveredProvider = provider
                } else if hoveredProvider == provider {
                    hoveredProvider = nil
                }
            }
            .onTapGesture {
                toggleProviderExpansion(provider)
            }

            if isExpanded {
                VStack(spacing: 10) {
                    Divider()
                        .background(theme.divider)
                        .padding(.bottom, 10)
                    SettingField(theme: theme, title: "模型选择", caption: nil) {
                        ModelPicker(
                            items: provider.models,
                            selection: modelSelectionBinding(for: provider),
                            theme: theme
                        )
                        .frame(width: fieldWidth)
                        .formFieldBackground(theme)
                    }

                    SettingField(theme: theme, title: "API Key", caption: nil) {
                        ZStack(alignment: .trailing) {
                            let eyeButtonInset: CGFloat = 8
                            let eyeButtonWidth: CGFloat = 16
                            Group {
                                if isAPIKeyRevealed(for: provider) {
                                    TextField("在此粘贴你的 API Key", text: apiKeyBinding(for: provider))
                                        .textFieldStyle(.plain)
                                } else {
                                    SecureField("在此粘贴你的 API Key", text: apiKeyBinding(for: provider))
                                        .textFieldStyle(.plain)
                                }
                            }
                            .foregroundColor(theme.sourceText)
                            .padding(.vertical, 2)
                            .padding(.trailing, eyeButtonWidth + eyeButtonInset * 2)

                            Button(action: { toggleAPIKeyReveal(for: provider) }) {
                                Image(systemName: isAPIKeyRevealed(for: provider) ? "eye.slash" : "eye")
                                    .foregroundColor(theme.translateText)
                            }
                            .buttonStyle(.plain)
                            .help(isAPIKeyRevealed(for: provider) ? "隐藏密钥" : "显示密钥")
                        }
                        .frame(width: fieldWidth)
                        .formFieldBackground(theme)
                    }

                    let isVerifying = verifyingProviders.contains(provider)
                    HStack {
                        Spacer()
                        HStack(spacing: 10) {
                            if isVerifying {
                                LoadingIndicator(theme: theme, size: 14, lineWidth: 2)
                            } else if let result = verificationResults[provider] {
                                HStack(spacing: 6) {
                                    Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                    Text(result.message)
                                        .font(.footnote)
                                }
                                .foregroundColor(result.isSuccess ? theme.translateText : theme.errorText)
                            }

                            Button(action: { startVerification(for: provider) }) {
                                Text("验证")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(theme.sourceText)
                            .disabled(isVerifying)
                        }
                    }
                    .padding(.top, 10)
                }
                .padding(.top, 6)
                .padding(.leading, 26)
                .padding(.bottom, 12)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .fill((isExpanded || isHovered) ? hoverBackground : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: rowCornerRadius, style: .continuous)
                .stroke(isExpanded ? theme.divider : Color.clear, lineWidth: 1)
        )
    }

    private func toggleProviderExpansion(_ provider: TranslationProvider) {
        if expandedProviders.contains(provider) {
            expandedProviders.remove(provider)
        } else {
            expandedProviders.insert(provider)
        }
    }

    private func applyProvider(_ provider: TranslationProvider) {
        normalizeModelSelection(for: provider)
        model.selectedProvider = provider
    }

    private func startVerification(for provider: TranslationProvider) {
        normalizeModelSelection(for: provider)
        verifyingProviders.insert(provider)
        verificationResults[provider] = nil
        Task {
            let result = await model.validateProvider(provider)
            await MainActor.run {
                verifyingProviders.remove(provider)
                switch result {
                case .success:
                    verificationResults[provider] = VerificationResult(message: "验证成功", isSuccess: true)
                case .failure(let error):
                    verificationResults[provider] = VerificationResult(message: error.localizedDescription, isSuccess: false)
                }
            }
        }
    }

    private func modelSelectionBinding(for provider: TranslationProvider) -> Binding<String> {
        switch provider {
        case .deepseek:
            return $model.deepseekModel
        case .doubao:
            return $model.doubaoModel
        case .gemini:
            return $model.geminiModel
        }
    }

    private func apiKeyBinding(for provider: TranslationProvider) -> Binding<String> {
        switch provider {
        case .deepseek:
            return $model.deepseekAPIKey
        case .doubao:
            return $model.doubaoAPIKey
        case .gemini:
            return $model.geminiAPIKey
        }
    }

    private func isAPIKeyRevealed(for provider: TranslationProvider) -> Bool {
        revealedProviders.contains(provider)
    }

    private func toggleAPIKeyReveal(for provider: TranslationProvider) {
        if revealedProviders.contains(provider) {
            revealedProviders.remove(provider)
        } else {
            revealedProviders.insert(provider)
        }
    }

    private func normalizeModelSelection(for provider: TranslationProvider) {
        let selection = modelSelectionBinding(for: provider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = provider.models.contains(selection) ? selection : provider.defaultModel
        if selection != resolved {
            modelSelectionBinding(for: provider).wrappedValue = resolved
        }
    }

    private func trimmedAPIKey(for provider: TranslationProvider) -> String {
        apiKeyBinding(for: provider).wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentHotKeyKeys: [String] {
        (pendingHotKey ?? model.hotKeyDefinition).displayKeys
    }

    private func handleShortcutAction() {
        if isEditingShortcut {
            guard let pendingHotKey else { return }
            model.hotKeyDefinition = pendingHotKey
            self.pendingHotKey = nil
            isEditingShortcut = false
            model.isEditingHotKey = false
            HotKeyManager.shared.setEnabled(true)
            keyCaptureMonitor.stop()
            return
        }

        isEditingShortcut = true
        model.isEditingHotKey = true
        HotKeyManager.shared.setEnabled(false)
        pendingHotKey = nil
        keyCaptureMonitor.start { event in
            if event.keyCode == 53 {
                DispatchQueue.main.async {
                    self.cancelShortcutEditing()
                }
                return true
            }
            guard let hotKey = HotKeyDefinition.from(event: event) else { return true }
            DispatchQueue.main.async {
                self.pendingHotKey = hotKey
            }
            return true
        }
    }

    private func cancelShortcutEditing() {
        pendingHotKey = nil
        isEditingShortcut = false
        model.isEditingHotKey = false
        HotKeyManager.shared.setEnabled(true)
        keyCaptureMonitor.stop()
    }
}

private struct SettingSection<Content: View>: View {
    let theme: ThemeOption
    let title: String
    let subtitle: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(theme.sourceText)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundColor(theme.translateText)
                }
            }
            Divider()
                .background(theme.divider)
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                )
                .shadow(color: theme.shadow.opacity(0.16), radius: 22, y: 12)
        )
    }
}

private struct SettingField<Content: View>: View {
    let theme: ThemeOption
    let title: String
    let caption: String?
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(theme.sourceText)
                if let caption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundColor(theme.translateText)
                }
            }
            Spacer()
            content
        }
    }
}

private extension View {
    func formFieldBackground(_ theme: ThemeOption) -> some View {
        self
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.divider, lineWidth: 1)
                    )
            )
    }
}

private struct ShortcutPill: View {
    let keys: [String]
    let theme: ThemeOption

    var body: some View {
        HStack(spacing: 6) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.callout.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(theme.background)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(theme.divider, lineWidth: 1)
                    )
                    .foregroundColor(theme.sourceText)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.cardBackground.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(theme.divider, lineWidth: 1)
                )
        )
    }
}

private final class KeyCaptureMonitor {
    private var monitor: Any?

    func start(handler: @escaping (NSEvent) -> Bool) {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if handler(event) {
                return nil
            }
            return event
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    deinit {
        stop()
    }
}

private struct SaveButtonFrameKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct ThemeChoiceRow: View {
    let option: ThemeOption
    let isSelected: Bool
    let theme: ThemeOption
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ThemePreview(option: option)
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.displayName)
                        .foregroundColor(theme.sourceText)
                        .font(.subheadline.weight(.semibold))
                    Text(option == .night ? "暗色背景配合柔和的翻译卡片" : "浅色背景配合纯净卡片")
                        .foregroundColor(theme.translateText)
                        .font(.footnote)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color.green)
                }
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? theme.divider.opacity(0.4) : Color.clear)
        )
    }
}

private struct ThemePreview: View {
    let option: ThemeOption

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(option.background)
            .overlay(
                VStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(option.cardBackground)
                        .frame(width: 46, height: 16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(option.divider, lineWidth: 1)
                        )
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(option.cardBackground.opacity(0.9))
                        .frame(width: 46, height: 10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(option.divider.opacity(0.8), lineWidth: 0.8)
                        )
                }
            )
            .frame(width: 64, height: 52)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(option.sourceText.opacity(0.15), lineWidth: 1)
            )
    }
}

private struct ModelPicker: NSViewRepresentable {
    let items: [String]
    @Binding var selection: String
    let theme: ThemeOption

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton()
        button.isBordered = false
        button.pullsDown = false
        button.focusRingType = .none
        button.target = context.coordinator
        button.action = #selector(Coordinator.didSelect(_:))
        context.coordinator.configure(button: button, items: items, selection: selection, theme: theme)
        return button
    }

    func updateNSView(_ nsView: NSPopUpButton, context: Context) {
        context.coordinator.configure(button: nsView, items: items, selection: selection, theme: theme)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    final class Coordinator: NSObject {
        @Binding var selection: String

        init(selection: Binding<String>) {
            _selection = selection
        }

        func configure(button: NSPopUpButton, items: [String], selection: String, theme: ThemeOption) {
            if button.menu == nil {
                button.menu = NSMenu()
            }
            button.menu?.autoenablesItems = false
            let currentItems = button.itemArray.map { $0.title }
            let menuWidth = MenuItemView.menuWidth(for: items)
            if currentItems != items {
                button.removeAllItems()
                for item in items {
                    let menuItem = NSMenuItem()
                    menuItem.title = item
                    menuItem.target = self
                    menuItem.action = #selector(menuItemSelected(_:))
                    let view = MenuItemView(
                        title: item,
                        isSelected: item == selection,
                        theme: theme
                    )
                    view.frame = NSRect(x: 0, y: 0, width: menuWidth, height: MenuItemView.rowHeight)
                    view.onSelect = { [weak self] title in
                        self?.selection = title
                        button.selectItem(withTitle: title)
                    }
                    menuItem.view = view
                    button.menu?.addItem(menuItem)
                }
            } else {
                for menuItem in button.itemArray {
                    if let view = menuItem.view as? MenuItemView {
                        view.update(isSelected: menuItem.title == selection, theme: theme)
                    }
                }
            }

            if let index = items.firstIndex(of: selection) {
                button.selectItem(at: index)
            } else if let first = items.first {
                button.selectItem(withTitle: first)
                self.selection = first
            }
        }

        @objc func didSelect(_ sender: NSPopUpButton) {
            if let title = sender.selectedItem?.title {
                selection = title
            }
        }

        @objc private func menuItemSelected(_ sender: NSMenuItem) {
            selection = sender.title
        }
    }

    private final class MenuItemView: NSView {
        static let rowHeight: CGFloat = 30
        private let titleLabel = NSTextField(labelWithString: "")
        private let checkmark = NSImageView()
        private let highlightView = NSView()
        private var tracking: NSTrackingArea?
        private var isHovering = false
        private var isSelected = false
        private var theme: ThemeOption = .night
        var onSelect: ((String) -> Void)?

        init(title: String, isSelected: Bool, theme: ThemeOption) {
            self.isSelected = isSelected
            self.theme = theme
            super.init(frame: .zero)
            wantsLayer = true
            layer?.cornerRadius = 8
            layer?.masksToBounds = true

            highlightView.wantsLayer = true
            highlightView.layer?.cornerRadius = 8
            highlightView.translatesAutoresizingMaskIntoConstraints = false

            checkmark.image = NSImage(systemSymbolName: "checkmark", accessibilityDescription: nil)
            checkmark.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .semibold)
            checkmark.translatesAutoresizingMaskIntoConstraints = false

            titleLabel.stringValue = title
            titleLabel.translatesAutoresizingMaskIntoConstraints = false
            titleLabel.alignment = .left

            addSubview(highlightView)
            addSubview(checkmark)
            addSubview(titleLabel)

            NSLayoutConstraint.activate([
                highlightView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
                highlightView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
                highlightView.centerYAnchor.constraint(equalTo: centerYAnchor),
                highlightView.heightAnchor.constraint(equalToConstant: 24),

                checkmark.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                checkmark.centerYAnchor.constraint(equalTo: centerYAnchor),
                checkmark.widthAnchor.constraint(equalToConstant: 14),
                checkmark.heightAnchor.constraint(equalToConstant: 14),

                titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 32),
                titleLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
            ])

            update(isSelected: isSelected, theme: theme)
        }

        required init?(coder: NSCoder) {
            nil
        }

        override var intrinsicContentSize: NSSize {
            NSSize(width: 240, height: Self.rowHeight)
        }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking {
                removeTrackingArea(tracking)
            }
            let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
            let area = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }

        override func mouseEntered(with event: NSEvent) {
            isHovering = true
            updateBackground()
        }

        override func mouseExited(with event: NSEvent) {
            isHovering = false
            updateBackground()
        }

        override func mouseDown(with event: NSEvent) {
            onSelect?(titleLabel.stringValue)
            enclosingMenuItem?.menu?.cancelTracking()
        }

        override var acceptsFirstResponder: Bool {
            false
        }

        func update(isSelected: Bool, theme: ThemeOption) {
            self.isSelected = isSelected
            self.theme = theme
            checkmark.isHidden = !isSelected
            checkmark.contentTintColor = theme.sourceTextNSColor
            titleLabel.textColor = theme.sourceTextNSColor
            updateBackground()
        }

        private func updateBackground() {
            let hoverColor: NSColor = theme == .night
                ? NSColor.white.withAlphaComponent(0.12)
                : NSColor.black.withAlphaComponent(0.08)
            highlightView.layer?.backgroundColor = isHovering ? hoverColor.cgColor : NSColor.clear.cgColor
        }

        static func menuWidth(for items: [String]) -> CGFloat {
            let font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
            let textWidth = items
                .map { ($0 as NSString).size(withAttributes: [.font: font]).width }
                .max() ?? 120
            let padding: CGFloat = 10 + 14 + 8 + 10
            return max(220, ceil(textWidth + padding + 32))
        }
    }
}

private extension ThemeOption {
    var sourceTextNSColor: NSColor {
        switch self {
        case .night:
            return NSColor(srgbRed: 240/255, green: 240/255, blue: 242/255, alpha: 1)
        case .light:
            return NSColor(srgbRed: 28/255, green: 28/255, blue: 30/255, alpha: 1)
        }
    }
}

struct TranslationCardView: View {
    let data: TranslationCardData
    let theme: ThemeOption
    let onHoverChange: (Bool) -> Void
    let onSpeak: (() -> Void)?
    let onSaveNote: (() -> Void)?
    let onAnalyze: (() -> Void)?

    @State private var hoverSpeak = false
    @State private var hoverNote = false
    @State private var hoverAnalyze = false
    @State private var toastHeight: CGFloat = 0
    @State private var selectedSourceLanguage: LanguageOption
    @State private var hoverRetry = false
    private let toolbarItemSize: CGFloat = 28
    private let cardEdgePadding: CGFloat = 20
    private let toastBottomPadding: CGFloat = 26

    init(
        data: TranslationCardData,
        theme: ThemeOption,
        onHoverChange: @escaping (Bool) -> Void,
        onSpeak: (() -> Void)?,
        onSaveNote: (() -> Void)?,
        onAnalyze: (() -> Void)?
    ) {
        self.data = data
        self.theme = theme
        self.onHoverChange = onHoverChange
        self.onSpeak = onSpeak
        self.onSaveNote = onSaveNote
        self.onAnalyze = onAnalyze
        _selectedSourceLanguage = State(initialValue: data.selectedSourceLanguage)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                toolbar
                    .padding(.bottom, 20)
                VStack() {
                    sourceSection
                        .padding(.bottom, 25)
                    VStack {
                        translationSection
                        wordPartsSection
                        selectedComponentsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 20)
                Spacer()
            }
            .padding(.vertical, cardEdgePadding)
            .padding(.horizontal, 20)
            .padding(.bottom, data.toast == nil ? 0 : toastHeight)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.cardBackground)
                    .shadow(color: theme.shadow, radius: 28, y: 12)
            )
            .frame(width: 520)
            .edgesIgnoringSafeArea(.all)
            if let toast = data.toast {
                VStack {
                    Spacer()
                    ToastView(toast: toast, theme: theme)
                        .padding(.bottom, toastBottomPadding)
                        .background(
                            GeometryReader { proxy in
                                Color.clear
                                    .preference(key: ToastHeightPreferenceKey.self, value: proxy.size.height)
                            }
                        )
                }
                .frame(maxHeight: .infinity)
            }
        }
        .onPreferenceChange(ToastHeightPreferenceKey.self) { height in
            if data.toast != nil {
                toastHeight = height
            }
        }
        .onChange(of: data.toast != nil) { _, hasToast in
            if !hasToast {
                toastHeight = 0
            }
        }
        .onChange(of: data.selectedSourceLanguage) { _, newValue in
            selectedSourceLanguage = newValue
        }
        .onHover { hovering in
            onHoverChange(hovering)
        }
    }

    @ViewBuilder
    private var sourceSection: some View {
        if data.sourceText.isEmpty {
            Text("未获取到选中文本")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.sourceText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
        } else if data.status == .success,
                  data.analysisType == .sentence,
                  let analysis = data.analysis,
                  let segments = SentenceSegmentation.segments(sourceText: data.sourceText, components: analysis.components) {
            FlowLayout(spacing: 0) {
                ForEach(segments) { segment in
                    SentenceSegmentView(
                        segment: segment,
                        theme: theme,
                        selectedIDs: data.selectedComponentIDs,
                        onToggle: data.onToggleComponent
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            Text(data.sourceText)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.sourceText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
        }
    }

    @ViewBuilder
    private var selectedComponentsSection: some View {
        if data.status == .success,
           data.analysisType == .sentence,
           let analysis = data.analysis,
           !data.selectedComponentIDs.isEmpty {
            SelectedComponentsView(
                analysis: analysis,
                selectedIDs: data.selectedComponentIDs,
                theme: theme
            )
            .padding(.top, 14)
        }
    }

    private var toolbar: some View {
        HStack(spacing: 2) {
            Spacer()
            Button(action: { onSpeak?() }) {
                Image(systemName: "speaker.wave.2.fill")
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .padding(4)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.translateText.opacity(hoverSpeak ? 0.12 : 0))
            )
            .frame(width: toolbarItemSize, height: toolbarItemSize)
            .foregroundColor(theme.translateText.opacity(data.sourceText.isEmpty ? 0.3 : 1))
            .scaleEffect(hoverSpeak ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 0.12), value: hoverSpeak)
            .onHover { hover in hoverSpeak = hover }
            .disabled(data.sourceText.isEmpty)

//            Button(action: { onSaveNote?() }) {
//                Image(systemName: "note.text")
//                    .imageScale(.medium)
//            }
//            .buttonStyle(.plain)
//            .padding(4)
//            .background(
//                RoundedRectangle(cornerRadius: 10, style: .continuous)
//                    .fill(theme.translateText.opacity(hoverNote ? 0.12 : 0))
//            )
//            .foregroundColor(theme.translateText.opacity(data.sourceText.isEmpty ? 0.3 : 1))
//            .scaleEffect(hoverNote ? 1.05 : 1.0)
//            .animation(.easeInOut(duration: 0.12), value: hoverNote)
//            .onHover { hover in hoverNote = hover }
//            .disabled(data.sourceText.isEmpty)
            if data.showAnalyzeButton {
                if data.isAnalyzing {
                    LoadingIndicator(theme: theme, size: 14, lineWidth: 2)
                        .frame(width: toolbarItemSize, height: toolbarItemSize)
                } else {
                    Button(action: { onAnalyze?() }) {
                        Image(systemName: "text.magnifyingglass")
                            .imageScale(.medium)
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(theme.translateText.opacity(hoverAnalyze ? 0.12 : 0))
                    )
                    .frame(width: toolbarItemSize, height: toolbarItemSize)
                    .foregroundColor(theme.translateText.opacity(data.sourceText.isEmpty ? 0.3 : 1))
                    .scaleEffect(hoverAnalyze ? 1.05 : 1.0)
                    .animation(.easeInOut(duration: 0.12), value: hoverAnalyze)
                    .onHover { hover in hoverAnalyze = hover }
                    .disabled(data.sourceText.isEmpty)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    @ViewBuilder
    private var translationSection: some View {
        switch data.status {
        case .placeholder:
            Text("无翻译")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.translateText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
        case .loading:
            HStack(spacing: 8) {
                LoadingIndicator(theme: theme, size: 16, lineWidth: 2)
                Text("翻译中...")
                    .foregroundColor(theme.translateText)
            }
            .font(.system(size: 20, weight: .semibold))
            .lineSpacing(6)
            .frame(maxWidth: .infinity, alignment: .center)
        case .success:
            Text(data.translatedText.isEmpty ? "无翻译" : data.translatedText)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(theme.translateText)
                .frame(maxWidth: .infinity, alignment: .center)
                .multilineTextAlignment(.leading)
                .lineSpacing(6)
        case .failure:
            VStack(spacing: 12) {
                let toast = data.inlineToast ?? ToastData(
                    kind: .failure,
                    message: data.translatedText.isEmpty ? "翻译失败" : data.translatedText
                )
                ToastView(toast: toast, theme: theme)
                    .frame(maxWidth: .infinity, alignment: .center)
                if let onRetry = data.onRetry {
                    HStack(spacing: 10) {
                        if data.showLanguagePicker {
                            Picker("", selection: $selectedSourceLanguage) {
                                ForEach(LanguageOption.allCases) { option in
                                    Text(option.displayName).tag(option)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .font(.footnote)
                            .padding(.vertical, 4) 
                            .onChange(of: selectedSourceLanguage) { _, newValue in
                                data.onChangeSourceLanguage?(newValue)
                            }
                        }
                        Button(action: onRetry) {
                            Text("重试")
                                .font(.footnote)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.plain)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(hoverRetry ? theme.translateText.opacity(0.12) : theme.cardBackground)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(theme.translateText.opacity(hoverRetry ? 0.5 : 0.35), lineWidth: 1)
                        )
                        .foregroundColor(theme.translateText)
                        .animation(.easeInOut(duration: 0.12), value: hoverRetry)
                        .onHover { hovering in
                            hoverRetry = hovering
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func tagView(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(theme.translateText.opacity(0.12))
            .foregroundColor(theme.translateText)
            .clipShape(Capsule())
    }


    private struct WordLine: Hashable {
        let line: String
        let tag: String
        let text: String
    }

    @ViewBuilder
    private var wordPartsSection: some View {
        if data.status == .success,
           data.analysisType == .word,
           data.wordParts.isEmpty == false {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(wordLines(from: data.wordParts), id: \.self) { line in
                    HStack(alignment: .center, spacing: 10) {
                        tagView(title: posChineseName(for: line.tag))
                        Text(line.text)
                            .foregroundColor(theme.translateText)
                            .font(.system(size: 16, weight: .semibold))
                            .frame(alignment: .center)
                    }
                }
            }
            .frame(alignment: .center)
            .padding(.top, 18)
        }
    }

    private func wordLines(from parts: [WordPart]) -> [WordLine] {
        parts.map { part in
            WordLine(line: "\(part.wordClass) \(part.content)", tag: part.wordClass, text: part.content)
        }
    }
}

private struct SentenceSegmentView: View {
    let segment: SentenceRenderSegment
    let theme: ThemeOption
    let selectedIDs: Set<SentenceComponentID>
    let onToggle: ((SentenceComponentID) -> Void)?

    @State private var isHovering = false

    private var componentID: SentenceComponentID? { segment.componentID }

    private var isInteractive: Bool { componentID != nil }

    private var isSelected: Bool {
        guard let componentID else { return false }
        return selectedIDs.contains(componentID)
    }

    private var backgroundOpacity: Double {
        if isSelected { return 0.22 }
        if isHovering { return 0.12 }
        return 0
    }

    var body: some View {
        Text(segment.text)
            .font(.system(size: 20, weight: .semibold))
            .foregroundColor(theme.sourceText)
            .padding(.vertical, 3)
            .padding(.horizontal, isInteractive ? 6 : 0)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(theme.translateText.opacity(backgroundOpacity))
            )
            .animation(.easeInOut(duration: 0.2), value: isHovering)
            .animation(.easeInOut(duration: 0.2), value: isSelected)
            .contentShape(Rectangle())
            .allowsHitTesting(isInteractive)
            .onHover { hovering in
                guard isInteractive else { return }
                isHovering = hovering
            }
            .onTapGesture {
                guard let componentID else { return }
                onToggle?(componentID)
            }
    }
}

private struct SelectedComponentsView: View {
    let analysis: SentenceAnalysis
    let selectedIDs: Set<SentenceComponentID>
    let theme: ThemeOption

    private var selectedComponents: [SentenceAnalysis.Component] {
        analysis.components
            .sorted { $0.start < $1.start }
            .filter { selectedIDs.contains($0.id) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(selectedComponents, id: \.id) { component in
                VStack(alignment: .leading, spacing: 6) {
                    Text(component.text)
                        .foregroundColor(theme.translateText)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 2)

                    HStack(alignment: .center, spacing: 10) {
                        tagView(title: posChineseName(for: component.wordClass))
                        Text(component.translation)
                            .foregroundColor(theme.translateText.opacity(0.9))
                            .font(.system(size: 15, weight: .medium))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(width: 300, alignment: .center)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(theme.translateText.opacity(0.08))
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .opacity
                    )
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .animation(.easeInOut(duration: 0.3), value: selectedIDs)
    }

    private func tagView(title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(theme.translateText.opacity(0.12))
            .foregroundColor(theme.translateText)
            .clipShape(Capsule())
    }

}

private func posChineseName(for wordClass: String) -> String {
    switch wordClass.trimmingCharacters(in: .whitespacesAndNewlines) {
    case "n.": return "名词"
    case "v.": return "动词"
    case "adj.": return "形容词"
    case "adv.": return "副词"
    case "num.": return "数词"
    case "pron.": return "代词"
    case "art.": return "冠词"
    case "prep.": return "介词"
    case "conj.": return "连词"
    case "int.": return "感叹词"
    default: return wordClass.isEmpty ? "词性" : wordClass
    }
}

//I am a teacher
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .environmentObject(AppModel())
    }
}

struct TranslationCardData {
    enum Status {
        case placeholder
        case loading
        case success
        case failure
    }

    let sourceText: String
    let translatedText: String
    let analysisType: AnalysisTextType?
    let wordParts: [WordPart]
    let analysis: SentenceAnalysis?
    let selectedComponentIDs: Set<SentenceComponentID>
    let status: Status
    let onRetry: (() -> Void)?
    let onSpeak: (() -> Void)?
    let onSaveNote: (() -> Void)?
    let onAnalyze: (() -> Void)?
    let onToggleComponent: ((SentenceComponentID) -> Void)?
    let showAnalyzeButton: Bool
    let isAnalyzing: Bool
    let toast: ToastData?
    let inlineToast: ToastData?
    let showLanguagePicker: Bool
    let detectedLanguageDisplayName: String?
    let selectedSourceLanguage: LanguageOption
    let onChangeSourceLanguage: ((LanguageOption) -> Void)?
}

private struct VerificationResult {
    let message: String
    let isSuccess: Bool
}

struct ToastData {
    enum Kind {
        case success
        case failure
    }
    let kind: Kind
    let message: String
}

struct ToastView: View {
    let toast: ToastData
    let theme: ThemeOption

    var body: some View {
        HStack {
            Image(systemName: toast.kind == .success ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
            Text(toast.message)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((toast.kind == .success ? theme.translateText : theme.errorText).opacity(0.12))
        )
        .foregroundColor(toast.kind == .success ? theme.translateText : theme.errorText)
    }
}

private struct ToastHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct LoadingIndicator: View {
    let theme: ThemeOption
    let size: CGFloat
    let lineWidth: CGFloat

    @State private var rotation = Angle.degrees(0)

    var body: some View {
        Circle()
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        theme.translateText.opacity(0.1),
                        theme.translateText.opacity(0.9),
                        theme.translateText.opacity(0.1)
                    ]),
                    center: .center
                ),
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
            )
            .frame(width: size, height: size)
            .rotationEffect(rotation)
            .onAppear {
                rotation = .degrees(0)
                withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                    rotation = .degrees(360)
                }
            }
    }
}
