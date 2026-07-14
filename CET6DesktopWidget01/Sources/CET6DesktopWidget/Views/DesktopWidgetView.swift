import Foundation
import AppKit
import SwiftUI

struct DesktopWidgetView: View {
    @ObservedObject var store: TaskStore
    var onOpenStudyWindow: () -> Void = {}
    @State private var newTaskTitle = ""
    @State private var selectedGoalID: String
    @State private var selectedGoalTitle: String
    @State private var widgetGoals: [GoalPlan]

    private static let allGoalsID = "__all_goals__"

    init(store: TaskStore, onOpenStudyWindow: @escaping () -> Void = {}) {
        self.store = store
        self.onOpenStudyWindow = onOpenStudyWindow
        let loadedGoals = GoalPlanStore01.load(defaultPlanText: "")
        let selectedGoal = Self.loadSelectedWidgetGoal(from: loadedGoals)
        _widgetGoals = State(initialValue: loadedGoals)
        _selectedGoalID = State(initialValue: selectedGoal.id)
        _selectedGoalTitle = State(initialValue: selectedGoal.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                header
                    .background(WindowDragArea())
                Spacer(minLength: 0)
                Button(action: onOpenStudyWindow) {
                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StudyTheme.ink)
                        .frame(width: 32, height: 32)
                        .background(StudyTheme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(StudyTheme.hairline, lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .help("打开学习窗口")
            }

            HStack(spacing: 10) {
                statusChip
                Spacer(minLength: 0)
                Text("\(widgetTasks.filter { !$0.isDone }.count) 待完成")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StudyTheme.secondaryInk)
            }

            inputRow
            taskList
        }
        .padding(20)
        .frame(width: 372, alignment: .topLeading)
        .frame(minHeight: 260, alignment: .topLeading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(StudyTheme.widgetPaper)
                VStack(spacing: 0) {
                    Rectangle().fill(Color.white.opacity(0.72)).frame(height: 1)
                    Spacer()
                    Rectangle().fill(Color.black.opacity(0.04)).frame(height: 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyTheme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 16, x: 0, y: 8)
        .preferredColorScheme(.light)
        .onReceive(NotificationCenter.default.publisher(for: .goalSelectionDidChange)) { _ in
            refreshSelectedGoal()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(selectedGoalTitle)
                    .font(StudyTheme.songti(size: 26, weight: .semibold))
                    .foregroundStyle(StudyTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                goalMenu
            }
            Text("今日目标")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(StudyTheme.secondaryInk)
        }
    }

    private var goalMenu: some View {
        Menu {
            Button {
                selectWidgetGoal(id: Self.allGoalsID, title: "所有")
            } label: {
                Label("所有", systemImage: selectedGoalID == Self.allGoalsID ? "checkmark" : "")
            }

            Divider()

            ForEach(widgetGoals) { goal in
                Button {
                    selectWidgetGoal(id: goal.id, title: goal.title)
                } label: {
                    Label(goal.title, systemImage: selectedGoalID == goal.id ? "checkmark" : "")
                }
            }
        } label: {
            Image(systemName: "chevron.down")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(StudyTheme.secondaryInk)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .buttonStyle(.plain)
        .help("切换日程项目")
    }

    private var statusChip: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(StudyCategory.today.tint)
                .frame(width: 6, height: 6)
            Text(DateKey.today())
                .font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(StudyTheme.paper)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(StudyTheme.hairline, lineWidth: 1)
        }
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            TextField("写下一件要完成的事", text: $newTaskTitle)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(StudyTheme.ink)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(StudyTheme.paper)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(StudyTheme.hairline, lineWidth: 1)
                }
                .onSubmit(addTask)

            Button(action: addTask) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .background(StudyTheme.command)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 9) {
            if widgetTasks.isEmpty {
                Text(selectedGoalID == Self.allGoalsID ? "今天还没有任何目标任务。" : "这个目标今天还没有任务。")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StudyTheme.secondaryInk)
                    .padding(.vertical, 2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(widgetTasks) { task in
                            Button {
                                store.toggleDone(task)
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(task.isDone ? StudyCategory.today.tint : StudyTheme.mutedInk)
                                        .font(.system(size: 15, weight: .medium))
                                        .frame(width: 20)
                                    Text(task.title)
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundStyle(task.isDone ? StudyTheme.mutedInk : StudyTheme.ink)
                                        .strikethrough(task.isDone)
                                        .multilineTextAlignment(.leading)
                                    if selectedGoalID == Self.allGoalsID {
                                        Text(task.goalTitle)
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(StudyTheme.secondaryInk)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 3)
                                            .background(StudyTheme.paper)
                                            .clipShape(Capsule())
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 132)
            }
        }
    }

    private var widgetTasks: [StudyTask] {
        selectedGoalID == Self.allGoalsID ? store.todayTasks : store.todayTasks(for: selectedGoalID)
    }

    private func addTask() {
        let targetGoal = selectedGoalID == Self.allGoalsID ? Self.loadSelectedWidgetGoal(from: widgetGoals) : (id: selectedGoalID, title: selectedGoalTitle)
        store.addTaskForToday(newTaskTitle, goalID: targetGoal.id, goalTitle: targetGoal.title)
        newTaskTitle = ""
    }

    private func refreshSelectedGoal() {
        let loadedGoals = GoalPlanStore01.load(defaultPlanText: "")
        widgetGoals = loadedGoals

        if selectedGoalID != Self.allGoalsID {
            let selectedGoal = Self.loadSelectedWidgetGoal(from: loadedGoals)
            selectedGoalID = selectedGoal.id
            selectedGoalTitle = selectedGoal.title
        }
    }

    private func selectWidgetGoal(id: String, title: String) {
        selectedGoalID = id
        selectedGoalTitle = title
    }

    private static func loadSelectedWidgetGoal(from goals: [GoalPlan]) -> (id: String, title: String) {
        let selectedGoalID = GoalPlanStore01.loadSelectedGoalID()
        let goal = goals.first { $0.id == selectedGoalID } ?? goals.first
        return (goal?.id ?? GoalPlanStore01.defaultGoalID, goal?.title ?? GoalPlanStore01.defaultGoalTitle)
    }
}

private struct WindowDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView {
        DragView()
    }

    func updateNSView(_ nsView: DragView, context: Context) {}

    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
    }
}

private struct SelectableEssayTextView: NSViewRepresentable {
    let text: String
    let onSelectionChange: (String) -> Void

    func makeNSView(context: Context) -> NSTextView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.isHorizontallyResizable = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textView.textColor = NSColor.labelColor
        textView.defaultParagraphStyle = Self.paragraphStyle
        textView.string = text
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        return textView
    }

    func updateNSView(_ textView: NSTextView, context: Context) {
        context.coordinator.onSelectionChange = onSelectionChange
        if textView.string != text {
            textView.string = text
        }
        textView.font = NSFont.systemFont(ofSize: 15, weight: .medium)
        textView.defaultParagraphStyle = Self.paragraphStyle
        textView.textContainer?.containerSize = NSSize(width: textView.bounds.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.invalidateIntrinsicContentSize()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textView: NSTextView, context: Context) -> CGSize? {
        let width = max(proposal.width ?? 640, 320)
        guard let textContainer = textView.textContainer, let layoutManager = textView.layoutManager else {
            return CGSize(width: width, height: 24)
        }

        textContainer.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textContainer.widthTracksTextView = true
        layoutManager.ensureLayout(for: textContainer)
        let usedRect = layoutManager.usedRect(for: textContainer)
        return CGSize(width: width, height: max(ceil(usedRect.height) + 4, 24))
    }

    private static var paragraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 2
        style.paragraphSpacing = 0
        return style
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelectionChange: onSelectionChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var onSelectionChange: (String) -> Void

        init(onSelectionChange: @escaping (String) -> Void) {
            self.onSelectionChange = onSelectionChange
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let ranges = textView.selectedRanges.compactMap { $0.rangeValue }
            let selectedText = ranges
                .filter { $0.length > 0 && NSMaxRange($0) <= (textView.string as NSString).length }
                .map { (textView.string as NSString).substring(with: $0) }
                .joined(separator: " ")
            onSelectionChange(selectedText)
        }
    }
}

#Preview {
    DesktopWidgetView(store: TaskStore()) {}
}

private enum StudyCategory: String, CaseIterable, Identifiable {
    case goals
    case plan
    case today
    case words
    case translation
    case writing
    case roots
    case flashcards
    case mistakes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .goals: "目标总览"
        case .plan: "计划书"
        case .today: "今日日程"
        case .words: "单词本"
        case .translation: "翻译训练"
        case .writing: "写作训练"
        case .roots: "词根词缀"
        case .flashcards: "闪卡复习"
        case .mistakes: "错词收藏"
        }
    }

    var subtitle: String {
        switch self {
        case .goals: "多目标与多计划表"
        case .plan: "手动输入与 AI 生成"
        case .today: "任务进度与勾选"
        case .words: "高频词与例句"
        case .translation: "中译英与英文润色"
        case .writing: "150-200 词范文"
        case .roots: "按构词法记忆"
        case .flashcards: "正反面快速过"
        case .mistakes: "收藏与薄弱项"
        }
    }

    var icon: String {
        switch self {
        case .goals: "target"
        case .plan: "doc.text.magnifyingglass"
        case .today: "calendar.badge.clock"
        case .words: "book.closed.fill"
        case .translation: "character.book.closed"
        case .writing: "pencil.and.outline"
        case .roots: "point.3.connected.trianglepath.dotted"
        case .flashcards: "rectangle.stack"
        case .mistakes: "bookmark"
        }
    }

    var tint: Color {
        switch self {
        case .goals: Color(red: 0.18, green: 0.22, blue: 0.42)       // 靛蓝
        case .plan: Color(red: 0.14, green: 0.24, blue: 0.38)        // 藏蓝
        case .today: Color(red: 0.18, green: 0.42, blue: 0.32)       // 松花绿
        case .words: Color(red: 0.65, green: 0.22, blue: 0.18)       // 朱砂
        case .translation: Color(red: 0.16, green: 0.34, blue: 0.42) // 石青
        case .writing: Color(red: 0.52, green: 0.38, blue: 0.18)     // 赭石
        case .roots: Color(red: 0.56, green: 0.46, blue: 0.16)       // 藤黄
        case .flashcards: Color(red: 0.38, green: 0.20, blue: 0.30)  // 紫檀
        case .mistakes: Color(red: 0.60, green: 0.36, blue: 0.12)    // 琥珀
        }
    }
}

private struct VocabularyWord: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let word: String
    let phonetic: String
    let partOfSpeech: String
    let meaning: String
    let example: String
    let exampleTranslation: String
    let phrases: [String]
    let phraseTranslations: [String]
    let mnemonic: String
    let tag: String
    let difficulty: Int

    init(
        id: String,
        word: String,
        phonetic: String,
        partOfSpeech: String = "未标注",
        meaning: String,
        example: String,
        exampleTranslation: String = "",
        phrases: [String] = [],
        phraseTranslations: [String] = [],
        mnemonic: String = "",
        tag: String,
        difficulty: Int
    ) {
        self.id = id
        self.word = word
        self.phonetic = phonetic
        self.partOfSpeech = partOfSpeech
        self.meaning = meaning
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.phrases = phrases
        self.phraseTranslations = phraseTranslations
        self.mnemonic = mnemonic
        self.tag = tag
        self.difficulty = difficulty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.word = try container.decode(String.self, forKey: .word)
        self.phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        self.partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? "未标注"
        self.meaning = try container.decode(String.self, forKey: .meaning)
        self.example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        self.exampleTranslation = try container.decodeIfPresent(String.self, forKey: .exampleTranslation) ?? ""
        self.phrases = try container.decodeIfPresent([String].self, forKey: .phrases) ?? []
        self.phraseTranslations = try container.decodeIfPresent([String].self, forKey: .phraseTranslations) ?? []
        self.mnemonic = try container.decodeIfPresent(String.self, forKey: .mnemonic) ?? ""
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? "自定义"
        self.difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 3
    }

    var trimmedExampleTranslation: String {
        exampleTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var phraseTranslationLine: String {
        let translations = phraseTranslations
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !translations.isEmpty else { return "" }

        if translations.count == phrases.count {
            return zip(phrases, translations)
                .map { phrase, translation in
                    "\(phrase)：\(translation)"
                }
                .joined(separator: " · ")
        }

        return translations.joined(separator: " · ")
    }
}

private struct RootItem: Identifiable {
    let id = UUID()
    let root: String
    let meaning: String
    let pattern: String
    let examples: String
    let cue: String
}

private struct PlanChatMessage: Identifiable {
    let id = UUID()
    let isUser: Bool
    let text: String
}

private struct TranslationPracticeRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let input: String
    let mode: String
    let title: String
    let versions: [TranslationVersion]
    let notes: [String]

    init(id: UUID = UUID(), createdAt: Date = Date(), result: TranslationPracticeResult) {
        self.id = id
        self.createdAt = createdAt
        self.input = result.input
        self.mode = result.mode
        self.title = result.title
        self.versions = result.versions
        self.notes = result.notes
    }
}

private struct WritingPracticeRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let createdAt: Date
    let prompt: String
    let title: String
    let essay: String
    let wordCount: Int
    let notes: [WritingPracticeNote]
    let usefulExpressions: [String]

    init(id: UUID = UUID(), createdAt: Date = Date(), result: WritingPracticeResult) {
        self.id = id
        self.createdAt = createdAt
        self.prompt = result.prompt
        self.title = result.title
        self.essay = result.essay
        self.wordCount = result.wordCount
        self.notes = result.notes
        self.usefulExpressions = result.usefulExpressions
    }
}

private enum WordReviewMode: String, CaseIterable, Identifiable {
    case all
    case favorites
    case hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "全部"
        case .favorites: "收藏"
        case .hard: "高难"
        }
    }
}

