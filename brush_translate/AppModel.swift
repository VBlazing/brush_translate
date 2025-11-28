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

    private let translator = TranslationService()
    private let overlay = TranslationOverlayController()
    private var cancellables = Set<AnyCancellable>()

    init() {
        let storedSource = UserDefaults.standard.string(forKey: UserDefaultsKeys.sourceLanguage) ?? LanguageOption.auto.code
        let storedTarget = UserDefaults.standard.string(forKey: UserDefaultsKeys.targetLanguage) ?? LanguageOption.simplifiedChinese.code
        let storedTheme = UserDefaults.standard.string(forKey: UserDefaultsKeys.theme) ?? ThemeOption.night.rawValue

        sourceLanguage = LanguageOption(rawValue: storedSource) ?? .auto
        targetLanguage = LanguageOption(rawValue: storedTarget) ?? .simplifiedChinese
        theme = ThemeOption(rawValue: storedTheme) ?? .night

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
                self.statusMessage = "正在读取选区..."
            }

            guard let selectedText = await SelectionCapture.captureSelectedText() else {
                await MainActor.run {
                    if SelectionCapture.isAccessibilityTrusted() {
                        self.statusMessage = "未获取到选中文本"
                        self.overlay.showPlaceholder(message: "未获取到选中文本", theme: self.theme)
                    } else {
                        self.statusMessage = "请在“隐私与安全性 > 辅助功能”允许本应用"
                        self.overlay.showPlaceholder(message: "请在系统设置开启辅助功能权限", theme: self.theme)
                    }
                }
                return
            }

            await MainActor.run {
                self.statusMessage = "正在翻译..."
            }

            do {
                let result = try await translator.translate(
                    text: selectedText,
                    from: sourceLanguage,
                    to: targetLanguage
                )

                await MainActor.run {
                    self.statusMessage = "翻译完成"
                    self.overlay.show(translation: result, theme: self.theme)
                }
            } catch {
                await MainActor.run {
                    self.statusMessage = "翻译失败：\(error.localizedDescription)"
                    self.overlay.showPlaceholder(message: "翻译失败", theme: self.theme)
                }
            }
        }
    }
}

enum UserDefaultsKeys {
    static let sourceLanguage = "brush_translate.source"
    static let targetLanguage = "brush_translate.target"
    static let theme = "brush_translate.theme"
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
            return Color(red: 24/255, green: 24/255, blue: 27/255) // #18181b
        case .light:
            return Color(red: 24/255, green: 24/255, blue: 27/255) // 同一背景
        }
    }

    var cardBackground: Color {
        switch self {
        case .night:
            return Color(red: 31/255, green: 31/255, blue: 36/255)
        case .light:
            return Color(red: 31/255, green: 31/255, blue: 36/255)
        }
    }

    var primaryText: Color {
        switch self {
        case .night:
            return Color.white.opacity(0.95)
        case .light:
            return Color.white.opacity(0.95)
        }
    }

    var accentText: Color {
        switch self {
        case .night:
            return Color.white
        case .light:
            return Color.white
        }
    }

    var divider: Color {
        switch self {
        case .night:
            return Color.white.opacity(0.14)
        case .light:
            return Color.white.opacity(0.14)
        }
    }

    var shadow: Color {
        switch self {
        case .night:
            return Color.black.opacity(0.6)
        case .light:
            return Color.black.opacity(0.6)
        }
    }

    var panelBackgroundColor: NSColor {
        switch self {
        case .night:
            return NSColor(srgbRed: 24/255, green: 24/255, blue: 27/255, alpha: 0.7)
        case .light:
            return NSColor(srgbRed: 24/255, green: 24/255, blue: 27/255, alpha: 0.7)
        }
    }
}
