//
//  Elf.swift
//  voicecalender
//

import Foundation
import Observation

/// 小精靈（見 CONTEXT.md）：語音輸入（或測試輸入）→ 背景把一句話解讀成使用者意圖（`IntentPreparer`）
/// → 照說話的順序一個一個執行成任務、顯示、語音報告（見 docs/specs/queue.md）。
/// 背景同時解讀多句話，但任務一次只執行一個（見 docs/specs/judgment.md）。
@Observable
final class Elf {

    let store: TodoStore
    /// 黑板：目前專注的範圍（見 docs/specs/todos.md 的「黑板」）。
    let board: Board

    // MARK: 除錯 UI

    private(set) var modelStatus = ""
    /// 由設定決定，可以在執行中更換；nil 表示沒有可以使用的 AI（見 docs/specs/settings.md）。
    private var autoAI: (any AutoAI)?

    // 控制
    private(set) var isVoiceOn = false
    var useAutoAI = true {
        didSet {
            log("開關", aiLabel, sentence: nil)
            // 手動 AI 一次只能貼一份 AI 回應，所以一次只解讀一句（見 docs/specs/queue.md）。
            intents.limit = useAutoAI ? 2 : 1
            prepare(intents.startable())
        }
    }

    // 輸入
    struct Sentence {
        let number: Int
        let text: String
        /// 語音或文字（測試輸入）。
        let source: String
    }

    private(set) var sentence = SentenceBuilder()

    // 校正
    private(set) var correctionInput = ""
    private(set) var correctionOutput = ""

    // 判斷
    private(set) var commands: [String] = []
    private(set) var currentCommand = ""
    private(set) var results: [String] = []
    private(set) var waitingText = ""
    /// 最近一次查到的天氣文字：還在更新的回話是它時，旁邊要有資料來源的標示（見 docs/specs/weather.md 的「標示」）。
    private var weatherMessage: String?
    var showsWeatherCredit: Bool {
        weatherMessage.map { elfMessage.contains($0) } ?? false
    }

    // 手動 AI
    struct AIRequest: Equatable {
        /// 一般判斷、釐清後判斷或刪除確認。
        let kind: String
        let text: String
    }

    /// 等手動 AI 回應的使用者提示詞，照順序；回答的排在最前面。
    private var manualWaits: [(request: AIRequest, reply: CheckedContinuation<String?, Never>)] = []
    /// 目前要貼回 AI 回應的那一筆。
    var manualRequest: AIRequest? { manualWaits.first?.request }

    // 測試紀錄
    struct LogEntry: Identifiable {
        let id: Int
        let sentence: Int?
        let stage: String
        let text: String

        var number: String { sentence.map { "#\($0)" } ?? "#-" }
        var line: String { "[\(number) \(stage)] \(text)" }
    }

    private(set) var testLog: [LogEntry] = []
    /// 複製與分享的測試紀錄是否附上固定提示詞的定義（設定的「預設提示詞」，見 docs/specs/settings.md）。
    var includesPrompts = false
    /// 上次印進紀錄的黑板；黑板看得到的內容變了才再印（見 docs/specs/judgment.md 的「紀錄」）。
    private var loggedBoard: [String] = []

    // 小精靈
    private(set) var elfMessage = "" {
        didSet {
            // 回話換成別的文字就不是提示對話框了（一句話裡還有其他指令時，提示頁只是回話裡的文字）。
            if hintPage?.text != elfMessage {
                hintPage = nil
            }
            if elfMessage != oldValue {
                let lost = !isReplyArchived && !oldValue.isEmpty ? "（舊的沒留下）" : ""
                log("對話流", "回話：「\(oldValue)」→「\(elfMessage)」\(lost)")
            }
            isReplyArchived = false
        }
    }

    // 使用者畫面（見 docs/specs/ui.md）

    /// 正在處理的一句話：目前的結果（輪到了、還在思考的也算）或插隊的回答；有校正結果時是校正後的句子。
    private(set) var processingSentence: Sentence? {
        didSet {
            guard let sentence = processingSentence else {
                return
            }
            if sentence.number == oldValue?.number {
                // 校正後的句子換掉紀錄裡的原句。
                if let last = conversation.indices.last, conversation[last].sentence == sentence.number {
                    log("對話流", "取代 使用者：\(conversation[last].text) → \(sentence.text)", sentence: sentence.number)
                    conversation[last].text = sentence.text
                }
                return
            }
            archiveReply()
            appendMessage(sentence: sentence.number, sentence.text)
        }
    }

    // 對話流（見 docs/specs/ui.md 的「對話流」）

    /// 一則對話：使用者說的一句話（有句子編號），或小精靈的回話。
    struct Message: Identifiable, Equatable {
        let id: Int
        let sentence: Int?
        var text: String
        /// 查到天氣的回話：標示一直跟著它（見 docs/specs/weather.md 的「標示」）。
        var showsWeatherCredit = false
        /// 小精靈的回話的插畫：回話結束時的狀態，之後固定（見 docs/specs/ui.md 的「對話流」）。
        var mood = Mood.done
        /// 凍結的提示對話框停的那一頁（見 docs/specs/help.md 的「提示對話框」）。
        var hint: String?

        var isUser: Bool { sentence != nil }
    }

    /// 對話流裡已經固定的話與回話，不存檔；最後一則回話還在更新時不在這裡，見 `liveReply`。
    private(set) var conversation: [Message] = []
    private var isReplyArchived = false

    /// 還在更新的最後一則回話：下一句話開始或觸控產生新的回話時才固定，放進 `conversation`。畫面上位置相同。
    var liveReply: String? {
        isReplyArchived || elfMessage.isEmpty ? nil : elfMessage
    }

    /// 回話固定在對話流：還沒凍結的提示對話框在這時凍結。
    private func archiveReply() {
        if let reply = liveReply {
            appendMessage(sentence: nil, reply, showsWeatherCredit: showsWeatherCredit, mood: settledMood, hint: liveHint?.name)
        }
        isReplyArchived = true
    }

    private func appendMessage(sentence: Int?, _ text: String, showsWeatherCredit: Bool = false, mood: Mood = .done, hint: String? = nil) {
        log("對話流", "加入 \(sentence == nil ? "小精靈" : "使用者")：\(text)", sentence: sentence ?? currentSentence)
        conversation.append(Message(id: (conversation.last?.id ?? 0) + 1, sentence: sentence, text: text, showsWeatherCredit: showsWeatherCredit, mood: mood, hint: hint))
    }

    // 提示（見 docs/specs/help.md）

    /// 最後一則回話是提示對話框時，它目前那一頁。
    private var hintPage: HintPage?

    /// 還沒凍結的提示對話框目前那一頁：最後一則回話還在更新、而且是提示對話框。最多只有這一個。
    var liveHint: HintPage? {
        liveReply == nil ? nil : hintPage
    }

    /// 正在念提示頁：念的時候不擋住後面的結果，換頁或下一個結果輪到就停（見 docs/specs/spoken-report.md 的「中斷」）。
    private var isSpeakingHint = false
    /// 每次念提示或停止就加一：還沒開始念就被停掉的那次不念。
    private var hintSpeechID = 0

    /// 排在正在處理的那一句後面、還沒呈現的句子（輸入、執行、結果佇列裡的）。
    var pending: [Sentence] {
        intents.entries.map(\.input.sentence).filter { $0.number != processingSentence?.number }
    }

    /// 背景沒在解讀、也沒在呈現：處理完了，或停在等回答；給測試等處理完。
    var isIdle: Bool {
        preparing.isEmpty && presenter == nil
    }

    /// 除錯 UI 的佇列狀態，每句一行（見 docs/specs/queue.md 的「紀錄」）。
    var queueStatus: [String] {
        let current = presenting.map { number in
            ["#\(number) 目前" + (waiting != nil || failure != nil ? "（等回答）" : "")]
        } ?? []
        return current + intents.entries.map { entry in
            let state = switch entry.state {
            case .queued: "排隊"
            case .preparing: "判斷中"
            case .ready: "準備好"
            }
            return "#\(entry.number) \(state)：\(entry.input.sentence.text)"
        }
    }

    enum Mood {
        case listening, thinking, done, confused
    }

    /// 還在更新的回話的插畫：執行中或等下一個結果是思考中，其他照回話的結果。
    /// 使用者正在說話不算：有沒有在聆聽看語音輸入開關（見 docs/specs/ui.md 的「對話流」）。
    var mood: Mood {
        isBusy || isThinking ? .thinking : settledMood
    }

    /// 回話的結果：錯誤確認或聽不懂、等回答、其他。回話固定時用這個，不會停在思考中。
    private var settledMood: Mood {
        if failure != nil || misheard {
            return .confused
        }
        return waiting != nil ? .listening : .done
    }

    /// 最近一個結果判斷出空的指令清單。
    private var misheard = false

    /// 便條的引導（見 docs/specs/help.md 的「便條」）。
    var guide: Guide.Line {
        Guide.line(unclear: unclear, used: guideUsed, boardHasTodos: !board.visible(store.todos, today: TodoStore.dayString(.now)).isEmpty)
    }

