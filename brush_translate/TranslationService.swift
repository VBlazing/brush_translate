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

struct AnalysisResult {
    let type: AnalysisTextType
    let sentence: SentenceAnalysis?
    let wordParts: [WordPart]
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
    case missingAPIKey(provider: TranslationProvider)
    case failedToTranslate
    case networkError(String)
    case invalidResponse
    case serviceError(String)
    case analyzeFailed(String)
    case languageMismatch(String)
}

final class TranslationService {
    private let cache = NSCache<NSString, TranslationResultBox>()

    init() {
        cache.countLimit = 200
    }

    func translate(
        text: String,
        from source: LanguageOption,
        to target: LanguageOption,
        provider: TranslationProvider,
        model: String,
        apiKey: String?,
        apiSecret: String? = nil,
        useCache: Bool = true
    ) async throws -> TranslationResult {
        let startTime = CFAbsoluteTimeGetCurrent()
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TranslationError.failedToTranslate }
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let trimmedSecret = apiSecret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch provider {
        case .youdao:
            guard trimmedKey.isEmpty == false, trimmedSecret.isEmpty == false else {
                throw TranslationError.missingAPIKey(provider: provider)
            }
        case .deepseek, .doubao, .gemini:
            guard trimmedKey.isEmpty == false else { throw TranslationError.missingAPIKey(provider: provider) }
        }
        if source != .auto, languageMatchesExpected(text: normalized, expected: source) == false {
            let detectedName = detectedDisplayName(for: normalized, fallback: "未知语言")
            throw TranslationError.languageMismatch(detectedName)
        }

        if useCache {
            let cacheKey = cacheKeyFor(text: normalized, source: source, target: target, provider: provider, model: model)
            print("cacheKey", cacheKey)
            if let cached = cache.object(forKey: cacheKey)?.value {
                logTranslationDuration(
                    startTime: startTime,
                    provider: provider,
                    model: model,
                    cacheHit: true
                )
                return cached
            }
        }