private enum MistakeMode: String, CaseIterable, Identifiable {
    case favorites
    case hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: "已收藏"
        case .hard: "高难候选"
        }
    }
}

private enum PlanWorkspaceMode: String, CaseIterable, Identifiable {
    case manual
    case ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .manual: "计划书"
        case .ai: "AI 定计划"
        }
    }
}

private enum StudyTheme {
    // ── 典雅古典色板 ──────────────────────────────────────
    // 底色：暖宣纸系
    static let windowBase = Color(red: 0.958, green: 0.945, blue: 0.918)
    static let sidebarBase = Color(red: 0.930, green: 0.915, blue: 0.882).opacity(0.85)
    static let paper = Color(red: 0.978, green: 0.968, blue: 0.938)
    static let widgetPaper = Color(red: 0.965, green: 0.952, blue: 0.918).opacity(0.93)
    static let panelBase = Color(red: 0.972, green: 0.962, blue: 0.930).opacity(0.75)
    static let panelStrong = Color(red: 0.988, green: 0.978, blue: 0.948).opacity(0.92)
    static let field = Color(red: 0.992, green: 0.985, blue: 0.960).opacity(0.96)

    // 描边 / 分割线：淡墨色
    static let hairline = Color(red: 0.28, green: 0.22, blue: 0.16).opacity(0.16)

    // 文字：水墨层级
    static let ink = Color(red: 0.10, green: 0.08, blue: 0.06)
    static let sidebarInk = Color(red: 0.14, green: 0.12, blue: 0.10)
    static let secondaryInk = Color(red: 0.38, green: 0.34, blue: 0.28)
    static let mutedInk = Color(red: 0.55, green: 0.50, blue: 0.42)

    // 强调色：传统中国色
    static let command = Color(red: 0.12, green: 0.16, blue: 0.28)        // 靛蓝 — 按钮 / 主操作
    static let quietGreen = Color(red: 0.18, green: 0.42, blue: 0.32)     // 松花绿 — 完成状态
    static let blue = Color(red: 0.14, green: 0.22, blue: 0.36)           // 藏蓝 — 链接 / 交互
    static let cinnabar = Color(red: 0.72, green: 0.22, blue: 0.18)       // 朱砂 — 错误 / 删除
    static let ochre = Color(red: 0.62, green: 0.42, blue: 0.20)          // 赭石 — 提示 / 标签
    static let indigo = Color(red: 0.16, green: 0.22, blue: 0.42)         // 靛蓝深 — 标题装饰

    // ── 字体系统 ──────────────────────────────────────────
    // 标题 — 宋体衬线
    static func songti(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("Songti SC", size: size).weight(weight)
    }
    // 正文 — 系统默认（去掉 .rounded）
    static func body(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.system(size: size, weight: weight)
    }
}

// ── 古典按钮样式 ──────────────────────────────────────────