    /// 便條開關；初始狀態由 App 從存檔提供。
    var showsGuide: Bool
    /// 用過的操作，由 App 存檔；全部是空的是新手階段。
    private(set) var guideUsed: Set<Guide.Step>
    /// 最近一個沒有指令的句子；之後有指令執行成功就清掉。
    private var unclear: String?

    // 語音報告（見 docs/specs/spoken-report.md）

    /// 語音報告開關；初始狀態由 App 從存檔提供。
    private(set) var isReportOn: Bool
    /// 查詢念全部；中斷時重設。
    private(set) var readAll = false
    private(set) var isSpeaking = false

    // 補救（見 docs/specs/recovery.md）

    /// 錯誤確認中可以重試。
    var canRetry: Bool { failure != nil }
    /// 錯誤確認的原因，給判斷失敗的彈窗。
    private(set) var failureMessage = ""
    var canUndo: Bool { history.canUndo && canTouch }
    var canRedo: Bool { history.canRedo && canTouch }

    /// 方框、checkbox、復原、重做：目前的結果不在執行中、沒在等回答，也不在錯誤確認；背景在解讀不影響。
    /// 沒有存檔（沒有權限）時都不能點，正在讀取已完成的時也不能（見 docs/specs/storage.md）。
    var canTouch: Bool {
        !isBusy && waiting == nil && failure == nil && store.unavailableReason == nil && !isLoadingRest && storageTask == nil
    }

    // 存檔（見 docs/specs/storage.md）

    /// 正在延遲讀取已完成的待辦。
    private(set) var isLoadingRest = false
    /// 除錯 UI 的測試清單開關（見 docs/specs/storage.md 的「測試清單」）。
    private(set) var isTestList = false
    /// 外部變動在任務進行中發生：任務結束後再重新讀取。
    private var pendingReload = false
    /// 啟動時的讀取完成之前，外部變動（含回到前景）不處理：啟動本身就在讀。
    private var hasLoaded = false
    /// 任務之外的背景讀取（外部變動、點開關的延遲讀取、重新開始、測試清單）。進行中不開始任務、不能點：
    /// 讀回來的待辦會整份換掉，任務做到一半就會被蓋掉。
    private var storageTask: Task<Void, Never>?
    private var storageTaskID = 0

    // MARK: -

    /// 目前的結果在等的回答。任務的快照保留到回答處理完。
    private enum Waiting {
        case clarify(Clarification)
        case confirmDelete(Clarification, ids: [Int])
        /// 「要全部念完嗎？」：還沒念的查詢項目。
        case readMore(unread: [Todo])
    }

    private var waiting: Waiting? {
        didSet { waitingText = waiting.map(Self.describe) ?? "" }
    }

    /// 同一句話裡，排在釐清或確認之後、還沒執行的指令。
    private var remaining: [Command] = []

    /// 錯誤確認中：失敗的那次判斷，與失敗的那句話。
    private var failure: Failure?
    private var failedSentence: Sentence?
    /// 失敗的那句話定稿時的畫面資訊；重試時沿用（見 docs/specs/screen-info.md）。
    private var failedScreen: ScreenInfo?
    private var history = TodoHistory()
    /// 這次執行的 undo 狀態從哪裡開始；同一句話裡復原、重做後移到那之後（見 docs/specs/todos.md 的「指令」）。
    private var undoStart: [Todo] = []

    private var reports: [String] = []
    /// 目前的結果裡成功的結果，呈現時念出來。
    private var spokenReports: [Report] = []
    /// 每次念或中斷就加一：被中斷的那次念完時，不能把新的念的狀態改掉。
    private var speechID = 0

    // 佇列（見 docs/specs/queue.md）

    /// 定稿的一句話與定稿時的畫面資訊。
    private struct Heard {
        let sentence: Sentence
        let screen: ScreenInfo
    }

    private var intents = IntentQueue<Heard, UserIntent>()
    /// 背景解讀中的句子。
    private var preparing: [Int: Task<Void, Never>] = [:]

    /// 插隊的回答，或彈窗的重試、略過：由呈現的 Task 在目前的結果等回答時處理。
    private enum Answer {
        case sentence(Sentence, screen: ScreenInfo)
        case retry
        case skip
    }

    private var pendingAnswer: Answer?
    /// 呈現的 Task：照順序執行、顯示、報告；沒有可以呈現的就結束，有新的再開始。
    private var presenter: Task<Void, Never>?
    private var presenterID = 0
    /// 目前呈現中的句子編號。
    private var presenting: Int?
    /// 正在執行目前的結果（執行器、等回答的 AI）。
    private var isBusy = false
    /// 輪到的句子還沒解讀好。
    private var isThinking = false

    /// 報告顯示時間（見 docs/specs/queue.md）：沒有念的結果最少顯示的時間；時間到了才換下一個。
    private var holdTask: Task<Void, Never>?
    private var holdID = 0
    /// nil 時不等（單元測試、Preview）。
    private let wait: ((Duration) async -> Void)?

    /// 遞增的時間點：開口、問題出現、念的開始與結束，只用來比先後。
    private var clock = 0
    /// 最近一次念的文字與期間，給回音比對。
    private var spoken: (text: String, from: Int, to: Int?)?

    /// nil 時不聆聽（單元測試、Preview）。
    private let speech: (any SpeechInput)?
    /// nil 時不念（單元測試、Preview）。
    private let speaker: (any SpeechOutput)?
    /// nil 時不讀寫存檔，待辦從測試待辦開始（單元測試、Preview）。
    private let storage: (any TodoStorage)?
    /// nil 時查天氣放棄（單元測試、Preview）。
    private let weather: WeatherLookup?
    private var pauseTask: Task<Void, Never>?

    private var sentenceCount = 0
    /// 聊天補充資訊的循環（見 docs/specs/chat.md 的「補充資訊」），由 App 存檔。
    private(set) var chatRotation: ChatRotation
    /// 開場問候輪到的提示頁；存在 UserDefaults（見 docs/specs/help.md 的「開場問候」）。
    private(set) var greetingIndex: Int
    /// 目前呈現中或回答的句子編號，給紀錄用。
    private var currentSentence: Int?

    /// `boardPage`、`showDone` 是存檔的黑板頁與 checkbox 狀態；`wait` 是報告顯示時間的等待。
    init(
        autoAI: (any AutoAI)?,
        speech: (any SpeechInput)? = nil,
        storage: (any TodoStorage)? = nil,
        weather: WeatherLookup? = nil,
        speaker: (any SpeechOutput)? = nil,
        reportOn: Bool = true,
        boardPage: BoardPage.Saved? = nil,
        showDone: Bool = false,
        chatRotation: ChatRotation = ChatRotation(),
        greetingIndex: Int = 0,
        guideUsed: Set<Guide.Step> = [],
        showsGuide: Bool = true,
        includesPrompts: Bool = false,
        wait: ((Duration) async -> Void)? = nil
    ) {
        self.includesPrompts = includesPrompts
        self.autoAI = autoAI
        self.speech = speech
        self.speaker = speaker
        self.wait = wait
        isReportOn = reportOn
        self.chatRotation = chatRotation
        self.greetingIndex = greetingIndex
        self.guideUsed = guideUsed
        self.showsGuide = showsGuide
        self.storage = storage
        self.weather = weather
        store = TodoStore(storage: storage, todos: storage == nil ? TestTodos.make() : [])
        board = Board(today: .now, saved: boardPage, showDone: showDone)
        storage?.onExternalChange = { [weak self] in
            self?.storageChanged()
        }
    }

    func start() async {
        // 開場問候不經過 AI，直接放進對話流：不念，也不是 `elfMessage`，所以不在畫面資訊裡（見 docs/specs/help.md 的「開場問候」）。
        if guideUsed.isEmpty {
            log("提示", "開場問候：新手", sentence: nil)
            appendMessage(sentence: nil, Greeting.novice)
        } else {
            let (page, next) = Greeting.page(greetingIndex)
            greetingIndex = next
            log("提示", "開場問候：\(page.name)", sentence: nil)
            appendMessage(sentence: nil, page.text)
        }
        updateModelStatus()
        await loadStorage("讀取")
        hasLoaded = true
        // 沒有權限的提示不能被「沒有 AI」蓋掉，接在後面（見 docs/specs/storage.md 的「權限」）。
        let unavailable = store.unavailableReason.map { [$0] } ?? []
        if !unavailable.isEmpty {
            elfMessage = unavailable[0]
        }
        if useAutoAI && autoAI == nil {
            elfMessage = (unavailable + ["\(Self.noAI)。"]).joined(separator: "\n\n")
        }
        if speech != nil {
            setVoice(true)
        }
    }

    func stop() {
        speech?.stop()
    }

    /// 開啟 App 時沒有 AI 就直接打開設定（見 docs/specs/settings.md 的「目前狀態」）。
    var hasAutoAI: Bool { autoAI != nil }