        do {
            let result: TranslationResult
            switch provider {
            case .deepseek:
                result = try await translateWithOpenAICompatible(
                url: URL(string: "https://api.deepseek.com/v1/chat/completions")!,
                provider: provider,
                model: model,
                text: normalized,
                from: source,
                to: target,
                apiKey: trimmedKey
            )
            case .doubao:
                if model == doubaoSeedTranslationModel {
                    result = try await translateWithDoubaoSeed(
                        text: normalized,
                        from: source,
                        to: target,
                        model: model,
                        apiKey: trimmedKey
                    )
                } else {
                    result = try await translateWithOpenAICompatible(
                        url: URL(string: "https://ark.cn-beijing.volces.com/api/v3/chat/completions")!,
                        provider: provider,
                        model: model,
                        text: normalized,
                        from: source,
                        to: target,
                        apiKey: trimmedKey
                    )
                }
            case .gemini:
                result = try await translateWithGemini(
                text: normalized,
                from: source,
                to: target,
                model: model,
                apiKey: trimmedKey
            )
            case .youdao:
                result = try await translateWithYoudao(
                    text: normalized,
                    from: source,
                    to: target,
                    model: model,
                    appKey: trimmedKey,
                    appSecret: trimmedSecret
                )
            }
            logTranslationDuration(
                startTime: startTime,
                provider: provider,
                model: model,
                cacheHit: false
            )
            return result
        } catch {
            logTranslationDuration(
                startTime: startTime,
                provider: provider,
                model: model,
                cacheHit: false
            )
            throw error
        }
    }

    func validate(provider: TranslationProvider, model: String, apiKey: String?, apiSecret: String? = nil) async throws {
        _ = try await translate(
            text: "Hello",
            from: .auto,
            to: .simplifiedChinese,
            provider: provider,
            model: model,
            apiKey: apiKey,
            apiSecret: apiSecret,
            useCache: false
        )
    }
    private func translateWithOpenAICompatible(
        url: URL,
        provider: TranslationProvider,
        model: String,
        text: String,
        from source: LanguageOption,
        to target: LanguageOption,
        apiKey: String
    ) async throws -> TranslationResult {
        let promptSource = source == .auto ? "auto-detect" : source.displayName
        let schema = translationSchema
        let systemPrompt = """
You are a translation engine. Return pure JSON matching this schema (no markdown):
\(schema)
Rules: translate input after "Translate:" from \(promptSource) to \(target.displayName). If success, set state=1 and translate_result; if failure, state=0 and error_message. Keep output in target language. Always translate literally, even if the input looks like a programming keyword or reserved word (e.g., true, false, null, class). Do not interpret the input as code, variables, or keywords.
"""
        let requestBody = ChatCompletionsRequest(
            model: model,
            messages: [
                .init(
                    role: "system",
                    content: systemPrompt
                ),
                .init(role: "user", content: "Translate (literal text, not code): \(text)")
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

            let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
            guard let content = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines), !content.isEmpty else {
                throw TranslationError.invalidResponse
            }
            print("content", content)
            let structured = try decodeStructured(content)
            switch structured.state {
            case 1:
                guard let result = structured.translateResult?.trimmingCharacters(in: .whitespacesAndNewlines),
                      result.isEmpty == false else { throw TranslationError.invalidResponse }
                let guessedLanguage = source == .auto ? detectedDisplayName(for: text, fallback: source.displayName) : source.displayName
                let translation = TranslationResult(
                    originalText: text,
                    translatedText: result,
                    alternatives: [],
                    detectedSource: guessedLanguage,
                    target: target.displayName
                )
                let cacheKey = cacheKeyFor(text: text, source: source, target: target, provider: provider, model: model)
                cache.setObject(TranslationResultBox(value: translation), forKey: cacheKey)
                return translation
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

    private func translateWithGemini(
        text: String,
        from source: LanguageOption,
        to target: LanguageOption,
        model: String,
        apiKey: String
    ) async throws -> TranslationResult {
        let promptSource = source == .auto ? "auto-detect" : source.displayName
        let schema = translationSchema
        let systemPrompt = """
You are a translation engine. Return pure JSON matching this schema (no markdown):
\(schema)
Rules: translate input after "Translate:" from \(promptSource) to \(target.displayName). If success, set state=1 and translate_result; if failure, state=0 and error_message. Keep output in target language. Always translate literally, even if the input looks like a programming keyword or reserved word (e.g., true, false, null, class). Do not interpret the input as code, variables, or keywords.
"""
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)")!
        let requestBody = GeminiRequest(
            contents: [
                .init(role: "user", parts: [.init(text: "Translate (literal text, not code): \(text)")])
            ],
            systemInstruction: .init(parts: [.init(text: systemPrompt)]),
            generationConfig: .init(temperature: 0, responseMimeType: "application/json")
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(requestBody)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unexpected response"
                throw TranslationError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(message)")
            }

            let decoded = try JSONDecoder().decode(GeminiResponse.self, from: data)
            guard let content = decoded.candidates.first?.content?.parts.first?.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !content.isEmpty else {
                throw TranslationError.invalidResponse
            }
            print("content", content)
            let structured = try decodeStructured(content)
            switch structured.state {
            case 1:
                guard let result = structured.translateResult?.trimmingCharacters(in: .whitespacesAndNewlines),
                      result.isEmpty == false else { throw TranslationError.invalidResponse }
                let guessedLanguage = source == .auto ? detectedDisplayName(for: text, fallback: source.displayName) : source.displayName
                let translation = TranslationResult(
                    originalText: text,
                    translatedText: result,
                    alternatives: [],
                    detectedSource: guessedLanguage,
                    target: target.displayName
                )
                let cacheKey = cacheKeyFor(text: text, source: source, target: target, provider: .gemini, model: model)
                cache.setObject(TranslationResultBox(value: translation), forKey: cacheKey)
                return translation
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

    private func translateWithDoubaoSeed(
        text: String,
        from source: LanguageOption,
        to target: LanguageOption,
        model: String,
        apiKey: String
    ) async throws -> TranslationResult {
        let url = URL(string: "https://ark.cn-beijing.volces.com/api/v3/responses")!
        let translationOptions: DoubaoSeedTranslationOptions?
        if source == .auto {
            translationOptions = DoubaoSeedTranslationOptions(
                targetLanguage: doubaoSeedLanguageCode(for: target)
            )
        } else {
            translationOptions = DoubaoSeedTranslationOptions(
                sourceLanguage: doubaoSeedLanguageCode(for: source),
                targetLanguage: doubaoSeedLanguageCode(for: target)
            )
        }
        let requestBody = DoubaoSeedRequest(
            model: model,
            input: [
                .init(
                    role: "user",
                    content: [
                        .init(
                            type: "input_text",
                            text: text,
                            translationOptions: translationOptions
                        )
                    ]
                )
            ]
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
            let decoded = try JSONDecoder().decode(DoubaoSeedResponse.self, from: data)
            let rawText = decoded.output
                .first?
                .content
                .first?
                .text?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !rawText.isEmpty else { throw TranslationError.invalidResponse }

            let guessedLanguage = source == .auto ? detectedDisplayName(for: text, fallback: source.displayName) : source.displayName
            let translation = TranslationResult(
                originalText: text,
                translatedText: rawText,
                alternatives: [],
                detectedSource: guessedLanguage,
                target: target.displayName
            )
            let cacheKey = cacheKeyFor(text: text, source: source, target: target, provider: .doubao, model: model)
            cache.setObject(TranslationResultBox(value: translation), forKey: cacheKey)
            return translation
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(error.localizedDescription)
        }
    }

    private func translateWithYoudao(
        text: String,
        from source: LanguageOption,
        to target: LanguageOption,
        model: String,
        appKey: String,
        appSecret: String
    ) async throws -> TranslationResult {
        let url = URL(string: "https://openapi.youdao.com/api")!
        let salt = UUID().uuidString
        let curtime = String(Int(Date().timeIntervalSince1970))
        let input = YoudaoHelpers.signInput(for: text)
        let sign = YoudaoHelpers.sha256Hex("\(appKey)\(input)\(salt)\(curtime)\(appSecret)")
        let parameters: [String: String] = [
            "q": text,
            "from": YoudaoHelpers.languageCode(for: source),
            "to": YoudaoHelpers.languageCode(for: target),
            "appKey": appKey,
            "salt": salt,
            "sign": sign,
            "signType": "v3",
            "curtime": curtime,
            "strict": source == .auto ? "false" : "true"
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = YoudaoHelpers.formURLEncoded(parameters)
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let message = String(data: data, encoding: .utf8) ?? "Unexpected response"
                throw TranslationError.networkError("HTTP \((response as? HTTPURLResponse)?.statusCode ?? -1): \(message)")
            }

            let decoded = try JSONDecoder().decode(YoudaoResponse.self, from: data)
            guard decoded.errorCode == "0" else {
                let detail = YoudaoHelpers.errorMessage(for: decoded.errorCode)
                let message = detail == nil
                    ? "有道错误码: \(decoded.errorCode)"
                    : "有道错误码: \(decoded.errorCode)（\(detail!)）"
                throw TranslationError.serviceError(message)
            }
            let translated = decoded.translation?.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !translated.isEmpty else { throw TranslationError.invalidResponse }
            let guessedLanguage: String
            if source == .auto, let pair = decoded.l, let fromCode = pair.split(separator: "2").first {
                guessedLanguage = YoudaoHelpers.displayName(for: String(fromCode))
            } else {
                guessedLanguage = source == .auto
                    ? detectedDisplayName(for: text, fallback: source.displayName)
                    : source.displayName
            }
            let translation = TranslationResult(
                originalText: text,
                translatedText: translated,
                alternatives: [],
                detectedSource: guessedLanguage,
                target: target.displayName
            )
            let cacheKey = cacheKeyFor(text: text, source: source, target: target, provider: .youdao, model: model)
            cache.setObject(TranslationResultBox(value: translation), forKey: cacheKey)
            return translation
        } catch let error as TranslationError {
            throw error
        } catch {
            throw TranslationError.networkError(error.localizedDescription)
        }
    }

    func analyze(text: String, translated: String, apiKey: String?, sourceLanguage: LanguageOption, targetLanguage: LanguageOption) async throws -> AnalysisResult {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw TranslationError.failedToTranslate }
        _ = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmedKey.isEmpty == false else { throw TranslationError.missingAPIKey(provider: .deepseek) }

        let url = URL(string: "https://api.deepseek.com/v1/chat/completions")!
        let analyzeSchema = """
{
    "type": "object",
    "properties": {
        "state": {
          "type": "integer",
          "description": "Parsing status (0 indicates failure, 1 indicates success)."
        },
        "text_type": {
          "enum": ["word", "sentence"],
          "description": "Whether the input text is a word or a sentence."
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
        },
        "word_parts": {
            "type": "array",
            "description": "Word translation with part-of-speech tagging. Each part should include up to three translations.",
            "items": {
                "type": "object",
                "properties": {
                    "word_class": {
                        "enum": ["n.", "adj.", "v.", "adv.", "num.", "pron.", "art.", "prep.", "conj.", "int."],
                        "description": "Part of speech of the word to be translated"
                    },
                    "translations": {
                        "type": "array",
                        "description": "Up to three translations for the current part of speech.",
                        "items": {
                            "type": "string"
                        }
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
        let requestBody = ChatCompletionsRequest(
            model: "deepseek-chat",
            messages: [
                .init(role: "system", content: "You are a text analyzer. Return pure JSON matching this schema exactly (no markdown): \n\(analyzeSchema)\nRules: 1) Target language: \(targetLanguageDisplay(from: targetLanguage)). 2) Source language: \(sourceLanguageDisplay(from: sourceLanguage)). 3) The user will provide a text (Source text). 4) First determine whether the text is a word or a sentence, and set `text_type`. 5) If it is a sentence, analyze each component of the Source text and translate them, while also providing their parts of speech. The analysis results should include phrases and words. Words are prioritized over phrases in the splitting process; when a word cannot be correctly translated, the phrase is used as the result. 6) Set the start and end indices of the components in the source text in the `start` and `end` attributes. 7) If the component is a verb, the tense needs to be restored; if the component is a noun, the plural needs to be restored to the singular. The restored string is set in the `component_with_lemmatize` attribute. 8) If it is a word, return `word_parts` with each part-of-speech and up to three translations. 9) Ensure that the structured content in the output are consistent with the target language."),
                .init(role: "user", content: "Source text: \(normalized)\n")
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

            let decoded = try JSONDecoder().decode(ChatCompletionsResponse.self, from: data)
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

            guard parsed.state == 1, let textType = parsed.textType else {
                throw TranslationError.analyzeFailed("解析失败")
            }

            switch textType {
            case .sentence:
                guard let list = parsed.componentList, list.isEmpty == false else {
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
                let analysis = SentenceAnalysis(state: parsed.state, components: components)
                return AnalysisResult(type: textType, sentence: analysis, wordParts: [])
            case .word:
                guard let parts = parsed.wordParts, parts.isEmpty == false else {
                    throw TranslationError.analyzeFailed("解析失败")
                }
                let mapped = parts.map { part in
                    let translations = part.translations.prefix(3)
                    return WordPart(wordClass: part.wordClass, content: translations.joined(separator: "；"))
                }
                return AnalysisResult(type: textType, sentence: nil, wordParts: mapped)
            }
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

    private func doubaoSeedLanguageCode(for option: LanguageOption) -> String {
        if option == .simplifiedChinese {
            return "zh"
        }
        return option.code
    }

    private func cacheKeyFor(text: String, source: LanguageOption, target: LanguageOption, provider: TranslationProvider, model: String) -> NSString {
        "\(provider.rawValue)|\(model)|\(source.code)|\(target.code)|\(text)" as NSString
    }

    private func logTranslationDuration(
        startTime: CFAbsoluteTime,
        provider: TranslationProvider,
        model: String,
        cacheHit: Bool
    ) {
        let elapsed = CFAbsoluteTimeGetCurrent() - startTime
        let tag = cacheHit ? "cache" : "network"
        let duration = String(format: "%.3f", elapsed)
        print("Translation time (\(provider.rawValue) \(model)) [\(tag)]: \(duration)s")
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

private let doubaoSeedTranslationModel = "doubao-seed-translation-250915"

private let translationSchema = """
{
    "type": "object",
    "properties": {
        "state": { "type": "integer" },
        "error_message": { "type": "string" },
        "translate_result": { "type": "string" }
    }
}
"""

private struct ChatCompletionsRequest: Encodable {
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

private struct DoubaoSeedRequest: Encodable {
    struct InputMessage: Encodable {
        struct ContentItem: Encodable {
            let type: String
            let text: String
            let translationOptions: DoubaoSeedTranslationOptions?

            enum CodingKeys: String, CodingKey {
                case type
                case text
                case translationOptions = "translation_options"
            }
        }

        let role: String
        let content: [ContentItem]
    }

    let model: String
    let input: [InputMessage]
}

private struct DoubaoSeedTranslationOptions: Encodable {
    let sourceLanguage: String?
    let targetLanguage: String

    init(sourceLanguage: String? = nil, targetLanguage: String) {
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
    }

    enum CodingKeys: String, CodingKey {
        case sourceLanguage = "source_language"
        case targetLanguage = "target_language"
    }
}

private struct DoubaoSeedResponse: Decodable {
    struct OutputItem: Decodable {
        struct ContentItem: Decodable {
            let type: String?
            let text: String?
        }

        let content: [ContentItem]
    }

    let output: [OutputItem]
}

private struct YoudaoResponse: Decodable {
    let errorCode: String
    let translation: [String]?
    let l: String?
}

private struct ChatCompletionsResponse: Decodable {
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
    let state: Int
    let errorMessage: String?
    let translateResult: String?

    enum CodingKeys: String, CodingKey {
        case state
        case errorMessage = "error_message"
        case translateResult = "translate_result"
    }
}

private struct GeminiRequest: Encodable {
    struct Part: Encodable {
        let text: String
    }

    struct Content: Encodable {
        let role: String
        let parts: [Part]
    }

    struct SystemInstruction: Encodable {
        let parts: [Part]
    }

    struct GenerationConfig: Encodable {
        let temperature: Double
        let responseMimeType: String

        enum CodingKeys: String, CodingKey {
            case temperature
            case responseMimeType = "response_mime_type"
        }
    }

    let contents: [Content]
    let systemInstruction: SystemInstruction
    let generationConfig: GenerationConfig

    enum CodingKeys: String, CodingKey {
        case contents
        case systemInstruction = "system_instruction"
        case generationConfig = "generation_config"
    }
}

private struct GeminiResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            struct Part: Decodable {
                let text: String?
            }
            let parts: [Part]
        }
        let content: Content?
    }

    let candidates: [Candidate]
}

private final class TranslationResultBox: NSObject {
    let value: TranslationResult

    init(value: TranslationResult) {
        self.value = value
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
    let textType: AnalysisTextType?
    let componentList: [AnalyzeItem]?
    let wordParts: [AnalyzeWordPart]?
    let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case state
        case textType = "text_type"
        case componentList = "component_list"
        case wordParts = "word_parts"
        case errorMessage = "error_message"
    }
}

enum AnalysisTextType: String, Decodable {
    case word
    case sentence
}

private struct AnalyzeWordPart: Decodable {
    let wordClass: String
    let translations: [String]

    enum CodingKeys: String, CodingKey {
        case wordClass = "word_class"
        case translations
    }
}

struct WordPart: Hashable, Decodable {
    let wordClass: String
    let content: String
}

extension TranslationError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let provider):
            if provider == .youdao {
                return "未配置 有道 App Key/Secret"
            }
            return "未配置 \(provider.displayName) API Key"
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
        case .languageMismatch(let detectedName):
            return "语言不一致，当前检测到语言为：\(detectedName)"
        }
    }
}
