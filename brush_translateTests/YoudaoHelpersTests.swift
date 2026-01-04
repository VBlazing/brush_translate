//
//  YoudaoHelpersTests.swift
//  brush_translateTests
//
//  Created by Codex on 2025/01/02.
//

import XCTest
@testable import brush_translate

final class YoudaoHelpersTests: XCTestCase {
    func testSignInputShortTextUsesOriginal() {
        let text = "short text"
        XCTAssertEqual(YoudaoHelpers.signInput(for: text), text)
    }

    func testSignInputLongTextUsesPrefixLengthSuffix() {
        let text = "abcdefghijklmnopqrstuvwxyz"
        let expected = "abcdefghij26qrstuvwxyz"
        XCTAssertEqual(YoudaoHelpers.signInput(for: text), expected)
    }

    func testLanguageCodeMapping() {
        XCTAssertEqual(YoudaoHelpers.languageCode(for: .auto), "auto")
        XCTAssertEqual(YoudaoHelpers.languageCode(for: .simplifiedChinese), "zh-CHS")
        XCTAssertEqual(YoudaoHelpers.languageCode(for: .traditionalChinese), "zh-CHT")
        XCTAssertEqual(YoudaoHelpers.languageCode(for: .english), "en")
    }

    func testErrorMessageMapping() {
        XCTAssertEqual(YoudaoHelpers.errorMessage(for: "101"), "缺少必填的参数")
        XCTAssertNil(YoudaoHelpers.errorMessage(for: "999"))
    }
}