    /// 離開設定時換成新的自動 AI；已經送出的使用者提示詞用原本的 AI 做完。
    func setAutoAI(_ ai: (any AutoAI)?) {
        autoAI = ai
        updateModelStatus()
        log("設定", aiLabel, sentence: nil)
        if useAutoAI && ai == nil && presenter == nil && waiting == nil && failure == nil {
            elfMessage = "\(Self.noAI)。"
        }
    }

    private static let noAI = IntentPreparer.noAI

    private func updateModelStatus() {
        modelStatus = autoAI.map { "\($0.name)　\($0.status)" } ?? Self.noAI
        print("[Model] \(modelStatus)")
    }

    // MARK: - 控制（除錯 UI）

    /// 語音輸入開關。關閉後不會自動打開；不中斷語音報告（見 docs/specs/ui.md）。
    func setVoice(_ on: Bool) {
        guard on != isVoiceOn else {
            return
        }
        isVoiceOn = on
        log("開關", "語音輸入：\(on ? "開" : "關")", sentence: nil)
        if on {
            Task {
                await speech?.start { [weak self] text, isFinal in
                    self?.receive(text, isFinal: isFinal)
                }
            }
        } else {
            speech?.stop()
            pauseTask?.cancel()
            sentence = SentenceBuilder()
        }
    }

    /// 測試輸入：每一行是一句話，開口時間是送出的時間；送出時關閉語音輸入。
    func submitTestInput(_ text: String) {
        let lines = Self.sentences(in: text)
        guard !lines.isEmpty else {
            return
        }
        setVoice(false)
        for line in lines {
            receive(line, source: "文字", spokenAt: tick())
        }
    }