/// 古典主操作按钮（圆润、朴素、克制）
struct SealButtonStyle: ButtonStyle {
    var tint: Color = StudyTheme.indigo // 默认使用古典靛蓝
    var isFilled: Bool = true
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StudyTheme.songti(size: 14, weight: .semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .foregroundStyle(isFilled ? .white : tint)
            .background(
                Capsule()
                    .fill(isFilled ? tint : Color.clear)
                    .opacity(configuration.isPressed ? 0.75 : 0.9)
            )
            .overlay(
                Capsule()
                    .stroke(tint.opacity(configuration.isPressed ? 0.4 : 0.3), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 古典次级辅助按钮（圆润、极其清淡）
struct BookmarkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(StudyTheme.songti(size: 13, weight: .regular))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(StudyTheme.ink.opacity(0.85))
            .background(
                Capsule()
                    .fill(StudyTheme.sidebarBase)
                    .brightness(configuration.isPressed ? -0.04 : 0)
            )
            .overlay(
                Capsule()
                    .stroke(StudyTheme.hairline, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

private struct FloatingWindowSwitchStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.80)) {
                configuration.isOn.toggle()
            }
        } label: {
            ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                Capsule()
                    .fill(configuration.isOn ? StudyTheme.command : Color.black.opacity(0.10))
                    .overlay {
                        Capsule()
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }

                Circle()
                    .fill(StudyTheme.paper)
                    .frame(width: 24, height: 24)
                    .padding(3)
                    .shadow(color: .black.opacity(0.10), radius: 1, x: 0, y: 1)
            }
            .frame(width: 52, height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("悬浮窗")
        .accessibilityValue(configuration.isOn ? "已打开" : "已关闭")
    }
}

struct StudyWindowView: View {
    private static let emergencyPlan = GoalPlanSheet(
        id: "emergency-plan",
        title: "计划表01",
        planText: "",
        createdAt: Date(timeIntervalSinceReferenceDate: 0),
        updatedAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    private static let emergencyGoal = GoalPlan(
        id: "emergency-goal",
        title: "待恢复目标",
        mode: "恢复模式",
        focus: "请重新打开应用以恢复目标数据。",
        plans: [emergencyPlan]
    )

    @ObservedObject var store: TaskStore
    @ObservedObject var widgetVisibility: WidgetVisibilityController
    @State private var selectedCategory: StudyCategory = .goals
    @State private var planWorkspaceMode: PlanWorkspaceMode = .manual
    @State private var goals: [GoalPlan]
    @State private var selectedGoalID: String
    @State private var selectedPlanID: String
    @State private var planText: String
    @State private var scheduleBlocks: [ScheduleBlock]
    @State private var isGeneratingSchedule = false
    @State private var scheduleStatus = "本地规则预览"
    @State private var isPlanEditorCollapsed = false
    @State private var isLoadingPlanText = false
    @State private var planLoadGeneration = 0
    @State private var aiPlanPrompt = ""
    @State private var aiPlanDraft = ""
    @State private var aiPlanStatus = "填写目标背景后，AI 会生成一份可保存、可同步的计划。"
    @State private var isRevisingPlan = false
    @State private var quickTaskTitle = ""
    @State private var newGoalTitle = ""
    @State private var newGoalMode = "生活目标"
    @State private var newGoalFocus = ""
    @State private var newPlanTitle = ""
    @State private var goalStatus = "选择一个目标，再查看它的计划表和今日任务。"
    @State private var wordSearch = ""
    @State private var newWordText = ""
    @State private var wordBankStatus = "回车即可加入单词本"
    @State private var isCompletingWord = false
    @State private var customWords: [VocabularyWord]
    @State private var isLoadingCustomWords = false
    @State private var customWordsLoadGeneration = 0
    @State private var favoriteWordIDs: Set<String> = []
    @State private var deletedWordIDs: Set<String>
    @State private var revealedDeleteWordID: String?
    @State private var translationInput = ""
    @State private var translationStatus = "输入中文句子生成多个六级译法；输入英文句子生成润色版本"
    @State private var isGeneratingTranslation = false
    @State private var translationRecords: [TranslationPracticeRecord]
    @State private var revealedDeleteTranslationID: UUID?
    @State private var writingPrompt = ""
    @State private var writingStatus = "输入主题、句子或六级写作原题，生成 150-200 词范文和注释"
    @State private var isGeneratingWriting = false
    @State private var writingRecords: [WritingPracticeRecord]
    @State private var revealedDeleteWritingID: UUID?
    @State private var collapsedWritingRecordIDs: Set<UUID> = []
    @State private var selectedWritingRecordID: UUID?
    @State private var selectedEssayText = ""
    @State private var selectedEssayTranslation = ""
    @State private var translatingSelectionFor = ""
    @State private var essaySelectionTranslationTask: Task<Void, Never>?
    @State private var reviewIndex = 0
    @State private var showsCardBack = false
    @State private var reviewMode: WordReviewMode = .all
    @State private var rootSearch = ""
    @State private var mistakeSearch = ""
    @State private var mistakeMode: MistakeMode = .favorites

    init(store: TaskStore, widgetVisibility: WidgetVisibilityController = WidgetVisibilityController()) {
        self.store = store
        self.widgetVisibility = widgetVisibility
        let loadedGoals = GoalPlanStore01.load(defaultPlanText: Self.defaultPlanText)
        let preferredGoalID = GoalPlanStore01.loadSelectedGoalID()
        let selectedGoal = loadedGoals.first { $0.id == preferredGoalID } ?? loadedGoals.first ?? Self.emergencyGoal
        let preferredPlanID = GoalPlanStore01.loadSelectedPlanID()
        let selectedPlan = selectedGoal.plans.first { $0.id == preferredPlanID } ?? selectedGoal.plans.first ?? Self.emergencyPlan
        let plan = selectedPlan.planText
        _goals = State(initialValue: loadedGoals.isEmpty ? [selectedGoal] : loadedGoals)
        _selectedGoalID = State(initialValue: selectedGoal.id)
        _selectedPlanID = State(initialValue: selectedPlan.id)
        _planText = State(initialValue: plan)
        let initialBlocks = selectedPlan.generatedSchedule ?? Self.generateSchedule(from: plan, anchorDateKey: DateKey.from(selectedPlan.createdAt))
        _scheduleBlocks = State(initialValue: store.resolvedPlanBlocks(initialBlocks, goalID: selectedGoal.id, planID: selectedPlan.id))
        _customWords = State(initialValue: [])
        _favoriteWordIDs = State(initialValue: Self.loadFavoriteWordIDs())
        _deletedWordIDs = State(initialValue: Self.loadDeletedWordIDs())
        _translationRecords = State(initialValue: Self.loadTranslationRecords())
        _writingRecords = State(initialValue: Self.loadWritingRecords())
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 210)

            Rectangle()
                .fill(StudyTheme.hairline)
                .frame(width: 1)

            detailPane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(shellBackground)
        .foregroundStyle(StudyTheme.ink)
        .preferredColorScheme(.light)
        .onChange(of: planText) { _, newValue in
            guard !isGeneratingSchedule, !isLoadingPlanText else { return }
            scheduleBlocks = resolvedScheduleBlocks(from: newValue)
            scheduleStatus = "本地规则预览"
            autosavePlanText(newValue)
        }
        .onChange(of: selectedGoalID) { _, newValue in
            selectGoal(newValue)
        }
        .onChange(of: selectedPlanID) { _, newValue in
            selectPlan(newValue)
        }
        .onChange(of: customWords) { _, newValue in
            guard !isLoadingCustomWords else { return }
            Self.saveCustomWords(newValue)
        }
        .onChange(of: favoriteWordIDs) { _, newValue in
            Self.saveFavoriteWordIDs(newValue)
        }
        .onChange(of: deletedWordIDs) { _, newValue in
            Self.saveDeletedWordIDs(newValue)
        }
        .onChange(of: translationRecords) { _, newValue in
            Self.saveTranslationRecords(newValue)
        }
        .onChange(of: writingRecords) { _, newValue in
            Self.saveWritingRecords(newValue)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dailyVocabularyDidImport)) { _ in
            Task {
                await reloadCustomWords(status: "已自动导入今日 20 个词")
            }
        }
        .task {
            await reloadCustomWords(status: nil)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Goals")
                            .font(StudyTheme.songti(size: 31, weight: .semibold))
                            .foregroundStyle(StudyTheme.ink)
                        Text("Life Desk")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(StudyTheme.mutedInk)
                    }
                    Spacer(minLength: 0)
                    Toggle(isOn: $widgetVisibility.isVisible) {}
                        .labelsHidden()
                        .toggleStyle(FloatingWindowSwitchStyle())
                        .help(widgetVisibility.isVisible ? "关闭悬浮窗" : "打开悬浮窗")
                }
                Text("目标 · 计划 · 执行 · 复盘")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StudyTheme.secondaryInk)
            }
            .padding(.top, 28)
            .padding(.horizontal, 20)

            ScrollView {
                VStack(spacing: 4) {
                    ForEach(availableCategories) { category in
                        sidebarButton(for: category)
                    }
                }
                .padding(.horizontal, 10)
            }

            Spacer()

            progressSummary
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
        }
        .background {
            ZStack {
                Rectangle().fill(.thinMaterial)
                StudyTheme.sidebarBase
                HStack {
                    Rectangle().fill(Color.white.opacity(0.42)).frame(width: 1)
                    Spacer()
                }
            }
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(selectedCategory.title)
                        .font(StudyTheme.songti(size: 29, weight: .semibold))
                    Text(selectedCategory.subtitle)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                }
                Spacer()
                currentTargetPicker
                statusPill
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Group {
                switch selectedCategory {
                case .goals:
                    goalsWorkspace
                case .plan:
                    combinedPlanWorkspace
                case .today:
                    todayWorkspace
                case .words:
                    wordBankWorkspace
                case .translation:
                    translationWorkspace
                case .writing:
                    writingWorkspace
                case .roots:
                    rootsWorkspace
                case .flashcards:
                    flashcardWorkspace
                case .mistakes:
                    mistakeWorkspace
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
        }
    }

    private var currentGoal: GoalPlan {
        goals.first { $0.id == selectedGoalID } ?? goals.first ?? Self.emergencyGoal
    }

    private var currentPlan: GoalPlanSheet {
        currentGoal.plans.first { $0.id == selectedPlanID } ?? currentGoal.plans.first ?? Self.emergencyPlan
    }

    private func resolvedScheduleBlocks(from text: String) -> [ScheduleBlock] {
        store.resolvedPlanBlocks(
            Self.generateSchedule(from: text, anchorDateKey: DateKey.from(currentPlan.createdAt)),
            goalID: currentGoal.id,
            planID: currentPlan.id
        )
    }

    private var availableCategories: [StudyCategory] {
        categories(for: currentGoal)
    }

    private func categories(for goal: GoalPlan) -> [StudyCategory] {
        let goalCategories: [StudyCategory] = [.goals, .plan, .today]
        let englishCategories: [StudyCategory] = [.words, .translation, .writing, .roots, .flashcards, .mistakes]

        return goalUsesEnglishTools(goal) ? goalCategories + englishCategories : goalCategories
    }

    private func goalUsesEnglishTools(_ goal: GoalPlan) -> Bool {
        let text = "\(goal.title) \(goal.mode) \(goal.focus)".lowercased()
        let keywords = ["cet", "六级", "英语", "英文", "单词", "词汇", "听力", "阅读", "翻译", "写作", "作文", "词根"]
        return keywords.contains { text.contains($0) }
    }

    private func ensureSelectedCategoryVisible(for goal: GoalPlan) {
        if !categories(for: goal).contains(selectedCategory) {
            selectedCategory = .goals
        }
    }

    private var currentTargetPicker: some View {
        HStack(spacing: 8) {
            Picker("当前目标", selection: $selectedGoalID) {
                ForEach(goals) { goal in
                    Text(goal.title).tag(goal.id)
                }
            }
            .labelsHidden()
            .frame(width: 170)

            Picker("当前计划表", selection: $selectedPlanID) {
                ForEach(currentGoal.plans) { plan in
                    Text(plan.title).tag(plan.id)
                }
            }
            .labelsHidden()
            .frame(width: 150)
        }
    }

    @ViewBuilder
    private func segmentedCapsule<T: Hashable>(
        selection: Binding<T>,
        options: [(T, String)]
    ) -> some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { option in
                Button {
                    selection.wrappedValue = option.0
                } label: {
                    Text(option.1)
                        .font(StudyTheme.songti(size: 13, weight: selection.wrappedValue == option.0 ? .semibold : .regular))
                        .foregroundStyle(selection.wrappedValue == option.0 ? StudyTheme.ink : StudyTheme.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(selection.wrappedValue == option.0 ? StudyTheme.paper : Color.clear)
                                .shadow(color: selection.wrappedValue == option.0 ? Color.black.opacity(0.06) : Color.clear, radius: 2, x: 0, y: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(StudyTheme.sidebarBase))
        .overlay(Capsule().stroke(StudyTheme.hairline, lineWidth: 1))
    }

    private var shellBackground: some View {
        ZStack {
            StudyTheme.windowBase
            LinearGradient(
                colors: [
                    StudyTheme.paper.opacity(0.96),
                    StudyTheme.windowBase,
                    selectedCategory.tint.opacity(0.045)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack(spacing: 0) {
                Rectangle().fill(Color.white.opacity(0.52)).frame(height: 1)
                Spacer()
            }
        }
    }

    private var progressSummary: some View {
        let tasks = store.todayTasks(for: currentGoal.id)
        let total = max(tasks.count, 1)
        let done = tasks.filter(\.isDone).count

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("今日完成")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(done)/\(tasks.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(StudyTheme.secondaryInk)
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.black.opacity(0.12))
                    Capsule()
                        .fill(StudyTheme.quietGreen)
                        .frame(width: proxy.size.width * CGFloat(done) / CGFloat(total))
                }
            }
            .frame(height: 7)
        }
        .padding(13)
        .background(StudyTheme.panelBase)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyTheme.hairline, lineWidth: 1)
        }
    }

    private var statusPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(selectedCategory.tint)
                .frame(width: 8, height: 8)
            Text(DateKey.today())
                .font(.system(size: 13, weight: .semibold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(StudyTheme.ink)
        .background(StudyTheme.paper)
        .clipShape(Capsule())
        .overlay {
            Capsule().stroke(StudyTheme.hairline, lineWidth: 1)
        }
    }

    private func sidebarButton(for category: StudyCategory) -> some View {
        let isSelected = selectedCategory == category

        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(isSelected ? category.tint.opacity(0.12) : Color.white.opacity(0.001))
                        .frame(width: 34, height: 34)
                    Image(systemName: category.icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? category.tint : StudyTheme.mutedInk)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(isSelected ? StudyTheme.ink : StudyTheme.sidebarInk)
                    Text(category.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(isSelected ? StudyTheme.secondaryInk : StudyTheme.sidebarInk.opacity(0.74))
                }

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .padding(.horizontal, 10)
            .background(isSelected ? StudyTheme.panelStrong : Color.white.opacity(0.001))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(StudyTheme.hairline, lineWidth: 1)
                }
            }
            .overlay(alignment: .trailing) {
                if isSelected {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(category.tint)
                        .frame(width: 3, height: 24)
                        .padding(.trailing, 1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var goalsWorkspace: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("目标")
                        .font(.system(size: 16, weight: .bold))
                    Spacer()
                    Text("\(goals.count) 个")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(goals) { goal in
                            goalCard(goal)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 9) {
                    Text("新建目标")
                        .font(.system(size: 14, weight: .bold))
                    TextField("例如：考研、健身、读书、项目作品集", text: $newGoalTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StudyTheme.panelStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    TextField("模式，例如：考试冲刺 / 习惯养成 / 长期项目", text: $newGoalMode)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StudyTheme.panelStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    TextField("这个目标最重要的执行原则", text: $newGoalFocus)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StudyTheme.panelStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onSubmit(addGoal)
                    Button {
                        addGoal()
                    } label: {
                        Label("新增目标", systemImage: "plus")
                    }
                    .buttonStyle(SealButtonStyle())
                    .tint(StudyCategory.goals.tint)
                }
                .padding(13)
                .background(StudyTheme.panelBase)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(StudyTheme.hairline, lineWidth: 1)
                }
            }
            .frame(width: 330)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(currentGoal.title)
                            .font(StudyTheme.songti(size: 24, weight: .semibold))
                        Text("\(currentGoal.mode) · \(currentGoal.focus)")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(StudyTheme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text(goalStatus)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                        .frame(maxWidth: 260, alignment: .trailing)
                }

                HStack(spacing: 10) {
                    TextField("新计划表名称", text: $newPlanTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(StudyTheme.panelStrong)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .onSubmit(addPlanToCurrentGoal)

                    Button {
                        addPlanToCurrentGoal()
                    } label: {
                        Label("新计划表", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(SealButtonStyle())
                    .tint(StudyCategory.goals.tint)
                }

                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(currentGoal.plans) { plan in
                            planSheetCard(plan)
                        }
                    }
                }
            }
        }
    }

    private func goalCard(_ goal: GoalPlan) -> some View {
        let isSelected = goal.id == selectedGoalID
        let todayCount = store.todayTasks(for: goal.id).count
        let doneCount = store.todayTasks(for: goal.id).filter(\.isDone).count

        return Button {
            selectedGoalID = goal.id
            selectedCategory = .goals
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: isSelected ? "target" : "circle")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isSelected ? StudyCategory.goals.tint : StudyTheme.mutedInk)
                    Text(goal.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(StudyTheme.ink)
                    Spacer()
                    Text(goal.mode)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                }
                Text(goal.focus)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(StudyTheme.secondaryInk)
                    .lineLimit(2)
                Text("\(goal.plans.count) 张计划表 · 今日 \(doneCount)/\(todayCount)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(StudyTheme.mutedInk)
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? StudyTheme.panelStrong : StudyTheme.panelBase)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? StudyCategory.goals.tint.opacity(0.45) : StudyTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                deleteGoal(goal)
            } label: {
                Label("删除目标", systemImage: "trash")
            }
            .disabled(goals.count <= 1)
        }
    }

    private func planSheetCard(_ plan: GoalPlanSheet) -> some View {
        let isSelected = plan.id == selectedPlanID
        let sourceBlocks = plan.generatedSchedule ?? Self.generateSchedule(from: plan.planText, anchorDateKey: DateKey.from(plan.createdAt))
        let blocks = store.resolvedPlanBlocks(sourceBlocks, goalID: currentGoal.id, planID: plan.id)
        let todayCount = blocks.filter { $0.dateKey == DateKey.today() }.count

        return Button {
            selectedPlanID = plan.id
            selectedCategory = .plan
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "doc.text.fill" : "doc.text")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isSelected ? StudyCategory.plan.tint : StudyTheme.mutedInk)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(plan.title)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(StudyTheme.ink)
                        Spacer()
                        Text("\(blocks.count) 项")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(StudyTheme.secondaryInk)
                    }
                    Text("今天 \(todayCount) 项 · \(plan.updatedAt.formatted(date: .abbreviated, time: .omitted)) 更新")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                    Text(plan.planText.components(separatedBy: .newlines).prefix(2).joined(separator: "；"))
                        .font(.system(size: 12))
                        .foregroundStyle(StudyTheme.mutedInk)
                        .lineLimit(2)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? StudyTheme.panelStrong : StudyTheme.panelBase)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? StudyCategory.plan.tint.opacity(0.45) : StudyTheme.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private var combinedPlanWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                segmentedCapsule(
                    selection: $planWorkspaceMode,
                    options: PlanWorkspaceMode.allCases.map { ($0, $0.title) }
                )
                .frame(width: 260)

                Spacer()
            }

            Group {
                switch planWorkspaceMode {
                case .manual:
                    planWorkspace
                case .ai:
                    aiPlanWorkspace
                }
            }
        }
    }

    private var planWorkspace: some View {
        HStack(alignment: .top, spacing: 18) {
            planEditorPane
            .frame(width: 360)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("生成日程")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(StudyTheme.ink)
                        Text(scheduleStatus)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StudyTheme.secondaryInk)
                            .lineLimit(2)
                            .truncationMode(.tail)
                            .frame(maxWidth: 260, alignment: .leading)
                    }
                    Spacer()
                    Button {
                        generateScheduleWithAI()
                    } label: {
                        Label(isGeneratingSchedule ? "拆解中" : "AI 拆解", systemImage: isGeneratingSchedule ? "hourglass" : "sparkles")
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .buttonStyle(SealButtonStyle())
                    .tint(StudyCategory.plan.tint)
                    .disabled(isGeneratingSchedule)

                    Button {
                        copyScheduleToPasteboard()
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(BookmarkButtonStyle())
                    .disabled(scheduleBlocks.isEmpty)

                    Button {
                        syncPlanTasks()
                    } label: {
                        Label("同步到任务库", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(StudyCategory.plan.tint)
                    .disabled(scheduleBlocks.isEmpty)
                }

                ScrollView {
                    if scheduleBlocks.isEmpty {
                        emptyPanel("这张计划表还没有可生成的日程", hint: "在左侧写入日期、时间段和任务内容后，会在这里生成当前目标的日程。")
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(scheduleBlocks) { block in
                                scheduleCard(block)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    private var planEditorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            if isPlanEditorCollapsed {
                collapsedPlanEditorPane
            } else {
                expandedPlanEditorPane
            }
        }
    }

    private var expandedPlanEditorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("\(currentGoal.title) · \(currentPlan.title)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(StudyTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Button {
                    pastePlanFromPasteboard()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }
                .buttonStyle(BookmarkButtonStyle())

                Button {
                    savePlan()
                } label: {
                    Label("保存计划书", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(SealButtonStyle())
                .tint(StudyCategory.plan.tint)
            }
            TextEditor(text: $planText)
                .font(StudyTheme.songti(size: 14))
                .foregroundStyle(StudyTheme.ink)
                .scrollContentBackground(.hidden)
                .padding(12)
                .background(StudyTheme.panelStrong)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(StudyTheme.hairline, lineWidth: 1)
                }
        }
    }

    private var collapsedPlanEditorPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(StudyCategory.today.tint)
                VStack(alignment: .leading, spacing: 3) {
                    Text("计划书已同步")
                        .font(.system(size: 16, weight: .bold))
                    Text("\(currentGoal.title) · \(currentPlan.title)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                        .lineLimit(2)
                }
                Spacer()
            }

            Text("左侧原文已收起，右侧日程和“今日日程”会继续保留。")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudyTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isPlanEditorCollapsed = false
            } label: {
                Label("显示/编辑原文", systemImage: "pencil")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(SealButtonStyle())
            .tint(StudyCategory.plan.tint)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyTheme.panelStrong)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyTheme.hairline, lineWidth: 1)
        }
    }

    private func copyScheduleToPasteboard() {
        let text = scheduleBlocks
            .map { block in
                "\(block.dateLabel) \(block.timeLabel) \(block.title)（\(block.category)）\n\(block.note)"
            }
            .joined(separator: "\n\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        scheduleStatus = "已复制 \(scheduleBlocks.count) 项日程"
    }

    private func pastePlanFromPasteboard() {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            scheduleStatus = "剪贴板里没有可粘贴的文本"
            return
        }

        planText = text
        isPlanEditorCollapsed = false
        scheduleBlocks = resolvedScheduleBlocks(from: text)
        autosavePlanText(text)
        scheduleStatus = "已粘贴计划书，本地规则预览"
    }

    private func syncPlanTasks() {
        let blocksToSync = scheduleBlocks
        guard !blocksToSync.isEmpty else {
            scheduleStatus = "没有可同步的日程"
            return
        }

        do {
            try updateCurrentPlan(planText: planText, title: currentPlan.title, generatedSchedule: blocksToSync)
            store.syncPlanTasks(blocksToSync, goal: currentGoal, plan: currentPlan)
            scheduleBlocks = store.resolvedPlanBlocks(blocksToSync, goalID: currentGoal.id, planID: currentPlan.id)
            let todayCount = scheduleBlocks.filter { $0.dateKey == DateKey.today() }.count
            scheduleStatus = "计划书已保存并同步到 \(currentGoal.title)，今天 \(todayCount) 项"
            isPlanEditorCollapsed = true
        } catch {
            scheduleStatus = "同步失败：\(error.localizedDescription)"
        }
    }

    private func savePlan() {
        let blocksToSync = scheduleBlocks.isEmpty ? Self.generateSchedule(from: planText, anchorDateKey: DateKey.from(currentPlan.createdAt)) : scheduleBlocks

        do {
            try updateCurrentPlan(planText: planText, title: currentPlan.title, generatedSchedule: blocksToSync)
            if !blocksToSync.isEmpty {
                store.syncPlanTasks(blocksToSync, goal: currentGoal, plan: currentPlan)
                scheduleBlocks = store.resolvedPlanBlocks(blocksToSync, goalID: currentGoal.id, planID: currentPlan.id)
            } else {
                scheduleBlocks = []
            }
            let todayCount = scheduleBlocks.filter { $0.dateKey == DateKey.today() }.count
            scheduleStatus = "\(currentGoal.title) 的 \(currentPlan.title) 已保存并同步，今天 \(todayCount) 项"
            isPlanEditorCollapsed = true
        } catch {
            scheduleStatus = "保存失败：\(error.localizedDescription)"
        }
    }

    private func generateScheduleWithAI() {
        let trimmedPlan = planText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPlan.isEmpty else {
            scheduleStatus = "请先输入计划书"
            return
        }

        isGeneratingSchedule = true
        scheduleStatus = "正在调用 DeepSeek 拆解..."
        let targetGoalID = currentGoal.id
        let targetPlan = currentPlan

        Task {
            do {
                let service = try DeepSeekPlanService()
                let generatedSchedule = try await service.generateSchedule(from: trimmedPlan)

                await MainActor.run {
                    do {
                        try persistGeneratedSchedule(generatedSchedule, goalID: targetGoalID, planID: targetPlan.id)
                        if selectedGoalID == targetGoalID, selectedPlanID == targetPlan.id {
                            scheduleBlocks = store.resolvedPlanBlocks(generatedSchedule, goalID: targetGoalID, planID: targetPlan.id)
                            scheduleStatus = "DeepSeek 已生成并保存 \(generatedSchedule.count) 项"
                        } else {
                            goalStatus = "AI 日程已保存到 \(targetPlan.title)"
                        }
                    } catch {
                        scheduleStatus = "AI 日程已生成，但保存失败：\(error.localizedDescription)"
                    }
                    isGeneratingSchedule = false
                }
            } catch {
                let fallback = Self.generateSchedule(from: trimmedPlan, anchorDateKey: DateKey.from(targetPlan.createdAt))

                await MainActor.run {
                    if selectedGoalID == targetGoalID, selectedPlanID == targetPlan.id {
                        scheduleBlocks = store.resolvedPlanBlocks(fallback, goalID: targetGoalID, planID: targetPlan.id)
                        scheduleStatus = scheduleAIErrorMessage(error, fallbackCount: fallback.count)
                    }
                    isGeneratingSchedule = false
                }
            }
        }
    }

    private func scheduleAIErrorMessage(_ error: Error, fallbackCount: Int) -> String {
        let suffix = fallbackCount > 0 ? "，已用本地规则生成 \(fallbackCount) 项" : "，请补充更明确的日期和任务"

        if let serviceError = error as? DeepSeekPlanService.ServiceError {
            switch serviceError {
            case .missingAPIKey:
                return "缺少 DeepSeek API Key\(suffix)"
            case .invalidResponse:
                return "AI 返回内容为空或无法解析\(suffix)"
            case .requestFailed(let message):
                if message.contains("JSON") || message.contains("格式") {
                    return "AI 返回格式异常\(suffix)"
                }
                return "AI 接口调用失败\(suffix)"
            }
        }

        if (error as NSError).domain == NSURLErrorDomain {
            return "网络连接失败\(suffix)"
        }

        return "AI 拆解失败\(suffix)"
    }

    private func scheduleCard(_ block: ScheduleBlock) -> some View {
        let task = store.task(for: block, goalID: currentGoal.id, planID: currentPlan.id)
        let isDone = task?.isDone ?? false

        return HStack(alignment: .top, spacing: 13) {
            Button {
                store.toggleDone(for: block, goal: currentGoal, plan: currentPlan)
                scheduleStatus = isDone ? "已标记为未完成" : "已标记完成"
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(isDone ? StudyCategory.today.tint : StudyTheme.mutedInk)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(isDone ? "标记为未完成" : "标记完成")

            VStack {
                Text(block.dateLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 104, height: 28)
                    .background(StudyCategory.plan.tint)
                    .clipShape(Capsule())
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(block.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(isDone ? StudyTheme.mutedInk : StudyTheme.ink)
                        .strikethrough(isDone)
                    Spacer()
                    Text(block.category)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudyCategory.plan.tint)
                }
                Text(block.note)
                    .font(.system(size: 13))
                    .foregroundStyle(StudyTheme.secondaryInk)
                    .strikethrough(isDone)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(13)
        .background(StudyTheme.panelStrong)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyTheme.hairline, lineWidth: 1)
        }
    }

    private var aiPlanWorkspace: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                        Text("告诉 AI 你的目标背景")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(StudyTheme.ink)
                    Text("例如：目标期限、每天可用时间、薄弱环节、执行偏好和想要的节奏。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                }

                TextEditor(text: $aiPlanPrompt)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(StudyTheme.ink)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 230)
                    .padding(10)
                    .background(StudyTheme.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }

                HStack {
                    Text(aiPlanStatus)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                    Spacer()
                    Button {
                        generateAIStudyPlan()
                    } label: {
                        Label(isRevisingPlan ? "定制中" : "AI 定计划", systemImage: isRevisingPlan ? "hourglass" : "sparkles")
                    }
                    .buttonStyle(SealButtonStyle())
                    .tint(StudyCategory.plan.tint)
                    .disabled(isRevisingPlan)
                }
            }
            .frame(width: 360)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("AI 计划预览")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(StudyTheme.ink)
                            Text(aiPlanDraft.isEmpty ? "生成后会在这里显示完整计划和日程拆分。" : "\(Self.generateSchedule(from: aiPlanDraft, anchorDateKey: DateKey.from(currentPlan.createdAt)).count) 项可同步日程")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StudyTheme.secondaryInk)
                    }
                    Spacer()
                    Button {
                        saveAIPlanDraft()
                    } label: {
                        Label("保存到计划书", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(BookmarkButtonStyle())
                    .disabled(aiPlanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        syncAIPlanDraft()
                    } label: {
                        Label("同步任务", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(SealButtonStyle())
                    .tint(StudyCategory.plan.tint)
                    .disabled(aiPlanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if aiPlanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyPanel("还没有 AI 计划", hint: "在左侧写清楚目标、期限、每天可用时间、薄弱项和偏好，点击“AI 定计划”。")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(aiPlanDraft)
                                .font(StudyTheme.songti(size: 13))
                                .foregroundStyle(StudyTheme.ink)
                                .textSelection(.enabled)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(StudyTheme.panelStrong)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            ForEach(Self.generateSchedule(from: aiPlanDraft, anchorDateKey: DateKey.from(currentPlan.createdAt))) { block in
                                scheduleCard(block)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func aiPlanBubble(_ message: PlanChatMessage) -> some View {
        Text(message.text)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(StudyTheme.ink)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(StudyTheme.panelStrong)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StudyTheme.hairline, lineWidth: 1)
            }
            .textSelection(.enabled)
    }

    private func generateAIStudyPlan() {
        let request = aiPlanPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            aiPlanStatus = "请先输入你的备考情况。"
            return
        }

        isRevisingPlan = true
        aiPlanStatus = "AI 正在定制计划..."

        Task {
            do {
                let service = try DeepSeekPlanService()
                let goalContext = """
                当前目标：\(currentGoal.title)
                当前模式：\(currentGoal.mode)
                执行重点：\(currentGoal.focus)
                用户补充：\(request)
                """
                let generated = try await service.createStudyPlan(userProfile: goalContext)

                await MainActor.run {
                    aiPlanDraft = generated.planText
                    aiPlanStatus = generated.reply
                    isRevisingPlan = false
                }
            } catch {
                await MainActor.run {
                    aiPlanStatus = "定计划失败：\(error.localizedDescription)"
                    isRevisingPlan = false
                }
            }
        }
    }

    private func saveAIPlanDraft() {
        let draft = aiPlanDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }
        let generatedBlocks = Self.generateSchedule(from: draft, anchorDateKey: DateKey.from(currentPlan.createdAt))

        do {
            try updateCurrentPlan(planText: draft, title: currentPlan.title, generatedSchedule: generatedBlocks)
            setPlanTextWithoutAutosave(draft)
            scheduleBlocks = store.resolvedPlanBlocks(generatedBlocks, goalID: currentGoal.id, planID: currentPlan.id)
            aiPlanStatus = "AI 计划已保存到“计划书”。"
            isPlanEditorCollapsed = false
        } catch {
            aiPlanStatus = "保存失败：\(error.localizedDescription)"
        }
    }

    private func syncAIPlanDraft() {
        let draft = aiPlanDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.isEmpty else { return }

        let generatedBlocks = Self.generateSchedule(from: draft, anchorDateKey: DateKey.from(currentPlan.createdAt))
        guard !generatedBlocks.isEmpty else {
            aiPlanStatus = "AI 计划里没有可同步的日程，请先保存或补充日期和任务。"
            return
        }

        store.syncPlanTasks(generatedBlocks, goal: currentGoal, plan: currentPlan)
        scheduleBlocks = store.resolvedPlanBlocks(generatedBlocks, goalID: currentGoal.id, planID: currentPlan.id)
        aiPlanStatus = "已同步 \(generatedBlocks.count) 项任务到 \(currentGoal.title)，计划书未被替换。"
        scheduleStatus = "AI 计划草稿已同步到任务库，当前计划书未改"
        isPlanEditorCollapsed = false
    }

    private func sendPlanRevisionRequest() {
        generateAIStudyPlan()
    }

    private var todayWorkspace: some View {
        let selectedTasks = store.todayTasks(for: currentGoal.id)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(currentGoal.title)
                        .font(.system(size: 16, weight: .bold))
                    Text("只显示这个目标今天要做的事。切换右上角目标即可查看其它计划表。")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                }
                Spacer()
                Text("\(selectedTasks.filter(\.isDone).count)/\(selectedTasks.count)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(StudyTheme.secondaryInk)
            }

            HStack(spacing: 10) {
                TextField("添加今日任务", text: $quickTaskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(StudyTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(StudyTheme.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }
                    .onSubmit(addQuickTask)

                Button(action: addQuickTask) {
                    Label("添加", systemImage: "plus")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(SealButtonStyle())
                .tint(StudyCategory.today.tint)
            }

            ScrollView {
                if selectedTasks.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("这个目标今天还没有同步到任务库的计划。")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(StudyTheme.ink)
                        Text("如果计划书里有今天的日期，请回到“计划书”页点“同步到任务库”。")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(StudyTheme.secondaryInk)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(StudyTheme.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }
                } else {
                    LazyVStack(spacing: 9) {
                        ForEach(selectedTasks) { task in
                            Button {
                                store.toggleDone(task)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(task.isDone ? StudyCategory.today.tint : StudyTheme.mutedInk)
                                    Text(task.title)
                                        .font(.system(size: 15, weight: .medium))
                                        .strikethrough(task.isDone)
                                        .foregroundStyle(task.isDone ? StudyTheme.mutedInk : StudyTheme.ink)
                                    Spacer()
                                }
                                .padding(13)
                                .background(StudyTheme.panelStrong)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(StudyTheme.hairline, lineWidth: 1)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private var wordBankWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                TextField("输入新单词，回车加入单词本", text: $newWordText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(StudyTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(StudyTheme.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }
                    .onSubmit(addCustomWord)

                Button(action: addCustomWord) {
                    Label(isCompletingWord ? "补全中" : "加入", systemImage: isCompletingWord ? "hourglass" : "plus")
                        .padding(.horizontal, 6)
                }
                .buttonStyle(SealButtonStyle())
                .tint(StudyCategory.words.tint)
                .disabled(isCompletingWord)
            }

            HStack(spacing: 10) {
                TextField("搜索单词、释义或标签", text: $wordSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(StudyTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(StudyTheme.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }
                Text("\(filteredWords.count) 词")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(StudyTheme.secondaryInk)
            }

            Text(wordBankStatus)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StudyTheme.secondaryInk)

            ScrollView {
                if filteredWords.isEmpty {
                    emptyPanel("没有匹配的单词")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredWords) { word in
                            wordRow(word)
                        }
                    }
                }
            }
        }
    }

    private func wordRow(_ word: VocabularyWord) -> some View {
        let isRevealed = revealedDeleteWordID == word.id

        return HStack(spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(word.word)
                            .font(StudyTheme.songti(size: 20, weight: .bold))
                            .foregroundStyle(StudyTheme.ink)
                        if !word.phonetic.isEmpty {
                            Text(word.phonetic)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(StudyTheme.secondaryInk)
                        }
                        Text(word.partOfSpeech)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(StudyTheme.secondaryInk)
                        Text(word.tag)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(StudyCategory.words.tint)
                    }

                    Text(word.meaning)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(StudyTheme.ink)
                    if !word.phrases.isEmpty {
                        Text(word.phrases.joined(separator: " · "))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StudyCategory.words.tint)
                    }
                    Text(word.example)
                        .font(StudyTheme.songti(size: 13))
                        .foregroundStyle(StudyTheme.secondaryInk)
                    if !word.mnemonic.isEmpty {
                        Text(word.mnemonic)
                            .font(.system(size: 12))
                            .foregroundStyle(StudyTheme.secondaryInk)
                    }
                }

                Spacer()

                Button {
                    toggleFavorite(word)
                } label: {
                    Image(systemName: favoriteWordIDs.contains(word.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(StudyCategory.words.tint)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .help(favoriteWordIDs.contains(word.id) ? "从错词收藏移除" : "加入错词收藏")
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
            .background(StudyTheme.panelStrong)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StudyTheme.hairline, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .gesture(
                DragGesture(minimumDistance: 12)
                    .onEnded { value in
                        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                            if value.translation.width < -28 {
                                revealedDeleteWordID = word.id
                            } else if value.translation.width > 20 {
                                revealedDeleteWordID = nil
                            }
                        }
                    }
            )
            .onTapGesture {
                if isRevealed {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        revealedDeleteWordID = nil
                    }
                }
            }

            if isRevealed {
                Button(role: .destructive) {
                    deleteWord(word)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .bold))
                        Text("删除")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 78)
                    .frame(minHeight: 86)
                    .background(StudyTheme.cinnabar)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isRevealed)
        .frame(maxWidth: .infinity, minHeight: 86, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contextMenu {
            Button(role: .destructive) {
                deleteWord(word)
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var translationWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("输入一句中文回车生成译法；输入一句英文回车润色", text: $translationInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(StudyTheme.ink)
                    .frame(minHeight: 44)
                    .padding(12)
                    .background(StudyTheme.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }
                    .onSubmit(generateTranslationPractice)

                HStack {
                    Text(translationStatus)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                    Spacer()
                    Button {
                        generateTranslationPractice()
                    } label: {
                        Label(isGeneratingTranslation ? "生成中" : "生成表达", systemImage: isGeneratingTranslation ? "hourglass" : "sparkles")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(SealButtonStyle())
                    .tint(StudyCategory.translation.tint)
                    .disabled(isGeneratingTranslation)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }

            ScrollView {
                if translationRecords.isEmpty {
                    emptyPanel("还没有翻译或润色记录", hint: "输入一句中文或英文，回车后会自动保存训练记录。")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(translationRecords) { record in
                            translationRecordRow(record)
                        }
                    }
                }
            }
        }
    }

    private func translationRecordRow(_ record: TranslationPracticeRecord) -> some View {
        let isRevealed = revealedDeleteTranslationID == record.id

        return deletableRecordRow(
            isRevealed: isRevealed,
            reveal: { revealedDeleteTranslationID = record.id },
            hide: { revealedDeleteTranslationID = nil },
            delete: { deleteTranslationRecord(record) }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.title)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(StudyTheme.ink)
                    Text(record.mode)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudyCategory.translation.tint)
                    Spacer()
                    Text(Self.displayDate(record.createdAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudyTheme.mutedInk)
                }

                Text("原句：\(record.input)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudyTheme.secondaryInk)

                ForEach(record.versions) { version in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(version.label)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudyCategory.translation.tint)
                        Text(version.text)
                            .font(StudyTheme.songti(size: 15, weight: .semibold))
                            .foregroundStyle(StudyTheme.ink)
                            .textSelection(.enabled)
                        if !version.reason.isEmpty {
                            Text(version.reason)
                                .font(.system(size: 12))
                                .foregroundStyle(StudyTheme.secondaryInk)
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.48))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                if !record.notes.isEmpty {
                    Text("提醒：" + record.notes.joined(separator: "；"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudyTheme.panelStrong)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StudyTheme.hairline, lineWidth: 1)
            }
        }
    }

    private var writingWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("输入作文主题、提示句或六级原题，回车生成范文", text: $writingPrompt)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(StudyTheme.ink)
                    .frame(minHeight: 44)
                    .padding(12)
                    .background(StudyTheme.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }
                    .onSubmit(generateWritingPractice)

                HStack {
                    Text(writingStatus)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                    Spacer()
                    Button {
                        generateWritingPractice()
                    } label: {
                        Label(isGeneratingWriting ? "生成中" : "生成作文", systemImage: isGeneratingWriting ? "hourglass" : "doc.text")
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(SealButtonStyle())
                    .tint(StudyCategory.writing.tint)
                    .disabled(isGeneratingWriting)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }

            ScrollView {
                if writingRecords.isEmpty {
                    emptyPanel("还没有写作记录", hint: "输入主题、提示句或六级原题，回车后会自动保存作文和注释。")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(writingRecords) { record in
                            writingRecordRow(record)
                        }
                    }
                }
            }
        }
    }

    private func writingRecordRow(_ record: WritingPracticeRecord) -> some View {
        let isRevealed = revealedDeleteWritingID == record.id
        let isCollapsed = collapsedWritingRecordIDs.contains(record.id)

        return deletableRecordRow(
            isRevealed: isRevealed,
            reveal: { revealedDeleteWritingID = record.id },
            hide: { revealedDeleteWritingID = nil },
            delete: { deleteWritingRecord(record) }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text(record.title)
                        .font(StudyTheme.songti(size: 18, weight: .bold))
                        .foregroundStyle(StudyTheme.ink)
                    Text("\(record.wordCount) words")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudyCategory.writing.tint)
                    Spacer()
                    Text(Self.displayDate(record.createdAt))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudyTheme.mutedInk)
                    Button {
                        toggleWritingRecordCollapse(record.id)
                    } label: {
                        Label(isCollapsed ? "展开" : "收起", systemImage: isCollapsed ? "chevron.down.circle" : "chevron.up.circle")
                    }
                    .font(.system(size: 12, weight: .bold))
                    .buttonStyle(.borderless)
                    .foregroundStyle(StudyCategory.writing.tint)
                }

                Text("题目：\(record.prompt)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudyTheme.secondaryInk)

                if isCollapsed {
                    Text(Self.essayPreview(record.essay))
                        .font(StudyTheme.songti(size: 13, weight: .medium))
                        .foregroundStyle(StudyTheme.secondaryInk)
                        .lineLimit(2)
                } else {
                    SelectableEssayTextView(text: record.essay) { selectedText in
                        handleEssaySelection(recordID: record.id, selectedText: selectedText)
                    }

                    if selectedWritingRecordID == record.id, !selectedEssayText.isEmpty {
                        essaySelectionPanel
                    }

                    if !record.usefulExpressions.isEmpty {
                        Text("可迁移表达：" + record.usefulExpressions.joined(separator: " · "))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudyCategory.writing.tint)
                    }

                    if !record.notes.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("注释")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(StudyTheme.ink)
                            ForEach(record.notes) { note in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("• \(note.target)：\(note.explanation)")
                                        .font(.system(size: 12))
                                        .foregroundStyle(StudyTheme.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 8)
                                    if let word = Self.extractSingleEnglishWord(from: note.target) {
                                        Button {
                                            addWordToBook(word)
                                        } label: {
                                            Label("加入单词本", systemImage: "plus.circle")
                                                .labelStyle(.titleAndIcon)
                                        }
                                        .font(.system(size: 11, weight: .bold))
                                        .buttonStyle(.borderless)
                                        .foregroundStyle(StudyCategory.writing.tint)
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.48))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(StudyTheme.panelStrong)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(StudyTheme.hairline, lineWidth: 1)
            }
        }
    }

    private var essaySelectionPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("已选中")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudyTheme.secondaryInk)
                Text(selectedEssayText)
                    .font(StudyTheme.songti(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(StudyTheme.ink)
                Spacer()
                if let word = Self.extractSingleEnglishWord(from: selectedEssayText) {
                    Button {
                        addWordToBook(word)
                    } label: {
                        Label("加入单词本", systemImage: "plus.circle")
                    }
                    .buttonStyle(BookmarkButtonStyle())
                    .tint(StudyCategory.writing.tint)
                }
            }

            if translatingSelectionFor == selectedEssayText {
                Label("正在翻译选中内容...", systemImage: "hourglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StudyTheme.secondaryInk)
            } else if !selectedEssayTranslation.isEmpty {
                Text("翻译：\(selectedEssayTranslation)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudyTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyCategory.writing.tint.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(StudyCategory.writing.tint.opacity(0.25), lineWidth: 1)
        }
    }

    private func deletableRecordRow<Content: View>(
        isRevealed: Bool,
        reveal: @escaping () -> Void,
        hide: @escaping () -> Void,
        delete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            content()
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .gesture(
                    DragGesture(minimumDistance: 12)
                        .onEnded { value in
                            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                                if value.translation.width < -28 {
                                    reveal()
                                } else if value.translation.width > 20 {
                                    hide()
                                }
                            }
                        }
                )
                .onTapGesture {
                    if isRevealed {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            hide()
                        }
                    }
                }

            if isRevealed {
                Button(role: .destructive) {
                    delete()
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .bold))
                        Text("删除")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: 78)
                    .frame(maxHeight: .infinity)
                    .background(StudyTheme.cinnabar)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: isRevealed)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contextMenu {
            Button(role: .destructive) {
                delete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var rootsWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("搜索词根、含义或例词", text: $rootSearch)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .foregroundStyle(StudyTheme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(StudyTheme.panelStrong)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(StudyTheme.hairline, lineWidth: 1)
                }

            ScrollView {
                if filteredRoots.isEmpty {
                    emptyPanel("没有匹配的词根词缀")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 12)], spacing: 12) {
                        ForEach(filteredRoots) { root in
                            rootCard(root)
                        }
                    }
                }
            }
        }
    }

    private func rootCard(_ root: RootItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(root.root)
                    .font(StudyTheme.songti(size: 22, weight: .bold))
                    .foregroundStyle(StudyCategory.roots.tint)
                Spacer()
                Text(root.pattern)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(StudyTheme.secondaryInk)
            }

            Text(root.meaning)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(StudyTheme.ink)
            Text(root.examples)
                .font(.system(size: 13))
                .foregroundStyle(StudyTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(root.cue)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(StudyCategory.roots.tint)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyTheme.panelStrong)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyTheme.hairline, lineWidth: 1)
        }
    }

    private var flashcardWorkspace: some View {
        let words = reviewWords

        return AnyView(VStack(spacing: 18) {
            segmentedCapsule(
                selection: $reviewMode,
                options: WordReviewMode.allCases.map { ($0, $0.title) }
            )
            .frame(maxWidth: 360)

            if words.isEmpty {
                Spacer(minLength: 10)
                emptyPanel("当前模式没有可复习的单词")
                Spacer()
            } else {
                let word = words[reviewIndex % words.count]

            Text("\(reviewIndex % words.count + 1) / \(words.count) · \(word.tag)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(StudyTheme.secondaryInk)

            Spacer(minLength: 10)

            Button {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    showsCardBack.toggle()
                }
            } label: {
                VStack(spacing: 14) {
                    Text(showsCardBack ? word.meaning : word.word)
                        .font(StudyTheme.songti(size: showsCardBack ? 28 : 50, weight: .bold))
                        .foregroundStyle(StudyTheme.ink)
                        .multilineTextAlignment(.center)
                    Text(showsCardBack ? word.example : (frontCardMeta(for: word).isEmpty ? "点击翻面" : frontCardMeta(for: word)))
                        .font(StudyTheme.songti(size: 16, weight: .medium))
                        .foregroundStyle(StudyTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 26)
                    if showsCardBack {
                        if !word.trimmedExampleTranslation.isEmpty {
                            Text(word.trimmedExampleTranslation)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(StudyTheme.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26)
                        }
                        if !word.phrases.isEmpty {
                            Text(word.phrases.joined(separator: " · "))
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(StudyCategory.flashcards.tint)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26)
                        }
                        if !word.phraseTranslationLine.isEmpty {
                            Text(word.phraseTranslationLine)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(StudyTheme.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26)
                        }
                        if !word.mnemonic.isEmpty {
                            Text(word.mnemonic)
                                .font(.system(size: 13))
                                .foregroundStyle(StudyTheme.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26)
                        }
                        Text("难度 \(word.difficulty)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudyCategory.flashcards.tint)
                    }
                }
                .frame(maxWidth: 560, minHeight: 300)
                .background(StudyTheme.panelStrong)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(StudyTheme.hairline, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)

            HStack(spacing: 12) {
                Button {
                    previousCard()
                } label: {
                    Label("上一个", systemImage: "chevron.left")
                }
                .buttonStyle(BookmarkButtonStyle())

                Button {
                    toggleCardFavorite(word)
                } label: {
                    Label(favoriteWordIDs.contains(word.id) ? "取消收藏" : "不熟收藏", systemImage: "bookmark")
                }
                .buttonStyle(BookmarkButtonStyle())
                .tint(StudyCategory.flashcards.tint)

                Button {
                    nextCard()
                } label: {
                    Label("认识", systemImage: "checkmark")
                }
                .buttonStyle(BookmarkButtonStyle())

                Button {
                    nextCard()
                } label: {
                    Label("下一个", systemImage: "chevron.right")
                }
                .buttonStyle(SealButtonStyle())
                .tint(StudyCategory.flashcards.tint)
            }

            Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: reviewMode) { _, _ in
            reviewIndex = 0
            showsCardBack = false
        })
    }

    private var mistakeWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                segmentedCapsule(
                    selection: $mistakeMode,
                    options: MistakeMode.allCases.map { ($0, $0.title) }
                )
                .frame(width: 230)

                TextField("搜索错词", text: $mistakeSearch)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .foregroundStyle(StudyTheme.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(StudyTheme.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }
            }

            ScrollView {
                if mistakeWords.isEmpty {
                    emptyPanel(mistakeMode == .favorites ? "还没有收藏错词" : "没有匹配的高难词")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(mistakeWords) { word in
                            mistakeRow(word)
                        }
                    }
                }
            }
        }
    }

    private func mistakeRow(_ word: VocabularyWord) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: favoriteWordIDs.contains(word.id) ? "bookmark.fill" : "exclamationmark.circle")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(StudyCategory.mistakes.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(word.word)
                        .font(StudyTheme.songti(size: 18, weight: .bold))
                        .foregroundStyle(StudyTheme.ink)
                    Text(word.tag)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudyCategory.mistakes.tint)
                }
                Text(word.meaning)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StudyTheme.ink)
                Text(word.example)
                    .font(StudyTheme.songti(size: 13))
                    .foregroundStyle(StudyTheme.secondaryInk)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                Text("难度 \(word.difficulty)")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudyTheme.secondaryInk)
                Button {
                    toggleFavorite(word)
                } label: {
                    Image(systemName: favoriteWordIDs.contains(word.id) ? "xmark.circle" : "plus.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(StudyCategory.mistakes.tint)
                }
                .buttonStyle(.plain)
                .help(favoriteWordIDs.contains(word.id) ? "移出错词收藏" : "加入错词收藏")
            }
        }
        .padding(14)
        .background(StudyTheme.panelStrong)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyTheme.hairline, lineWidth: 1)
        }
    }

    private var filteredWords: [VocabularyWord] {
        let query = wordSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return allWords }

        return allWords.filter { word in
            word.word.lowercased().contains(query)
                || word.meaning.lowercased().contains(query)
                || word.partOfSpeech.lowercased().contains(query)
                || word.phrases.joined(separator: " ").lowercased().contains(query)
                || word.mnemonic.lowercased().contains(query)
                || word.tag.lowercased().contains(query)
        }
    }

    private var allWords: [VocabularyWord] {
        (customWords + Self.words).filter { !deletedWordIDs.contains($0.id) }
    }

    private var reviewWords: [VocabularyWord] {
        switch reviewMode {
        case .all:
            return allWords
        case .favorites:
            return allWords.filter { favoriteWordIDs.contains($0.id) }
        case .hard:
            return allWords.filter { $0.difficulty >= 4 }
        }
    }

    private var filteredRoots: [RootItem] {
        let query = rootSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return Self.roots }

        return Self.roots.filter { root in
            root.root.lowercased().contains(query)
                || root.meaning.lowercased().contains(query)
                || root.pattern.lowercased().contains(query)
                || root.examples.lowercased().contains(query)
                || root.cue.lowercased().contains(query)
        }
    }

    private var mistakeWords: [VocabularyWord] {
        let source: [VocabularyWord]
        switch mistakeMode {
        case .favorites:
            source = allWords.filter { favoriteWordIDs.contains($0.id) }
        case .hard:
            source = allWords.filter { $0.difficulty >= 4 }
        }

        let query = mistakeSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return source }

        return source.filter { word in
            word.word.lowercased().contains(query)
                || word.meaning.lowercased().contains(query)
                || word.partOfSpeech.lowercased().contains(query)
                || word.phrases.joined(separator: " ").lowercased().contains(query)
                || word.mnemonic.lowercased().contains(query)
                || word.tag.lowercased().contains(query)
        }
    }

    private func selectGoal(_ goalID: String) {
        guard let goal = goals.first(where: { $0.id == goalID }) else {
            guard let fallback = goals.first else { return }
            if selectedGoalID != fallback.id {
                selectedGoalID = fallback.id
            }
            return
        }

        GoalPlanStore01.saveSelectedGoalID(goal.id)
        guard let plan = goal.plans.first(where: { $0.id == selectedPlanID }) ?? goal.plans.first else { return }
        selectedPlanID = plan.id
        loadPlan(plan)
        ensureSelectedCategoryVisible(for: goal)
        goalStatus = "已切换到 \(goal.title)"
    }

    private func selectPlan(_ planID: String) {
        guard let plan = currentGoal.plans.first(where: { $0.id == planID }) else {
            guard let fallbackPlan = currentGoal.plans.first else { return }
            selectedPlanID = fallbackPlan.id
            loadPlan(fallbackPlan)
            return
        }

        GoalPlanStore01.saveSelectedPlanID(plan.id)
        loadPlan(plan)
        goalStatus = "正在查看 \(currentGoal.title) 的 \(plan.title)"
    }

    private func loadPlan(_ plan: GoalPlanSheet) {
        isPlanEditorCollapsed = false
        setPlanTextWithoutAutosave(plan.planText)
        let sourceBlocks = plan.generatedSchedule ?? Self.generateSchedule(from: plan.planText, anchorDateKey: DateKey.from(plan.createdAt))
        scheduleBlocks = store.resolvedPlanBlocks(sourceBlocks, goalID: currentGoal.id, planID: plan.id)
        scheduleStatus = "\(currentGoal.title) · \(plan.title) · \(plan.generatedSchedule == nil ? "本地规则预览" : "已保存日程")"
    }

    private func setPlanTextWithoutAutosave(_ text: String) {
        isLoadingPlanText = true
        planLoadGeneration += 1
        let generation = planLoadGeneration
        planText = text
        Task { @MainActor in
            await Task.yield()
            if planLoadGeneration == generation {
                isLoadingPlanText = false
            }
        }
    }

    private func autosavePlanText(_ text: String) {
        guard !isLoadingPlanText else { return }
        do {
            try updateCurrentPlan(planText: text, title: currentPlan.title, generatedSchedule: nil)
        } catch {
            scheduleStatus = "自动保存失败：\(error.localizedDescription)"
        }
    }

    private func updateCurrentPlan(planText: String, title: String, generatedSchedule: [ScheduleBlock]?) throws {
        guard let goalIndex = goals.firstIndex(where: { $0.id == selectedGoalID }),
              let planIndex = goals[goalIndex].plans.firstIndex(where: { $0.id == selectedPlanID }) else {
            return
        }

        goals[goalIndex].plans[planIndex].title = title
        goals[goalIndex].plans[planIndex].planText = planText
        goals[goalIndex].plans[planIndex].generatedSchedule = generatedSchedule
        goals[goalIndex].plans[planIndex].updatedAt = Date()
        try saveGoals()
    }

    private func persistGeneratedSchedule(_ blocks: [ScheduleBlock], goalID: String, planID: String) throws {
        guard let goalIndex = goals.firstIndex(where: { $0.id == goalID }),
              let planIndex = goals[goalIndex].plans.firstIndex(where: { $0.id == planID }) else {
            return
        }

        goals[goalIndex].plans[planIndex].generatedSchedule = blocks
        goals[goalIndex].plans[planIndex].updatedAt = Date()
        try saveGoals()
    }

    private func addGoal() {
        let title = newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            goalStatus = "请先输入目标名称"
            return
        }

        let mode = newGoalMode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "生活目标" : newGoalMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let focus = newGoalFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "把目标拆成每天可执行、可勾选、可复盘的任务。" : newGoalFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = GoalPlanSheet(
            title: "计划表01",
            planText: """
            第1天 08:00-08:30 明确 \(title) 的本周重点
            第1天 20:00-20:40 完成一个最小行动并记录结果
            第2天 20:00-20:45 继续推进，复盘阻力和调整方法
            """
        )
        let goal = GoalPlan(title: title, mode: mode, focus: focus, plans: [plan])

        goals.append(goal)

        do {
            try saveGoals()
            newGoalTitle = ""
            newGoalMode = "生活目标"
            newGoalFocus = ""
            selectedGoalID = goal.id
            selectedPlanID = plan.id
            selectedCategory = .plan
            goalStatus = "已新增 \(title)"
        } catch {
            goalStatus = "新增失败：\(error.localizedDescription)"
        }
    }

    private func deleteGoal(_ goal: GoalPlan) {
        guard goals.count > 1 else {
            goalStatus = "至少要保留一个目标"
            return
        }

        let deletedTitle = goal.title
        goals.removeAll { $0.id == goal.id }
        store.removeTasks(for: goal.id)

        if selectedGoalID == goal.id {
            guard let fallback = goals.first, let fallbackPlan = fallback.plans.first else { return }
            selectedGoalID = fallback.id
            selectedPlanID = fallbackPlan.id
            loadPlan(fallbackPlan)
            ensureSelectedCategoryVisible(for: fallback)
        }

        do {
            try saveGoals()
            goalStatus = "已删除 \(deletedTitle)"
        } catch {
            goalStatus = "删除失败：\(error.localizedDescription)"
        }
    }

    private func addPlanToCurrentGoal() {
        let title = newPlanTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nextPlanTitle(for: currentGoal) : newPlanTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let goalIndex = goals.firstIndex(where: { $0.id == selectedGoalID }) else { return }

        let plan = GoalPlanSheet(
            title: title,
            planText: """
            第1天 08:00-08:30 \(currentGoal.title) 第一项行动
            第1天 20:00-20:30 记录今天完成情况
            第2天 20:00-20:45 根据反馈继续推进
            """
        )

        goals[goalIndex].plans.append(plan)

        do {
            try saveGoals()
            newPlanTitle = ""
            selectedPlanID = plan.id
            selectedCategory = .plan
            goalStatus = "已新增 \(title)"
        } catch {
            goalStatus = "新增计划表失败：\(error.localizedDescription)"
        }
    }

    private func saveGoals() throws {
        try GoalPlanStore01.save(goals)
    }

    private func nextPlanTitle(for goal: GoalPlan) -> String {
        var index = goal.plans.count + 1
        while goal.plans.contains(where: { $0.title == String(format: "计划表%02d", index) }) {
            index += 1
        }
        return String(format: "计划表%02d", index)
    }

    private func addQuickTask() {
        store.addTaskForToday(quickTaskTitle, goalID: currentGoal.id, goalTitle: currentGoal.title)
        quickTaskTitle = ""
    }

    private func addCustomWord() {
        guard let newWord = Self.customWord(from: newWordText) else {
            wordBankStatus = "请输入一个英文单词"
            return
        }

        guard !allWords.contains(where: { $0.id == newWord.id || $0.word.caseInsensitiveCompare(newWord.word) == .orderedSame }) else {
            wordBankStatus = "\(newWord.word) 已在单词本里"
            newWordText = ""
            return
        }

        isCompletingWord = true
        wordSearch = ""
        newWordText = ""
        wordBankStatus = "正在用 API 补全 \(newWord.word)..."

        Task {
            do {
                let service = try DeepSeekPlanService()
                let result = try await service.completeVocabularyWord(newWord.word)
                let completedWord = Self.customWord(from: result)

                await MainActor.run {
                    insertCustomWord(completedWord)
                    wordBankStatus = "已补全并加入 \(completedWord.word)"
                    isCompletingWord = false
                }
            } catch {
                await MainActor.run {
                    insertCustomWord(newWord)
                    wordBankStatus = "API 补全失败，已先加入 \(newWord.word)：\(error.localizedDescription)"
                    isCompletingWord = false
                }
            }
        }
    }

    private func generateTranslationPractice() {
        let input = translationInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            translationStatus = "请先输入一句中文或英文"
            return
        }

        isGeneratingTranslation = true
        translationStatus = "正在生成六级高分表达..."

        Task {
            do {
                let service = try DeepSeekPlanService()
                let result = try await service.generateTranslationPractice(for: input)

                await MainActor.run {
                    translationRecords.insert(TranslationPracticeRecord(result: result), at: 0)
                    translationInput = ""
                    translationStatus = "已保存 1 条\(result.mode)记录"
                    isGeneratingTranslation = false
                }
            } catch {
                await MainActor.run {
                    translationStatus = "生成失败：\(error.localizedDescription)"
                    isGeneratingTranslation = false
                }
            }
        }
    }

    private func generateWritingPractice() {
        let prompt = writingPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            writingStatus = "请先输入作文主题、句子或原题"
            return
        }

        isGeneratingWriting = true
        writingStatus = "正在生成 150-200 词六级范文..."

        Task {
            do {
                let service = try DeepSeekPlanService()
                let result = try await service.generateCET6Essay(for: prompt)

                await MainActor.run {
                    writingRecords.insert(WritingPracticeRecord(result: result), at: 0)
                    writingPrompt = ""
                    writingStatus = "已保存 1 篇作文，约 \(result.wordCount) 词"
                    isGeneratingWriting = false
                }
            } catch {
                await MainActor.run {
                    writingStatus = "生成失败：\(error.localizedDescription)"
                    isGeneratingWriting = false
                }
            }
        }
    }

    private func handleEssaySelection(recordID: UUID, selectedText: String) {
        let cleaned = Self.cleanedSelection(selectedText)
        essaySelectionTranslationTask?.cancel()

        guard !cleaned.isEmpty else {
            selectedWritingRecordID = nil
            selectedEssayText = ""
            selectedEssayTranslation = ""
            translatingSelectionFor = ""
            return
        }

        selectedWritingRecordID = recordID
        selectedEssayText = cleaned
        selectedEssayTranslation = ""

        translatingSelectionFor = cleaned
        essaySelectionTranslationTask = Task {
            do {
                let service = try DeepSeekPlanService()
                let translation = try await service.translateSelectionToChinese(cleaned)

                await MainActor.run {
                    guard selectedWritingRecordID == recordID, selectedEssayText == cleaned else { return }
                    selectedEssayTranslation = translation
                    translatingSelectionFor = ""
                }
            } catch {
                await MainActor.run {
                    guard selectedWritingRecordID == recordID, selectedEssayText == cleaned else { return }
                    selectedEssayTranslation = "翻译失败：\(error.localizedDescription)"
                    translatingSelectionFor = ""
                }
            }
        }
    }

    private func addWordToBook(_ rawWord: String) {
        guard let newWord = Self.customWord(from: rawWord) else {
            writingStatus = "请选择一个英文单词"
            return
        }

        guard !allWords.contains(where: { $0.id == newWord.id || $0.word.caseInsensitiveCompare(newWord.word) == .orderedSame }) else {
            writingStatus = "\(newWord.word) 已在单词本里"
            wordBankStatus = "\(newWord.word) 已在单词本里"
            return
        }

        writingStatus = "正在加入单词本：\(newWord.word)..."

        Task {
            do {
                let service = try DeepSeekPlanService()
                let result = try await service.completeVocabularyWord(newWord.word)
                let completedWord = Self.customWord(from: result)

                await MainActor.run {
                    insertCustomWord(completedWord)
                    writingStatus = "已加入单词本：\(completedWord.word)"
                    wordBankStatus = "已补全并加入 \(completedWord.word)"
                }
            } catch {
                await MainActor.run {
                    insertCustomWord(newWord)
                    writingStatus = "已先加入单词本：\(newWord.word)"
                    wordBankStatus = "API 补全失败，已先加入 \(newWord.word)：\(error.localizedDescription)"
                }
            }
        }
    }

    private func insertCustomWord(_ word: VocabularyWord) {
        guard !allWords.contains(where: { $0.id == word.id || $0.word.caseInsensitiveCompare(word.word) == .orderedSame }) else {
            wordBankStatus = "\(word.word) 已在单词本里"
            return
        }

        deletedWordIDs.remove(word.id)
        customWords.insert(word, at: 0)
    }

    private func deleteWord(_ word: VocabularyWord) {
        customWords.removeAll { $0.id == word.id }
        favoriteWordIDs.remove(word.id)
        deletedWordIDs.insert(word.id)
        reviewIndex = min(reviewIndex, max(reviewWords.count - 1, 0))
        wordBankStatus = "已删除 \(word.word)"
    }

    private func deleteTranslationRecord(_ record: TranslationPracticeRecord) {
        translationRecords.removeAll { $0.id == record.id }
        revealedDeleteTranslationID = nil
        translationStatus = "已删除 1 条翻译训练记录"
    }

    private func deleteWritingRecord(_ record: WritingPracticeRecord) {
        writingRecords.removeAll { $0.id == record.id }
        revealedDeleteWritingID = nil
        collapsedWritingRecordIDs.remove(record.id)
        if selectedWritingRecordID == record.id {
            selectedWritingRecordID = nil
            selectedEssayText = ""
            selectedEssayTranslation = ""
            translatingSelectionFor = ""
        }
        writingStatus = "已删除 1 篇写作记录"
    }

    private func toggleWritingRecordCollapse(_ id: UUID) {
        if collapsedWritingRecordIDs.contains(id) {
            collapsedWritingRecordIDs.remove(id)
        } else {
            collapsedWritingRecordIDs.insert(id)
            if selectedWritingRecordID == id {
                essaySelectionTranslationTask?.cancel()
                selectedWritingRecordID = nil
                selectedEssayText = ""
                selectedEssayTranslation = ""
                translatingSelectionFor = ""
            }
        }
    }

    private func toggleFavorite(_ word: VocabularyWord) {
        if favoriteWordIDs.contains(word.id) {
            favoriteWordIDs.remove(word.id)
        } else {
            favoriteWordIDs.insert(word.id)
        }
    }

    private func nextCard() {
        let total = max(reviewWords.count, 1)
        reviewIndex = (reviewIndex + 1) % total
        showsCardBack = false
    }

    private func previousCard() {
        let total = max(reviewWords.count, 1)
        reviewIndex = (reviewIndex - 1 + total) % total
        showsCardBack = false
    }

    private func toggleCardFavorite(_ word: VocabularyWord) {
        toggleFavorite(word)
        nextCard()
    }

    private func frontCardMeta(for word: VocabularyWord) -> String {
        [word.phonetic, word.partOfSpeech]
            .filter { !$0.isEmpty && $0 != "未标注" }
            .joined(separator: "  ")
    }

    private func emptyPanel(_ message: String, hint: String = "可以换个筛选条件，或先在单词本里添加新词。") -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(StudyTheme.ink)
            Text(hint)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(StudyTheme.secondaryInk)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyTheme.panelStrong)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyTheme.hairline, lineWidth: 1)
        }
    }

    private static func customWord(from text: String) -> VocabularyWord? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard let first = parts.first else { return nil }
        let word = String(first).trimmingCharacters(in: .whitespacesAndNewlines)
        guard word.range(of: #"[A-Za-z]"#, options: .regularExpression) != nil else { return nil }

        let normalized = word.lowercased()
        let meaning = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : "自定义词，待补充释义"

        return VocabularyWord(
            id: "custom-\(normalized)",
            word: normalized,
            phonetic: "",
            partOfSpeech: "未标注",
            meaning: meaning.isEmpty ? "自定义词，待补充释义" : meaning,
            example: "Write your own sentence with \(normalized).",
            exampleTranslation: "",
            phrases: [],
            phraseTranslations: [],
            mnemonic: "",
            tag: "自定义",
            difficulty: 3
        )
    }

    private static func customWord(from result: WordLookupResult) -> VocabularyWord {
        let normalized = result.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return VocabularyWord(
            id: "custom-\(normalized)",
            word: normalized,
            phonetic: result.phonetic,
            partOfSpeech: result.partOfSpeech,
            meaning: result.meaning,
            example: result.example,
            exampleTranslation: result.exampleTranslation,
            phrases: result.phrases,
            phraseTranslations: result.phraseTranslations,
            mnemonic: result.mnemonic,
            tag: result.tag,
            difficulty: result.difficulty
        )
    }

    private static func cleanedSelection(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractSingleEnglishWord(from text: String) -> String? {
        let cleaned = cleanedSelection(text)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?()[]{}\"“”‘’"))
        guard cleaned.range(of: #"^[A-Za-z][A-Za-z'-]*$"#, options: .regularExpression) != nil else {
            return nil
        }
        return cleaned.lowercased()
    }

    private static func essayPreview(_ essay: String) -> String {
        let cleaned = cleanedSelection(essay)
        guard cleaned.count > 180 else { return cleaned }
        return String(cleaned.prefix(180)) + "..."
    }

    nonisolated private static func loadCustomWords() -> [VocabularyWord] {
        let defaultsWords: [VocabularyWord]
        if let data = UserDefaults.standard.data(forKey: customWordsKey),
           let words = try? JSONDecoder().decode([VocabularyWord].self, from: data) {
            defaultsWords = words
        } else {
            defaultsWords = []
        }

        guard let dataURL = customWordsFileURL(),
              let fileData = try? Data(contentsOf: dataURL),
              let fileWords = try? JSONDecoder().decode([VocabularyWord].self, from: fileData) else {
            return defaultsWords
        }

        return mergeWords(fileWords + defaultsWords)
    }

    @MainActor
    private func reloadCustomWords(status: String?) async {
        customWordsLoadGeneration += 1
        let generation = customWordsLoadGeneration
        let loadedWords = await Task.detached(priority: .userInitiated) {
            Self.loadCustomWords()
        }.value
        guard !Task.isCancelled, customWordsLoadGeneration == generation else { return }

        isLoadingCustomWords = true
        customWords = loadedWords
        if let status {
            wordBankStatus = status
        }
        reviewIndex = 0
        showsCardBack = false
        await Task.yield()
        if customWordsLoadGeneration == generation {
            isLoadingCustomWords = false
        }
    }

    private static func saveCustomWords(_ words: [VocabularyWord]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(mergeWords(words)) else { return }
        UserDefaults.standard.set(data, forKey: customWordsKey)
        if let dataURL = customWordsFileURL() {
            try? FileManager.default.createDirectory(at: dataURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: dataURL, options: .atomic)
        }
    }

    nonisolated private static func mergeWords(_ words: [VocabularyWord]) -> [VocabularyWord] {
        var seen: Set<String> = []
        var merged: [VocabularyWord] = []

        for word in words {
            let key = word.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(word)
        }

        return merged
    }

    nonisolated private static func customWordsFileURL() -> URL? {
        let folderURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("CET-6", isDirectory: true)
            .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)

        let existing = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        )) ?? []

        if let latest = existing
            .filter({ $0.lastPathComponent.range(of: #"^custom_words\d+\.json$"#, options: .regularExpression) != nil })
            .sorted(by: numberedFileSort)
            .first {
            return latest
        }

        return folderURL.appendingPathComponent("custom_words01.json")
    }

    private static func loadTranslationRecords() -> [TranslationPracticeRecord] {
        loadRecords(
            defaultsKey: translationRecordsKey,
            fileURL: numberedDataFileURL(prefix: "translation_records")
        )
    }

    private static func saveTranslationRecords(_ records: [TranslationPracticeRecord]) {
        saveRecords(records, defaultsKey: translationRecordsKey, fileURL: numberedDataFileURL(prefix: "translation_records"))
    }

    private static func loadWritingRecords() -> [WritingPracticeRecord] {
        loadRecords(
            defaultsKey: writingRecordsKey,
            fileURL: numberedDataFileURL(prefix: "writing_records")
        )
    }

    private static func saveWritingRecords(_ records: [WritingPracticeRecord]) {
        saveRecords(records, defaultsKey: writingRecordsKey, fileURL: numberedDataFileURL(prefix: "writing_records"))
    }

    private static func loadRecords<T: Decodable & Identifiable>(defaultsKey: String, fileURL: URL?) -> [T] where T.ID: Hashable {
        let defaultsRecords: [T]
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let records = try? JSONDecoder().decode([T].self, from: data) {
            defaultsRecords = records
        } else {
            defaultsRecords = []
        }

        guard let fileURL,
              let fileData = try? Data(contentsOf: fileURL),
              let fileRecords = try? JSONDecoder().decode([T].self, from: fileData) else {
            return defaultsRecords
        }

        return mergeRecords(preferred: fileRecords, fallback: defaultsRecords)
    }

    static func mergeRecords<T: Identifiable>(preferred: [T], fallback: [T]) -> [T] where T.ID: Hashable {
        var seenIDs: Set<T.ID> = []
        return (preferred + fallback).filter { seenIDs.insert($0.id).inserted }
    }

    private static func saveRecords<T: Encodable>(_ records: [T], defaultsKey: String, fileURL: URL?) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func numberedDataFileURL(prefix: String) -> URL? {
        let folderURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("CET-6", isDirectory: true)
            .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)

        let existing = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        )) ?? []

        let pattern = "^\(NSRegularExpression.escapedPattern(for: prefix))\\d+\\.json$"
        if let latest = existing
            .filter({ $0.lastPathComponent.range(of: pattern, options: .regularExpression) != nil })
            .sorted(by: numberedFileSort)
            .first {
            return latest
        }

        return folderURL.appendingPathComponent("\(prefix)01.json")
    }

    nonisolated static func numberedFileSort(_ lhs: URL, _ rhs: URL) -> Bool {
        let lhsIndex = numberedFileIndex(lhs)
        let rhsIndex = numberedFileIndex(rhs)
        if lhsIndex == rhsIndex {
            return lhs.lastPathComponent > rhs.lastPathComponent
        }
        return lhsIndex > rhsIndex
    }

    nonisolated private static func numberedFileIndex(_ url: URL) -> Int {
        let stem = url.deletingPathExtension().lastPathComponent
        let suffix = String(stem.reversed().prefix(while: \Character.isNumber).reversed())
        return Int(suffix) ?? 0
    }

    private static func loadFavoriteWordIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: favoriteWordsKey) ?? [])
    }

    private static func saveFavoriteWordIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: favoriteWordsKey)
    }

    private static func loadDeletedWordIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: deletedWordsKey) ?? [])
    }

    private static func saveDeletedWordIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: deletedWordsKey)
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    nonisolated private static let customWordsKey = "CET6DesktopWidget.customWords"
    private static let favoriteWordsKey = "CET6DesktopWidget.favoriteWordIDs"
    private static let deletedWordsKey = "CET6DesktopWidget.deletedWordIDs"
    private static let translationRecordsKey = "CET6DesktopWidget.translationRecords"
    private static let writingRecordsKey = "CET6DesktopWidget.writingRecords"

    static let defaultPlanText = """
    第1天 08:00-08:40 高频词 60 个，重点看同义替换
    第1天 20:30-21:10 听力 Section A 精听 2 篇
    第2天 08:00-08:45 词根词缀复盘，整理错词
    第2天 20:00-21:00 阅读长篇匹配 1 套并复盘
    第3天 19:30-20:30 翻译与写作模板各 1 组
    """

    private static let words: [VocabularyWord] = [
        VocabularyWord(id: "adequate", word: "adequate", phonetic: "/ˈædɪkwət/", meaning: "足够的；合格的", example: "The evidence is adequate to support the conclusion.", tag: "写作替换", difficulty: 3),
        VocabularyWord(id: "allocate", word: "allocate", phonetic: "/ˈæləkeɪt/", meaning: "分配；拨出", example: "Students should allocate time for vocabulary review.", tag: "计划表达", difficulty: 4),
        VocabularyWord(id: "consequence", word: "consequence", phonetic: "/ˈkɒnsɪkwəns/", meaning: "结果；后果", example: "Every decision has a long-term consequence.", tag: "阅读高频", difficulty: 4),
        VocabularyWord(id: "derive", word: "derive", phonetic: "/dɪˈraɪv/", meaning: "获得；源自", example: "Many English words derive from Latin roots.", tag: "词根", difficulty: 3),
        VocabularyWord(id: "eliminate", word: "eliminate", phonetic: "/ɪˈlɪmɪneɪt/", meaning: "消除；淘汰", example: "Good notes help eliminate repeated mistakes.", tag: "错题", difficulty: 4),
        VocabularyWord(id: "notion", word: "notion", phonetic: "/ˈnəʊʃn/", meaning: "概念；看法", example: "The passage challenges the common notion of success.", tag: "阅读观点", difficulty: 3),
        VocabularyWord(id: "substantial", word: "substantial", phonetic: "/səbˈstænʃl/", meaning: "大量的；实质性的", example: "A substantial improvement requires consistent practice.", tag: "写作升级", difficulty: 5),
        VocabularyWord(id: "transition", word: "transition", phonetic: "/trænˈzɪʃn/", meaning: "转变；过渡", example: "The transition from input to output matters in language learning.", tag: "综合", difficulty: 4)
    ]

    private static let roots: [RootItem] = [
        RootItem(root: "spect / spic", meaning: "看", pattern: "词根", examples: "inspect 检查 · perspective 视角 · conspicuous 显眼的", cue: "遇到 spect 先想“看见、观察、视角”。"),
        RootItem(root: "duc / duct", meaning: "引导；带来", pattern: "词根", examples: "conduct 执行 · reduce 减少 · introduce 介绍", cue: "duce/duct 常和“带、引、导向某结果”有关。"),
        RootItem(root: "form", meaning: "形状；形成", pattern: "词根", examples: "transform 转变 · uniform 统一的 · reform 改革", cue: "form 相关词优先抓“形态变化”。"),
        RootItem(root: "ject", meaning: "投掷；抛出", pattern: "词根", examples: "project 项目 · reject 拒绝 · objective 客观的", cue: "ject 像把东西抛出去：投射、拒出、目标物。"),
        RootItem(root: "port", meaning: "携带；运输", pattern: "词根", examples: "transport 运输 · import 进口 · portable 便携的", cue: "port 常指“带着走”或跨区域移动。"),
        RootItem(root: "scrib / script", meaning: "写", pattern: "词根", examples: "describe 描述 · manuscript 手稿 · prescription 处方", cue: "script 看到就联想文字、记录、书写。"),
        RootItem(root: "pre-", meaning: "在前；预先", pattern: "前缀", examples: "predict 预测 · preview 预览 · prejudice 偏见", cue: "pre- 先发生，常表示提前判断或预先处理。"),
        RootItem(root: "sub-", meaning: "在下；次级；接近", pattern: "前缀", examples: "subway 地铁 · subconscious 潜意识 · substantial 实质性的", cue: "sub- 往下看：下面、隐藏、基础层。"),
        RootItem(root: "-tion / -sion", meaning: "行为；状态；结果", pattern: "后缀", examples: "transition 转变 · conclusion 结论 · expansion 扩张", cue: "名词后缀，阅读里常是抽象概念或过程结果。"),
        RootItem(root: "-ive", meaning: "具有某种倾向的", pattern: "后缀", examples: "effective 有效的 · objective 客观的 · productive 高产的", cue: "-ive 多把动词/名词变成形容词，表示属性。")
    ]

    static func generateSchedule(from text: String, anchorDateKey: String = DateKey.today()) -> [ScheduleBlock] {
        let dayBlocks = scheduleBlocksFromDayHeadings(text, anchorDateKey: anchorDateKey)
        if !dayBlocks.isEmpty {
            return dayBlocks
        }

        let datedHeadingBlocks = scheduleBlocksFromDatedHeadings(text, anchorDateKey: anchorDateKey)
        if !datedHeadingBlocks.isEmpty {
            return datedHeadingBlocks
        }

        let sectionBlocks = scheduleBlocksFromSections(text, anchorDateKey: anchorDateKey)
        if !sectionBlocks.isEmpty {
            return sectionBlocks
        }

        let separators = CharacterSet(charactersIn: "\n;；")
        let fragments = text
            .components(separatedBy: separators)
            .map { cleanPlanLine($0) }
            .filter { !$0.isEmpty }

        guard !fragments.isEmpty else { return [] }

        return fragments.prefix(80).enumerated().flatMap { index, line in
            let title = titleFromPlanLine(line)
            return dateKeys(from: line, anchorDateKey: anchorDateKey).map { dateKey in
                ScheduleBlock(
                    dateKey: dateKey,
                    timeLabel: timeLabel(from: line, index: index),
                    title: title,
                    note: noteFromPlanLine(line, title: title),
                    category: category(from: line)
                )
            }
        }
    }

    private static func scheduleBlocksFromDayHeadings(_ text: String, anchorDateKey: String) -> [ScheduleBlock] {
        let lines = text.components(separatedBy: .newlines)
        let headingPattern = #"^\s*#+\s*Day\s*([0-9]+)\s*[:：]\s*(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: headingPattern, options: [.caseInsensitive]) else { return [] }
        var sections: [(day: Int, title: String, body: [String])] = []
        var currentIndex: Int?

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            if let match = regex.firstMatch(in: line, range: range),
               match.numberOfRanges >= 3,
               let day = Int(nsLine.substring(with: match.range(at: 1))) {
                let title = cleanPlanLine(nsLine.substring(with: match.range(at: 2)))
                sections.append((day: day, title: title.isEmpty ? "第\(day)天任务" : title, body: []))
                currentIndex = sections.count - 1
                continue
            }

            guard let currentIndex else { continue }
            let cleaned = cleanPlanLine(line)
            guard !cleaned.isEmpty, !cleaned.hasPrefix("---") else { continue }
            sections[currentIndex].body.append(cleaned)
        }

        return sections.compactMap { section in
            guard let dateKey = DateKey.addingDays(section.day - 1, to: anchorDateKey) else { return nil }
            let note = daySectionNote(from: section.body)
            return ScheduleBlock(
                dateKey: dateKey,
                timeLabel: "1-2 小时",
                title: section.title,
                note: note,
                category: category(from: "\(section.title) \(note)")
            )
        }
    }

    private static func daySectionNote(from lines: [String]) -> String {
        let importantPrefixes = ["今日产出", "今日任务", "学习内容", "重点理解", "适用题型"]
        var picked: [String] = []
        var shouldTakeNext = false

        for line in lines {
            if importantPrefixes.contains(where: { line.hasPrefix($0) }) {
                picked.append(line)
                shouldTakeNext = true
                continue
            }

            if shouldTakeNext, !line.hasPrefix("#") {
                picked.append(line)
                shouldTakeNext = false
                if picked.count >= 4 { break }
            }
        }

        if picked.isEmpty {
            picked = lines
                .filter { !$0.hasPrefix("#") && !$0.hasPrefix("[") && !$0.hasPrefix("]") }
                .prefix(3)
                .map { $0 }
        }

        let note = picked
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " -*")) }
            .filter { !$0.isEmpty }
            .prefix(4)
            .joined(separator: "；")
        return note.isEmpty ? "按计划完成案例、代码和复盘。" : note
    }

    private static func scheduleBlocksFromDatedHeadings(_ text: String, anchorDateKey: String) -> [ScheduleBlock] {
        let lines = text.components(separatedBy: .newlines)
        let headingPattern = #"^\s*#+\s*([0-9]{1,2}|[一二三四五六七八九十]+)\s*月\s*([0-9]{1,2}|[一二三四五六七八九十]+)\s*(?:日|号)?\s*$"#
        guard let regex = try? NSRegularExpression(pattern: headingPattern) else { return [] }

        var currentDateKey: String?
        var blocks: [ScheduleBlock] = []

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            if let match = regex.firstMatch(in: line, range: range),
               match.numberOfRanges >= 3,
               let month = numberValue(nsLine.substring(with: match.range(at: 1))),
               let day = numberValue(nsLine.substring(with: match.range(at: 2))) {
                currentDateKey = DateKey.from(month: month, day: day, relativeTo: anchorDateKey)
                continue
            }

            guard let dateKey = currentDateKey else { continue }
            let cleaned = listItemTitle(from: cleanPlanLine(line))
            guard !cleaned.isEmpty, !cleaned.hasPrefix("```") else { continue }

            blocks.append(
                ScheduleBlock(
                    dateKey: dateKey,
                    timeLabel: "今日任务",
                    title: cleaned,
                    note: "按计划完成并复盘。",
                    category: category(from: cleaned)
                )
            )
        }

        return blocks
    }

    private static func scheduleBlocksFromSections(_ text: String, anchorDateKey: String) -> [ScheduleBlock] {
        let pattern = #"第\s*[0-9一二三四五六七八九十]+\s*次[:：]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard !matches.isEmpty else { return [] }

        return matches.enumerated().flatMap { index, match in
            let start = match.range.location
            let end = index + 1 < matches.count ? matches[index + 1].range.location : nsText.length
            let section = nsText.substring(with: NSRange(location: start, length: end - start))
            let keys = dateKeys(from: section, anchorDateKey: anchorDateKey)
            let title = taskTitle(fromSection: section)
            let note = sectionNote(fromSection: section)

            return keys.map { dateKey in
                ScheduleBlock(
                    dateKey: dateKey,
                    timeLabel: timeLabel(from: section, index: index),
                    title: title,
                    note: note,
                    category: category(from: section)
                )
            }
        }
    }

    private static func cleanPlanLine(_ line: String) -> String {
        line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-•*# "))
    }

    private static func listItemTitle(from line: String) -> String {
        line
            .replacingOccurrences(of: #"^\s*[0-9一二三四五六七八九十]+[\.\、\)]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func titleFromPlanLine(_ line: String) -> String {
        var title = line
        if let range = title.range(of: #"第?[0-9一二三四五六七八九十]+[天日周]"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        if let range = title.range(of: #"[0-9一二三四五六七八九十]{1,3}\s*月\s*[0-9一二三四五六七八九十]{1,3}\s*[日号]?"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        if let range = title.range(of: #"[0-2]?[0-9]:[0-5][0-9]([\-—~到][0-2]?[0-9]:[0-5][0-9])?"#, options: .regularExpression) {
            title.removeSubrange(range)
        }
        title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? line : title
    }

    private static func taskTitle(fromSection section: String) -> String {
        if let range = section.range(of: #"任务[:：]\s*([^\n。；;]+)"#, options: .regularExpression) {
            var title = String(section[range])
            title = title.replacingOccurrences(of: #"任务[:：]\s*"#, with: "", options: .regularExpression)
            title = title.trimmingCharacters(in: CharacterSet(charactersIn: " 。；;\n\t"))
            return title.isEmpty ? "复习任务" : title
        }

        return titleFromPlanLine(section)
    }

    private static func sectionNote(fromSection section: String) -> String {
        let lines = section
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { !$0.hasPrefix("第") && !$0.hasPrefix("任务") }

        return lines.prefix(3).joined(separator: "；").isEmpty ? "按计划完成并复盘。" : lines.prefix(3).joined(separator: "；")
    }

    private static func noteFromPlanLine(_ line: String, title: String) -> String {
        if line == title {
            return "按 35 分钟学习、5 分钟回顾的节奏执行。"
        }
        return line
    }

    private static func dateKeys(from text: String, anchorDateKey: String) -> [String] {
        if let relativeDay = relativeDayNumber(from: text),
           let dateKey = DateKey.addingDays(relativeDay - 1, to: anchorDateKey) {
            return [dateKey]
        }

        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{1,2}|[一二三四五六七八九十]+)\s*月\s*([0-9]{1,2}|[一二三四五六七八九十]+)"#) else {
            return [DateKey.today()]
        }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        var keys: [String] = []

        for match in matches {
            guard match.numberOfRanges >= 3,
                  let month = numberValue(nsText.substring(with: match.range(at: 1))),
                  let firstDay = numberValue(nsText.substring(with: match.range(at: 2))) else {
                continue
            }

            appendDateKey(month: month, day: firstDay, anchorDateKey: anchorDateKey, to: &keys)

            let tailStart = match.range.location + match.range.length
            let tail = nsText.substring(from: tailStart)
            for day in extraDays(afterMonthDayIn: tail) {
                appendDateKey(month: month, day: day, anchorDateKey: anchorDateKey, to: &keys)
            }
        }

        return keys.isEmpty ? [DateKey.today()] : Array(NSOrderedSet(array: keys)) as? [String] ?? keys
    }

    private static func relativeDayNumber(from text: String) -> Int? {
        guard let range = text.range(of: #"第\s*([0-9一二三四五六七八九十]+)\s*天"#, options: .regularExpression) else {
            return nil
        }

        let matched = String(text[range])
            .replacingOccurrences(of: "第", with: "")
            .replacingOccurrences(of: "天", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return numberValue(matched)
    }

    private static func appendDateKey(month: Int, day: Int, anchorDateKey: String, to keys: inout [String]) {
        guard (1...12).contains(month),
              (1...31).contains(day),
              let key = DateKey.from(month: month, day: day, relativeTo: anchorDateKey),
              !keys.contains(key) else {
            return
        }

        keys.append(key)
    }

    private static func extraDays(afterMonthDayIn tail: String) -> [Int] {
        var days: [Int] = []
        var index = tail.startIndex

        while index < tail.endIndex {
            while index < tail.endIndex {
                let character = tail[index]
                if character == "日" || character == "号" || character == " " || character == "、" || character == "," || character == "，" || character == "/" || character == "和" || character == "及" {
                    index = tail.index(after: index)
                } else {
                    break
                }
            }

            let start = index
            while index < tail.endIndex, tail[index].isNumber {
                index = tail.index(after: index)
            }

            guard start != index else { break }
            let value = Int(tail[start..<index]) ?? 0
            guard (1...31).contains(value) else { break }
            days.append(value)
        }

        return days
    }

    private static func numberValue(_ text: String) -> Int? {
        if let value = Int(text) {
            return value
        }

        let digits: [Character: Int] = [
            "零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
            "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
        ]

        if text.count == 1, let character = text.first, let value = digits[character] {
            return value
        }
        if text == "十" { return 10 }
        if text.hasPrefix("十"), let last = text.last, let value = digits[last] {
            return 10 + value
        }
        if text.hasSuffix("十"), let first = text.first, let value = digits[first] {
            return value * 10
        }
        if text.contains("十") {
            let parts = text.split(separator: "十")
            guard let first = parts.first?.first,
                  let firstValue = digits[first],
                  let last = parts.last?.first,
                  let lastValue = digits[last] else {
                return nil
            }
            return firstValue * 10 + lastValue
        }

        return nil
    }

    private static func timeLabel(from line: String, index: Int) -> String {
        if let range = line.range(of: #"[0-2]?[0-9]:[0-5][0-9]([\-—~到][0-2]?[0-9]:[0-5][0-9])?"#, options: .regularExpression) {
            return String(line[range])
        }
        let fallback = ["08:00", "10:00", "14:30", "19:30", "21:00"]
        return fallback[index % fallback.count]
    }

    private static func category(from line: String) -> String {
        if line.contains("词") { return "词汇" }
        if line.contains("听") { return "听力" }
        if line.contains("读") || line.contains("阅读") { return "阅读" }
        if line.contains("写") || line.contains("翻译") { return "输出" }
        return "复习"
    }
}
