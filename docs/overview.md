# 專案概述

## 目的

VoiceTodo 是一個 macOS SwiftUI App，驗證「說出需求，由 AI 推斷意圖並執行」作為操作介面的可行性。構想的情境是智慧眼鏡、穿戴裝置搭配 LLM；這個專案以語音操作的待辦清單助手作為 demo，待辦存在 Apple 提醒事項。日期的說法與換算保留為核心功能；不做行事曆檢視。

用詞見根目錄的 [CONTEXT.md](../CONTEXT.md)。

### 領域

```
┌──────────── 核心領域：用語音操作待辦 ────────────┐
│  一句話 → 使用者意圖 → 指令 → 任務                │
│                                    │（釐清、確認、取消、放棄）
│                                    ▼              │
│               待辦清單（待辦、黑板、undo／redo）   │
└──────────────────────────────────────────────────┘
     ▲ 不能影響核心                 ▲ 透過介面使用
┌─ 支援子領域 ─┐       ┌─ 外部 ──────────────────────────┐
│ 聊天          │       │ 語音辨識、TTS、AI、               │
│ 額外能力（天氣）│       │ 存檔（提醒事項）、天氣服務、定位   │
└──────────────┘       └─────────────────────────────────┘
```

## 主要功能

- 黑板顯示目前專注的範圍（預設是今天起 7 天），是待辦的所有指令的前置條件：沒說日期就以黑板為準，只有新增在黑板超過一天時會先問是哪一天（黑板是「目前」時用今天）；查詢的結果固定在黑板上，找目標的指令只在黑板上找目標；範圍內的待辦包括過去的都顯示，依日期分組（今天、明天…、月份，參考提醒事項 App 的「排程」）；每行有編號，找目標的指令可以說編號（「第 3 到 10 項移到後天」）；可以切換是否顯示已完成，並回到上一頁、下一頁
- 待辦：新增、查詢、改日期或內容、複製到別的日期、設定完成、刪除（需 yes／no 確認）
- 語音報告：每個結果輪到時念出成功的結果與問題，查詢與問題裡列出的項目預設念 3 項；只有說「停止」等明確的動作才中斷，念的時候說的話排在後面；右上角有開關
- 佇列：背景平行地把說的話解讀成使用者意圖，結果照說話的順序呈現，每個結果佔一段報告顯示時間；等回答時後面的結果不出現，回答插隊；說「全部取消」丟掉所有還沒輪到的
- 低觸控：語音可以完成所有操作，觸控是多給的選擇：復原、重做、語音輸入開關、語音報告開關、判斷失敗彈窗、黑板的方框、點內容複製文字（只有觸控）、上一頁與下一頁、提示對話框的箭頭與連結、工具列的提示按鈕與「顯示已完成」、設定
- 判斷失敗的結果輪到時進入錯誤確認，可以重試或說「略過」；資料可以 undo／redo
- 一句話可以包含多條指令，依序執行，每條指令是一個任務
- 找到多筆或沒講清楚時提出釐清；取消或找不到目標時還原該任務
- 問用法時小精靈回固定的提示頁（提示對話框）：從總導覽開始，可以點連結、箭頭或用說的換頁，不讓對話流變長；工具列的提示按鈕打開總導覽
- 說了 App 沒有的功能或隨口的話時，小精靈依 App 的定位與自己的角色（[世界觀](elf-world.md)）簡短接話（聊天）並念出來；問提示頁沒有的用法或問小精靈時照實回答，平常輪流聊一點自己的事
- 對話流是固定的對話紀錄：開場問候，接著每句話後面接小精靈的回話（帶插畫），回話原地說明接下來要做、正在做、做了什麼；排隊與正在說的話是還沒送出的泡泡
- 除錯 UI（macOS 在設定打開除錯模式）顯示語音輸入、校正、判斷各自目前的資訊，以及可一鍵複製的測試紀錄
- 測試用：除錯 UI 可以打字取代語音（每行一句）、切換成手動 AI（貼回 JSON），並重新開始
- 存檔是 Apple 提醒事項：讀取所有清單裡未完成的提醒事項（包括沒有日期的），已完成的在打開「顯示已完成」時才讀，每個任務結束後把差異寫回；刪除後 undo 會帶回原本的清單與備註；提醒事項在 App 以外被改了就重新讀取並清空 undo；沒有權限時只能聊天
- 沒有日期的待辦排在黑板最底下，任何範圍都看得到
- 通知由提醒事項 App 跳出：App 新增有時間的待辦時加 alarm，改日期或時間時 alarm 跟著移
- 備份（建立備份、換成備份）目前暫停
- 額外能力：查天氣。說日期（可以加時段）與地點（沒說就是所在地），小精靈念出每一天的天氣、溫度與降雨機率；不改待辦、沒有自己的 UI（憲章 P1-4）

