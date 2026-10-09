# 判斷的對齊評估

對齊評估是一種 eval（評估）：用固定的測試句與預期答案，量測 AI 的準確度。

用來確認 Foundation Models 判斷的準確度對齊 Gemini：同一份測試句，各自走 App 的路徑（規則校正 → 規則判斷 → AI 校正 ∥ AI 判斷，校正採用時重判），比最後採用的指令清單。FM 的分數至少要等於 Gemini。

## 測試句

寫在 [`AIAlignmentEval.swift`](../../voice_todoTests/AIAlignmentEval.swift) 的 `AlignmentCase.all`，預期是依 spec 寫的指令清單（寫法同 [judge-cases](judge-cases.md)），不是 Gemini 的輸出：Gemini 也會錯。

- 評估句：查詢、新增、修改、刪除、聊天、錯字。
- 提示頁裡規則判斷不收的句型：用內容描述的新增、修改、設定完成。
- 換說法：實機說過的與相近的（「讓第二項改到明天」「弄第三跟第四項改到10月1號」）。

規則判斷命中的句子兩邊一定相同，不放進來（評估會檢查）。FM 提示詞裡的句型參考（類似 few-shot prompting（少樣本提示），但用句型模板，不用例句）不能和測試句重複，否則量不出真正的準確度。

## 做法

每句一個新的 `Elf`（測試待辦、黑板是「目前」），結果是最後採用的判斷（作廢的不算）。聽不懂和空清單相同。

```sh
# 記錄 Gemini（讀 App 的 Keychain 裡的 API key）；測試句改了才重跑
TEST_RUNNER_AI_EVAL=gemini xcodebuild test -scheme voice_todo -destination 'platform=macOS' -only-testing:voice_todoTests/AIAlignmentEval
# 從測試結果匯出 AIAlignmentGemini.json（見下面），放進 voice_todoTests/

# FM 對照；TEST_RUNNER_AI_EVAL_ONLY='句子1|句子2' 只跑這些句子
TEST_RUNNER_AI_EVAL=fm xcodebuild test -scheme voice_todo -destination 'platform=macOS' -only-testing:voice_todoTests/AIAlignmentEval
```

結果是 `AIAlignmentReport.md`：總分、FM 每句的耗時，每句的預期、Gemini、FM 與 FM 的校正。它附在測試結果裡（Gemini 的記錄 `AIAlignmentGemini.json` 也是）；macOS 27 起終端機讀不到 App 的容器，從測試結果匯出：

```sh
R=$(ls -td ~/Library/Developer/Xcode/DerivedData/voice_todo-*/Logs/Test/*.xcresult | head -1)
xcrun xcresulttool export attachments --path "$R" --output-path <資料夾>
```

## 調整的方式

- 先跑一次基準；之後每輪先只重跑上一輪錯的句子，輪末跑完整一次。
- 可以改 FM 的 class 與 App 的規則（規則判斷、規則校正）；規則的改進兩邊都算到。
- 停損：基準之後最多 3 輪，FM 仍然低於 Gemini 就停，結論是這台裝置的 FM 對不齊。
- 速度只記錄（見憲章 D0-3；這次的取捨是準確度優先）。

最近一次的結果見 [todo_list](../../todo_list.md) 的「Foundation Models 對齊」。
