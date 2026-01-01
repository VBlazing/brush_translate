//
//  TranslationProvider.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/12/29.
//

import Foundation

enum TranslationProvider: String, CaseIterable, Identifiable {
    case deepseek
    case doubao
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepseek:
            return "DeepSeek"
        case .doubao:
            return "豆包"
        case .gemini:
            return "Gemini"
        }
    }

    var iconName: String {
        switch self {
        case .deepseek:
            return "bolt.circle.fill"
        case .doubao:
            return "leaf.circle.fill"
        case .gemini:
            return "sparkles"
        }
    }

    var models: [String] {
        switch self {
        case .deepseek:
            return ["deepseek-chat"]
        case .doubao:
            return [
                "doubao-seed-translation-250915",
                "doubao-seed-1-6-flash-250828",
                "doubao-seed-1-6-vision-250815",
                "doubao-seed-1-6-251015"
            ]
        case .gemini:
            return ["gemini-2.5-pro"]
        }
    }

    var defaultModel: String {
        models.first ?? ""
    }
}
