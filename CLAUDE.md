# 專案

VoiceTodo 是一個以語音操作的待辦清單助手，用來驗證一個構想是否可行：未來在智慧眼鏡、穿戴裝置搭配 LLM 的情境下，「說出需求，由 AI 推斷意圖並執行」是最合理的操作介面。這是驗證用的 demo，不是正式產品。日期的說法與換算是核心功能；不做行事曆（年曆、月曆的檢視）。

領域模型：核心領域是用語音操作待辦（使用者意圖、任務、佇列等，詞以 `CONTEXT.md` 為準）；支援子領域是聊天（只做 help 與趣味）與額外能力（待辦清單以外的能力，例如天氣，見憲章 P1-4），都不能影響核心領域（見 [chat](docs/specs/chat.md) 的「前提」、[weather](docs/specs/weather.md)）。細節服務領域模型，不反過來綁住它。

原則見憲章，它是最高原則：

@CONSTITUTION.md

多步驟任務的 CHECKLIST.md，最後一段是對照憲章的完成檢查（原則與憲章 checklist），和進度放在同一個檔案；沒有 CHECKLIST.md 的小任務，直接在回報裡列出結果。

用詞以根目錄的 `CONTEXT.md` 為準：使用者只看得到小精靈，開發者討論時用精準的詞（規則、任務、判斷階段…），不說「小精靈」。

# 重要：不要啟動 iOS Simulator

開發者的 Mac 效能不足，啟動 iOS Simulator 可能讓電腦當機。不要在 Simulator 上跑 App 或測試（不用 `-destination 'platform=iOS Simulator…'`）。

- 單元測試只在 macOS 上跑。
- 確認 iOS 能編譯，只用不簽章的裝置編譯：`xcodebuild build -scheme voice_todo -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`。
- iOS 的實際行為由開發者用實機測試。

# 專案文件

文件結構全域 CLAUDE.md。這個專案另外有 `docs/eval/`：評估 AI 用的材料（手動 AI 的提示詞、測試句清單）。

AI 知道的 App 能力跟著 spec 走：功能 spec 一改（能力、說法、限制的新增、刪除或改變），同一次修改就檢查兩個 AI 收到的內容；沒有要改的，在回報的檢查表寫「不適用」並附理由。

- AI 聊天：負責回答用法、帶提示，要掌握目前的行為。檢查聊天提示詞（`ChatPrompt`）與補充資訊的使用說明、提示（`ChatExtra`，規則見 [chat](docs/specs/chat.md) 的「補充資訊」）。
- AI 判斷：要知道能呼叫哪些執行器、怎麼呼叫。檢查判斷提示詞與輸出結構（`JudgePrompt`）、手動 AI 的 [judge-prompt](docs/eval/judge-prompt.md)（同步規則見 [judgment](docs/specs/judgment.md) 的「手動 AI」）與 [judge-cases](docs/eval/judge-cases.md)。

小精靈的背景與世界觀以 `docs/elf-world.md` 為準：要修改小精靈的出身、尺寸、個性或角色設定時，先改這份檔案，再改聊天提示詞等程式。

# 回報格式

完成時的回報讓開發者不用讀細節就能判斷，依序：

1. **一句結論**：做了什麼、測試結果、還沒驗證的。
2. **邊界圖**：用 [overview](docs/overview.md) 的「邊界圖」，以 ★ 標出這次改的地方，註明邊界有沒有變；改到邊界就明講。
3. **檢查表**：表格，每列一項憲章的完成檢查與測試，結果（✅／❌／不適用）加一句證據。
4. **要開發者決定的事**：每項附推薦；沒有就寫「無」。
5. **commit message**。

檔案清單與過程細節，開發者問了才給。

提出方案時也一樣：用邊界圖標出會改的地方，選項用表格比較，最後寫推薦與要開發者決定的事。

# Commit Message

每次完成修改後，提供建議的 commit message，以**中文**撰寫，遵循 [Conventional Commits](https://www.conventionalcommits.org/) 慣例：

```
<type>(<scope>): <subject>

<body>
```

- `type`：`feat`（新功能）、`fix`（修 bug）、`docs`（文件）、`refactor`（重構）、`test`（測試）、`chore`（雜項、設定）、`style`（格式）、`perf`（效能）
- `scope`：選填，受影響的模組，例如 `speech`、`ui`
- `type`、`scope` 維持英文；`subject`、`body` 用中文
- `subject`：簡短（25 字內）、句尾不加句號
- `body`：選填，說明「為什麼」改，而非「改了什麼」

範例：

```
fix(speech): 落子後清空辨識器

暫定結果會改寫並黏字，自己去重一直出錯，改由辨識器定稿。
```

# TODO

目前的待辦、專注修改的方向與實測缺失清單，見 [`todo_list.md`](todo_list.md)。開始修改前先讀。
