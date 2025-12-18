//
//  AppModel.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import Combine
import SwiftUI

final class AppModel: ObservableObject {
    @Published var sourceLanguage: LanguageOption
    @Published var targetLanguage: LanguageOption
    @Published var statusMessage: String = "等待选中文本..."
    @Published var theme: ThemeOption
    @Published var deepseekAPIKey: String

    private let translator = TranslationService()
    private let overlay = TranslationOverlayController()
    private var cancellables = Set<AnyCancellable>()
    private var lastTranslation: TranslationResult?
    private var lastAnalysis: SentenceAnalysis?
    private var selectedComponentIDs = Set<SentenceComponentID>()
    private var activeTranslationToken: UUID?
    private var activeAnalysisToken: UUID?

    init() {
        let storedSource = UserDefaults.standard.string(forKey: UserDefaultsKeys.sourceLanguage) ?? LanguageOption.auto.code
        let storedTarget = UserDefaults.standard.string(forKey: UserDefaultsKeys.targetLanguage) ?? LanguageOption.simplifiedChinese.code
        let storedTheme = UserDefaults.standard.string(forKey: UserDefaultsKeys.theme) ?? ThemeOption.night.rawValue
        let storedAPIKey = UserDefaults.standard.string(forKey: UserDefaultsKeys.deepseekAPIKey) ?? ""

        sourceLanguage = LanguageOption(rawValue: storedSource) ?? .auto
        targetLanguage = LanguageOption(rawValue: storedTarget) ?? .simplifiedChinese
        theme = ThemeOption(rawValue: storedTheme) ?? .night
        deepseekAPIKey = storedAPIKey

        $sourceLanguage
            .sink { value in
                UserDefaults.standard.setValue(value.code, forKey: UserDefaultsKeys.sourceLanguage)
            }
            .store(in: &cancellables)

        $targetLanguage
            .sink { value in
                UserDefaults.standard.setValue(value.code, forKey: UserDefaultsKeys.targetLanguage)
            }
            .store(in: &cancellables)

        $theme
            .sink { value in
                UserDefaults.standard.setValue(value.rawValue, forKey: UserDefaultsKeys.theme)
            }
            .store(in: &cancellables)

        $deepseekAPIKey
            .sink { value in
                UserDefaults.standard.setValue(value, forKey: UserDefaultsKeys.deepseekAPIKey)
            }
            .store(in: &cancellables)

        overlay.onDidHide = { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                self.activeTranslationToken = nil
                self.activeAnalysisToken = nil
            }
        }

        HotKeyManager.shared.register { [weak self] in
            self?.triggerTranslationFromSelection()
        }
    }

    func openSettings() {
        NSApp.setActivationPolicy(.regular)
        SettingsWindowController.shared.show(with: self)
    }

    func enterAccessoryMode() {
        NSApp.setActivationPolicy(.accessory)
    }

    func triggerTranslationFromSelection() {
        Task {
            await MainActor.run {
                if self.overlay.isVisible {
                    self.overlay.hideImmediately()
                }
                self.statusMessage = "正在读取选区..."
            }

            guard let selectedText = await SelectionCapture.captureSelectedText() else {
                await MainActor.run {
                    if SelectionCapture.isAccessibilityTrusted() {
                        self.statusMessage = "未获取到选中文本"
                        self.overlay.showPlaceholder(theme: self.theme)
                    } else {
                        self.statusMessage = "请在“隐私与安全性 > 辅助功能”允许本应用"
                    }
                }
                return
            }

            await translateAndShow(for: selectedText)
        }
    }

    private func translateAndShow(for selectedText: String) async {
        let trimmed = selectedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            await MainActor.run {
                self.statusMessage = "未获取到选中文本"
                self.overlay.showPlaceholder(theme: self.theme)
            }
            return
        }

        let token = UUID()
        await MainActor.run {
            self.activeTranslationToken = token
            self.activeAnalysisToken = nil
            self.statusMessage = "正在翻译..."
            self.overlay.showLoading(sourceText: trimmed, theme: self.theme)
        }

        do {
            let result = try await translator.translate(
                text: trimmed,
                from: sourceLanguage,
                to: targetLanguage,
                apiKey: deepseekAPIKey
            )

            await MainActor.run {
                guard self.activeTranslationToken == token else { return }
                self.statusMessage = "翻译完成"
                self.lastTranslation = result
                self.lastAnalysis = nil
                self.selectedComponentIDs.removeAll()
                self.overlay.showSuccess(
                    translation: result,
                    theme: self.theme,
                    onAnalyze: { [weak self] in
                        self?.startAnalyze()
                    }
                )
            }
        } catch {
            let failureMessage: String
            if let translationError = error as? TranslationError {
                failureMessage = translationError.localizedDescription
            } else {
                failureMessage = "翻译失败"
            }
            await MainActor.run {
                guard self.activeTranslationToken == token else { return }
                self.statusMessage = "翻译失败：\(failureMessage)"
                self.overlay.showFailure(
                    sourceText: trimmed,
                    message: failureMessage,
                    theme: self.theme,
                    retry: { [weak self] in
                        Task { [weak self] in
                            guard let self else { return }
                            await self.translateAndShow(for: trimmed)
                        }
                    }
                )
            }
        }
    }

    private func startAnalyze() {
        guard let translation = lastTranslation, translation.form == .sentence else { return }
        let token = UUID()
        Task {
            await MainActor.run {
                self.activeAnalysisToken = token
                self.lastAnalysis = nil
                self.selectedComponentIDs.removeAll()
                self.presentOverlaySuccess(translation: translation, isAnalyzing: true)
            }

            do {
                let analysis = try await translator.analyze(
                    text: translation.originalText,
                    translated: translation.translatedText,
                    apiKey: deepseekAPIKey,
                    sourceLanguage: sourceLanguage,
                    targetLanguage: targetLanguage
                )
                await MainActor.run {
                    guard self.activeAnalysisToken == token else { return }
                    self.lastAnalysis = analysis
                    self.selectedComponentIDs.removeAll()
                    self.presentOverlaySuccess(
                        translation: translation,
                        isAnalyzing: false,
                        toast: ToastData(kind: .success, message: "解析成功")
                    )
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    guard self.activeAnalysisToken == token else { return }
                    self.presentOverlaySuccess(translation: translation, isAnalyzing: false)
                }
            } catch {
                let message = (error as? TranslationError)?.localizedDescription ?? "解析失败"
                await MainActor.run {
                    guard self.activeAnalysisToken == token else { return }
                    self.presentOverlaySuccess(
                        translation: translation,
                        isAnalyzing: false,
                        toast: ToastData(kind: .failure, message: message)
                    )
                }
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    guard self.activeAnalysisToken == token else { return }
                    self.presentOverlaySuccess(translation: translation, isAnalyzing: false)
                }
            }
        }
    }

    @MainActor
    private func presentOverlaySuccess(translation: TranslationResult, isAnalyzing: Bool, toast: ToastData? = nil) {
        overlay.showSuccess(
            translation: translation,
            analysis: lastAnalysis,
            selectedComponentIDs: selectedComponentIDs,
            theme: theme,
            isAnalyzing: isAnalyzing,
            toast: toast,
            onAnalyze: { [weak self] in
                self?.startAnalyze()
            },
            onToggleComponent: { [weak self] id in
                self?.toggleComponent(id)
            }
        )
    }

    private func toggleComponent(_ id: SentenceComponentID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            withAnimation(.easeInOut(duration: 0.3)) {
                if self.selectedComponentIDs.contains(id) {
                    self.selectedComponentIDs.remove(id)
                } else {
                    self.selectedComponentIDs.insert(id)
                }
            }
            guard let translation = self.lastTranslation else { return }
            self.presentOverlaySuccess(translation: translation, isAnalyzing: false)
        }
    }
}

