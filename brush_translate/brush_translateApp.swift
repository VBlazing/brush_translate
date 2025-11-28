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

    var body: some Scene {
        MenuBarExtra("Brush Translate", systemImage: "character.book.closed") {
//            Button("翻译选中文本 (⌥T)") {
//                model.triggerTranslationFromSelection()
//            }
            Button("打开设置") {
                model.openSettings()
            }
            Divider()
            Button("退出应用") {
                NSApp.terminate(nil)
            }
        }

        WindowGroup("刷词翻译设置") {
            ContentView()
                .environmentObject(model)
        }

        Settings {
            ContentView()
                .environmentObject(model)
        }
    }
}
