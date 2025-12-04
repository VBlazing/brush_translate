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
    case missingAPIKey
    case failedToTranslate
    case networkError(String)
    case invalidResponse
}

final class TranslationService {
    func translate(text: String, from source: LanguageOption, to target: LanguageOption, apiKey: String?) async throws -> TranslationResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TranslationError.failedToTranslate }
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedKey.isEmpty == false else { throw TranslationError.missingAPIKey }
        return try await translateWithDeepseek(text: normalized, from: source, to: target, apiKey: trimmedKey)
    }

    private func translateWithDeepseek(text: String, from source: LanguageOption, to target: LanguageOption, apiKey: String) async throws -> TranslationResult {
        let url = URL(string: "https://api.deepseek.com/v1/chat/completions")!
        let promptSource = source == .auto ? "auto-detect" : source.displayName
        let requestBody = DeepseekRequest(
            model: "deepseek-chat",
            messages: [
                .init(role: "system", content: "Translate the user content to \(target.displayName). If the source language is \(promptSource), detect it automatically. Return only the translated text."),
                .init(role: "user", content: text)
            ],
            temperature: 0
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unexpected response"
                throw TranslationError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(message)")
            }

            let decoded = try JSONDecoder().decode(DeepseekResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
                throw TranslationError.invalidResponse
            }

            let guessedLanguage = source == .auto ? detectedDisplayName(for: text, fallback: source.displayName) : source.displayName

            return TranslationResult(
                originalText: text,
                translatedText: content,
                alternatives: [],
                detectedSource: guessedLanguage,
                target: target.displayName
            )
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(error.localizedDescription)
        }
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

private struct DeepseekRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
}

private struct DeepseekResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let role: String?
            let content: String?
        }
        let message: Message
    }

    let choices: [Choice]
}

extension TranslationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "未配置 Deepseek API Key"
        case .failedToTranslate:
            return "没有可翻译的内容"
        case .networkError(let message):
            return message
        case .invalidResponse:
            return "翻译服务返回无效数据"
        }
    }
}
