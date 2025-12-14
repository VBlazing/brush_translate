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
                    Text(data.sourceText.isEmpty ? "未获取到选中文本" : data.sourceText)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(theme.sourceText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(6)
                        .padding(.bottom, 25)
                    VStack {
                        translationSection
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
        }
        .onHover { hovering in
            onHoverChange(hovering)
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
                        .scaleEffect(0.7)
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

#Preview {
    ContentView()
        .environmentObject(AppModel())
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
    let status: Status
    let onRetry: (() -> Void)?
    let onSpeak: (() -> Void)?
    let onSaveNote: (() -> Void)?
    let onAnalyze: (() -> Void)?
    let showAnalyzeButton: Bool
    let isAnalyzing: Bool
}
