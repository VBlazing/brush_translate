//
//  TranslationService.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import AppKit
import CoreServices
import Foundation
import NaturalLanguage

struct TranslationResult {
    let originalText: String
    let translatedText: String
    let alternatives: [String]
    let detectedSource: String
    let target: String
}

enum TranslationError: Error {
    case failedToTranslate
}

final class TranslationService {
    func translate(text: String, from source: LanguageOption, to target: LanguageOption) async throws -> TranslationResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TranslationError.failedToTranslate }

        return fallbackTranslation(for: normalized, from: source, to: target)
    }

    private func fallbackTranslation(for text: String, from source: LanguageOption, to target: LanguageOption) -> TranslationResult {
        let guessedLanguage = source == .auto ? detectedDisplayName(for: text, fallback: source.displayName) : source.displayName
        let placeholder = "[占位翻译]\n\(text)"
        let definitions = definitionsForWord(text)

        return TranslationResult(
            originalText: text,
            translatedText: placeholder,
            alternatives: definitions,
            detectedSource: guessedLanguage,
            target: target.displayName
        )
    }

    private func detectLanguage(for text: String) -> String? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return nil }
        return language.rawValue
    }

    private func detectedDisplayName(for text: String, fallback: String) -> String {
        guard let code = detectLanguage(for: text) else { return fallback }
        if let option = LanguageOption.allCases.first(where: { $0.code == code }) {
            return option.displayName
        }
        return "未知语言"
    }

    private func definitionsForWord(_ word: String) -> [String] {
        guard !word.contains(" ") else { return [] }
        let cfRange = CFRange(location: 0, length: word.utf16.count)
        if let definition = DCSCopyTextDefinition(nil, word as CFString, cfRange)?.takeRetainedValue() as String? {
            let lines = definition
                .components(separatedBy: CharacterSet.newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            return Array(lines.prefix(4))
        }
        return []
    }
}
