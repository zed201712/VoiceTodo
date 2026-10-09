//
//  ContentView.swift
//  voicecalender
//

#if os(macOS)
// 除錯 UI 只在 macOS 的除錯模式（見 docs/specs/ui.md）。
import AppKit
import SwiftUI

/// 除錯 UI（見 docs/specs/ui.md）：接在使用者畫面右邊，不重複小精靈、待辦與補救按鈕。
struct ContentView: View {

    @Bindable var elf: Elf
    @State private var testInput = ""
    @State private var manualResponse = ""

    var body: some View {
        // 不捲動：控制、目前的資訊、測試紀錄分成三欄，一眼看完。
        HStack(alignment: .top, spacing: 12) {

            VStack(alignment: .leading, spacing: 12) {
                Text(elf.modelStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                section("控制") {
                    HStack(spacing: 16) {
                        Toggle("語音輸入", isOn: Binding(get: { elf.isVoiceOn }, set: { elf.setVoice($0) }))
                        Toggle("自動 AI", isOn: $elf.useAutoAI)
                        // 只讀寫「VoiceTodo 測試」清單（見 docs/specs/storage.md 的「測試清單」）。
                        Toggle("測試清單", isOn: Binding(get: { elf.isTestList }, set: { elf.setTestList($0) }))
                    }
                    Button("重新開始") {
                        elf.restart()
                        testInput = ""
                        manualResponse = ""
                    }
                }

                section("測試輸入") {
                    editor($testInput)
                    Button("送出") {
                        elf.submitTestInput(testInput)
                        testInput = ""
                    }
                }

                section("手動 AI") {
                    field("種類", elf.manualRequest?.kind ?? "")
                    field("請求", elf.manualRequest?.text ?? "")
                    editor($manualResponse)
                    Button("送出") {
                        elf.submitManualResponse(manualResponse)
                        manualResponse = ""
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(width: 320)

            VStack(alignment: .leading, spacing: 12) {
                section("輸入") {
                    field("即時", elf.sentence.volatileText)
                    field("累積", elf.sentence.finalText)
                    field("佇列", elf.queueStatus.joined(separator: "\n"))
                }

                section("校正") {
                    field("輸入", elf.correctionInput)
                    field("輸出", elf.correctionOutput)
                }

                section("判斷") {
                    field("指令", elf.commands.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n"))
                    field("執行中", elf.currentCommand)
                    field("結果", elf.results.joined(separator: "\n"))
                    field("等待", elf.waitingText)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 380)

            section("測試紀錄") {
                Button("複製") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(elf.testLogText, forType: .string)
                }
                Table(elf.testLog) {
                    TableColumn("#", value: \.number).width(40)
                    TableColumn("階段", value: \.stage).width(80)
                    TableColumn("內容") { entry in
                        Text(entry.text).textSelection(.enabled)
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
        .padding()
        .frame(minWidth: 1000)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func editor(_ text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(.system(.body, design: .monospaced))
            .frame(height: 70)
            .border(.separator)
    }

    private func field(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            if !label.isEmpty {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)
            }
            Text(value.isEmpty ? "—" : value)
                .textSelection(.enabled)
        }
        .font(.system(.body, design: .monospaced))
    }
}

#Preview {
    ContentView(elf: Elf(autoAI: FoundationModelsAI()))
}
#endif
