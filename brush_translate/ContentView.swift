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

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Text(data.sourceText.isEmpty ? "未获取到选中文本" : data.sourceText)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.sourceText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(6)

                Spacer()
                translationSection
            }
//            The function cannot complete because messaging failed in some way or because the application with
            .padding(.vertical, 40)
            .padding(.horizontal, 60)
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
                ProgressView()
                    .progressViewStyle(.circular)
                Text("翻译中...")
            }
            .font(.system(size: 18, weight: .medium))
            .foregroundColor(theme.translateText)
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
                Text(data.translatedText.isEmpty ? "翻译失败" : data.translatedText)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(theme.translateText)
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
    let status: Status
    let onRetry: (() -> Void)?
}
