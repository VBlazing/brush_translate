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
    let form: TranslationForm?
    let wordParts: [WordPart]
    let alternatives: [String]
    let detectedSource: String
    let target: String
}

struct SentenceAnalysis {
    let state: Int
    let components: [Component]

    struct Component: Hashable {
        let text: String
        let translation: String
        let wordClass: String
        let start: Int
        let end: Int
        let lemmatized: String?
        let type: ComponentType?
    }
}

struct SentenceComponentID: Hashable, Sendable {
    let start: Int
    let end: Int
}

enum ComponentType: String, Decodable, Sendable {
    case word
    case phrases
}

extension SentenceAnalysis.Component {
    var id: SentenceComponentID {
        SentenceComponentID(start: start, end: end)
    }
}

enum TranslationError: Error {
    case missingAPIKey
    case failedToTranslate
    case networkError(String)
    case invalidResponse
    case serviceError(String)
    case analyzeFailed(String)
}

final class TranslationService {
    func translate(text: String, from source: LanguageOption, to target: LanguageOption, apiKey: String?) async throws -> TranslationResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TranslationError.failedToTranslate }
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedKey.isEmpty == false else { throw TranslationError.missingAPIKey }
        if source != .auto, languageMatchesExpected(text: normalized, expected: source) == false {
            throw TranslationError.serviceError("语言不一致")
        }
        return try await translateWithDeepseek(text: normalized, from: source, to: target, apiKey: trimmedKey)
    }
    private func translateWithDeepseek(text: String, from source: LanguageOption, to target: LanguageOption, apiKey: String) async throws -> TranslationResult {
        let url = URL(string: "https://api.deepseek.com/v1/chat/completions")!
        let promptSource = source == .auto ? "auto-detect" : source.displayName
        let schema = """
{
    "type": "object",
    "properties": {
        "state": {
            "type": "integer",
            "description": "Translation success or failure is indicated by a value of 1 (success) and 0 (failure)."
        },
        "error_message": {
            "type": "string",
            "description": "Translation error message (only present when state is 0, the value is null when state is 1)."
        },
        "translate_result": {
            "type": "object",
            "description": "Translation result object (only present when state is 1, the value is null when state is 0).",
            "properties": {
                "form": {
                    "enum": ["word", "sentence"],
                    "description": "The format of the content to be translated"
                },
                "content": {
                    "type": "string",
                    "description": "The translation results of the sentence (only present when form is sentence, the value is null when form is word)."
                },
                "content_with_parts_of_speech": {
                    "type": "array",
                    "description": "Word translation with part-of-speech tagging: Each element corresponds to a part-of-speech tag and the translation corresponding to that part of speech (only present when form is word, the value is null when form is sentence).",
                    "items": {
                        "type": "object",
                        "properties": {
                            "word_class": {
                                "type": "string",
                                "description": "Part of speech of the word to be translated"
                            },
                            "content": {
                                "type": "string",
                                "description": "The translation of the word of the current part of speech should include at least two translations separated by a semicolon."
                            }
                        }
                    }
                }
            }
        }
    }
}
"""

//        6) If the text to be translated is a sentence, analyze the sentence, extract each component of the sentence, translate them, and add them to the constant_list (Phrases have higher priority than words; if the component parts can form a phrase, the phrase is returned first)

        let requestBody = DeepseekRequest(
            model: "deepseek-chat",
            messages: [
                .init(role: "system", content: "You are a translation engine. Translate user-provided content. Always respond with pure JSON matching this schema (exact text, no changes): \n\(schema)\nRules: 1) Target language: \(target.displayName). 2) Source language: \(promptSource). 3) The user input format is 'Translate: text', which directly and accurately translates the text following 'Translate'. 4) Ensure that the structured content and error messages in the output are consistent with the target language. 5) If the text to be translated is words, provide all parts of speech for this word. 6) Please carefully check the output to ensure it is correct before returning the result. 7) Do not use word association; rely entirely on user input."),
                .init(role: "user", content: "Translate: \(text)")
            ],
            temperature: 0,
            responseFormat: .init(type: "json_object")
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
            print("content", content)
            let structured = try decodeStructured(content)
            switch structured.state {
            case 1:
                guard let result = structured.translateResult else { throw TranslationError.invalidResponse }
                let guessedLanguage = source == .auto ? detectedDisplayName(for: text, fallback: source.displayName) : source.displayName

                switch result.form {
                case .sentence:
                    guard let content = result.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
                        throw TranslationError.invalidResponse
                    }
                    return TranslationResult(
                        originalText: text,
                        translatedText: content,
                        form: result.form,
                        wordParts: [],
                        alternatives: [],
                        detectedSource: guessedLanguage,
                        target: target.displayName
                    )
                case .word:
                    guard let parts = result.contentWithPartsOfSpeech, parts.isEmpty == false else {
                        throw TranslationError.invalidResponse
                    }
                    let mapped = parts.map { WordPart(wordClass: $0.wordClass, content: $0.content) }
                    let joined = mapped.map { "\($0.wordClass): \($0.content)" }.joined(separator: "\n")
                    return TranslationResult(
                        originalText: text,
                        translatedText: joined,
                        form: result.form,
                        wordParts: mapped,
                        alternatives: [],
                        detectedSource: guessedLanguage,
                        target: target.displayName
                    )
                }
            case 0:
                throw TranslationError.serviceError(structured.errorMessage ?? "翻译失败")
            default:
                throw TranslationError.invalidResponse
            }
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(error.localizedDescription)
        }
    }

    func analyze(text: String, translated: String, apiKey: String?, sourceLanguage: LanguageOption, targetLanguage: LanguageOption) async throws -> SentenceAnalysis {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TranslationError.failedToTranslate }
        let translatedTrimmed = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedKey.isEmpty == false else { throw TranslationError.missingAPIKey }

        let url = URL(string: "https://api.deepseek.com/v1/chat/completions")!
        let analyzeSchema = """
{
    "type": "object",
    "properties": {
        "state": {
          "type": "integer",
          "description": "Sentence parsing status (0 indicates failure, 1 indicates success)."
        },
        "component_list": {
            "type": "array",
            "description": "The list of words and phrases that make up a sentence, and their translations in the current context.",
            "items": {
                "type": "object",
                "properties": {
                    "component": {
                        "type": "string",
                        "description": "The words and phrases that make up a sentence"
                    },
                    "start": {
                        "type": "integer",
                        "description": "The starting index of component in the source sentence"
                    },
                    "end": {
                        "type": "integer",
                        "description": "The end index of component in the source sentence"
                    },
                    "component_with_lemmatize": {
                      "type": "string",
                      "description": "Tense or quantity restoration of words/phrases. E.G. 1) cars -> car 2) took away -> take away"
                    },
                    "translation": {
                        "type": "string",
                        "description": "The translation of current component within the context of the sentence being translated."
                    },
                    "word_class": {
                        "enum": ["n.", "adj.", "v.", "adv.", "num.", "pron.", "art.", "prep.", "conj.", "int."],
                        "description": "Part of speech of the current component within the context of the sentence being translated."
                    },
                    "type": {
                      "enum": ["word", "phrases"],
                      "description": "Type of component attribute"
                    }
                }
            }
        }
    }
}
"""
//        举个例子：get up 拆分为 get 和 up时无法表达意思，所以拆分结果为 get up，其余情况都赢拆分为
//        If a phrase cannot accurately express its meaning after being further broken down into words, then the phrase will appear in the breakdown results.
//        and a sentence already translated into the target language (Translated sentence)
//        Each component's translation should correspond one-to-one with the translated sentence.
//        Translated sentence: \(translatedTrimmed)\n
        let requestBody = DeepseekRequest(
            model: "deepseek-chat",
            messages: [
                .init(role: "system", content: "You are a sentence analyzer. Return pure JSON matching this schema exactly (no markdown): \n\(analyzeSchema)\nRules: 1) Target language: \(targetLanguageDisplay(from: targetLanguage)). 2) Source language: \(sourceLanguageDisplay(from: sourceLanguage)). 3) The user will provide a sentence to be translated (Source sentence). 4) Analyze each component of the Source sentence and translate them, while also providing their parts of speech.  5) The analysis results of the source sentence should include phrases and words. Words are prioritized over phrases in the splitting process; when a word cannot be correctly translated, the phrase is used as the result. 6) Set the start and end indices of the components in the source sentence in the `start` and `end` attributes. 7) If the component is a verb, the tense needs to be restored; if the component is a noun, the plural needs to be restored to the singular. The restored string is set in the `component_with_lemmatize` attribute. 8) Ensure that the structured content in the output are consistent with the target language."),
                .init(role: "user", content: "Source sentence: \(normalized)\n")
            ],
            temperature: 0,
            responseFormat: .init(type: "json_object")
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(trimmedKey)", forHTTPHeaderField: "Authorization")
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
            
            print("content", content)

            let jsonSlice: String
            if let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") {
                jsonSlice = String(content[start...end])
            } else {
                throw TranslationError.invalidResponse
            }

            guard let jsonData = jsonSlice.data(using: .utf8) else {
                throw TranslationError.invalidResponse
            }
            let parsed = try JSONDecoder().decode(AnalyzeResponse.self, from: jsonData)

            guard parsed.state == 1, let list = parsed.componentList, list.isEmpty == false else {
                throw TranslationError.analyzeFailed("解析失败")
            }

            let components = list.map {
                SentenceAnalysis.Component(
                    text: $0.component,
                    translation: $0.translation,
                    wordClass: $0.wordClass,
                    start: $0.start,
                    end: $0.end,
                    lemmatized: $0.componentWithLemmatize,
                    type: $0.type
                )
            }
            return SentenceAnalysis(state: parsed.state, components: components)
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

    private func sourceLanguageDisplay(from option: LanguageOption) -> String {
        option.displayName
    }

    private func targetLanguageDisplay(from option: LanguageOption) -> String {
        option.displayName
    }

    private func languageMatchesExpected(text: String, expected: LanguageOption) -> Bool {
        guard let detectedCode = detectLanguage(for: text) else { return true }
        switch expected {
        case .simplifiedChinese, .traditionalChinese:
            return detectedCode.hasPrefix("zh")
        default:
            return detectedCode == expected.code
        }
    }

    private func decodeStructured(_ content: String) throws -> StructuredTranslationResponse {
        let jsonSlice: String
        if let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") {
            jsonSlice = String(content[start...end])
        } else {
            throw TranslationError.invalidResponse
        }

        guard let data = jsonSlice.data(using: .utf8) else {
            throw TranslationError.invalidResponse
        }
        return try JSONDecoder().decode(StructuredTranslationResponse.self, from: data)
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

    struct ResponseFormat: Encodable {
        let type: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case responseFormat = "response_format"
    }
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

