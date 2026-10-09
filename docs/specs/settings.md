# 設定

## Problem Statement

自動 AI 原本在 App 入口寫死，Gemini 的 API key 讀環境變數；iPhone 直接開啟 App 時讀不到環境變數，也沒辦法換 AI。使用者需要在 App 裡選擇用哪個 AI，並填入它需要的資訊。

## 目前狀態

**開放 Gemini 與 Apple Intelligence**：Ollama 暫不開放（缺失見 todo_list.md），程式保留，下面的規格在重新開放時適用。

- 設定畫面有 Apple Intelligence 與 Gemini 兩個開關（一次只開一個）、Gemini 的 API key（含清除）、模型與測試連線。
- 開放的 AI 只有一個時，固定使用它，不需要選擇：設定畫面不顯示 AI 的開關與模型欄位；之前選過其他 AI 的設定也用它。
- Apple Intelligence 和 Gemini 的對齊程度以 [ai-alignment](../eval/ai-alignment.md) 評估。
- 開啟 App 時沒有可以使用的 AI，直接打開設定畫面（iOS 的 sheet、macOS 的設定視窗）。

## Solution

設定畫面選擇自動 AI（Apple Intelligence、Gemini、Ollama，一次只開一個），並填入 Gemini API key、Ollama 的位址與兩者的模型；可以先測試連線。離開設定畫面時儲存並立即生效。沒有可以使用的 AI 時，小精靈提示無法運作。

一句話：**設定決定用哪個自動 AI；沒有 AI 就告訴使用者 App 無法運作。**

## User Stories

1. 作為使用者，我想在 App 裡填入 Gemini API key，不用設定環境變數。
2. 作為使用者，我想選擇用 Apple Intelligence、Gemini 或 Ollama，並知道我的裝置能不能用 Apple Intelligence。
3. 作為使用者，我想在 iPhone 上使用 Mac 上的 Ollama，填入 Mac 的 IP 與 port。
4. 作為使用者，我想沒有任何 AI 可以用時，小精靈直接告訴我，而不是沒有反應。
5. 作為使用者，我想改完設定就生效，不用重開 App。
6. 作為使用者，我想選 Gemini 與 Ollama 用哪個模型。
7. 作為使用者，我想填完設定先測試連線，知道 key、位址與模型對不對。

## Implementation Decisions

### 入口

- iOS：導覽列的齒輪按鈕，以 sheet 打開設定。
- macOS：系統的「設定」視窗，從導覽列的齒輪、選單或 ⌘, 打開。
- 兩個平台共用同一個設定畫面。設定不是操作待辦，是「低觸控」的例外（見 CLAUDE.md）。

### 天氣資料的標示

設定頁最下面是天氣資料與地名資料的標示，文字與連結見 [weather](weather.md) 的「標示」。

### AI 的選擇

- 三個開關：Apple Intelligence（Foundation Models）、Gemini、Ollama。一次只能開一個：開一個，其他自動關；可以全部關。
- **Apple Intelligence**：開啟前檢查這台裝置能不能用；不能用時開關無法打開，並顯示原因（裝置不支援、Apple Intelligence 沒有開啟、模型還沒準備好）。
- **Gemini**、**Ollama**：無法事先檢查連不連得到，開關一定可以打開；判斷時失敗就進入錯誤確認，回報原因（見 [recovery](recovery.md)）。Gemini 沒有 API key 時視為沒有 AI。
- 第一次開啟：開 Gemini。Apple Intelligence 比 Gemini 慢很多，由使用者自己打開。
- 選擇存在 UserDefaults。

### Gemini

- API key：密碼輸入框（不顯示內容、不自動修正、不自動大寫）。狀態顯示「已設定（…末四碼）」或「未設定」，不顯示完整的 key。
- 清除：垃圾桶圖示按鈕，清掉已存的 key。
- 模型：文字欄位，預設 `gemini-3.1-flash-lite`。
- key 存在 Keychain。不再讀環境變數 `GEMINI_API_KEY`。
- 沒有 key 時，狀態與失敗原因是「未設定 Gemini API key，請到設定填入」。

### Ollama

- IP 與 port 兩個欄位，預設 `localhost`、`11434`。在 Mac 上用預設值；iPhone 要填 Mac 的區網 IP。
- 模型：文字欄位，預設 `gemma4:e2b`。
- Mac 上的 Ollama 要接受區網連線（`OLLAMA_HOST=0.0.0.0`、防火牆），由使用者自己設定，App 不處理。
- App 允許以 http 連線區網位址（ATS 的 local networking）；iOS 申請區網存取權限。

