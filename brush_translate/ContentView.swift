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
    @State private var revealAPIKey = false
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

            SettingField(theme: theme, title: "Deepseek API Key", caption: "用于调用大模型翻译，仅保存在本机") {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Group {
                            if revealAPIKey {
                                TextField("在此粘贴你的 API Key", text: $model.deepseekAPIKey)
                                    .textFieldStyle(.plain)
                            } else {
                                SecureField("在此粘贴你的 API Key", text: $model.deepseekAPIKey)
                                    .textFieldStyle(.plain)
                            }
                        }
                        .foregroundColor(theme.sourceText)
                        .padding(.vertical, 2)
                        .frame(maxWidth: 200)
                        .formFieldBackground(theme)

                        Button(action: { revealAPIKey.toggle() }) {
                            Image(systemName: revealAPIKey ? "eye.slash" : "eye")
                                .foregroundColor(theme.translateText)
                        }
                        .buttonStyle(.plain)
                        .help(revealAPIKey ? "隐藏密钥" : "显示密钥")
                    }

                    HStack(spacing: 8) {
                        if model.deepseekAPIKey.isEmpty {
                            Image(systemName: "lock.slash")
                                .foregroundColor(Color.orange)
                            Text("未配置密钥，翻译将无法调用大模型接口。")
                                .foregroundColor(theme.translateText)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(Color.green)
                            Text("已保存到本机，仅用于翻译调用。")
                                .foregroundColor(theme.translateText)
                        }
                    }
                    .font(.footnote)
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

    private var currentHotKeyKeys: [String] {
        (pendingHotKey ?? model.hotKeyDefinition).displayKeys
    }

    private func handleShortcutAction() {
        if isEditingShortcut {
            guard let pendingHotKey else { return }
            model.hotKeyDefinition = pendingHotKey
            self.pendingHotKey = nil
            isEditingShortcut = false
            keyCaptureMonitor.stop()
            return
        }

        isEditingShortcut = true
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
    private let toolbarItemSize: CGFloat = 28
    private let cardEdgePadding: CGFloat = 20
    private let toastBottomPadding: CGFloat = 26

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
        .onChange(of: data.toast != nil) { hasToast in
            if !hasToast {
                toastHeight = 0
            }
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
                if let inlineToast = data.inlineToast {
                    ToastView(toast: inlineToast, theme: theme)
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    Text(data.translatedText.isEmpty ? "翻译失败" : data.translatedText)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(theme.errorText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.leading)
                }
                if let onRetry = data.onRetry {
                    Button("重试", action: onRetry)
                        .buttonStyle(.borderedProminent)
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
