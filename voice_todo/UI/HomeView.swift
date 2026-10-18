//
//  HomeView.swift
//  voicecalender
//

import SwiftUI

/// 使用者畫面（見 docs/specs/ui.md）：iOS 與 macOS 共用。直的上面是對話流、下面是木框黑板；橫的黑板在左、對話流在右。
struct HomeView: View {

    let elf: Elf
    let openSettings: () -> Void

    @State private var chatPosition = ScrollPosition()
    @State private var showsNewMessage = false
    /// 點內容複製後在黑板上短暫顯示的回饋；`id` 讓連點同一筆也重新計時。
    @State private var copiedNotice: (id: Int, text: String)?

    private static let spacing: CGFloat = 12
    private static let avatarSize: CGFloat = 56

    var body: some View {
        NavigationStack {
            HomeLayout(spacing: Self.spacing) {
                chat
                board
                buttonBar
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .background(Palette.background)
            // 不顯示標題，右上角是提示按鈕、「顯示已完成」開關、語音報告開關與齒輪。
            .navigationTitle("")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#else
            .toolbar(removing: .title)
#endif
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button { elf.openHint(HintPage.overview) } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .disabled(!elf.canOpenHint)
                    .help("提示")
                    // 便條目前隱藏（見 docs/specs/help.md 的「便條」）；日後有其他訊息要置頂時可以沿用。
                    // Button { elf.showsGuide.toggle() } label: {
                    //     Image(systemName: elf.showsGuide ? "pin.fill" : "pin.slash")
                    // }
                    // .help(elf.showsGuide ? "隱藏便條" : "顯示便條")
                    Button { elf.setDisplay(showDone: !elf.showDone) } label: {
                        Image(systemName: elf.showDone ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    .disabled(!elf.canTouch)
                    .help(elf.showDone ? "隱藏已完成" : "顯示已完成")
                    Button { elf.setReport(!elf.isReportOn) } label: {
                        Image(systemName: elf.isReportOn ? "speaker.wave.2.fill" : "speaker.slash")
                    }
                    .help(elf.isReportOn ? "關閉語音報告" : "打開語音報告")
                    Button {
                        openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .help("設定")
                }
            }
            .alert("判斷失敗", isPresented: Binding(get: { elf.canRetry }, set: { _ in })) {
                Button("重試") { elf.retry() }
                Button("略過", role: .cancel) { elf.skip() }
            } message: {
                Text(elf.failureMessage)
            }
        }
    }

    // MARK: - 對話流

    /// 照時間固定的話與回話（最後一則回話還在更新）、排隊的話與正在說的話（還沒送出的顏色）。
    /// 有新內容時在最下面就跟著捲，在往上看就浮出新訊息橫條（見 `ChatScroll`）。引導是置頂的便條，不在對話裡。
    private var chat: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(elf.conversation) { message in
                    if message.isUser {
                        userBubble(Text(message.text))
                    } else if let page = message.hint.flatMap(HintPage.named) {
                        hintReply(page, live: false)
                    } else {
                        elfReply(message.text, weatherCredit: message.showsWeatherCredit, mood: message.mood)
                    }
                }
                if let page = elf.liveHint {
                    hintReply(page, live: true)
                } else if let reply = elf.liveReply {
                    elfReply(reply, weatherCredit: elf.showsWeatherCredit, mood: elf.mood)
                        .animation(.easeInOut(duration: 0.2), value: elf.mood)
                        .animation(.easeInOut(duration: 0.2), value: reply)
                }
                ForEach(elf.pending, id: \.number) { sentence in
                    userBubble(Text(sentence.text), sent: false)
                }
                if !elf.sentence.finalText.isEmpty || !elf.sentence.volatileText.isEmpty {
                    userBubble(Text("\(Text(elf.sentence.finalText))\(Text(elf.sentence.volatileText).foregroundStyle(.tertiary))"), sent: false)
                }
            }
            .padding(12)
        }
        // 便條目前隱藏（見 docs/specs/help.md 的「便條」）。
        // 便條佔住頂端的空間：對話從它下面開始，捲動時才從半透明的便條後面經過；關掉時對話從頂端開始。
        // .safeAreaInset(edge: .top, spacing: 0) {
        //     if elf.showsGuide {
        //         guideNote
        //     }
        // }
        .scrollPosition($chatPosition)
        // 用排版後的高度判斷，不監看資料：資料改變時新內容還沒排版，也會漏掉天氣標示這類改變高度的東西。
        // defaultScrollAnchor(.bottom, for: .sizeChanges) 在實機上新內容不會捲到底，不用它。
        // 不加動畫：回話一段段更新時，動畫還沒結束下一段就到了，會被當成在往上看。
        .onScrollGeometryChange(for: ChatScroll.Geometry.self) {
            ChatScroll.Geometry(contentHeight: $0.contentSize.height, visibleBottom: $0.visibleRect.maxY)
        } action: { old, new in
            switch ChatScroll.change(from: old, to: new) {
            case .follow: chatPosition.scrollTo(edge: .bottom)
            case .showNewMessage: showsNewMessage = true
            case .hideNewMessage: showsNewMessage = false
            case .none: break
            }
        }
        .overlay(alignment: .bottom) {
            if showsNewMessage {
                newMessageBar
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showsNewMessage)
        // .animation(.easeInOut(duration: 0.2), value: elf.guide.text)
        // .animation(.easeInOut(duration: 0.2), value: elf.showsGuide)
        .background(Palette.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 22))
    }

    /// 新訊息橫條：往上看時有新內容，顯示最新一則；點了捲到最下面（像 LINE）。樣式和便條一樣。
    private var newMessageBar: some View {
        Button {
            chatPosition.scrollTo(edge: .bottom)
            showsNewMessage = false
        } label: {
            HStack(spacing: 8) {
                if let mood = latestMessage.mood {
                    Image(mood.image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 24, height: 24)
                } else {
                    Circle().fill(Palette.userBubble).frame(width: 16, height: 16)
                }
                Text(latestMessage.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").foregroundStyle(Palette.accent)
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
        }
        .buttonStyle(.plain)
        .padding(8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// 對話流最下面的一則：正在說的話、排隊的話、處理中的回話、固定的話與回話。`mood` 為 nil 是使用者的話。
    private var latestMessage: (text: String, mood: Elf.Mood?) {
        let sentence = elf.sentence.finalText + elf.sentence.volatileText
        if !sentence.isEmpty { return (sentence, nil) }
        if let last = elf.pending.last { return (last.text, nil) }
        if let reply = elf.liveReply { return (reply, elf.mood) }
        guard let last = elf.conversation.last else { return ("", nil) }
        return (last.text, last.isUser ? nil : last.mood)
    }

    // 便條目前隱藏（見 docs/specs/help.md 的「便條」）。
    // /// 便條：一行引導，不是一句回話，所以固定在對話流頂端，不插進對話；太長截斷成「…」。
    // /// 點了等於說出便條上的那句話（見 docs/specs/help.md 的「便條」）。
    // private var guideNote: some View {
    //     Button {
    //         elf.openHint(elf.guide.page)
    //     } label: {
    //         Label {
    //             Text(elf.guide.text)
    //                 .lineLimit(1)
    //                 .truncationMode(.tail)
    //         } icon: {
    //             Image(systemName: "pin.fill").foregroundStyle(Palette.accent)
    //         }
    //         .font(.subheadline)
    //         .padding(.horizontal, 12)
    //         .padding(.vertical, 8)
    //         .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    //         .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    //         .shadow(color: .black.opacity(0.06), radius: 3, y: 1)
    //     }
    //     .buttonStyle(.plain)
    //     .disabled(!elf.canOpenHint)
    //     .padding(8)
    // }

    /// 提示對話框（見 docs/specs/help.md 的「提示對話框」）：小精靈的回話，高度固定在最長的一頁，換頁時箭頭不移動。
    /// 凍結的停在那一頁，箭頭與連結不能點。
    private func hintReply(_ page: HintPage, live: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(Elf.Mood.done.image)
                .resizable()
                .scaledToFit()
                .frame(width: Self.avatarSize, height: Self.avatarSize)
            VStack(alignment: .leading, spacing: 4) {
                // 每一頁都排版、只顯示目前這頁：高度就是最長的一頁。
                ZStack(alignment: .topLeading) {
                    ForEach(HintPage.all, id: \.name) { each in
                        hintPage(each, live: live)
                            .opacity(each == page ? 1 : 0)
                            .accessibilityHidden(each != page)
                    }
                }
                HStack {
                    Button { elf.stepHint(-1) } label: { Image(systemName: "chevron.left").touchTarget() }
                    Spacer()
                    Text("\((HintPage.all.firstIndex(of: page) ?? 0) + 1)／\(HintPage.all.count)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { elf.stepHint(1) } label: { Image(systemName: "chevron.right").touchTarget() }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.link)
                .disabled(!live)
            }
            .bubble(Palette.elfBubble)
        }
    }

    /// 一頁提示：連結嵌在文字裡（藍色粗體），點了換到那一頁；凍結時連結不能點、不用藍色。
    private func hintPage(_ page: HintPage, live: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(page.lines, id: \.self) { line in
                Text(Self.hintLine(line, live: live)).font(.subheadline)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .tint(Palette.link)
        .environment(\.openURL, OpenURLAction { url in
            if live, url.scheme == "hint", let index = Int(url.host() ?? ""), HintPage.all.indices.contains(index) {
                elf.openHint(HintPage.all[index].name)
            }
            return .handled
        })
    }

    /// `[頁名]` 換成連結；網址用頁的順序，不放中文。
    private static func hintLine(_ line: String, live: Bool) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(line)
        while let match = rest.firstMatch(of: HintPage.link) {
            result += AttributedString(rest[..<match.range.lowerBound])
            var link = AttributedString(match.1)
            link.inlinePresentationIntent = .stronglyEmphasized
            if live, let index = HintPage.all.firstIndex(where: { $0.name == match.1 }) {
                link.link = URL(string: "hint://\(index)")
                link.foregroundColor = Palette.link
            }
            result += link
            rest = rest[match.range.upperBound...]
        }
        return result + AttributedString(rest)
    }

    /// 小精靈的一則回話：左邊是那則回話狀態的插畫，沒有狀態文字（見 docs/specs/ui.md 的「對話流」）。
    /// 天氣資料的授權要求在顯示資料的地方旁邊標示來源，所以標示跟著那則回話（見 docs/specs/weather.md 的「標示」）。
    private func elfReply(_ text: String, weatherCredit: Bool, mood: Elf.Mood) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(mood.image)
                .resizable()
                .scaledToFit()
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .id(mood)
                .transition(.opacity)
            VStack(alignment: .leading, spacing: 8) {
                Text(text)
                    .contentTransition(.opacity)
                if weatherCredit {
                    Text(LocalizedStringKey(OpenMeteoWeather.credit))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .bubble(Palette.elfBubble)
        }
    }

    /// `sent` 為 false：排隊或正在說、還沒輪到小精靈處理的話，用淡色泡泡與虛線框；字維持一般顏色，對比才夠。
    private func userBubble(_ text: Text, sent: Bool = true) -> some View {
        text
            .bubble(sent ? Palette.userBubble : Palette.userBubble.opacity(0.35))
            .overlay {
                if !sent {
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Palette.userBubbleBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }
            .padding(.leading, 48)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    // MARK: - 黑板

    private var board: some View {
        let today = TodoStore.dayString(.now)
        let page = elf.boardPage
        let todos = elf.visibleTodos()
        return VStack(alignment: .leading, spacing: 6) {
            // 上一頁、範圍與查詢條件（藍色）、下一頁；右邊是筆數。
            HStack(spacing: 4) {
                Button { elf.goBack() } label: { Image(systemName: "chevron.left").touchTarget() }
                    .disabled(!elf.canGoBack)
                    .help("上一頁")
                Text("\(page.title)\(page.condition.map { Text(page.title.isEmpty ? $0 : " \($0)").foregroundStyle(Palette.query) } ?? Text(" "))")
                    .font(.headline)
                    .lineLimit(1)
                Button { elf.goForward() } label: { Image(systemName: "chevron.right").touchTarget() }
                    .disabled(!elf.canGoForward)
                    .help("下一頁")
                Spacer(minLength: 4)
                Text("\(todos.count) 筆")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Palette.chalkDim)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(Palette.chalkDim.opacity(0.5))
                .frame(height: 1)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if todos.isEmpty {
                        Text("無資料").foregroundStyle(Palette.chalkDim)
                    }
                    // 依日期分組，編號跨組連續（見 docs/specs/ui.md 的「黑板」）。
                    ForEach(BoardSection.lines(todos, today: today)) { line in
                        switch line {
                        case .header(let title, let isToday, let isMonth):
                            // 月份組的標題比組裡的日期小標題醒目一級。
                            Text(title)
                                .font(isMonth ? .headline : .subheadline)
                                .fontWeight(isToday ? .bold : nil)
                                .foregroundStyle(isToday ? Palette.chalkToday : isMonth ? Palette.chalk : Palette.chalkDim)
                                .padding(.top, 8)
                        case .todo(let todo, let number):
                            row(todo, number: number)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animation(.easeInOut(duration: 0.2), value: todos)
        }
        .overlay(alignment: .bottom) {
            if let notice = copiedNotice {
                Text(notice.text)
                    .font(.subheadline)
                    .lineLimit(1)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.75), in: Capsule())
                    .foregroundStyle(Palette.chalk)
                    .transition(.opacity)
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(1.5))
                        withAnimation { copiedNotice = nil }
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.slate, in: RoundedRectangle(cornerRadius: 6))
        .padding(10)
        .background(Palette.wood, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
        // 黑板是深色底：按鈕與停用的樣式用深色模式的顏色。
        .environment(\.colorScheme, .dark)
    }

    /// 編號、方框、時間、內容；內容折行時其他欄對齊第一行。
    private func row(_ todo: Todo, number: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(number)")
                .monospacedDigit()
                .foregroundStyle(Palette.chalkDim)
                .frame(width: 28, alignment: .trailing)
            Button { elf.toggleDone(todo.id) } label: {
                Image(systemName: todo.isDone ? "checkmark.square" : "square")
                    .font(.title2)
                    .touchTarget()
            }
            .buttonStyle(.plain)
            .disabled(!elf.canTouch)
            Text(todo.time ?? "")
                .monospacedDigit()
                .foregroundStyle(Palette.chalkDim)
                .frame(width: 48, alignment: .leading)
            // 點內容複製文字，任何時候都能點（見 docs/specs/todos.md 的「黑板」）。
            Text(todo.content)
                .strikethrough(todo.isDone)
                .onTapGesture {
                    if let text = elf.copyContent(todo.id) {
                        copiedNotice = ((copiedNotice?.id ?? 0) + 1, text)
                    }
                }
        }
        .foregroundStyle(todo.isDone ? Palette.chalkDim : Palette.chalk)
    }

    // MARK: - 按鈕列

    /// 復原、語音輸入開關、重做（見 docs/specs/ui.md 的「按鈕列」）。
    private var buttonBar: some View {
        HStack(spacing: 32) {
            iconButton("arrow.uturn.backward", help: "復原", enabled: elf.canUndo) { elf.undo() }
            Button {
                elf.setVoice(!elf.isVoiceOn)
            } label: {
                Image(systemName: elf.isVoiceOn ? "mic.fill" : "mic.slash")
                    .font(.title)
                    .frame(width: 64, height: 64)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .tint(Palette.accent)
            .help(elf.isVoiceOn ? "關閉語音輸入" : "打開語音輸入")
            iconButton("arrow.uturn.forward", help: "重做", enabled: elf.canRedo) { elf.redo() }
        }
        .frame(maxWidth: .infinity)
    }

    private func iconButton(_ symbol: String, help: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.circle)
        .tint(Palette.accent)
        .disabled(!enabled)
        .help(help)
    }
}

private extension View {
    /// 至少 44pt 的點擊範圍（見 docs/specs/ui.md 的「黑板」）。
    func touchTarget() -> some View {
        frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
    }

    func bubble(_ color: Color) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(color, in: RoundedRectangle(cornerRadius: 16))
            .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

private extension Elf.Mood {
    /// Assets 裡的插畫。
    var image: String {
        switch self {
        case .listening: "elf_listening"
        case .thinking: "elf_thinking"
        case .done: "elf_done"
        case .confused: "elf_confused"
        }
    }
}

/// 顏色 token：淺色與深色模式各一組；黑板兩種模式相同。
private enum Palette {
    static let background = Color(light: 0xF6F1E9, dark: 0x1D1A17)
    static let surface = Color(light: 0xFFFDF9, dark: 0x2C2824)
    static let elfBubble = Color(light: 0xFFFFFF, dark: 0x3A3530)
    static let userBubble = Color(light: 0xE4ECFA, dark: 0x2B3A52)
    static let userBubbleBorder = Color(light: 0x9DB3D9, dark: 0x5C7299)
    static let slate = Color(light: 0x2E4A3C, dark: 0x2E4A3C)
    static let wood = Color(light: 0xA9743F, dark: 0x7A5634)
    /// 淺色用較深的橘，對比才達到 4.5:1（見 docs/specs/ui.md）。
    static let accent = Color(light: 0xA0550F, dark: 0xF0A04B)
    /// 黑板的文字：粉筆白；過去、已完成與時間較淡，在黑板上的對比仍有 4.5:1。
    static let chalk = Color(light: 0xF4F1E8, dark: 0xF4F1E8)
    static let chalkDim = Color(light: 0xB9C6BD, dark: 0xB9C6BD)
    /// 黑板上的今天：粉筆黃。
    static let chalkToday = Color(light: 0xF5D76E, dark: 0xF5D76E)
    /// 黑板標題的查詢條件：黑板固定深色底，用淺藍。
    static let query = Color(light: 0x8EC5FF, dark: 0x8EC5FF)
    /// 提示對話框的連結與箭頭：在小精靈的泡泡上對比至少 4.5:1。
    static let link = Color(light: 0x1F5FBF, dark: 0x8EC5FF)
}

private extension Color {
    init(light: UInt32, dark: UInt32) {
        #if os(iOS)
        self.init(uiColor: UIColor { $0.userInterfaceStyle == .dark ? UIColor(rgb: dark) : UIColor(rgb: light) })
        #else
        self.init(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(rgb: dark) : NSColor(rgb: light) })
        #endif
    }
}

#if os(iOS)
private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension NSColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat(rgb >> 16 & 0xFF) / 255, green: CGFloat(rgb >> 8 & 0xFF) / 255, blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}
#endif

#Preview {
    HomeView(elf: Elf(autoAI: nil)) {}
}

/// 對話流、黑板、按鈕列的位置（見 docs/specs/ui.md 的「版面」）：比高還寬時黑板在左半，對話流與按鈕列在右半；否則由上而下。
/// 用同一個 Layout 擺放，不用 if 分成兩棵 view：換版面時對話流不會重建，捲動位置不變。
private struct HomeLayout: Layout {

    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    /// subviews 依序是對話流、黑板、按鈕列。
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let chat = subviews[0], board = subviews[1], buttonBar = subviews[2]
        if bounds.width > bounds.height {
            let half = (bounds.width - spacing) / 2
            let right = bounds.minX + half + spacing
            let barHeight = buttonBar.sizeThatFits(ProposedViewSize(width: half, height: nil)).height
            board.place(at: bounds.origin, proposal: ProposedViewSize(width: half, height: bounds.height))
            chat.place(at: CGPoint(x: right, y: bounds.minY),
                       proposal: ProposedViewSize(width: half, height: bounds.height - barHeight - spacing))
            buttonBar.place(at: CGPoint(x: right, y: bounds.maxY - barHeight),
                            proposal: ProposedViewSize(width: half, height: barHeight))
        } else {
            // 對話流依畫面高度的比例，按鈕列固定，剩下的都給黑板。
            let chatHeight = bounds.height * 0.42
            let barHeight = buttonBar.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil)).height
            chat.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: chatHeight))
            board.place(at: CGPoint(x: bounds.minX, y: bounds.minY + chatHeight + spacing),
                        proposal: ProposedViewSize(width: bounds.width, height: bounds.height - chatHeight - barHeight - spacing * 2))
            buttonBar.place(at: CGPoint(x: bounds.minX, y: bounds.maxY - barHeight),
                            proposal: ProposedViewSize(width: bounds.width, height: barHeight))
        }
    }
}
