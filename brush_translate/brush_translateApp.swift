//
//  brush_translateApp.swift
//  brush_translate
//
//  Created by 赵泽宇 on 2025/11/26.
//

import SwiftUI
import AppKit

@main
struct brush_translateApp: App {
    @StateObject private var model = AppModel()
    
    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra("Brush Translate", systemImage: "character.book.closed") {
            Picker("原文语言", selection: $model.sourceLanguage) {
                ForEach(LanguageOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Picker("译文语言", selection: $model.targetLanguage) {
                ForEach(LanguageOption.allCases.filter { $0 != .auto }) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Picker("主题", selection: $model.theme) {
                ForEach(ThemeOption.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }

            Divider()
            Button("选择服务") {
                model.openSettings(tab: .service)
            }
            Button("设置") {
                model.openSettings(tab: .general)
            }
            Divider()
            Button("退出") {
                NSApp.terminate(nil)
            }
        }
    }
}
