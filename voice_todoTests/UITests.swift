//
//  UITests.swift
//  voicecalenderTests
//

import Foundation
import Testing
@testable import voicecalender

// MARK: - 對話流的捲動

struct ChatScrollTests {

    private func geometry(_ contentHeight: CGFloat, visibleBottom: CGFloat) -> ChatScroll.Geometry {
        ChatScroll.Geometry(contentHeight: contentHeight, visibleBottom: visibleBottom)
    }

    @Test func 在最下面時變長_跟著捲() {
        #expect(ChatScroll.change(from: geometry(1000, visibleBottom: 1000), to: geometry(1100, visibleBottom: 1000)) == .follow)
    }

    @Test func 差一點點到最下面也算在最下面() {
        #expect(ChatScroll.change(from: geometry(1000, visibleBottom: 980), to: geometry(1100, visibleBottom: 980)) == .follow)
    }

    @Test func 內容不滿一頁時變長_跟著捲() {
        #expect(ChatScroll.change(from: geometry(200, visibleBottom: 500), to: geometry(300, visibleBottom: 500)) == .follow)
    }

    @Test func 往上看時變長_不捲_顯示橫條() {
        #expect(ChatScroll.change(from: geometry(1000, visibleBottom: 600), to: geometry(1100, visibleBottom: 600)) == .showNewMessage)
    }

    @Test func 往上看時自己捲到最下面_收起橫條() {
        #expect(ChatScroll.change(from: geometry(1100, visibleBottom: 600), to: geometry(1100, visibleBottom: 1100)) == .hideNewMessage)
    }

    @Test func 往上看時捲動但沒到最下面_不動() {
        #expect(ChatScroll.change(from: geometry(1100, visibleBottom: 600), to: geometry(1100, visibleBottom: 800)) == .none)
    }
}