private struct StructuredTranslationResponse: Decodable {
    struct TranslateResult: Decodable {
        let form: TranslationForm
        let content: String?
        let contentWithPartsOfSpeech: [WordPartResponse]?

        enum CodingKeys: String, CodingKey {
            case form
            case content
            case contentWithPartsOfSpeech = "content_with_parts_of_speech"
        }
    }

    struct WordPartResponse: Decodable {
        let wordClass: String
        let content: String

        enum CodingKeys: String, CodingKey {
            case wordClass = "word_class"
            case content
        }
    }

    let state: Int
    let errorMessage: String?
    let translateResult: TranslateResult?

    enum CodingKeys: String, CodingKey {
        case state
        case errorMessage = "error_message"
        case translateResult = "translate_result"
    }
}

private struct AnalyzeResponse: Decodable {
    struct AnalyzeItem: Decodable {
        let component: String
        let wordClass: String
        let translation: String
        let start: Int
        let end: Int
        let componentWithLemmatize: String?
        let type: ComponentType?

        enum CodingKeys: String, CodingKey {
            case component
            case wordClass = "word_class"
            case translation
            case start
            case end
            case componentWithLemmatize = "component_with_lemmatize"
            case type
        }
    }

    let state: Int
    let componentList: [AnalyzeItem]?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case state
        case componentList = "component_list"
        case errorMessage = "error_message"
    }
}

enum TranslationForm: String, Decodable {
    case word
    case sentence
}

struct WordPart: Hashable, Decodable {
    let wordClass: String
    let content: String
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
        case .serviceError(let message):
            return message
        case .analyzeFailed(let message):
            return message
        }
    }
}
