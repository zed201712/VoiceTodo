//
//  ChatScroll.swift
//  voicecalender
//

import Foundation

/// 對話流的位置改變時要做什麼（見 docs/specs/ui.md 的「新內容」）。
/// 看的是變長之前的位置：變長之後新內容已經排版，原本在最下面的也會變成不在最下面。
enum ChatScroll: Equatable {
    case follow
    case showNewMessage
    case hideNewMessage
    case none

    /// 內容的高度與看得到的範圍的底端，同一個座標。
    struct Geometry: Equatable {
        var contentHeight: CGFloat
        var visibleBottom: CGFloat
    }

    /// 差這麼多也算在最下面。
    static let tolerance: CGFloat = 30

    static func change(from old: Geometry, to new: Geometry) -> ChatScroll {
        if new.contentHeight > old.contentHeight {
            return isAtBottom(old) ? .follow : .showNewMessage
        }
        return isAtBottom(new) ? .hideNewMessage : .none
    }

    private static func isAtBottom(_ geometry: Geometry) -> Bool {
        geometry.visibleBottom >= geometry.contentHeight - tolerance
    }
}
