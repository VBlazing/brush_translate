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
    let translation: TranslationResult
    let theme: ThemeOption
    let onHoverChange: (Bool) -> Void
    private let labelColor = Color(red: 113/255, green: 113/255, blue: 122/255)

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Text(translation.originalText.isEmpty ? "无内容" : translation.originalText)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.sourceText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(6)
            
                Spacer(minLength: 4)
                Text(translation.translatedText.isEmpty ? "无翻译" : translation.translatedText)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.translateText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(6)

            }
//            The function cannot complete because messaging failed in some way or because the application with
            .padding(.vertical, 40)
            .padding(.horizontal, 60)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(theme.cardBackground)
                    .shadow(color: theme.shadow, radius: 28, y: 12)
            )
            .edgesIgnoringSafeArea(.all)
        }
        .frame(width: 520)
        .onHover { hovering in
            onHoverChange(hovering)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppModel())
}