## 架構與資料流

```
麥克風（或除錯 UI 的測試輸入，每行一句）
  → 語音輸入階段：確定結果累積，停頓 1.5 秒定稿成一句話（附開口時間）
  → 全部取消、輔助關鍵字：馬上處理；回音：丟掉；回答：插隊；其他 → 輸入佇列
  ── 執行佇列（背景，同時最多 2 句，不改任何狀態）：解讀成使用者意圖 ──
  → 關鍵字：App 直接處理，不經過 AI
  → 規則判斷：固定的句型直接產生指令，命中就不經過 AI 校正與判斷
  → 畫面資訊：定稿時拍下使用者看到的畫面，每個欄位最多 100 字
  → 校正階段（和判斷同時開始）：自動 AI 依畫面資訊與常識修正錯別字，字數不變才採用；採用時作廢原句的判斷、用新句子重判
  → 判斷階段：自動 AI 以結構化輸出產生指令清單（每句話一次）→ 轉成 JSON
              或切換成手動 AI 時，等開發者貼回手動 AI 的 JSON
              → 同一個解析器變成指令清單
  ── 結果佇列：照說話的順序，輪到才執行、呈現 ──
  → 有指令：執行任務：執行器換算日期、找出目標並改變待辦；釐清、刪除確認、失敗還原
    沒有指令：聊天階段（背景先準備，輪到時黑板或待辦變了就重做）：先挑選補充資訊（問到的段落、查不到就全部、沒問就輪流一段世界觀），自動 AI 依畫面資訊與補充資訊簡短接話；釐清中沒有指令則取消，不聊天
  → 語音報告：規則把成功的結果組成句子，加上聊天的回應與問題，用系統 TTS 念出；念完（或報告顯示時間結束）才換下一個結果
  → 使用者畫面：對話流（開場問候、話與回話、提示對話框、排隊的話）、黑板（待辦清單）、按鈕列
    macOS 除錯模式另外顯示除錯 UI（含測試紀錄）
```

完整的路徑見 [flow](specs/flow.md)，佇列見 [queue](specs/queue.md)。背景可以同時解讀多句話，但任務一次只執行一個、照說話的順序；語音在背景持續聆聽。

### 邊界圖

一句話從進來到呈現的每一站與邊界；回報改動時用這張圖標出改了哪裡（見 CLAUDE.md 的「回報格式」）。

```
麥克風／測試輸入
  ▼
語音輸入階段 ── 定稿 ──→ 一句話
  ├─ 特例：全部取消、輔助關鍵字、回音、回答 ──→ 馬上處理
  ▼
輸入佇列
  ▼
執行佇列（背景，不改任何狀態）
  判斷層：規則判斷 ｜ 校正 ∥ AI 判斷 → 沒有指令就聊天
          只產生指令，不改任何東西
  ▼
結果佇列（照說話順序）
  ▼
執行層：指令 → 執行器（CommandExecutor ｜ 小精靈：undo、黑板、念的方式、說明、查天氣 → 天氣服務）
        聊天的回應 ｜ 錯誤確認
  ▼
呈現：對話流、黑板、語音報告
  ▼
存檔：任務結束後整份寫入提醒事項（alarm 跟著變）；外部變動 → 重新讀取
```