    static func sentences(in text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// 手動 AI 回應：交給最前面那一筆。
    func submitManualResponse(_ json: String) {
        guard !manualWaits.isEmpty else {
            elfMessage = "目前沒有等待手動 AI"
            log("手動 AI", "目前沒有等待手動 AI，不處理：\(json)", sentence: nil)
            return
        }
        manualWaits.removeFirst().reply.resume(returning: json)
    }

    /// 重新開始：清空測試紀錄、三個佇列、所有等待與 undo 的歷史，再從存檔重新讀取；不改變待辦與開關。
    /// 測試清單打開時，先把測試清單換回測試待辦（見 docs/specs/storage.md 的「重新開始」）。
    func restart() {
        clearQueues()
        interrupt("重新開始")
        readAll = false
        waiting = nil
        remaining = []
        failure = nil
        failedSentence = nil
        history = TodoHistory()
        reports = []
        spokenReports = []
        correctionInput = ""
        correctionOutput = ""
        commands = []
        currentCommand = ""
        results = []

        board.reset(today: .now)
        elfMessage = ""
        conversation = []
        testLog = []
        loggedBoard = []
        sentenceCount = 0
        currentSentence = nil
        processingSentence = nil
        misheard = false
        unclear = nil
        log("重新開始", isTestList ? "測試清單換回測試待辦" : "重新讀取存檔", sentence: nil)
        readStorage {
            if self.isTestList {
                await self.switchTestData(TestTodos.make())
            } else {
                await self.loadStorage("重新讀取")
            }
        }
    }

    /// 背景讀取存檔：照順序一個接一個，全部做完前不開始任務。
    private func readStorage(_ work: @escaping () async -> Void) {
        let previous = storageTask
        storageTaskID += 1
        let id = storageTaskID
        storageTask = Task {
            await previous?.value
            await work()
            if id == storageTaskID {
                storageTask = nil
            }
        }
    }

    // MARK: - 存檔（見 docs/specs/storage.md）

    /// 讀取存檔，在測試紀錄與 console 記讀到幾筆、花了多久；回傳待辦是否改變。沒有存檔時不讀。
    @discardableResult
    private func loadStorage(_ stage: String) async -> Bool {
        guard storage != nil else {
            return false
        }
        let start = ContinuousClock.now
        let changed = await store.load()
        log("存檔", "\(stage)：\(store.unavailableReason ?? "\(store.todos.count) 筆")（\(IntentPreparer.elapsed(since: start))）", sentence: nil)
        if store.unavailableReason == nil, board.showDone {
            await loadRest()
        }
        return changed
    }

    /// 延遲讀取已完成的待辦；讀進來的補進 undo 歷史的每一個狀態。失敗時回傳原因（見 docs/specs/storage.md 的「延遲讀取」）。
    @discardableResult
    private func loadRest() async -> String? {
        guard storage != nil else {
            return nil
        }
        isLoadingRest = true
        defer { isLoadingRest = false }
        let start = ContinuousClock.now
        do {
            let rest = try await store.loadRest()
            history.insert(rest)
            if !rest.isEmpty {
                undoStart += rest
                log("存檔", "讀取已完成：\(rest.count) 筆（\(IntentPreparer.elapsed(since: start))）", sentence: nil)
            }
            return nil
        } catch {
            log("存檔", "讀取已完成失敗：\(error.localizedDescription)", sentence: nil)
            return error.localizedDescription
        }
    }

    /// 勾選「完成」之前要先讀已完成的：設定顯示勾選完成、刪除完成自動勾選（見 docs/specs/todos.md 的「黑板」）。
    private func needsRest(_ command: Command) -> Bool {
        guard storage != nil, !board.showDone else {
            return false
        }
        return command.action == .setDisplay && command.showDone == true
            || command.action == .deleteTodos && command.isDone == true
    }

    /// 存檔被 App 以外的地方改了，或回到前景：任務進行中先記著，任務結束後再重新讀取（見 docs/specs/storage.md 的「外部變動」）。
    func storageChanged() {
        guard storage != nil, hasLoaded else {
            return
        }
        guard !isBusy, !isWaitingTask else {
            pendingReload = true
            return
        }
        pendingReload = false
        readStorage {
            await self.reloadExternal()
        }
    }

    /// 等釐清或刪除確認：任務還沒結束。
    private var isWaitingTask: Bool {
        switch waiting {
        case .clarify?, .confirmDelete?: true
        case .readMore?, nil: false
        }
    }

    /// 讀回來的和記憶體裡的相同就是 App 自己寫入造成的，忽略；不同就換掉並清空 undo 的歷史。
    private func reloadExternal() async {
        let before = store.todos
        guard await loadStorage("外部變動") else {
            return
        }
        let changes = TodoHistory.storageChanges(from: before, to: store.todos)
        log("存檔", (["外部變動的差異：\(changes.count) 項"] + changes).joined(separator: "\n"), sentence: nil)
        history = TodoHistory()
        // 不改還在更新的回話：可能正在等回答；先把它固定在對話流裡，再加這一則。
        archiveReply()
        appendMessage(sentence: nil, store.unavailableReason ?? "提醒事項有變動，已更新")
    }

    private func applyPendingReload() {
        if pendingReload {
            storageChanged()
        }
    }

    /// 除錯 UI 的測試清單開關（見 docs/specs/storage.md 的「測試清單」）。
    func setTestList(_ on: Bool) {
        guard on != isTestList, storage != nil else {
            return
        }
        isTestList = on
        log("開關", "測試清單：\(on ? "開" : "關")", sentence: nil)
        readStorage {
            await self.switchTestData(on ? TestTodos.make() : nil)
        }
    }

    /// 換清單時清空 undo 的歷史。
    private func switchTestData(_ seed: [Todo]?) async {
        history = TodoHistory()
        do {
            try await store.useTestData(seed)
            log("存檔", seed == nil ? "回到所有清單：\(store.todos.count) 筆" : "測試清單：\(store.todos.count) 筆", sentence: nil)
            if store.unavailableReason == nil, board.showDone {
                await loadRest()
            }
        } catch {
            elfMessage = error.localizedDescription
            log("存檔", "測試清單失敗：\(error.localizedDescription)", sentence: nil)
        }
    }

    /// 複製用的純文字：今天日期與目前用的 AI、固定提示詞的定義（有打開時），之後每行一筆紀錄。
    var testLogText: String {
        testLogText(includesPrompts: includesPrompts)
    }

    func testLogText(includesPrompts: Bool) -> String {
        let header = "測試紀錄　今天：\(DatePhrase.describe(.now))　\(aiLabel)"
        guard includesPrompts else {
            return ([header] + testLog.map(\.line)).joined(separator: "\n")
        }
        let correction = (autoAI as? any CorrectionAI).map { [(IntentPreparer.correctionPromptName, $0.correctionPrompt)] } ?? []
        let chat = (autoAI as? any ChatAI).map { [(IntentPreparer.chatPromptName, $0.chatPrompt)] } ?? []
        let prompts = ((autoAI.map { [(IntentPreparer.judgePromptName, $0.judgePrompt), (Self.confirmPromptName, $0.confirmPrompt)] } ?? []) + correction + chat)
            .map { "固定提示詞「\($0)」：\n\($1.instructions)\n輸出結構：\n\($1.schema)\n" }
        return ([header, ""] + prompts + testLog.map(\.line)).joined(separator: "\n")
    }

    private static let confirmPromptName = "刪除確認提示詞"

    // MARK: - 語音輸入階段

    /// 辨識結果不中斷語音報告：只有「停止」等明確的話才會（見 docs/specs/spoken-report.md 的「中斷」）。
    private func receive(_ text: String, isFinal: Bool) {
        guard isVoiceOn else {
            return
        }
        let moment = tick()
        guard isFinal else {
            sentence.receiveVolatile(text, at: moment)
            restartPauseTimer()
            return
        }
        if let finished = sentence.receiveFinal(text, at: moment) {
            receive(finished.text, source: "語音", spokenAt: finished.spokenAt)
        }
    }

    private func restartPauseTimer() {
        pauseTask?.cancel()
        pauseTask = Task {
            do {
                try await Task.sleep(for: SentenceBuilder.pause)
            } catch {
                return
            }
            if let finished = sentence.pause() {
                receive(finished.text, source: "語音", spokenAt: finished.spokenAt)
            } else if !sentence.volatileText.isEmpty {
                await speech?.finalize()
            }
        }
    }

    /// 一句話進來（見 docs/specs/queue.md 的「一句話進來時」）：全部取消、輔助關鍵字、回音、回答，其他的放進輸入佇列。
    private func receive(_ heard: String, source: String, spokenAt: Int) {
        sentenceCount += 1
        let number = sentenceCount
        // 說「顯示全部」時，這句話記成「顯示所有資料」（見 docs/specs/todos.md 的「黑板」）。
        let heard = BoardKeywords.action(heard) == .showEverything ? BoardKeywords.showEverythingText : heard
        log("輸入", "\(source)：\(heard)", sentence: number)
        // 規則校正在定稿當下：之後的關鍵字、AI 校正、判斷與聊天都用處理後的句子（見 docs/specs/correction.md）。
        let text = Correction.tool(heard)
        if text != heard {
            log("校正", "規則：\(heard) → \(text)", sentence: number)
        }

        // 只比對原句：AI 校正改出來的句子不會走到這裡。
        if CancelAllKeywords.matches(heard) {
            processingSentence = Sentence(number: number, text: text, source: source)
            cancelAll(number)
            return
        }
        if handleAuxiliary(text, number: number) {
            processingSentence = Sentence(number: number, text: text, source: source)
            return
        }
        // 念提示頁時，提示的說法不是回音：提示頁裡本來就有連結名稱與要使用者照著說的話（見 docs/specs/queue.md）。
        if let spoken, spoken.from <= spokenAt, spoken.to.map({ spokenAt <= $0 }) ?? true, Echo.isEcho(text, of: spoken.text),
           !(isSpeakingHint && isHintCommand(JudgeTool.command(text, today: .now, links: liveHint?.links ?? []))) {
            log("回音", "丟掉「\(text)」（正在念：\(spoken.text)）", sentence: number)
            return
        }

        let sentence = Sentence(number: number, text: text, source: source)
        let screen = snapshot()
        if intents.claimAnswer(spokenAt: spokenAt) {
            log("插隊", "回答：\(waiting.map { Self.describe($0) } ?? "錯誤確認")", sentence: number)
            pendingAnswer = .sentence(sentence, screen: screen)
            advance()
            return
        }
        log("排隊", text, sentence: number)
        prepare(intents.enqueue(number, Heard(sentence: sentence, screen: screen), spokenAt: spokenAt))
        advance()
    }

    /// 輔助關鍵字：只控制報告與麥克風，不碰任務與佇列（見 docs/specs/flow.md 的「App 直接處理的話」）。
    private func handleAuxiliary(_ text: String, number: Int) -> Bool {
        if VoiceOffKeywords.matches(text) {
            setVoice(false)
            return true
        }
        if ReportKeywords.isStop(text) {
            stopReport()
            return true
        }
        if let on = ReportKeywords.toggle(text) {
            setReport(on)
            return true
        }
        return false
    }

    private func tick() -> Int {
        clock += 1
        return clock
    }

    // MARK: - 背景：解讀成使用者意圖

    private func prepare(_ entries: [IntentQueue<Heard, UserIntent>.Entry]) {
        for entry in entries {
            let preparer = makePreparer(urgent: false)
            let number = entry.number
            let start = ContinuousClock.now
            // 規則判斷命中就不用等：輪到前不會先顯示「思考中」，提示的換頁也不會先讓提示對話框凍結。
            if let intent = preparer.rule(entry.input.sentence.text, number: number, screen: entry.input.screen) {
                log("準備好", Self.ready(intent, since: start), sentence: number)
                prepare(intents.prepared(number, intent))
                continue
            }
            preparing[number] = Task {
                let intent = await preparer.prepare(entry.input.sentence.text, number: number, screen: entry.input.screen)
                guard !Task.isCancelled, let intent else {
                    return
                }
                preparing[number] = nil
                log("準備好", Self.ready(intent, since: start), sentence: number)
                prepare(intents.prepared(number, intent))
                advance()
            }
        }
    }

    /// 準備好的紀錄：從開始解讀到準備好的耗時（規則判斷、校正、判斷都算），加上內容摘要（見 docs/specs/queue.md 的「紀錄」）。
    private static func ready(_ intent: UserIntent, since start: ContinuousClock.Instant) -> String {
        "耗時 \(IntentPreparer.elapsed(since: start))：\(summary(of: intent))"
    }

    /// `urgent` 是回答：手動 AI 時排在最前面。
    private func makePreparer(urgent: Bool) -> IntentPreparer {
        IntentPreparer(
            respond: { [unowned self] number, stage, kind, prompt, request, automatically in
                try await respond(stage, kind: kind, prompt: prompt, request: request, sentence: number, urgent: urgent, automatically: automatically)
            },
            log: { [unowned self] number, stage, text in
                log(stage, text, sentence: number)
            },
            showCorrection: { [unowned self] input, note in
                correctionInput = input
                correctionOutput = note
            },
            adoptCorrection: { [unowned self] number, corrected in
                // 正在處理的就是這一句時（還在思考、或是回答），馬上換成校正後的句子。
                if let processing = processingSentence, processing.number == number {
                    processingSentence = Sentence(number: number, text: corrected, source: processing.source)
                }
            },
            autoAI: autoAI,
            useAutoAI: useAutoAI,
            chatExtra: { [unowned self] text in
                ChatExtra.pick(for: text, rotation: &chatRotation)
            })
    }

    // MARK: - 呈現：照順序一個一個執行、顯示、報告

    private func advance() {
        guard presenter == nil else {
            return
        }
        presenterID += 1
        let id = presenterID
        presenter = Task {
            await present()
            if presenterID == id {
                presenter = nil
            }
        }
    }

    /// 等前一個結果的報告顯示時間；目前的結果在等回答時處理回答，否則輪到下一個解讀好的使用者意圖。
    private func present() async {
        while !Task.isCancelled {
            await awaitHold()
            guard !Task.isCancelled else {
                return
            }
            if waiting != nil || failure != nil {
                guard let answer = pendingAnswer else {
                    return
                }
                pendingAnswer = nil
                await handle(answer)
                continue
            }
            guard let (entry, intent) = intents.next() else {
                if intents.isHeadPending && !isThinking, let head = intents.entries.first {
                    isThinking = true
                    processingSentence = head.input.sentence
                    elfMessage = "思考中…"
                }
                return
            }
            isThinking = false
            await present(entry.input.sentence, intent, screen: entry.input.screen)
        }
    }

    /// 輪到一個使用者意圖：執行、記 undo、報告。
    private func present(_ sentence: Sentence, _ intent: UserIntent, screen: ScreenInfo) async {
        if case .commands(let list) = intent.kind, liveHint != nil, !list.isEmpty, list.allSatisfy(isHintTurn) {
            turnHint(list, sentence: sentence)
            return
        }
        presenting = sentence.number
        currentSentence = sentence.number
        processingSentence = Sentence(number: sentence.number, text: intent.text, source: sentence.source)
        log("輪到", sentence.text)
        await perform(sentence) {
            await self.execute(intent, sentence: sentence, screen: screen)
        }
    }

    /// 執行目前的結果（或回答），記 undo 狀態，再報告；`work` 回傳 false 時不記 undo（錯誤確認中的復原、重做）。
    private func perform(_ sentence: Sentence, _ work: () async -> Bool) async {
        stopHintSpeech("下一個結果")
        commands = []
        currentCommand = ""
        results = []
        reports = []
        spokenReports = []
        misheard = false
        while let reading = storageTask {
            await reading.value
            if reading == storageTask { break }
        }
        isBusy = true
        undoStart = store.todos
        let records = await work()
        isBusy = false
        guard !Task.isCancelled else {
            return
        }
        if records {
            history.record(before: undoStart, after: store.todos)
        }
        log("小精靈", elfMessage)
        applyPendingReload()
        await finishResult()
    }

    /// 回傳 false 時不記 undo 狀態。
    private func execute(_ intent: UserIntent, sentence: Sentence, screen heardScreen: ScreenInfo) async -> Bool {
        if intent.readAll {
            readAll = true
        }
        switch intent.kind {
        case .commands(let list):
            elfMessage = "思考中…"
            fixNumbers()
            await run(list)
        case .chat(let reply, let note, let screen):
            var outcome = (reply: reply, note: note)
            // 聊天依賴畫面：前面的結果改了黑板或待辦就用現在的畫面重做（見 docs/specs/chat.md）。
            let now = snapshot()
            if !now.sameBoard(as: screen) {
                log("聊天", "黑板或待辦變了，用現在的畫面重做")
                guard let redone = await makePreparer(urgent: true).chat(intent.text, number: sentence.number, screen: now) else {
                    return false
                }
                outcome = redone
            }
            showChat(outcome.reply, note: outcome.note, text: intent.text)
        case .failed(let message, let failure):
            fail(message, failure, sentence: sentence, screen: heardScreen)
        }
        return true
    }

    /// 插隊的回答（見 docs/specs/queue.md 的「等回答與插隊」），或彈窗的重試、略過。
    private func handle(_ answer: Answer) async {
        intents.endQuestion()
        switch answer {
        case .retry:
            await retryFailure()
        case .skip:
            skipFailure()
            finishSkip()
            await finishResult()
        case .sentence(let sentence, let screen):
            currentSentence = sentence.number
            processingSentence = sentence
            await perform(sentence) {
                await self.answer(sentence, screen: screen)
            }
        }
    }

    /// 回傳 false 時不記 undo 狀態。
    private func answer(_ sentence: Sentence, screen: ScreenInfo) async -> Bool {
        let text = sentence.text
        let current = waiting
        waiting = nil

        if failure != nil {
            switch RecoveryKeywords.action(text) {
            case .retry?:
                await retryFailure(inPlace: true)
                return true
            case .skip?:
                skipFailure()
                finishSkip()
                return false
            case .undo?, .redo?:
                skipFailure()
                moveHistory(undo: RecoveryKeywords.action(text) == .undo)
                return false
            case nil:
                // 說了別的：等於略過，這句話照常判斷，馬上呈現（見 docs/specs/recovery.md）。
                skipFailure()
                return await interpretNew(sentence, screen: screen)
            }
        }

        switch current {
        case .readMore(let unread)?:
            if let yes = ReportKeywords.moreAnswer(text) {
                answerMore(yes, unread: unread)
                return true
            }
            // 說了別的：readAll 重設，這句話照常判斷，馬上呈現。
            readAll = false
            log("中斷", "沒有回答要不要全部念完")
            return await interpretNew(sentence, screen: screen)

        case .confirmDelete(let clarification, let ids)?:
            // yes／no 關鍵字之後、AI 之前先用規則判斷：命中就是新需求，原本的刪除取消（在 interpret 裡）。
            if ConfirmationKeywords.answer(text) == nil, JudgeTool.command(text, today: .now) != nil {
                await clarify(text, number: sentence.number, screen: screen, clarification: clarification)
                return true
            }
            guard let answer = await answerDelete(text, question: clarification.question) else {
                return true
            }
            guard answer != .other else {
                // 指定其中某些項目或說了新需求：和釐清一樣，由這句話判斷出的新指令取代刪除。
                await clarify(text, number: sentence.number, screen: screen, clarification: clarification)
                return true
            }
            finishDelete(confirmed: answer == .yes, ids: ids)
            guard !Task.isCancelled else {
                return true
            }
            await run(remaining)

        case .clarify(let clarification)?:
            await clarify(text, number: sentence.number, screen: screen, clarification: clarification)

        case nil:
            return true
        }
        return true
    }

    /// 回答裡說了新的話：照一般的一句話判斷，屬於目前的生命週期。
    private func interpretNew(_ sentence: Sentence, screen: ScreenInfo) async -> Bool {
        elfMessage = "思考中…"
        guard let intent = await makePreparer(urgent: true).prepare(sentence.text, number: sentence.number, screen: screen) else {
            return true
        }
        return await execute(intent, sentence: sentence, screen: screen)
    }

    /// 原本的任務由回答後的新指令取代；同一句話裡還沒執行的指令排在後面。
    private func clarify(_ text: String, number: Int, screen: ScreenInfo, clarification: Clarification) async {
        endTask(restore: true)
        elfMessage = "思考中…"
        let rest = remaining
        remaining = []
        let result = await makePreparer(urgent: true).interpret(text, number: number, screen: screen, clarification: clarification, rest: rest)
        await apply(result, sentence: Sentence(number: number, text: text, source: ""), screen: screen)
    }

    private func apply(_ result: Interpretation?, sentence: Sentence, screen: ScreenInfo) async {
        switch result {
        case .commands(let list, _)?:
            fixNumbers()
            await run(list)
        case .failed(let message, let failure)?:
            fail(message, failure, sentence: sentence, screen: screen)
        case .none?, nil:
            break
        }
    }

    /// 報告目前的結果（見 docs/specs/spoken-report.md）：念成功的結果，接著念問題；沒有念的結果用公式的報告顯示時間。
    private func finishResult() async {
        // 提示頁顯示出來，這個結果就結束；念提示不佔報告顯示時間（見 docs/specs/queue.md）。
        if let page = liveHint, spokenReports.isEmpty, currentQuestion == nil {
            speakHint(page)
            return
        }
        let collected = spokenReports
        spokenReports = []
        let canSpeak = isReportOn && speaker != nil
        var body = ""
        var question = currentQuestion
        if canSpeak, let speech = SpokenReport.compose(collected, readAll: readAll, canAsk: waiting == nil && failure == nil) {
            body = speech.text
            if !speech.unread.isEmpty {
                body = String(speech.text.dropLast(SpokenReport.askMore.count))
                question = SpokenReport.askMore
                waiting = .readMore(unread: speech.unread)
                elfMessage += "\n\n" + SpokenReport.askMore
            }
        }
        var interrupted = false
        if canSpeak && !body.isEmpty {
            interrupted = !(await speak(body))
        }
        guard !Task.isCancelled else {
            return
        }
        if let question {
            // 問題開始念（或顯示）的時候就是問題出現；之後開口的第一句話是回答。
            intents.ask(at: tick())
            if canSpeak && !interrupted {
                await speak(SpokenReport.question(question))
            }
            return
        }
        if !canSpeak || body.isEmpty {
            hold(elfMessage)
        }
    }

    /// 釐清、刪除確認、錯誤確認的問題；語音報告打開時念出來。
    private var currentQuestion: String? {
        if failure != nil {
            return elfMessage
        }
        switch waiting {
        case .clarify(let clarification)?, .confirmDelete(let clarification, _)?:
            return clarification.question
        case .readMore?, nil:
            return nil
        }
    }

    /// 沒有念的結果：報告顯示時間用公式（見 docs/specs/queue.md 的「報告顯示時間」）。
    private func hold(_ text: String) {
        let duration = DisplayTime.of(text)
        log("顯示時間", duration.formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1))))
        holdID += 1
        let wait = wait
        holdTask = Task { await wait?(duration) }
    }

    private func awaitHold() async {
        while let task = holdTask {
            let id = holdID
            await task.value
            if id == holdID {
                holdTask = nil
            }
        }
    }

    /// 全部取消（見 docs/specs/queue.md）：清空三個佇列，結束目前的結果；已經執行的結果不還原。
    private func cancelAll(_ number: Int) {
        let dropped = intents.entries.map { "#\($0.number)" }
        clearQueues()
        interrupt("全部取消")
        switch waiting {
        case .clarify?, .confirmDelete?:
            endTask(restore: true)
        case .readMore?, nil:
            break
        }
        waiting = nil
        remaining = []
        if failure != nil {
            failure = nil
            failedSentence = nil
        }
        applyPendingReload()
        elfMessage = "已全部取消"
        log("全部取消", dropped.isEmpty ? "沒有排隊的話" : "清掉 \(dropped.joined(separator: "、"))", sentence: number)
    }

    /// 取消背景的解讀與呈現、丟掉等手動 AI 的使用者提示詞。
    private func clearQueues() {
        preparing.values.forEach { $0.cancel() }
        preparing = [:]
        _ = intents.removeAll()
        intents.endQuestion()
        presenter?.cancel()
        presenter = nil
        presenterID += 1
        holdTask?.cancel()
        holdTask = nil
        holdID += 1
        pendingAnswer = nil
        presenting = nil
        isBusy = false
        isThinking = false
        let waits = manualWaits
        manualWaits = []
        waits.forEach { $0.reply.resume(returning: nil) }
    }

    // MARK: - 任務

    /// 一句話開始執行：編號對到這時黑板上的待辦（見 docs/specs/todos.md 的「編號」）。
    private func fixNumbers() {
        board.fixNumbers(store.todos, today: TodoStore.dayString(.now))
    }

    /// 依序執行指令；遇到釐清或刪除確認就停下，等回答。
    private func run(_ list: [Command]) async {
        remaining = []
        commands = list.map(\.summary)
        for (index, command) in list.enumerated() {
            currentCommand = command.summary
            elfMessage = (reports + ["接下來要做：\n" + Self.numbered(commands), "正在執行：\(command.summary)"])
                .joined(separator: "\n\n")

            // 查天氣不用存檔，沒有權限時照常（見 docs/specs/weather.md）。
            if command.action == .weather {
                await lookUpWeather(command, stage: "指令 \(index + 1)/\(list.count)")
                guard !Task.isCancelled else {
                    return
                }
                continue
            }

            // 沒有存檔時待辦的所有指令都放棄（見 docs/specs/storage.md 的「權限」）。
            if let reason = store.unavailableReason {
                report("指令 \(index + 1)/\(list.count)", command, "放棄", "沒有執行「\(command.summary)」：\(reason)")
                continue
            }

            if let done = runOnElf(command) {
                if done {
                    succeeded(command)
                }
                report("指令 \(index + 1)/\(list.count)", command, done ? "完成" : "放棄", elfMessage)
                continue
            }

            let stage = "指令 \(index + 1)/\(list.count)"
            // 勾選「完成」前先讀已完成的，在任務的快照之前（見 docs/specs/storage.md 的「延遲讀取」）。
            if needsRest(command), let reason = await loadRest() {
                report(stage, command, "放棄", "沒有執行「\(command.summary)」：\(reason)")
                continue
            }
            guard !Task.isCancelled else {
                return
            }
            let dates = dateResults(command)
            store.beginTask()
            let outcome = CommandExecutor(store: store, board: board, today: .now).execute(command)

            switch outcome {
            case .done(let message, let spoken):
                if let spoken {
                    spokenReports.append(spoken)
                }
                endTask(restore: false)
                succeeded(command)
                report(stage, command, "完成", message, dates: shownDates(command, spoken, parsed: dates))
            case .abandon(let reason):
                report(stage, command, "放棄", "沒有執行「\(command.summary)」：\(reason)")
                endTask(restore: true)
            case .notFound:
                report(stage, command, "放棄", "找不到")
                endTask(restore: true)
            case .clarify(let question):
                waiting = .clarify(Clarification(question: question, command: command))
                report(stage, command, "釐清", question)
            case .confirmDelete(let question, let ids):
                waiting = .confirmDelete(Clarification(question: question, command: command), ids: ids)
                report(stage, command, "確認", question)
            }

            if waiting != nil {
                remaining = Array(list[(index + 1)...])
                break
            }
        }
        currentCommand = ""
        elfMessage = reports.joined(separator: "\n\n")
    }

    /// 查天氣（見 docs/specs/weather.md）：不改待辦、不記 undo；查不到的原因也念出來。
    private func lookUpWeather(_ command: Command, stage: String) async {
        _ = dateResults(command)
        guard let weather else {
            report(stage, command, "放棄", "沒有執行「\(command.summary)」：沒有天氣服務")
            return
        }
        elfMessage = (reports + ["查天氣中…"]).joined(separator: "\n\n")
        switch await weather.run(command, now: .now, log: { self.log("天氣服務", $0) }) {
        case .done(let message, let days, let log):
            self.log("天氣", log)
            spokenReports.append(.weather(days))
            succeeded(command)
            report(stage, command, "完成", message)
            weatherMessage = message
        case .failed(let message, let log):
            self.log("天氣", log)
            spokenReports.append(.chat(message))
            report(stage, command, "失敗", message)
        case .abandon(let reason):
            report(stage, command, "放棄", "沒有執行「\(command.summary)」：\(reason)")
        }
    }

    /// `dates` 是日期的換算結果，列在回報上面。
    private func report(_ stage: String, _ command: Command, _ outcome: String, _ message: String, dates: [String] = []) {
        let result = "\(command.summary) → \(outcome)：\(message)"
        results.append(result)
        reports.append((dates + [message]).joined(separator: "\n"))
        log(stage, result)
    }

    /// 回話的換算結果是實際用的值（見 docs/specs/todos.md 的「指令」）：新增、修改是待辦最後的日期與時間，
    /// 查詢是黑板的範圍與時間條件；其他用解析的換算結果（時間是範圍）。
    private func shownDates(_ command: Command, _ report: Report?, parsed: [String]) -> [String] {
        let when = { (todo: Todo) in [todo.date.map { ParsedDate.slashed($0) }, todo.time].compactMap { $0 }.joined(separator: " ") }
        switch report {
        case .added(let todo)?:
            return [when(todo)]
        case .modified(_, let after)? where command.newDate != nil:
            // 用編號一次改好幾筆時，相同的日期與時間只列一次。
            return after.map(when).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
        case .queried? where command.date != nil:
            guard case .days(let from, let to, _) = board.page.range else {
                return parsed
            }
            let days = from == to ? ParsedDate.slashed(from) : "\(ParsedDate.slashed(from)) ~ \(ParsedDate.slashed(to))"
            return [[days, board.page.time?.label].compactMap { $0 }.joined(separator: " ")]
        default:
            return parsed
        }
    }

    /// 指令的日期：完整的分析記在測試紀錄，解析的換算結果另外給回話（見 docs/specs/date-time.md 的「解析結果」）。
    /// 查詢日期的回報本身就是換算結果，「下次」要找到待辦才知道是哪天，都不列。
    private func dateResults(_ command: Command) -> [String] {
        [command.date, command.newDate].compactMap { $0 }.compactMap { text in
            switch DatePhrase.parse(text, today: .now) {
            case .success(let date):
                log("日期", date.analysis)
                return command.action == .queryDate || date.days == .next ? nil : date.result
            case .failure(let error):
                log("日期", error.analysis)
                return nil
            }
        }
    }

    /// 指令執行成功：便條不再是「剛聽不懂」，用過的操作記下來（見 docs/specs/help.md 的「便條」）。
    private func succeeded(_ command: Command) {
        unclear = nil
        if let step = Guide.Step(command.action) {
            guideUsed.insert(step)
        }
    }

    private func endTask(restore: Bool) {
        store.endTask(restore: restore)
        if restore {
            log("還原", "資料還原到任務開始前")
        }
    }

    /// 聊天的回應，或退回「聽不懂」（見 docs/specs/chat.md）。
    private func showChat(_ reply: String?, note: String, text: String) {
        unclear = text
        guard let reply else {
            results = [note]
            misheard = true
            elfMessage = "聽不懂「\(text)」"
            return
        }
        results = [reply]
        elfMessage = reply
        spokenReports.append(.chat(reply))
    }

    // MARK: - 刪除確認

    /// 先用關鍵字判斷，判斷不出來交給 AI。取消時回傳 nil。
    private func answerDelete(_ text: String, question: String) async -> ConfirmAnswer? {
        if let keyword = ConfirmationKeywords.answer(text) {
            log("確認", "關鍵字判斷「\(text)」→ \(keyword ? "yes" : "no")")
            return keyword ? .yes : .no
        }
        return await askAI(text, question: question)
    }

    private func finishDelete(confirmed: Bool, ids: [Int]) {
        let command = Command(.deleteTodos)
        if confirmed {
            store.delete(ids: ids)
            spokenReports.append(.deleted(count: ids.count))
            endTask(restore: false)
            succeeded(Command(.deleteTodos))
            report("確認", command, "完成", "已刪除 \(ids.count) 項")
        } else {
            report("確認", command, "取消", "已取消刪除")
            endTask(restore: true)
        }
        elfMessage = reports.joined(separator: "\n\n")
    }

    /// AI 判斷 yes／no／other；失敗或回應不合法就當成 no。取消時回傳 nil。
    private func askAI(_ text: String, question: String) async -> ConfirmAnswer? {
        let request = "問題：\(question)\n回答：\(text)"
        let ai = autoAI
        let json: String?
        do {
            json = try await respond("確認", kind: "刪除確認", prompt: Self.confirmPromptName, request: request, sentence: currentSentence, urgent: true) {
                guard let ai else {
                    throw AutoAIError(Self.noAI)
                }
                return try await ai.confirmDelete(request)
            }
        } catch {
            log("確認", "AI 失敗，當成 no：\(error.localizedDescription)")
            return .no
        }
        guard let json else {
            return nil
        }
        do {
            let answer = try CommandJSON.decodeAnswer(json)
            log("確認", "AI 判斷「\(text)」→ \(answer.rawValue)")
            return answer
        } catch {
            log("確認", "回應不合法，當成 no：\(error.localizedDescription)")
            return .no
        }
    }

    /// 黑板的標題：範圍與查詢條件。
    private var boardTitle: String {
        [board.page.title, board.page.condition ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// 黑板看得到的待辦，每筆一行，帶編號。
    private var boardLines: [String] {
        board.visible(store.todos, today: TodoStore.dayString(.now)).enumerated().map { "\($0.offset + 1). \($0.element.line)" }
    }

    /// 畫面資訊的快照：黑板看得到的待辦、最後一則回話（開場問候不算）、等回答的問題、還沒凍結的提示那一頁。
    /// 便條不在裡面：它是給使用者的引導。
    private func snapshot() -> ScreenInfo {
        let question: String? = switch waiting {
        case .clarify(let clarification)?, .confirmDelete(let clarification, _)?: clarification.question
        case .readMore?, nil: nil
        }
        return ScreenInfo(
            now: ScreenInfo.now(.now),
            boardTitle: boardTitle,
            board: boardLines,
            dialog: elfMessage.components(separatedBy: "\n"),
            question: question,
            hint: liveHint.map { ScreenInfo.Hint(page: $0.name, links: $0.links) })
    }

    // MARK: - 補救

    /// 進入錯誤確認（見 docs/specs/recovery.md）：輪到失敗的結果，或回答的判斷失敗時。
    private func fail(_ message: String, _ failed: Failure, sentence: Sentence, screen: ScreenInfo) {
        failure = failed
        failedSentence = sentence
        failedScreen = screen
        failureMessage = message
        remaining = []
        results = [message]
        elfMessage = "\(message)。說『重試』再試一次，或說『略過』。"
        log("判斷", message)
    }

    /// 只重做失敗的那一次判斷，不再校正；`inPlace` 時已經在 perform 裡（語音的重試）。
    private func retryFailure(inPlace: Bool = false) async {
        guard let failed = failure, let sentence = failedSentence, let screen = failedScreen else {
            return
        }
        failure = nil
        waiting = nil
        currentSentence = sentence.number
        log("判斷", "重試")
        let work = {
            self.elfMessage = "思考中…"
            let result = await self.makePreparer(urgent: true).judge(failed.text, number: sentence.number, clarification: failed.clarification, rest: failed.rest, hint: failed.hint)
            switch result {
            case .none(let text)?:
                guard let outcome = await self.makePreparer(urgent: true).chat(text, number: sentence.number, screen: screen) else {
                    return
                }
                self.showChat(outcome.reply, note: outcome.note, text: text)
            default:
                await self.apply(result, sentence: sentence, screen: screen)
            }
        }
        if inPlace {
            await work()
        } else {
            await perform(sentence) {
                await work()
                return true
            }
        }
    }

    /// 彈窗的重試。
    func retry() {
        guard failure != nil else {
            return
        }
        pendingAnswer = .retry
        advance()
    }

    /// 彈窗的略過：丟掉失敗的那句話，換到下一個結果。
    func skip() {
        guard failure != nil else {
            return
        }
        pendingAnswer = .skip
        advance()
    }

    /// 按復原：正在念就中斷，馬上復原；回報也有報告顯示時間，之後換到下一個結果（見 docs/specs/queue.md 的「觸控」）。
    func undo() {
        guard canUndo else {
            return
        }
        interrupt("復原")
        archiveReply()
        moveHistory(undo: true)
        hold(elfMessage)
        advance()
    }

    func redo() {
        guard canRedo else {
            return
        }
        interrupt("重做")
        archiveReply()
        moveHistory(undo: false)
        hold(elfMessage)
        advance()
    }

    private func finishSkip() {
        guard let sentence = failedSentence else {
            return
        }
        failedSentence = nil
        elfMessage = "已略過「\(sentence.text)」"
    }

    /// 錯誤確認中：丟掉失敗的那句話。
    private func skipFailure() {
        guard failure != nil else {
            return
        }
        failure = nil
        log("判斷", "略過", sentence: failedSentence?.number)
    }

    /// 由小精靈執行的執行器（見 Command.Action）：回傳是否成功；其他執行器回傳 nil，交給 CommandExecutor。
    private func runOnElf(_ command: Command) -> Bool? {
        switch command.action {
        case .undo, .redo:
            // 同一句話裡前面的改變先記成一個 undo 狀態，再復原或重做。
            history.record(before: undoStart, after: store.todos)
            moveHistory(undo: command.action == .undo)
            undoStart = store.todos
        case .previousPage where !board.canGoBack, .nextPage where !board.canGoForward, .help, .previousHint, .nextHint:
            return showHint(command)
        case .previousPage: navigate(.back)
        case .nextPage: navigate(.forward)
        case .showEverything: navigate(.showEverything)
        // case .createBackup: return backUp(.create)  // 備份暫停（見 docs/specs/backup.md）
        // case .replaceBackup: return backUp(.replace)
        case .readAll:
            readAll = true
            elfMessage = "好，之後會全部念完。"
            spokenReports.append(.chat(elfMessage))
        default:
            return nil
        }
        return true
    }

    // MARK: - 黑板的話與觸控（見 docs/specs/todos.md 的「黑板」）

    /// 顯示全部、上一頁、下一頁。
    private func navigate(_ action: BoardAction) {
        switch action {
        case .showEverything:
            board.move(to: .everything)
            elfMessage = "已顯示所有資料"
        case .back:
            elfMessage = board.canGoBack ? "已回到上一頁" : "沒有上一頁"
            board.goBack()
        case .forward:
            elfMessage = board.canGoForward ? "已到下一頁" : "沒有下一頁"
            board.goForward()
        }
        log("黑板", elfMessage)
    }

    // MARK: - 提示（見 docs/specs/help.md）

    private func isHintCommand(_ command: Command?) -> Bool {
        [.help, .previousHint, .nextHint].contains(command?.action)
    }

    /// 翻提示頁的指令；上一頁、下一頁在黑板沒有可以去的頁時也是。
    private func isHintTurn(_ command: Command) -> Bool {
        switch command.action {
        case .help, .previousHint, .nextHint: true
        case .previousPage: !board.canGoBack
        case .nextPage: !board.canGoForward
        default: false
        }
    }

    /// 要顯示的那一頁；上一頁、下一頁從還沒凍結的提示算起，沒有就從最後一個凍結的提示算起，都沒有是總導覽。頁名不在清單裡是 nil。
    private func hintTarget(_ command: Command) -> HintPage? {
        let overview = HintPage.named(HintPage.overview)!
        switch command.action {
        case .help:
            return HintPage.named(command.page ?? HintPage.overview)
        default:
            let offset = [.previousHint, .previousPage].contains(command.action) ? -1 : 1
            let frozen = conversation.last { $0.hint != nil }?.hint.flatMap(HintPage.named)
            return (liveHint ?? frozen)?.step(offset) ?? overview
        }
    }

    /// 一句話裡的說明、上個提示、下個提示（在任務裡）：還沒凍結就原地換頁，否則回話是新的提示對話框。回傳是否成功。
    private func showHint(_ command: Command) -> Bool {
        guard let page = hintTarget(command) else {
            elfMessage = "沒有「\(command.page ?? "")」這一頁提示"
            return false
        }
        hintPage = page
        elfMessage = page.text
        log("提示", "提示：\(page.name)（新的）")
        return true
    }

    /// 還沒凍結時，這句話全部是翻提示頁：原地換頁，這句話不出現在對話流，不另外回話；換頁就是回饋。
    private func turnHint(_ list: [Command], sentence: Sentence) {
        currentSentence = sentence.number
        log("輪到", sentence.text)
        for (index, command) in list.enumerated() {
            guard let page = hintTarget(command) else {
                log("指令 \(index + 1)/\(list.count)", "\(command.summary) → 放棄：沒有這一頁")
                continue
            }
            hintPage = page
            elfMessage = page.text
            unclear = nil
            log("指令 \(index + 1)/\(list.count)", "\(command.summary) → 完成：提示：\(page.name)（原地）")
        }
        if let page = liveHint {
            speakHint(page)
        }
    }

    /// 觸控：提示對話框的連結、工具列的提示按鈕、點便條。還沒凍結就原地換頁，否則在最後開新的提示對話框。
    func openHint(_ name: String) {
        touchHint(Command(.help, page: name))
    }

    /// 觸控：提示對話框的左、右箭頭。
    func stepHint(_ offset: Int) {
        touchHint(Command(offset < 0 ? .previousHint : .nextHint))
    }

    /// 開新的提示對話框要等目前的結果執行完：執行中的回話還會更新，會蓋掉它。
    var canOpenHint: Bool {
        liveHint != nil || !isBusy && !isThinking
    }

    private func touchHint(_ command: Command) {
        guard canOpenHint, let page = hintTarget(command) else {
            return
        }
        let inPlace = liveHint != nil
        if !inPlace {
            archiveReply()
        }
        hintPage = page
        elfMessage = page.text
        log("觸控", "提示：\(page.name)（\(inPlace ? "原地" : "新的")）", sentence: nil)
        speakHint(page)
    }

    /// 念提示頁，不等念完：後面的結果照常輪到（見 docs/specs/queue.md 的「報告顯示時間」）。正在念的提示先停。
    private func speakHint(_ page: HintPage) {
        stopHintSpeech("換頁")
        guard isReportOn, speaker != nil else {
            return
        }
        isSpeakingHint = true
        let id = hintSpeechID
        Task {
            guard id == hintSpeechID else {
                return
            }
            await speak(page.text)
            if id == hintSpeechID {
                isSpeakingHint = false
            }
        }
    }

    /// 換頁或下一個結果輪到時停止念提示；不重設 readAll。
    private func stopHintSpeech(_ reason: String) {
        guard isSpeakingHint else {
            return
        }
        hintSpeechID += 1
        isSpeakingHint = false
        interrupt(reason, resetsReadAll: false)
    }

    // 備份暫停（見 docs/specs/backup.md）。
    // // MARK: - 備份（見 docs/specs/backup.md）
    //
    // /// 建立備份、換成備份；回傳是否成功。換成備份不合法時待辦不變、不念。
    // private func backUp(_ action: BackupAction) -> Bool {
    //     var done = true
    //     switch action {
    //     case .create:
    //         clipboard?.copy(Backup.make(store.todos))
    //         elfMessage = "已建立備份，共 \(store.todos.count) 筆待辦，已放到剪貼簿"
    //         spokenReports.append(.chat(elfMessage))
    //     case .replace:
    //         do {
    //             let todos = try Backup.read(clipboard?.paste() ?? "")
    //             store.replace(withBackup: todos)
    //             board.move(to: .everything)
    //             elfMessage = "已換成備份，共 \(todos.count) 筆待辦"
    //             spokenReports.append(.chat(elfMessage))
    //         } catch {
    //             elfMessage = error.localizedDescription
    //             done = false
    //         }
    //     }
    //     log("備份", elfMessage)
    //     return done
    // }

    /// 點方框：切換完成，等於一條設定完成指令；不移動黑板，不中斷語音報告。
    func toggleDone(_ id: Int) {
        guard canTouch, let todo = store.todos.first(where: { $0.id == id }) else {
            return
        }
        let before = store.todos
        store.beginTask()
        try? store.setDone(id: id, isDone: !todo.isDone)
        store.endTask(restore: false)
        history.record(before: before, after: store.todos)
        succeeded(Command(.setDone))
        archiveReply()
        elfMessage = CommandExecutor.doneReport(todo, isDone: !todo.isDone)
        log("觸控", elfMessage, sentence: nil)
    }

    /// 點 checkbox 或「顯示已完成」開關：等於一條設定顯示指令；不中斷語音報告。勾選「完成」前先讀已完成的。
    func setDisplay(showDone: Bool) {
        guard canTouch else {
            return
        }
        let command = Command(.setDisplay, showDone: showDone)
        guard needsRest(command) else {
            showDisplay(command)
            return
        }
        readStorage {
            if let reason = await self.loadRest() {
                self.archiveReply()
                self.elfMessage = reason
                return
            }
            self.showDisplay(command)
        }
    }

    private func showDisplay(_ command: Command) {
        guard case .done(let message, _) = CommandExecutor(store: store, board: board, today: .now).execute(command) else {
            return
        }
        archiveReply()
        elfMessage = message
        log("觸控", message, sentence: nil)
    }

    /// 資料換成上一個（undo）或 undo 之前（redo）的狀態，回報差異並存檔。
    private func moveHistory(undo: Bool) {
        let current = store.todos
        guard let target = undo ? history.undo(current: current) : history.redo(current: current) else {
            elfMessage = undo ? "沒有可以復原的狀態" : "沒有可以重做的狀態"
            return
        }
        store.replace(with: target)
        let changes = TodoHistory.changes(from: current, to: target)
        elfMessage = ([undo ? "已復原：" : "已重做："] + changes).joined(separator: "\n")
        // 黑板沒有涵蓋這些變化時，才移到看得到它們的範圍。
        let days = TodoHistory.changedDays(from: current, to: target)
        if let first = days.min(), let last = days.max() {
            board.reveal(from: first, to: last)
        }
        board.reveal(target.filter { !current.contains($0) })
        log(undo ? "復原" : "重做", elfMessage, sentence: nil)
    }

    // MARK: - AI 的來源

    /// 把使用者提示詞交給自動 AI 或手動 AI，回傳 JSON 字串（見 docs/specs/judgment.md 的「判斷的來源」）。
    /// 手動 AI 照順序等開發者貼回，`urgent`（回答）排在最前面。自動 AI 失敗時丟出錯誤；取消時回傳 nil。
    private func respond(
        _ stage: String,
        kind: String,
        prompt: String,
        request: String,
        sentence: Int?,
        urgent: Bool,
        automatically: () async throws -> String
    ) async throws -> String? {
        let isAuto = useAutoAI
        log(stage, isAuto ? "自動 AI｜\(kind)｜\(prompt)" : "手動 AI｜\(kind)", sentence: sentence)
        log(stage, "請求：\(request)", sentence: sentence)

        let json: String?
        if isAuto {
            let start = ContinuousClock.now
            do {
                json = try await automatically()
            } catch where Task.isCancelled {
                return nil
            }
            if !Task.isCancelled {
                log(stage, "回應（\(IntentPreparer.elapsed(since: start))）：\(json ?? "")", sentence: sentence)
            }
        } else {
            if urgent {
                elfMessage = "等待手動 AI 回應…"
            }
            let request = AIRequest(kind: kind, text: request)
            json = await withCheckedContinuation { reply in
                if urgent {
                    manualWaits.insert((request, reply), at: 0)
                } else {
                    manualWaits.append((request, reply))
                }
            }
            if let json {
                log(stage, "回應：\(json)", sentence: sentence)
            }
        }
        return Task.isCancelled ? nil : json
    }

    // MARK: - 語音報告（見 docs/specs/spoken-report.md）

    /// 語音報告開關（按鈕或語音）。關閉時正在念就中斷，目前的結果改用公式的報告顯示時間；也不再等「要全部念完嗎」。
    func setReport(_ on: Bool) {
        guard on != isReportOn else {
            return
        }
        if !on {
            if interrupt("關閉開關") {
                hold(elfMessage)
            }
            endReadMore()
        }
        isReportOn = on
        log("開關", "語音報告：\(on ? "開" : "關")", sentence: nil)
    }

    /// 說「停止」：目前的報告結束，換到下一個；在等「要全部念完嗎」時和「不要」相同；在念問題時問題仍然在等回答。
    private func stopReport() {
        interrupt("停止")
        endReadMore()
    }

    private func answerMore(_ yes: Bool, unread: [Todo]) {
        guard yes else {
            elfMessage = "好，不念了"
            return
        }
        readAll = true
        elfMessage = (["剩下的 \(unread.count) 項："] + unread.map(\.line)).joined(separator: "\n")
        spokenReports.append(.chat(SpokenReport.items(unread)))
    }

    private func endReadMore() {
        guard case .readMore = waiting else {
            return
        }
        waiting = nil
        intents.endQuestion()
        advance()
    }

    /// 念完回傳 true；被中斷回傳 false。
    @discardableResult
    private func speak(_ text: String) async -> Bool {
        guard isReportOn, let speaker else {
            return true
        }
        log("報告", text)
        speechID += 1
        let id = speechID
        isSpeaking = true
        spoken = (text, tick(), nil)
        await speaker.speak(text)
        guard speechID == id else {
            return false
        }
        isSpeaking = false
        spoken?.to = tick()
        return true
    }

    /// 正在念時停止，readAll 回到預設（`resetsReadAll` 為 false 時不變）；有中斷就回傳 true。
    @discardableResult
    private func interrupt(_ reason: String, resetsReadAll: Bool = true) -> Bool {
        guard isSpeaking else {
            return false
        }
        speechID += 1
        isSpeaking = false
        isSpeakingHint = false
        spoken?.to = tick()
        if resetsReadAll {
            readAll = false
        }
        speaker?.stop()
        log("中斷", reason)
        return true
    }

    // MARK: - Helpers

    /// 開關紀錄與測試紀錄開頭用：目前用的 AI。
    private var aiLabel: String {
        useAutoAI ? "AI：自動（\(autoAI?.name ?? "無")）" : "AI：手動"
    }

    private static func describe(_ waiting: Waiting) -> String {
        switch waiting {
        case .clarify(let clarification): "釐清「\(clarification.command.summary)」：\(clarification.question)"
        case .confirmDelete(let clarification, _): "刪除確認：\(clarification.question)"
        case .readMore(let unread): "要全部念完嗎（還有 \(unread.count) 項）"
        }
    }

    /// 測試紀錄的「準備好」：使用者意圖的摘要。
    private static func summary(of intent: UserIntent) -> String {
        switch intent.kind {
        case .commands(let list): list.isEmpty ? "沒有指令" : list.map(\.summary).joined(separator: "、")
        case .chat(let reply, let note, _): reply.map { "聊天：\($0)" } ?? "聽不懂：\(note)"
        case .failed(let message, _): message
        }
    }

    private static func numbered(_ items: [String]) -> String {
        items.enumerated()
            .map { "\($0.offset + 1). \($0.element)" }
            .joined(separator: "\n")
    }

    /// 記一筆測試紀錄並印到 console（見 docs/specs/judgment.md 的「紀錄」）。
    private func log(_ stage: String, _ text: String) {
        log(stage, text, sentence: currentSentence)
    }

    /// 每記一筆就檢查黑板：看得到的內容變了，接著印出整個黑板，記在同一句話底下。
    private func log(_ stage: String, _ text: String, sentence: Int?) {
        append(stage, text, sentence: sentence)
        let shown = [boardTitle].filter { !$0.isEmpty } + boardLines
        if shown != loggedBoard {
            loggedBoard = shown
            append("黑板", shown.isEmpty ? "無資料" : shown.joined(separator: "\n"), sentence: sentence)
        }
    }

    private func append(_ stage: String, _ text: String, sentence: Int?) {
        let entry = LogEntry(id: testLog.count, sentence: sentence, stage: stage, text: text)
        testLog.append(entry)
        print(entry.line)
    }
}