enum UserDefaultsKeys {
    static let sourceLanguage = "brush_translate.source"
    static let targetLanguage = "brush_translate.target"
    static let theme = "brush_translate.theme"
    static let deepseekAPIKey = "brush_translate.deepseek.apiKey"
}

enum LanguageOption: String, CaseIterable, Identifiable {
    case auto = "auto"
    case simplifiedChinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case english = "en"
    case japanese = "ja"
    case korean = "ko"
    case spanish = "es"
    case french = "fr"
    case german = "de"

    var id: String { rawValue }

    var code: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "自动检测"
        case .simplifiedChinese: return "中文（简体）"
        case .traditionalChinese: return "中文（繁体）"
        case .english: return "英语"
        case .japanese: return "日语"
        case .korean: return "韩语"
        case .spanish: return "西班牙语"
        case .french: return "法语"
        case .german: return "德语"
        }
    }
}

enum ThemeOption: String, CaseIterable, Identifiable {
    case night
    case light

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .night: return "夜间模式"
        case .light: return "明亮模式"
        }
    }

    var background: Color {
        switch self {
        case .night:
            return Color(red: 31/255, green: 31/255, blue: 36/255) // brighter dark
        case .light:
            return Color(red: 245/255, green: 247/255, blue: 250/255) // 柔和浅灰底
        }
    }

    var cardBackground: Color {
        switch self {
        case .night:
            return Color(red: 39/255, green: 39/255, blue: 48/255)
        case .light:
            return Color(red: 1.0, green: 1.0, blue: 1.0) // 纯净卡片背景
        }
    }

    var sourceText: Color {
        switch self {
        case .night:
            return Color(red: 240/255, green: 240/255, blue: 242/255)
        case .light:
            return Color(red: 28/255, green: 28/255, blue: 30/255)
        }
    }

    var translateText: Color {
        switch self {
        case .night:
            return Color(red: 200/255, green: 203/255, blue: 210/255)
        case .light:
            return Color(red: 82/255, green: 82/255, blue: 90/255)
        }
    }

    var errorText: Color {
        switch self {
        case .night:
            return Color(red: 255/255, green: 111/255, blue: 111/255)
        case .light:
            return Color(red: 220/255, green: 34/255, blue: 34/255)
        }
    }

    var divider: Color {
        switch self {
        case .night:
            return Color.white.opacity(0.18)
        case .light:
            return Color.black.opacity(0.08)
        }
    }

    var shadow: Color {
        switch self {
        case .night:
            return Color.black.opacity(0.45)
        case .light:
            return Color.black.opacity(0.12)
        }
    }

    var panelBackgroundColor: NSColor {
        switch self {
        case .night:
            return NSColor(srgbRed: 31/255, green: 31/255, blue: 36/255, alpha: 0.75)
        case .light:
            return NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 0.9)
        }
    }
}
