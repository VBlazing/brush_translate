//
//  ContentView.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header
            form
            footer
        }
        .padding(24)
        .frame(minWidth: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("刷词翻译设置")
                .font(.title2)
                .bold()
            Text("菜单栏常驻 · 全局快捷键 Option + T")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Picker("源语言", selection: $model.sourceLanguage) {
                    ForEach(LanguageOption.allCases) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .frame(maxWidth: .infinity)

                Picker("目标语言", selection: $model.targetLanguage) {
                    ForEach(LanguageOption.allCases.filter { $0 != .auto }) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("快捷键：Option + T", systemImage: "keyboard")
                    .font(.subheadline)
                Text("选中文字或句子，按快捷键直接获取选区并触发翻译，结果会在屏幕中央显示。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Picker("主题", selection: $model.theme) {
                ForEach(ThemeOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
            .pickerStyle(.segmented)

            VStack(alignment: .leading, spacing: 6) {
                Text("Deepseek API Key")
                    .font(.subheadline)
                SecureField("在此粘贴你的 API Key", text: $model.deepseekAPIKey)
                    .textFieldStyle(.roundedBorder)
                Text("必须配置后才能调用大模型翻译，密钥仅保存在本机。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 12) {
                Button(action: model.triggerTranslationFromSelection) {
                    Label("翻译当前选区", systemImage: "play.fill")
                }
                Button(action: model.openSettings) {
                    Label("在菜单栏找到应用图标以快速访问", systemImage: "menubar.rectangle")
                }
                .buttonStyle(.borderless)
                .foregroundColor(.secondary)
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("状态：\(model.statusMessage)")
                .font(.footnote)
                .foregroundColor(.secondary)
            Text("如需展示释义，请在系统偏好设置中为本应用开启辅助功能权限，用以获取选中文本。")
                .font(.footnote)
                .foregroundColor(.secondary)
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
                        selectedComponentsSection
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 20)
                Spacer()
            }
            .padding(.vertical, 20)
            .padding(.horizontal, 20)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.cardBackground)
                    .shadow(color: theme.shadow, radius: 28, y: 12)
            )
            .frame(width: 520)
            .edgesIgnoringSafeArea(.all)
            if let toast = data.toast {
                ToastView(toast: toast, theme: theme)
                    .padding(.bottom, 12)
                    .frame(maxHeight: .infinity, alignment: .bottom)
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
                  data.form == .sentence,
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
           data.form == .sentence,
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
                    ProgressView()
                        .tint(theme.translateText)
                        .scaleEffect(0.5)
                        .frame(width: 28, height: 28)
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
            HStack(spacing: 6) {
                ProgressView()
                    .tint(theme.translateText)
                    .scaleEffect(0.6)
                Text("翻译中...")
                    .foregroundColor(theme.translateText)
            }
            .font(.system(size: 18, weight: .medium))
            .frame(maxWidth: .infinity, alignment: .center)
        case .success:
            if data.form == .word {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(wordLines(from: data), id: \.self) { line in
                        HStack(alignment: .center, spacing: 10) {
                            tagView(title: line.tag)
                            Text(line.text)
                                .foregroundColor(theme.translateText)
                                .font(.system(size: 16, weight: .semibold))
                                .frame(alignment: .center)
                        }
                    }
                }
                .frame(alignment: .center)
            } else {
                Text(data.translatedText.isEmpty ? "无翻译" : data.translatedText)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.translateText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(6)
            }
        case .failure:
            VStack(spacing: 12) {
                Text(data.translatedText.isEmpty ? "翻译失败" : data.translatedText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.errorText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.leading)
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

    private func parseWordLines(_ content: String) -> [WordLine] {
        content
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { line in
                if let range = line.range(of: ":") ?? line.range(of: "：") {
                    let tag = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                    let text = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                    return WordLine(line: line, tag: tag.isEmpty ? "词性" : tag, text: text.isEmpty ? line : text)
                }
                let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                if let first = parts.first, parts.count > 1 {
                    let tag = String(first)
                    let text = String(parts[1]).trimmingCharacters(in: .whitespaces)
                    return WordLine(line: line, tag: tag, text: text.isEmpty ? line : text)
                }
                return WordLine(line: line, tag: "词性", text: line)
            }
    }

    private func wordLines(from data: TranslationCardData) -> [WordLine] {
        if !data.wordParts.isEmpty {
            return data.wordParts.map { part in
                WordLine(line: "\(part.wordClass) \(part.content)", tag: part.wordClass, text: part.content)
            }
        }
        return parseWordLines(data.translatedText)
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
//    I am a teacher

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
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
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
}

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
    let form: TranslationForm?
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
                .imageScale(.medium)
            Text(toast.message)
                .font(.footnote)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill((toast.kind == .success ? theme.translateText : theme.errorText).opacity(0.12))
        )
        .foregroundColor(toast.kind == .success ? theme.translateText : theme.errorText)
    }
}