## 檔案結構

依 clean architecture 分層，依賴由外往內（UI／Infrastructure → Application → Domain）；測試照同樣的分層放在 `voice_todoTests/`。

| 資料夾 | 內容 | 對應 |
|---|---|---|
| `Domain/` | 待辦與執行器（`TodoStore`、`Commands`）、規則判斷（`JudgeTool`）、undo／redo 的狀態（`TodoHistory`）、存檔的介面（`TodoStorage`）、測試待辦（`TestTodos`）、日期與時間的說法（`DatePhrase`、`TimePhrase`）、一句話的切分（`SentenceBuilder`）、三個佇列與報告顯示時間（`IntentQueue`）、查天氣的規則（`Weather`）、座標落在哪個鄉鎮市區（`Towns`）、提示頁與便條的引導（`Hint`） | [todos](specs/todos.md)、[date-time](specs/date-time.md)、[voice-input](specs/voice-input.md)、[recovery](specs/recovery.md)、[queue](specs/queue.md)、[weather](specs/weather.md)、[help](specs/help.md) 的規則 |
| `Application/` | 小精靈：照順序執行與呈現（`Elf`）、背景把一句話解讀成使用者意圖（`IntentPreparer`）、自動 AI、語音輸入的介面（`AutoAI`、`SpeechInput`）、AI 回應的解析（`CommandJSON`）、畫面資訊（`ScreenInfo`）、聊天的補充資訊（`ChatExtra`）、自動 AI 的設定（`AISettings`）、查天氣與天氣服務的介面（`WeatherLookup`） | [flow](specs/flow.md)、[queue](specs/queue.md)、[judgment](specs/judgment.md)、[screen-info](specs/screen-info.md)、[chat](specs/chat.md)、[settings](specs/settings.md)、[weather](specs/weather.md) |
| `Infrastructure/AI/` | 各自動 AI 的實作與共用的提示詞（`JudgePrompt`、`CorrectionPrompt`、`ChatPrompt`） | [judgment](specs/judgment.md) 的「自動 AI」、[correction](specs/correction.md)、[chat](specs/chat.md) |
| `Infrastructure/Speech/` | 語音辨識（`SpeechManager`） | [voice-input](specs/voice-input.md) |
| `Infrastructure/Weather/` | 天氣服務（Open-Meteo）、地名搜尋（MapKit）、所在地（CoreLocation）、鄉鎮市區邊界的資料（`towns.json`） | [weather](specs/weather.md) |
| `Infrastructure/Storage/` | 待辦存在提醒事項（`EventKitTodoStorage`：差異、刪除快照、alarm）、設定存在 UserDefaults 與 Keychain（`SettingsStorage`） | [storage](specs/storage.md)、[notifications](specs/notifications.md)、[settings](specs/settings.md) |
| `UI/` | 使用者畫面（兩個平台共用）、對話流的捲動（`ChatScroll`）、除錯 UI（`ContentView`，只在 macOS）、設定（`SettingsView`） | [ui](specs/ui.md)、[settings](specs/settings.md) |
| `App/` | App 入口：組裝各層，依設定產生自動 AI（`AIFactory`）；單元測試時不聆聽、不存檔 | [settings](specs/settings.md) |
| `tools/`（專案根目錄） | 產生 App 內建資料的腳本：鄉鎮市區邊界（`make_towns.py`） | [weather](specs/weather.md) 的「結構」 |

## 技術

