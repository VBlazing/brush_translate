//
//  YoudaoHelpers.swift
//  brush_translate
//
//  Created by Codex on 2025/01/02.
//

import CryptoKit
import Foundation

struct YoudaoHelpers {
    static func languageCode(for option: LanguageOption) -> String {
        switch option {
        case .simplifiedChinese:
            return "zh-CHS"
        case .traditionalChinese:
            return "zh-CHT"
        case .auto:
            return "auto"
        default:
            return option.code
        }
    }

    static func displayName(for code: String) -> String {
        switch code.lowercased() {
        case "zh-chs":
            return LanguageOption.simplifiedChinese.displayName
        case "zh-cht":
            return LanguageOption.traditionalChinese.displayName
        case "en":
            return LanguageOption.english.displayName
        case "ja":
            return LanguageOption.japanese.displayName
        case "ko":
            return LanguageOption.korean.displayName
        case "es":
            return LanguageOption.spanish.displayName
        case "fr":
            return LanguageOption.french.displayName
        case "de":
            return LanguageOption.german.displayName
        default:
            return "未知语言"
        }
    }

    static func signInput(for text: String) -> String {
        if text.count <= 20 {
            return text
        }
        let prefix = String(text.prefix(10))
        let suffix = String(text.suffix(10))
        return "\(prefix)\(text.count)\(suffix)"
    }

    static func sha256Hex(_ string: String) -> String {
        let digest = SHA256.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func formURLEncoded(_ parameters: [String: String]) -> Data {
        var components = URLComponents()
        components.queryItems = parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        let query = components.percentEncodedQuery ?? ""
        return Data(query.utf8)
    }

    static func errorMessage(for code: String) -> String? {
        switch code {
        case "101":
            return "缺少必填的参数"
        case "102":
            return "不支持的语言类型"
        case "103":
            return "翻译文本过长"
        case "104":
            return "不支持的API类型"
        case "105":
            return "不支持的签名类型"
        case "106":
            return "不支持的响应类型"
        case "107":
            return "不支持的传输加密类型"
        case "108":
            return "应用ID无效"
        case "109":
            return "batchLog格式不正确"
        case "110":
            return "无相关服务的有效应用"
        case "111":
            return "开发者账号无效"
        case "112":
            return "请求服务无效"
        case "113":
            return "q不能为空"
        case "114":
            return "不支持的图片传输方式"
        case "116":
            return "strict字段取值无效"
        case "201":
            return "解密失败"
        case "202":
            return "签名检验失败"
        case "203":
            return "访问IP地址不在可访问IP列表"
        case "205":
            return "请求接口与应用平台类型不一致"
        case "206":
            return "时间戳无效导致签名校验失败"
        case "207":
            return "重放请求"
        case "301":
            return "辞典查询失败"
        case "302":
            return "翻译查询失败"
        case "303":
            return "服务端其它异常"
        case "304":
            return "翻译失败"
        case "308":
            return "rejectFallback参数错误"
        case "309":
            return "domain参数错误"
        default:
            return nil
        }
    }
}