### 測試連線

- Gemini、Ollama 各一個「測試連線」圖示按鈕（插頭 `powerplug`，滑鼠停留時顯示「測試連線」），用欄位上目前的值測試，不必先離開設定；測試中按鈕不能再按。
- **Gemini**：查詢該模型的資訊（`models/<模型>`），確認 key 有效、模型存在；不呼叫生成，不耗 token。
- **Ollama**：讀取已下載的模型清單（`/api/tags`），確認連得到、模型已下載。
- 結果顯示在按鈕旁：「連線成功」，或失敗原因（key 無效、找不到模型、連不到、逾時等）。

### 除錯模式（只在 macOS）

- 開關「除錯模式」，預設關。打開時主視窗在使用者畫面右邊顯示除錯 UI（見 [ui](ui.md)）。
- 存在 UserDefaults。iOS 不顯示這個開關。

### 預設提示詞

- 「開發」區塊的開關「預設提示詞」，兩個平台都有，預設關。打開時，複製與分享的測試紀錄開頭附上自動 AI 的固定提示詞定義（見 [judgment](judgment.md) 的「紀錄」）；定義很長，平常不附。
- 存在 UserDefaults。

### 分享測試紀錄

- 「開發」區塊的「分享測試紀錄」，兩個平台都有：接在「預設提示詞」後面；macOS 的最前面是除錯模式。
- 按下時用系統的分享（iOS 是分享面板，macOS 是分享選單）分享按下那一刻的測試紀錄，以文字分享，不做成檔案。內容和除錯 UI 的「複製」完全相同（見 [ui](ui.md) 的「除錯 UI」）：讓沒有除錯 UI 的 iPhone 也能把一次實測的經過交給開發者。
- 是開發者的觀察工具，和除錯 UI 一樣不是產品功能：沒有語音指令。

### 儲存與生效

- 沒有儲存按鈕：離開設定畫面時儲存（AI 的選擇、Gemini API key 與模型、Ollama 的位址與模型、除錯模式、預設提示詞），並立刻換成新的自動 AI、顯示或隱藏除錯 UI；除錯 UI 的 AI 狀態跟著更新。

### 沒有 AI 可以使用

- 情況：三個都關；選了不開放的 AI（Ollama）；選了 Apple Intelligence 但這台裝置已經不能用（例如 Apple Intelligence 被關掉）；選了 Gemini 但沒有 API key。
- 開啟 App 與每次需要判斷時，小精靈顯示「目前沒有可以使用的 AI，無法運作，請到設定開啟。」
- 說的話照常排隊；判斷失敗的結果輪到時進入錯誤確認，後面的結果不出現。到設定開好 AI 後重試就能繼續。
- 除錯 UI 改用手動 AI 時不受影響。

## Testing Decisions

- 以假的 key 來源驗證 Gemini：沒有 key 時的狀態與失敗原因。
- 測試連線：以假的網路回應驗證成功與各種失敗原因的文字（Gemini 的 key 無效、找不到模型；Ollama 連不到、模型沒下載）。
- 選擇：開一個其他自動關；Apple Intelligence 不能用時無法打開；第一次開啟是 Gemini；選了不開放的 AI 時沒有 AI。
- 沒有 AI：判斷時進入錯誤確認並回報「目前沒有可以使用的 AI」；換成可以用的 AI 後重試就能繼續；手動 AI 不受影響。
- 手動驗證：
  - [ ] Keychain 存、讀、清除；重開 App 後 key 還在
  - [ ] 離開設定後立刻用新的 AI
  - [ ] macOS 切換除錯模式後，除錯 UI 立刻顯示或隱藏
  - [ ] 「預設提示詞」關時分享的紀錄沒有固定提示詞，打開後有；重開 App 後開關還在
  - [ ] iPhone 在設定按「分享測試紀錄」，用 AirDrop 或郵件傳到 Mac，內容和除錯 UI 複製的相同
  - [ ] iPhone 連到 Mac 上的 Ollama
  - [ ] 測試連線：Gemini 正確與錯誤的 key、Ollama 開著與關著
  - [ ] 最下面有 Open-Meteo 與地名資料的標示，連結都能點開

## Out of Scope

- 從清單選模型（模型用文字欄位輸入）