- macOS 26、iOS 26、SwiftUI：同一個 target 支援兩個平台，共用使用者畫面；除錯 UI 只在 macOS
- Speech（`SpeechAnalyzer`、`SpeechTranscriber`，zh-TW）
- EventKit（提醒事項是待辦的存檔，含 alarm）
- AVFoundation（`AVAudioEngine`、`AVAudioConverter`，輸入打開回音消除；iOS 另外要啟用同時播放與錄音的 `AVAudioSession`）
- Open-Meteo（天氣服務，不用 key）、MapKit（地名搜尋）、CoreLocation（所在地）、內政部國土測繪中心的鄉鎮市區界線（App 內建，所在地的名稱）
- AVSpeechSynthesizer（語音報告的 TTS，zh-TW，裝置上執行）
- 自動 AI（在設定裡選擇）：Foundation Models（裝置端 LLM、結構化輸出，只做判斷）、Ollama（本機服務、JSON Schema，暫不開放）或 Gemini API（雲端、JSON Schema，預設）

## 文件索引

### 憲章

- [CONSTITUTION](../CONSTITUTION.md)：專案最上層的原則（產品原則、開發原則）與功能完成時的 checklist；下層文件和它衝突時先檢查

### Specs

- [judge-tool](specs/judge-tool.md)：規則判斷：和 AI 判斷對等，AI 判斷之前，固定的句型直接產生指令
- [flow](specs/flow.md)：一句話的路徑：關鍵字、校正、判斷後走任務（含釐清）或聊天
- [queue](specs/queue.md)：輸入、執行、結果三個佇列：背景只解讀，照說話順序呈現；報告顯示時間、插隊、全部取消、觸控
- [screen-info](specs/screen-info.md)：畫面資訊：自動 AI 看到的畫面快照，每個欄位最多 100 字並在單位邊界截斷
- [chat](specs/chat.md)：聊天階段：判斷沒有指令時依 App 的定位與小精靈的角色簡短接話並念出；補充資訊（使用說明與世界觀片段）
- [voice-input](specs/voice-input.md)：語音輸入階段：只用確定結果，停頓後定稿成一句話排隊
- [correction](specs/correction.md)：校正階段：依畫面資訊與常識只修錯別字，字數不變才採用
- [judgment](specs/judgment.md)：判斷階段：AI 輸出指令清單、任務用執行器執行、釐清、刪除確認、還原
- [todos](specs/todos.md)：待辦資料（時間可以沒有）、黑板是待辦的所有指令的前置條件、編號、各指令的日期與時間、每種指令與「聽不懂」
- [date-time](specs/date-time.md)：日期與時間的通用規則：語法、有效性、時段依用途換成時間點或範圍
- [ui](specs/ui.md)：使用者畫面（對話流、回話、便條、黑板、按鈕列、判斷失敗彈窗）與除錯 UI
- [help](specs/help.md)：提示：固定的提示頁、提示對話框（換頁與凍結）、說明指令、便條的引導、新手階段
- [recovery](specs/recovery.md)：補救：錯誤確認、重試、略過、undo／redo
- [storage](specs/storage.md)：存檔是 Apple 提醒事項：整份讀寫、差異、刪除快照、外部變動、權限
- [spoken-report](specs/spoken-report.md)：語音報告：念出成功的結果與問題、查詢預設 3 項與 readAll、只有停止等才中斷、開關
- [backup](specs/backup.md)：備份（目前暫停）：建立備份放到剪貼簿、換成備份整份取代待辦；兩個 App 共用的 JSON 格式
- [settings](specs/settings.md)：設定：選擇自動 AI、Gemini API key、Ollama 位址、模型與測試連線、除錯模式、分享測試紀錄
- [weather](specs/weather.md)：查天氣（額外能力）：日期與時段沿用查詢的換算、所在地或指定城市、規則組成的句子、失敗的回報
- [notifications](specs/notifications.md)：通知由提醒事項 App 跳出；App 只在新增或改日期、時間時維護 alarm

### 角色

- [elf-world](elf-world.md)：小精靈世界觀：出身、身高體重、個性與閒聊時的角色邊界；改小精靈的背景或世界觀先改這份

### Eval

- [judge-prompt](eval/judge-prompt.md)：給手動 AI 的判斷階段提示詞
- [judge-cases](eval/judge-cases.md)：比較不同 AI 判斷成效的測試句與預期 JSON
- [ai-alignment](eval/ai-alignment.md)：Foundation Models 和 Gemini 的對齊評估
