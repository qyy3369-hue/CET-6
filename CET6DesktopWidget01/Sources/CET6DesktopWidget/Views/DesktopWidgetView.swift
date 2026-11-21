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
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(GoalsButtonStyle(.icon))
                .accessibilityLabel("打开学习窗口")
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
            RoundedRectangle(cornerRadius: 16)
                .fill(StudyTheme.paper)
                .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(StudyTheme.hairline) }
        }
        .clipShape(.rect(cornerRadius: 16))
        .shadow(color: .black.opacity(0.10), radius: 14, x: 0, y: 6)
        .onReceive(NotificationCenter.default.publisher(for: .goalSelectionDidChange)) { _ in
            refreshSelectedGoal()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("今天")
                    .font(StudyTheme.heading(size: 25, weight: .semibold))
                    .foregroundStyle(StudyTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                goalMenu
            }
            Text(selectedGoalID == Self.allGoalsID ? "所有任务" : selectedGoalTitle)
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
            GoalsButtonFace(
                label: Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24),
                kind: .icon
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .accessibilityLabel("切换日程项目")
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
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(StudyTheme.ink)
                .goalsInput(minHeight: 34)
                .onSubmit(addTask)

            Button(action: addTask) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(GoalsButtonStyle(.icon, tint: StudyTheme.blue))
            .accessibilityLabel("添加任务")
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
                                        .foregroundStyle(task.isDone ? StudyTheme.quietGreen : StudyTheme.mutedInk)
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
                                .padding(.horizontal, 5)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(GoalsButtonStyle(.row))
                            .accessibilityValue(task.isDone ? "已完成" : "待完成")
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
        if targetGoal.id == Self.allGoalsID {
            store.addTaskForToday(newTaskTitle, goalID: "unassigned", goalTitle: "未归类")
        } else {
            store.addTaskForToday(newTaskTitle, goalID: targetGoal.id, goalTitle: targetGoal.title)
        }
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
        guard let goal else { return (allGoalsID, "所有") }
        return (goal.id, goal.title)
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

private struct DesktopWidgetPreview: PreviewProvider {
    static var previews: some View {
        DesktopWidgetView(store: TaskStore()) {}
    }
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

    var icon: String {
        switch self {
        case .goals: "rectangle.grid.2x2"
        case .plan: "doc.text"
        case .today: "calendar"
        case .words: "book.closed"
        case .translation: "character.book.closed"
        case .writing: "pencil.and.outline"
        case .roots: "point.3.connected.trianglepath.dotted"
        case .flashcards: "rectangle.stack"
        case .mistakes: "bookmark"
        }
    }

    var tint: Color { StudyTheme.blue }
}

struct VocabularyWord: Codable, Equatable, Identifiable, Sendable {
    static let pendingMeaning = "自定义词，待补充释义"
    static let restoredPendingMeaning = "历史已斩词；恢复后可在单词本中补充释义"

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

    var needsMeaning: Bool { Self.isMissingMeaning(meaning) }

    static func isMissingMeaning(_ meaning: String) -> Bool {
        switch meaning.trimmingCharacters(in: .whitespacesAndNewlines) {
        case "", pendingMeaning, restoredPendingMeaning: true
        default: false
        }
    }

    static func starterExample(for word: String) -> String {
        "Write your own sentence with \(word)."
    }

    func fillingMeaning(from result: WordLookupResult) -> VocabularyWord {
        let needsExample = example.isEmpty || example == Self.starterExample(for: word)
        return VocabularyWord(
            id: id,
            word: word,
            phonetic: phonetic.isEmpty ? result.phonetic : phonetic,
            partOfSpeech: partOfSpeech.isEmpty || partOfSpeech == "未标注" ? result.partOfSpeech : partOfSpeech,
            meaning: result.meaning,
            example: needsExample && !result.example.isEmpty ? result.example : example,
            exampleTranslation: needsExample && !result.example.isEmpty ? result.exampleTranslation : exampleTranslation,
            phrases: phrases.isEmpty ? result.phrases : phrases,
            phraseTranslations: phrases.isEmpty ? result.phraseTranslations : phraseTranslations,
            mnemonic: mnemonic.isEmpty ? result.mnemonic : mnemonic,
            tag: tag.isEmpty || tag == "自定义" ? result.tag : tag,
            difficulty: difficulty
        )
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
    case due
    case all
    case favorites
    case hard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .due: "到期优先"
        case .all: "全部"
        case .favorites: "收藏"
        case .hard: "高难"
        }
    }
}

private enum FlashcardReviewFocus01: Hashable {
    case workspace
    case answer
    case correction
}

private enum MistakeMode: String, CaseIterable, Identifiable {
    case favorites
    case hard
    case banished

    var id: String { rawValue }

    var title: String {
        switch self {
        case .favorites: "已收藏"
        case .hard: "高难候选"
        case .banished: "已斩"
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

// Goals console · neutral surfaces, hairline borders, and short transitions
// Pre-emit critique: Philosophy 4, Hierarchy 5, Execution 4, Specificity 4, Restraint 5, Variety 4.
enum StudyTheme {
    static let windowBase = surface(light: 0xF7F7F7, dark: 0x141414)
    static let sidebarBase = surface(light: 0xFAFAFA, dark: 0x171717)
    static let paper = surface(light: 0xFFFFFF, dark: 0x1D1D1D)
    static let panelBase = paper
    static let panelStrong = paper
    static let field = surface(light: 0xF2F2F2, dark: 0x262626)
    static let hairline = surface(light: 0xE5E5E5, dark: 0x343434)
    static let focusBorder = surface(light: 0x777777, dark: 0xA3A3A3)
    static let ink = surface(light: 0x171717, dark: 0xF3F3F3)
    static let sidebarInk = surface(light: 0x555555, dark: 0xB7B7B7)
    static let secondaryInk = surface(light: 0x555555, dark: 0xB5B5B5)
    static let mutedInk = surface(light: 0x6B6B6B, dark: 0xA3A3A3)

    static let blue = surface(light: 0x285C9C, dark: 0xA3C7FF)
    static let command = surface(light: 0x222222, dark: 0x454545)
    static let quietGreen = surface(light: 0x217153, dark: 0x78D2A9)
    static let cinnabar = surface(light: 0xAE3B48, dark: 0xFF9CA8)
    static let ochre = surface(light: 0x8B5B14, dark: 0xF3BC69)
    static let indigo = blue
    static let selection = surface(light: 0xE8F0FC, dark: 0x233348)
    static let buttonSurface = surface(light: 0xFDFCFB, dark: 0x242423)
    static let buttonPrimary = surface(light: 0xEDEAE6, dark: 0x333230)
    static let buttonSelected = surface(light: 0xE9E6E2, dark: 0x3A3835)
    static let buttonBorder = surface(light: 0xE0DCD7, dark: 0x454340)
    static let buttonBorderStrong = surface(light: 0xC9C4BE, dark: 0x605B56)
    static let buttonDestructive = surface(light: 0xF8E9EB, dark: 0x39272A)

    static func heading(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }

    private static func surface(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: Double((hex >> 16) & 0xff) / 255,
                green: Double((hex >> 8) & 0xff) / 255,
                blue: Double(hex & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

struct StudyWindowView: View {
    private enum ConsoleOverlay {
        case search
        case goals
    }

    private static let sidebarWidth: CGFloat = 248

    private static let emptyPlan = GoalPlanSheet(
        id: "empty-plan",
        title: "暂无计划",
        planText: "",
        createdAt: Date(timeIntervalSinceReferenceDate: 0),
        updatedAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    private static let emptyGoal = GoalPlan(
        id: "empty-goal",
        title: "暂无目标",
        mode: "",
        focus: "",
        plans: []
    )

    @ObservedObject var store: TaskStore
    @ObservedObject var widgetVisibility: WidgetVisibilityController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("Goals.console.sidebarVisible") private var sidebarVisible = true
    @State private var consoleOverlay: ConsoleOverlay?
    @State private var plansExpanded = false
    @State private var vocabularyExpanded = true
    @State private var practiceExpanded = true
    @State private var selectedCategory: StudyCategory = .goals
    @State private var settingsPane: GoalsSettingsPane?
    @State private var showsNewGoal = false
    @State private var newGoalError: String?
    @State private var todayGoalID: String?
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
    @State private var generatedAIPlan: (planID: String, text: String)?
    @State private var aiPlanStatus = "填写目标背景后，AI 会生成一份可保存、可同步的计划。"
    @State private var isRevisingPlan = false
    @State private var quickTaskTitle = ""
    @State private var newGoalTitle = ""
    @State private var newGoalMode = "生活目标"
    @State private var newGoalFocus = ""
    @State private var newPlanTitle = ""
    @State private var goalStatus = ""
    @State private var wordSearch = ""
    @State private var newWordText = ""
    @FocusState private var isWordSearchFocused: Bool
    @State private var expandedWordIDs: Set<String> = []
    @State private var wordBankStatus = ""
    @State private var isCompletingWord = false
    @State private var completingMeaningIDs: Set<String> = []
    @State private var showsImageWordImport = false
    @State private var customWords: [VocabularyWord]
    @State private var isLoadingCustomWords = false
    @State private var customWordsLoadGeneration = 0
    @State private var favoriteWordIDs: Set<String> = []
    @State private var deletedWordIDs: Set<String>
    @State private var banishedWordKeys: Set<String>
    @State private var banishedWordRecords: [BanishedVocabularyRecord01]
    @State private var lastBanishedRecord: BanishedVocabularyRecord01?
    @State private var banishUndoTask: Task<Void, Never>?
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
    @State private var frontMnemonics = FlashcardMnemonicStore.load()
    @State private var isGeneratingFrontMnemonics = false
    @State private var failedFrontMnemonics: [String: String] = [:]
    @State private var reviewMode: WordReviewMode = .due
    @State private var reviewAnswer = ""
    @State private var reviewJudgment: VocabularyAnswerJudgment?
    @State private var reviewedWordID: String?
    @State private var reviewCorrectionAnswer = ""
    @State private var hasCompletedReviewCorrection = false
    @State private var reviewStatus = "输入一个核心中文含义；输入 、 可直接标记为不认识。"
    @State private var isJudgingReviewAnswer = false
    @State private var reviewProgressByWordID: [String: FlashcardReviewProgress01]
    @State private var reviewDismissedWordIDs: Set<String>
    @StateObject private var vocabularySpeech = VocabularySpeechService01()
    @State private var lastAutoSpokenWordID: String?
    @State private var pendingVocabularySpeechTask: Task<Void, Never>?
    @FocusState private var flashcardReviewFocus: FlashcardReviewFocus01?
    @State private var rootSearch = ""
    @State private var mistakeSearch = ""
    @State private var mistakeMode: MistakeMode = .favorites

    init(store: TaskStore, widgetVisibility: WidgetVisibilityController = WidgetVisibilityController()) {
        self.store = store
        self.widgetVisibility = widgetVisibility
        let loadedGoals = GoalPlanStore01.load(defaultPlanText: Self.defaultPlanText)
        let preferredGoalID = GoalPlanStore01.loadSelectedGoalID()
        let selectedGoal = loadedGoals.first { $0.id == preferredGoalID } ?? loadedGoals.first ?? Self.emptyGoal
        let preferredPlanID = GoalPlanStore01.loadSelectedPlanID()
        let selectedPlan = selectedGoal.plans.first { $0.id == preferredPlanID } ?? selectedGoal.plans.first ?? Self.emptyPlan
        let plan = selectedPlan.planText
        _goals = State(initialValue: loadedGoals)
        _selectedGoalID = State(initialValue: selectedGoal.id)
        _selectedPlanID = State(initialValue: selectedPlan.id)
        _planText = State(initialValue: plan)
        let initialBlocks = selectedPlan.generatedSchedule ?? Self.generateSchedule(from: plan, anchorDateKey: DateKey.from(selectedPlan.createdAt))
        _scheduleBlocks = State(initialValue: store.resolvedPlanBlocks(initialBlocks, goalID: selectedGoal.id, planID: selectedPlan.id))
        _customWords = State(initialValue: [])
        let initialFavoriteWordIDs = Self.loadFavoriteWordIDs()
        let initialReviewProgress = FlashcardReviewStore01.load()
        let inferredDismissedWordIDs = FlashcardReviewQueue01.inferredDismissedWordIDs(
            progressByWordID: initialReviewProgress,
            favoriteWordIDs: initialFavoriteWordIDs
        )
        let initialDismissedWordIDs = Self.loadReviewDismissedWordIDs().union(inferredDismissedWordIDs)
        Self.saveReviewDismissedWordIDs(initialDismissedWordIDs)
        let preparedBanishedLibrary = Self.prepareBanishedVocabularyLibrary()
        let initialBanishedRecords = preparedBanishedLibrary.records
        let initialBanishedKeys = preparedBanishedLibrary.keys
        _favoriteWordIDs = State(initialValue: initialFavoriteWordIDs)
        _deletedWordIDs = State(initialValue: Self.loadDeletedWordIDs())
        _banishedWordKeys = State(initialValue: initialBanishedKeys)
        _banishedWordRecords = State(initialValue: initialBanishedRecords)
        _translationRecords = State(initialValue: Self.loadTranslationRecords())
        _writingRecords = State(initialValue: Self.loadWritingRecords())
        _reviewProgressByWordID = State(initialValue: initialReviewProgress)
        _reviewDismissedWordIDs = State(initialValue: initialDismissedWordIDs)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            consoleLayout
                .allowsHitTesting(consoleOverlay == nil)
                .accessibilityHidden(consoleOverlay != nil)

            if consoleOverlay == .goals {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { showConsoleOverlay(nil) }
                    .accessibilityHidden(true)
                consoleGoalMenu
                    .padding(.top, 60)
                    .padding(.leading, 12)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95, anchor: .topLeading)))
                    .zIndex(1)
            }

            if consoleOverlay == .search {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay { StudyTheme.windowBase.opacity(0.32) }
                    .onTapGesture { showConsoleOverlay(nil) }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                    .zIndex(2)

                ConsoleCommandPalette(search: consoleCommands) { showConsoleOverlay(nil) }
                    .frame(maxWidth: 540)
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 90)
                    .onExitCommand { showConsoleOverlay(nil) }
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
                    .zIndex(3)
            }
        }
        .frame(minWidth: 940, minHeight: 586)
        .background(StudyTheme.windowBase)
        .foregroundStyle(StudyTheme.ink)
        .tint(StudyTheme.blue)
        .sheet(item: $settingsPane) { pane in
            GoalsSettingsView(display: widgetVisibility, speech: vocabularySpeech, initialPane: pane)
        }
        .sheet(isPresented: $showsNewGoal) {
            newGoalForm
        }
        .sheet(isPresented: $showsImageWordImport) {
            ImageVocabularyImportView(onImport: importImageWords)
        }
        .onChange(of: goals.map(\.id)) { _, goalIDs in
            if let todayGoalID, !goalIDs.contains(todayGoalID) {
                self.todayGoalID = nil
            }
        }
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
        .onChange(of: reviewProgressByWordID) { _, newValue in
            do {
                try FlashcardReviewStore01.save(newValue)
            } catch {
                reviewStatus = "复习结果已更新，但进度文件保存失败：\(error.localizedDescription)"
            }
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

    private var consoleLayout: some View {
        HStack(spacing: 0) {
            ZStack(alignment: .trailing) {
                if sidebarVisible {
                    sidebar
                        .frame(width: Self.sidebarWidth)
                        .transition(.opacity)
                }
            }
            .frame(width: sidebarVisible ? Self.sidebarWidth : 0, alignment: .trailing)
            .clipped()
            .allowsHitTesting(sidebarVisible)
            .accessibilityHidden(!sidebarVisible)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: sidebarVisible)

            VStack(spacing: 0) {
                consoleToolbar
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var consoleToolbar: some View {
        HStack(spacing: 9) {
            Button {
                sidebarVisible.toggle()
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 16))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(GoalsButtonStyle(.row))
            .accessibilityLabel(sidebarVisible ? "收起侧栏" : "展开侧栏")
            .help(sidebarVisible ? "收起侧栏" : "展开侧栏")

            Divider().frame(height: 17)

            Text(consoleContextTitle)
                .foregroundStyle(StudyTheme.mutedInk)
                .lineLimit(1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(StudyTheme.mutedInk)
                .accessibilityHidden(true)
            Text(selectedCategory.title)
                .fontWeight(.medium)
                .lineLimit(1)

            Spacer(minLength: 12)

            Button {
                showConsoleOverlay(.search)
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                    Text("快速搜索")
                    Spacer(minLength: 8)
                    ConsoleKeycap("⌘K")
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 9)
                .frame(width: 180, height: 30)
            }
            .buttonStyle(GoalsButtonStyle(.icon))
            .keyboardShortcut("k", modifiers: .command)

            if !sidebarVisible {
                Button {
                    settingsPane = .general
                } label: {
                    Image(systemName: "gearshape").frame(width: 30, height: 30)
                }
                .buttonStyle(GoalsButtonStyle(.row))
                .keyboardShortcut(",", modifiers: .command)
                .accessibilityLabel("设置")
                .help("设置")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 15)
        .frame(height: 51)
        .background(StudyTheme.paper)
        .overlay(alignment: .bottom) { Rectangle().fill(StudyTheme.hairline).frame(height: 1) }
    }

    private var consoleContextTitle: String {
        if selectedCategory == .plan, !goals.isEmpty { return currentGoal.title }
        if selectedCategory == .today, let todayGoalID,
           let goal = goals.first(where: { $0.id == todayGoalID }) { return goal.title }
        return "Goals"
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 13) {
            Button {
                showConsoleOverlay(.goals)
            } label: {
                HStack(spacing: 10) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                        .frame(width: 32, height: 32)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(goals.isEmpty ? "Goals" : currentGoal.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(StudyTheme.ink)
                        Text(goals.isEmpty ? "暂无目标" : currentGoal.mode)
                            .font(.system(size: 11))
                            .foregroundStyle(StudyTheme.mutedInk)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(StudyTheme.mutedInk)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 6)
            }
            .buttonStyle(GoalsButtonStyle(.row))
            .accessibilityLabel(goals.isEmpty ? "选择目标，暂无目标" : "切换目标，当前为 \(currentGoal.title)")

            ScrollView {
                VStack(alignment: .leading, spacing: 13) {
                    VStack(spacing: 2) {
                        sidebarButton(for: .goals)
                        sidebarButton(for: .today)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        sidebarHeading("工作区")
                        sidebarButton(for: .plan)
                        if !goals.isEmpty {
                            sidebarDisclosure("计划表", icon: "folder", expanded: $plansExpanded) {
                                ForEach(currentGoal.plans) { plan in
                                    sidebarRow(plan.title, icon: "number", isSelected: selectedCategory == .plan && selectedPlanID == plan.id) {
                                        openConsolePlan(plan, in: currentGoal)
                                    }
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        sidebarHeading("英语学习")
                        sidebarDisclosure("词汇", icon: "books.vertical", expanded: $vocabularyExpanded) {
                            ForEach([StudyCategory.words, .flashcards, .mistakes], content: sidebarButton)
                        }
                        sidebarDisclosure("语言练习", icon: "character.bubble", expanded: $practiceExpanded) {
                            ForEach([StudyCategory.translation, .writing, .roots], content: sidebarButton)
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            VStack(alignment: .leading, spacing: 7) {
                progressSummary.padding(.horizontal, 8)
                Rectangle().fill(StudyTheme.hairline).frame(height: 1)
                sidebarRow("设置", icon: "gearshape", shortcut: "⌘,") {
                    settingsPane = .general
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        .padding(12)
        .background(StudyTheme.sidebarBase)
        .overlay(alignment: .trailing) { Rectangle().fill(StudyTheme.hairline).frame(width: 1) }
    }

    private func sidebarHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(StudyTheme.mutedInk)
            .padding(.leading, 9)
            .padding(.bottom, 3)
            .accessibilityAddTraits(.isHeader)
    }

    private func sidebarDisclosure<Content: View>(
        _ title: String, icon: String, expanded: Binding<Bool>, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 2) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                    expanded.wrappedValue.toggle()
                }
            } label: {
                HStack(spacing: 9) {
                    Image(systemName: icon).frame(width: 16)
                    Text(title)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded.wrappedValue ? 90 : 0))
                        .accessibilityHidden(true)
                }
                .font(.system(size: 13))
                .padding(.horizontal, 9)
                .frame(height: 30)
            }
            .buttonStyle(GoalsButtonStyle(.row))
            .accessibilityValue(expanded.wrappedValue ? "已展开" : "已折叠")

            if expanded.wrappedValue {
                VStack(spacing: 2, content: content)
                    .padding(.leading, 16)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(StudyTheme.hairline).frame(width: 1).padding(.leading, 16)
                    }
                    .padding(.leading, 1)
                    .transition(.opacity)
            }
        }
    }

    private var consoleGoalMenu: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !goals.isEmpty {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(goals) { goal in
                            sidebarRow(goal.title, icon: goal.id == selectedGoalID ? "checkmark" : "target", isSelected: goal.id == selectedGoalID) {
                                showConsoleOverlay(nil)
                                selectedGoalID = goal.id
                                if selectedCategory == .today { todayGoalID = goal.id }
                            }
                        }
                    }
                }
                .frame(height: min(CGFloat(goals.count) * 32, 224))

                Rectangle().fill(StudyTheme.hairline).frame(height: 1).padding(.vertical, 2)
            }

            sidebarRow("新建目标", icon: "plus") {
                showConsoleOverlay(nil)
                openNewGoalForm()
            }
            Button("关闭", action: { showConsoleOverlay(nil) })
                .keyboardShortcut(.cancelAction)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .padding(6)
        .frame(width: Self.sidebarWidth - 24)
        .background(StudyTheme.paper, in: .rect(cornerRadius: 8))
        .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(StudyTheme.hairline) }
        .shadow(color: .black.opacity(0.16), radius: 14, x: 0, y: 7)
    }

    private func showConsoleOverlay(_ overlay: ConsoleOverlay?) {
        let isSearch = (overlay ?? consoleOverlay) == .search
        withAnimation(reduceMotion ? nil : .easeOut(duration: isSearch ? 0.2 : 0.1)) {
            consoleOverlay = overlay
        }
    }

    private func consoleCommands(_ query: String) -> [ConsoleCommand] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pages: [StudyCategory] = [.goals, .today, .plan, .words, .flashcards, .mistakes, .translation, .writing, .roots]
        let pageCommands = pages.compactMap { page -> ConsoleCommand? in
            guard query.isEmpty || page.title.localizedStandardContains(query) else { return nil }
            return ConsoleCommand(id: "page-\(page.id)", title: page.title, detail: "页面", icon: page.icon) {
                selectedCategory = page
            }
        }
        let actions = [
            ConsoleCommand(id: "settings", title: "设置", detail: "操作", icon: "gearshape") { settingsPane = .general },
            ConsoleCommand(id: "deepseek", title: "DeepSeek 设置", detail: "操作", icon: "terminal") { settingsPane = .deepSeek },
            ConsoleCommand(id: "create-goal", title: "新建目标", detail: "操作", icon: "plus", action: openNewGoalForm)
        ].filter { query.isEmpty || $0.title.localizedStandardContains(query) }
        guard !query.isEmpty else { return pageCommands + actions }

        var matches = pageCommands + actions
        for goal in goals {
            let matchesGoal = goal.title.localizedStandardContains(query)
            if matchesGoal {
                matches.append(ConsoleCommand(id: "goal-\(goal.id)", title: goal.title, detail: "目标", icon: "target") {
                    selectedGoalID = goal.id
                    selectedCategory = .goals
                })
            }
            for plan in goal.plans where matchesGoal || plan.title.localizedStandardContains(query) {
                matches.append(ConsoleCommand(id: "plan-\(goal.id)-\(plan.id)", title: plan.title, detail: goal.title, icon: "doc.text") {
                    openConsolePlan(plan, in: goal)
                })
            }
        }
        for word in allWords.lazy.filter({
            $0.word.localizedStandardContains(query) || $0.meaning.localizedStandardContains(query)
        }).prefix(12) {
            matches.append(ConsoleCommand(id: "word-\(word.id)", title: word.word, detail: "单词本", icon: "book.closed") {
                wordSearch = word.word
                selectedCategory = .words
            })
        }
        return matches
    }

    private func openNewGoalForm() {
        newGoalError = nil
        showsNewGoal = true
    }

    private func openConsolePlan(_ plan: GoalPlanSheet, in goal: GoalPlan) {
        selectedGoalID = goal.id
        selectedPlanID = plan.id
        planWorkspaceMode = .manual
        selectedCategory = .plan
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                Text(selectedCategory.title)
                    .font(StudyTheme.heading(size: 28, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()

                if selectedCategory == .plan && !goals.isEmpty {
                    currentTargetPicker
                }
                if selectedCategory == .goals && !goals.isEmpty {
                    Button(action: openNewGoalForm) {
                        Label("新建目标", systemImage: "plus")
                    }
                    .buttonStyle(GoalsButtonStyle(.primary))
                }
                if selectedCategory == .flashcards {
                    Button {
                        settingsPane = .speech
                    } label: {
                        Label("朗读设置", systemImage: "speaker.wave.2")
                    }
                    .buttonStyle(GoalsButtonStyle())
                }
            }
            .padding(.horizontal, 26)
            .padding(.top, 22)
            .padding(.bottom, 18)

            ZStack {
                Group {
                    switch selectedCategory {
                    case .goals: goalsWorkspace
                    case .plan: combinedPlanWorkspace
                    case .today: todayWorkspace
                    case .words: wordBankWorkspace
                    case .translation: translationWorkspace
                    case .writing: writingWorkspace
                    case .roots: rootsWorkspace
                    case .flashcards: flashcardWorkspace
                    case .mistakes: mistakeWorkspace
                    }
                }
                .id(selectedCategory)
                .transition(workspaceTransition)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: selectedCategory)
            .padding(.horizontal, 26)
            .padding(.bottom, 22)
        }
    }

    private var workspaceTransition: AnyTransition {
        reduceMotion ? .identity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: 5)),
            removal: .opacity
        )
    }

    private var currentGoal: GoalPlan {
        goals.first { $0.id == selectedGoalID } ?? goals.first ?? Self.emptyGoal
    }

    private var currentPlan: GoalPlanSheet {
        currentGoal.plans.first { $0.id == selectedPlanID } ?? currentGoal.plans.first ?? Self.emptyPlan
    }

    private func resolvedScheduleBlocks(from text: String) -> [ScheduleBlock] {
        store.resolvedPlanBlocks(
            Self.generateSchedule(from: text, anchorDateKey: DateKey.from(currentPlan.createdAt)),
            goalID: currentGoal.id,
            planID: currentPlan.id
        )
    }

    private var currentTargetPicker: some View {
        HStack(spacing: 8) {
            GoalsMenuPicker(title: "当前目标", selection: $selectedGoalID, options: goals.map { ($0.id, $0.title) })
            .frame(width: 170)

            GoalsMenuPicker(title: "当前计划表", selection: $selectedPlanID, options: currentGoal.plans.map { ($0.id, $0.title) })
            .frame(width: 150)
        }
    }

    private var progressSummary: some View {
        let tasks = store.todayTasks
        let done = tasks.filter(\.isDone).count

        return Button {
            selectedCategory = .today
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Text("今日完成")
                    Spacer()
                    Text("\(done) / \(tasks.count)")
                        .monospacedDigit()
                }
                .font(.system(size: 12, weight: .medium))
                ProgressView(value: Double(done), total: Double(max(tasks.count, 1)))
                    .tint(StudyTheme.blue)
                    .labelsHidden()
            }
            .foregroundStyle(StudyTheme.secondaryInk)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
        }
        .buttonStyle(GoalsButtonStyle(.row))
        .accessibilityLabel("今日完成 \(done) 项，共 \(tasks.count) 项")
    }

    private func sidebarButton(for category: StudyCategory) -> some View {
        let pending = category == .today ? store.todayTasks.filter { !$0.isDone }.count : 0
        return sidebarRow(category.title, icon: category.icon, isSelected: selectedCategory == category, badge: pending) {
            selectedCategory = category
        }
    }

    private func sidebarRow(
        _ title: String, icon: String, isSelected: Bool = false, badge: Int = 0,
        shortcut: String? = nil, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(StudyTheme.blue)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 18)
                        .background(StudyTheme.selection, in: .capsule)
                        .accessibilityLabel("\(badge) 项待完成")
                }
                if let shortcut {
                    ConsoleKeycap(shortcut).accessibilityHidden(true)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 9)
            .frame(height: 30)
        }
        .buttonStyle(GoalsButtonStyle(.row, selected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var goalsWorkspace: some View {
        let tasks = store.todayTasks
        let complete = tasks.filter(\.isDone).count

        return VStack(spacing: 16) {
            HStack(spacing: 14) {
                consoleOverviewCard("今日任务", value: "\(complete) / \(tasks.count)", icon: "calendar") {
                    todayGoalID = nil
                    selectedCategory = .today
                }
                consoleOverviewCard("单词本", value: "\(allWords.count) 个单词", icon: "book.closed") {
                    wordSearch = ""
                    selectedCategory = .words
                }
            }
            goalDirectory
        }
    }

    private func consoleOverviewCard(_ title: String, value: String, icon: String, open: @escaping () -> Void) -> some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Image(systemName: icon).accessibilityHidden(true)
                    Text(title)
                    Spacer()
                    Image(systemName: "arrow.up.right").accessibilityHidden(true)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(StudyTheme.secondaryInk)
                Text(value)
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(StudyTheme.ink)
            }
            .padding(15)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(GoalsButtonStyle(.card))
    }

    private var goalDirectory: some View {
        Group {
            if goals.isEmpty {
                ContentUnavailableView {
                    Label("暂无目标", systemImage: "target")
                } description: {
                    Text("新建目标后，就可以在里面编辑计划表和安排任务。")
                } actions: {
                    Button(action: openNewGoalForm) {
                        Label("新建目标", systemImage: "plus")
                    }
                    .buttonStyle(GoalsButtonStyle(.primary))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(StudyTheme.paper, in: .rect(cornerRadius: 14))
                .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(StudyTheme.hairline) }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("我的目标").font(.headline)
                            Spacer()
                            Text("\(goals.count)").monospacedDigit()
                                .foregroundStyle(StudyTheme.secondaryInk)
                        }

                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(goals, content: goalCard)
                            }
                        }
                    }
                    .frame(width: 218)

                    VStack(alignment: .leading, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(currentGoal.title)
                                .font(.system(size: 25, weight: .semibold))
                            Text([currentGoal.mode, currentGoal.focus].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.callout)
                                .foregroundStyle(StudyTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StudyTheme.paper, in: .rect(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(StudyTheme.hairline) }

                        HStack(spacing: 10) {
                            Text("计划表")
                                .font(.headline)
                            Spacer()
                            TextField("新计划表名称（选填）", text: $newPlanTitle)
                                .goalsInput()
                                .frame(maxWidth: 180)
                                .onSubmit(addPlanToCurrentGoal)

                            Button(action: addPlanToCurrentGoal) {
                                Label("新建计划表", systemImage: "plus")
                            }
                            .buttonStyle(GoalsButtonStyle())
                        }

                        if !goalStatus.isEmpty {
                            Text(goalStatus)
                                .font(.callout)
                                .foregroundStyle(StudyTheme.secondaryInk)
                        }

                        ScrollView {
                            LazyVStack(spacing: 8) {
                                ForEach(currentGoal.plans, content: planSheetCard)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var newGoalForm: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("新建目标")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 6) {
                Text("目标名称").font(.headline)
                TextField("例如：六级备考", text: $newGoalTitle)
                    .goalsInput()
                    .accessibilityLabel("目标名称")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("类型").font(.headline)
                TextField("例如：考试冲刺、长期项目", text: $newGoalMode)
                    .goalsInput()
                    .accessibilityLabel("目标类型")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("重点（选填）").font(.headline)
                TextField("写下这个目标最重要的事", text: $newGoalFocus)
                    .goalsInput()
                    .accessibilityLabel("目标重点")
            }

            if let newGoalError {
                Text(newGoalError)
                    .font(.callout)
                    .foregroundStyle(StudyTheme.cinnabar)
            }

            HStack {
                Spacer()
                Button("取消") { showsNewGoal = false }
                    .buttonStyle(GoalsButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("创建", action: addGoal)
                    .buttonStyle(GoalsButtonStyle(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(newGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 410)
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
        }
        .buttonStyle(GoalsButtonStyle(.card, selected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
        }
        .buttonStyle(GoalsButtonStyle(.card, selected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder
    private var combinedPlanWorkspace: some View {
        if goals.isEmpty {
            ContentUnavailableView {
                Label("暂无计划表", systemImage: "doc.text")
            } description: {
                Text("先创建目标，再写计划或用 DeepSeek 生成草稿。")
            } actions: {
                Button(action: openNewGoalForm) {
                    Label("新建目标", systemImage: "plus")
                }
                .buttonStyle(GoalsButtonStyle(.primary))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(StudyTheme.paper, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(StudyTheme.hairline) }
        } else {
            activePlanWorkspace
        }
    }

    private var activePlanWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                GoalsSegmentedControl(
                    title: "计划模式",
                    selection: $planWorkspaceMode,
                    options: PlanWorkspaceMode.allCases.map { ($0, $0.title) }
                )
                .frame(width: 260)

                Spacer()
            }

            ZStack {
                Group {
                    switch planWorkspaceMode {
                    case .manual: planWorkspace
                    case .ai: aiPlanWorkspace
                    }
                }
                .id(planWorkspaceMode)
                .transition(workspaceTransition)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: planWorkspaceMode)
        }
    }

    private var planWorkspace: some View {
        HStack(alignment: .top, spacing: 18) {
            planEditorPane
            .frame(idealWidth: 326, maxWidth: 356)

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
                    .buttonStyle(GoalsButtonStyle(.primary))
                    .tint(StudyCategory.plan.tint)
                    .disabled(isGeneratingSchedule)

                    Button {
                        copyScheduleToPasteboard()
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(GoalsButtonStyle())
                    .disabled(scheduleBlocks.isEmpty)

                    Button {
                        syncPlanTasks()
                    } label: {
                        Label("同步到任务库", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(GoalsButtonStyle(tint: StudyCategory.plan.tint))
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
                .buttonStyle(GoalsButtonStyle())

                Button {
                    savePlan()
                } label: {
                    Label("保存计划书", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(GoalsButtonStyle(.primary))
                .tint(StudyCategory.plan.tint)
            }
            TextEditor(text: $planText)
                .font(StudyTheme.heading(size: 14))
                .foregroundStyle(StudyTheme.ink)
                .scrollContentBackground(.hidden)
                .goalsInput(vertical: 10, radius: 12)
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
            .buttonStyle(GoalsButtonStyle(.primary))
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
                    .foregroundStyle(isDone ? StudyTheme.quietGreen : StudyTheme.mutedInk)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(GoalsButtonStyle(.icon))
            .accessibilityLabel(isDone ? "标记为未完成" : "标记完成")
            .help(isDone ? "标记为未完成" : "标记完成")

            VStack {
                Text(block.dateLabel)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(StudyTheme.blue)
                    .frame(width: 104, height: 28)
                    .background(StudyTheme.selection)
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
                    .goalsInput(vertical: 10, radius: 12)

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
                    .buttonStyle(GoalsButtonStyle(.primary))
                    .tint(StudyCategory.plan.tint)
                    .disabled(isRevisingPlan)
                }
            }
            .frame(idealWidth: 326, maxWidth: 356)

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
                    .buttonStyle(GoalsButtonStyle())
                    .disabled(aiPlanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button {
                        syncAIPlanDraft()
                    } label: {
                        Label("同步任务", systemImage: "arrow.triangle.2.circlepath")
                    }
                    .buttonStyle(GoalsButtonStyle(.primary))
                    .tint(StudyCategory.plan.tint)
                    .disabled(aiPlanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if aiPlanDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    emptyPanel("还没有 AI 计划", hint: "在左侧写清楚目标、期限、每天可用时间、薄弱项和偏好，点击“AI 定计划”。")
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(aiPlanDraft)
                                .font(StudyTheme.heading(size: 13))
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

    private var aiPlanDraft: String {
        guard generatedAIPlan?.planID == currentPlan.id else { return "" }
        return generatedAIPlan?.text ?? ""
    }

    private func generateAIStudyPlan() {
        let request = aiPlanPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else {
            aiPlanStatus = "请先输入你的备考情况。"
            return
        }

        let targetGoal = currentGoal
        let targetPlanID = currentPlan.id
        isRevisingPlan = true
        aiPlanStatus = "AI 正在定制计划..."

        Task {
            do {
                let service = try DeepSeekPlanService()
                let goalContext = """
                当前目标：\(targetGoal.title)
                当前模式：\(targetGoal.mode)
                执行重点：\(targetGoal.focus)
                用户补充：\(request)
                """
                let generated = try await service.createStudyPlan(userProfile: goalContext)

                await MainActor.run {
                    generatedAIPlan = (targetPlanID, generated.planText)
                    aiPlanStatus = currentPlan.id == targetPlanID ? generated.reply : "草稿已生成，可切回原计划表查看。"
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
        let tasks = todayGoalID.map { store.todayTasks(for: $0) } ?? store.todayTasks

        return HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("任务")
                        .font(.headline)
                    Spacer()
                    if !goals.isEmpty {
                        GoalsMenuPicker(
                            title: "任务范围",
                            selection: $todayGoalID,
                            options: [(nil, "所有目标")] + goals.map { (Optional($0.id), $0.title) }
                        )
                        .frame(width: 155)
                    }
                }

                HStack(spacing: 8) {
                    TextField(todayTaskPlaceholder, text: $quickTaskTitle)
                        .goalsInput()
                        .onSubmit(addQuickTask)
                    Button(action: addQuickTask) {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(GoalsButtonStyle(.primary))
                    .disabled(quickTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                if tasks.isEmpty {
                    ContentUnavailableView("暂无今日任务", systemImage: "checklist", description: Text("可以直接添加，也可以从计划表同步。"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(tasks) { task in
                                Button {
                                    store.toggleDone(task)
                                } label: {
                                    HStack(spacing: 11) {
                                        Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 17))
                                            .foregroundStyle(task.isDone ? StudyTheme.quietGreen : StudyTheme.mutedInk)
                                        Text(task.title)
                                            .multilineTextAlignment(.leading)
                                            .strikethrough(task.isDone)
                                            .foregroundStyle(task.isDone ? StudyTheme.secondaryInk : StudyTheme.ink)
                                        Spacer(minLength: 8)
                                        if todayGoalID == nil {
                                            Text(task.goalTitle)
                                                .font(.caption)
                                                .foregroundStyle(StudyTheme.secondaryInk)
                                                .lineLimit(1)
                                        }
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 11)
                                }
                                .buttonStyle(GoalsButtonStyle(.row))
                                .accessibilityValue(task.isDone ? "已完成" : "待完成")
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(StudyTheme.paper, in: .rect(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(StudyTheme.hairline) }

            todayOverview(tasks)
                .frame(width: 196)
        }
    }

    private var todayTaskGoal: GoalPlan? {
        let goalID = todayGoalID ?? selectedGoalID
        return goals.first { $0.id == goalID }
    }

    private var todayTaskPlaceholder: String {
        todayTaskGoal.map { "添加任务到\($0.title)" } ?? "添加今日任务"
    }

    private func todayOverview(_ tasks: [StudyTask]) -> some View {
        let done = tasks.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: 14) {
            Label(DateKey.today(), systemImage: "calendar")
                .font(.callout)
                .foregroundStyle(StudyTheme.secondaryInk)

            Text("\(done) / \(tasks.count)")
                .font(.system(size: 29, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .accessibilityLabel("已完成 \(done) 项，共 \(tasks.count) 项")

            ProgressView(value: Double(done), total: Double(max(tasks.count, 1)))
                .labelsHidden()
            Text("\(tasks.count - done) 项待完成")
                .font(.callout)
                .foregroundStyle(StudyTheme.secondaryInk)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(StudyTheme.paper, in: .rect(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(StudyTheme.hairline) }
    }

    private var wordBankWorkspace: some View {
        let missingMeanings = allWords.filter(\.needsMeaning)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                TextField("输入新单词", text: $newWordText)
                    .font(.system(size: 16))
                    .goalsInput(minHeight: 46, radius: 9)
                    .onSubmit(addCustomWord)

                Button(action: addCustomWord) {
                    Label(isCompletingWord ? "补全中" : "添加单词", systemImage: isCompletingWord ? "hourglass" : "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(minWidth: 95, minHeight: 30)
                }
                .buttonStyle(GoalsButtonStyle(.primary))
                .disabled(isCompletingWord || !completingMeaningIDs.isEmpty
                          || newWordText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("图片导词", systemImage: "text.viewfinder") {
                    showsImageWordImport = true
                }
                .buttonStyle(GoalsButtonStyle())
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(StudyTheme.mutedInk)
                    .accessibilityHidden(true)
                TextField("搜索单词、释义或标签", text: $wordSearch)
                    .focusEffectDisabled()
                    .focused($isWordSearchFocused)
            }
            .font(.system(size: 13))
            .goalsInput(horizontal: 11, vertical: 6, minHeight: 34, focused: isWordSearchFocused)

            HStack {
                Text("\(filteredWords.count) 个单词")
                    .font(.headline)
                Spacer()
                if !wordBankStatus.isEmpty {
                    Text(wordBankStatus)
                        .font(.callout)
                        .foregroundStyle(StudyTheme.secondaryInk)
                }
                if !missingMeanings.isEmpty {
                    Button("补全缺失释义（\(missingMeanings.count)）", systemImage: "sparkles") {
                        completeMissingMeanings(missingMeanings)
                    }
                    .buttonStyle(GoalsButtonStyle())
                    .disabled(isCompletingWord || !completingMeaningIDs.isEmpty)
                    .help("将缺少释义的词分批发送给 DeepSeek")
                }
            }

            ScrollView {
                if filteredWords.isEmpty {
                    emptyPanel(
                        allWords.isEmpty ? "还没有单词" : "没有匹配的单词",
                        hint: allWords.isEmpty ? "输入一个英文单词开始收集。" : "试试其他单词、释义或标签。"
                    )
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredWords, content: wordRow)
                    }
                }
            }
        }
    }

    private func wordRow(_ word: VocabularyWord) -> some View {
        let isRevealed = revealedDeleteWordID == word.id
        let isExpanded = expandedWordIDs.contains(word.id)
        let hasTag = !word.tag.isEmpty && word.tag != "自定义"
        let hasDetails = !word.phrases.isEmpty || !word.example.isEmpty || !word.mnemonic.isEmpty || hasTag

        return HStack(spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 11) {
                    HStack(alignment: .firstTextBaseline, spacing: 9) {
                        Text(word.word)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(StudyTheme.ink)
                        if !word.phonetic.isEmpty {
                            Text(word.phonetic)
                                .font(.system(size: 13))
                                .foregroundStyle(StudyTheme.secondaryInk)
                        }
                        if word.partOfSpeech != "未标注" {
                            Text(word.partOfSpeech)
                                .font(.system(size: 12))
                                .foregroundStyle(StudyTheme.secondaryInk)
                        }
                    }

                    Text(word.meaning)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(StudyTheme.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if isExpanded {
                        VStack(alignment: .leading, spacing: 13) {
                            Divider()
                            if !word.phrases.isEmpty {
                                wordDetail("搭配", text: word.phrases.joined(separator: " · "), note: word.phraseTranslationLine)
                            }
                            if !word.example.isEmpty {
                                wordDetail("例句", text: word.example, note: word.exampleTranslation)
                            }
                            if !word.mnemonic.isEmpty {
                                wordDetail("助记", text: word.mnemonic)
                            }
                            if hasTag {
                                Text(word.tag)
                                    .font(.caption)
                                    .foregroundStyle(StudyTheme.mutedInk)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if word.needsMeaning {
                    let working = completingMeaningIDs.contains(word.id)
                    Button(working ? "补全中" : "补全释义", systemImage: working ? "hourglass" : "sparkles") {
                        completeMissingMeanings([word])
                    }
                    .buttonStyle(GoalsButtonStyle(.compact))
                    .disabled(isCompletingWord || !completingMeaningIDs.isEmpty)
                    .accessibilityLabel(working ? "正在补全 \(word.word)" : "补全 \(word.word) 的释义")
                }

                if hasDetails {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            if isExpanded { expandedWordIDs.remove(word.id) }
                            else { expandedWordIDs.insert(word.id) }
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(GoalsButtonStyle(.row))
                    .accessibilityLabel(isExpanded ? "收起词条详情" : "展开词条详情")
                    .help(isExpanded ? "收起词条详情" : "展开词条详情")
                }

                Button {
                    toggleFavorite(word)
                } label: {
                    Image(systemName: favoriteWordIDs.contains(word.id) ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(StudyCategory.words.tint)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(GoalsButtonStyle(.icon))
                .accessibilityLabel(favoriteWordIDs.contains(word.id) ? "从错词收藏移除" : "加入错词收藏")
                .help(favoriteWordIDs.contains(word.id) ? "从错词收藏移除" : "加入错词收藏")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
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
                    .frame(width: 78)
                    .frame(minHeight: 86)
                }
                .buttonStyle(GoalsButtonStyle(.card))
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

    private func wordDetail(_ title: String, text: String, note: String = "") -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(StudyTheme.secondaryInk)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(StudyTheme.ink)
                .lineSpacing(3)
            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(StudyTheme.secondaryInk)
                    .lineSpacing(3)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func practiceComposer(
        input: Binding<String>,
        placeholder: String,
        status: String,
        actionTitle: String,
        actionIcon: String,
        isWorking: Bool,
        perform: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            TextField(placeholder, text: input)
                .font(.system(size: 15))
                .foregroundStyle(StudyTheme.ink)
                .goalsInput(minHeight: 36)
                .onSubmit(perform)

            HStack {
                Text(status)
                    .font(.callout)
                    .foregroundStyle(StudyTheme.secondaryInk)
                Spacer()
                Button(action: perform) {
                    Label(isWorking ? "生成中" : actionTitle, systemImage: isWorking ? "hourglass" : actionIcon)
                }
                .buttonStyle(GoalsButtonStyle(.primary))
                .disabled(isWorking || input.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(14)
        .background(StudyTheme.paper, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(StudyTheme.hairline) }
    }

    private var translationWorkspace: some View {
        VStack(alignment: .leading, spacing: 16) {
            practiceComposer(
                input: $translationInput,
                placeholder: "输入中文或英文句子",
                status: translationStatus,
                actionTitle: "生成表达",
                actionIcon: "sparkles",
                isWorking: isGeneratingTranslation,
                perform: generateTranslationPractice
            )

            Text("练习记录（\(translationRecords.count)）")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                if translationRecords.isEmpty {
                    emptyPanel("还没有翻译或润色记录", hint: "生成的译文和润色结果会自动保存在这里。")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(translationRecords, content: translationRecordRow)
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
                            .font(StudyTheme.heading(size: 15, weight: .semibold))
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
                    .background(StudyTheme.field)
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
        VStack(alignment: .leading, spacing: 16) {
            practiceComposer(
                input: $writingPrompt,
                placeholder: "输入作文主题、提示句或六级原题",
                status: writingStatus,
                actionTitle: "生成作文",
                actionIcon: "doc.text",
                isWorking: isGeneratingWriting,
                perform: generateWritingPractice
            )

            Text("练习记录（\(writingRecords.count)）")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ScrollView {
                if writingRecords.isEmpty {
                    emptyPanel("还没有写作记录", hint: "生成的作文和注释会自动保存在这里。")
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(writingRecords, content: writingRecordRow)
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
                        .font(StudyTheme.heading(size: 18, weight: .bold))
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
                    .buttonStyle(GoalsButtonStyle(.compact, tint: StudyCategory.writing.tint))
                }

                Text("题目：\(record.prompt)")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(StudyTheme.secondaryInk)

                if isCollapsed {
                    Text(Self.essayPreview(record.essay))
                        .font(StudyTheme.heading(size: 13, weight: .medium))
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
                                        .buttonStyle(GoalsButtonStyle(.compact, tint: StudyCategory.writing.tint))
                                    }
                                }
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(StudyTheme.field)
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
                    .font(StudyTheme.heading(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .foregroundStyle(StudyTheme.ink)
                Spacer()
                if let word = Self.extractSingleEnglishWord(from: selectedEssayText) {
                    Button {
                        addWordToBook(word)
                    } label: {
                        Label("加入单词本", systemImage: "plus.circle")
                    }
                    .buttonStyle(GoalsButtonStyle())
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
                    .frame(width: 78)
                    .frame(maxHeight: .infinity)
                }
                .buttonStyle(GoalsButtonStyle(.card))
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
                .font(.system(size: 15))
                .foregroundStyle(StudyTheme.ink)
                .goalsInput(minHeight: 36)

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
                    .font(StudyTheme.heading(size: 22, weight: .bold))
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
        let word = activeReviewWord

        return AnyView(ScrollView {
            VStack(spacing: 14) {
                HStack(alignment: .center, spacing: 18) {
                    GoalsSegmentedControl(
                        title: "复习模式",
                        selection: $reviewMode,
                        options: WordReviewMode.allCases.map { ($0, $0.title) }
                    )
                    .frame(maxWidth: 420)

                    Spacer(minLength: 10)

                    HStack(spacing: 12) {
                        reviewMetric(title: "待复习", value: dueReviewCount)
                        reviewMetric(title: "已开始", value: startedReviewCount)
                        reviewMetric(title: "已掌握", value: masteredReviewCount)
                    }
                }

                if word == nil {
                    emptyPanel(
                        reviewMode == .due ? "当前没有到期单词" : "当前模式没有可复习的单词",
                        hint: reviewMode == .due ? "完成得很好；新词加入单词本后会自动进入学习队列。" : "可以换个筛选条件，或先在单词本里添加新词。"
                    )
                    .padding(.top, 12)
                } else if let word {
                    let progress = reviewProgressByWordID[word.id]

                    HStack(spacing: 12) {
                        HStack(spacing: 8) {
                            Text(reviewQueueLabel(for: word, queue: words))
                            Text("·")
                            Text(word.tag)
                            Text("·")
                            Text("等级 \(progress?.level ?? 0)/5")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StudyTheme.secondaryInk)

                        Spacer(minLength: 12)

                        }

                    VStack(spacing: 12) {
                        HStack(spacing: 10) {
                            Text(word.word)
                                .font(StudyTheme.heading(size: 42, weight: .bold))
                                .foregroundStyle(StudyTheme.ink)
                                .multilineTextAlignment(.center)

                            Button {
                                vocabularySpeech.speak(word.word)
                            } label: {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(StudyCategory.flashcards.tint)
                                    .frame(width: 34, height: 34)
                            }
                            .buttonStyle(GoalsButtonStyle(.icon))
                            .help("重播单词发音")
                            .accessibilityLabel("重播 \(word.word) 的发音")
                        }
                        Text(frontCardMeta(for: word).isEmpty ? "写出一个核心中文含义" : frontCardMeta(for: word))
                            .font(StudyTheme.heading(size: 22, weight: .semibold))
                            .foregroundStyle(StudyTheme.ink.opacity(0.76))
                            .multilineTextAlignment(.center)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                            .padding(.horizontal, 22)

                        if FlashcardMnemonic.shouldShow(level: progress?.level ?? 0, showingAnswer: showsCardBack) {
                            flashcardFrontMnemonic(for: word)
                        }

                    if let judgment = reviewJudgment, showsCardBack {
                        Label(
                            judgment.isCorrect ? "回答正确" : "回答错误",
                            systemImage: judgment.isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill"
                        )
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(judgment.isCorrect ? StudyCategory.today.tint : StudyCategory.words.tint)

                        Text(word.meaning)
                            .font(StudyTheme.heading(size: 25, weight: .bold))
                            .foregroundStyle(StudyTheme.ink)
                            .multilineTextAlignment(.center)

                        Text(judgment.reason)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StudyTheme.secondaryInk)

                        if !word.mnemonic.isEmpty {
                            Text("助记：\(word.mnemonic)")
                                .font(.system(size: 13))
                                .foregroundStyle(StudyTheme.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26)
                        }

                        if !word.example.isEmpty {
                            Text(word.example)
                                .font(StudyTheme.heading(size: 15, weight: .medium))
                                .foregroundStyle(StudyTheme.secondaryInk)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 26)
                        }

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
                        Text(reviewStatus)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudyCategory.flashcards.tint)
                    }
                    }
                    .frame(maxWidth: 620, minHeight: 210)
                    .padding(.vertical, 14)
                    .background(StudyTheme.panelStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }

                if reviewJudgment == nil {
                    HStack(spacing: 10) {
                        TextField("输入中文含义；、 表示不认识", text: $reviewAnswer)
                            .font(.system(size: 15))
                            .focused($flashcardReviewFocus, equals: .answer)
                            .goalsInput(minHeight: 38, focused: flashcardReviewFocus == .answer)
                            .onSubmit { advanceFlashcardReviewStep() }
                            .onKeyPress(keys: Self.flashcardDirectionKeys, phases: .down) { _ in
                                advanceFlashcardReviewStep() ? .handled : .ignored
                            }

                        Button {
                            advanceFlashcardReviewStep()
                        } label: {
                            Label(isJudgingReviewAnswer ? "判分中" : "提交判分", systemImage: isJudgingReviewAnswer ? "hourglass" : "paperplane")
                        }
                        .buttonStyle(GoalsButtonStyle(.primary))
                        .tint(StudyCategory.flashcards.tint)
                        .disabled(isJudgingReviewAnswer || reviewAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .frame(maxWidth: 620)

                    Text(reviewStatus)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                } else if reviewJudgment?.isCorrect == false, !hasCompletedReviewCorrection {
                    HStack(spacing: 10) {
                        TextField("复述卡片中的一个正确含义", text: $reviewCorrectionAnswer)
                            .font(.system(size: 15))
                            .focused($flashcardReviewFocus, equals: .correction)
                            .goalsInput(minHeight: 38, focused: flashcardReviewFocus == .correction)
                            .onSubmit { advanceFlashcardReviewStep() }
                            .onKeyPress(keys: Self.flashcardDirectionKeys, phases: .down) { _ in
                                advanceFlashcardReviewStep() ? .handled : .ignored
                            }

                        Button("确认复述") {
                            advanceFlashcardReviewStep()
                        }
                        .buttonStyle(GoalsButtonStyle(.primary))
                        .tint(StudyCategory.flashcards.tint)
                        .disabled(reviewCorrectionAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    .frame(maxWidth: 620)
                }

                HStack(spacing: 12) {
                    Button {
                        previousCard()
                    } label: {
                        Label("上一个", systemImage: "chevron.left")
                    }
                    .buttonStyle(GoalsButtonStyle())
                    .disabled(isJudgingReviewAnswer)

                    Button {
                        toggleCardFavorite(word)
                    } label: {
                        Label(favoriteWordIDs.contains(word.id) ? "取消收藏" : "不熟收藏", systemImage: "bookmark")
                    }
                    .buttonStyle(GoalsButtonStyle())
                    .tint(StudyCategory.flashcards.tint)

                    Button {
                        banishWord(word)
                    } label: {
                        Label("斩", systemImage: "scissors")
                    }
                    .buttonStyle(GoalsButtonStyle(tint: StudyTheme.cinnabar))
                    .disabled(isJudgingReviewAnswer)
                    .help("从词书和全部复习界面永久移除此词")

                    Button {
                        advanceFlashcardReviewStep()
                    } label: {
                        Label(reviewAdvanceButtonTitle, systemImage: "chevron.right")
                    }
                    .buttonStyle(GoalsButtonStyle(.primary))
                    .tint(StudyCategory.flashcards.tint)
                    .disabled(isJudgingReviewAnswer || (reviewJudgment?.isCorrect == false && !hasCompletedReviewCorrection))
                }

                if let lastBanishedRecord {
                    HStack(spacing: 8) {
                        Image(systemName: "scissors")
                            .foregroundStyle(StudyTheme.cinnabar)
                        Text("已斩 \(lastBanishedRecord.word.word)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(StudyTheme.secondaryInk)
                        Button("撤销") {
                            restoreBanishedWord(lastBanishedRecord)
                        }
                        .font(.system(size: 12, weight: .bold))
                        .buttonStyle(GoalsButtonStyle(.compact, tint: StudyCategory.flashcards.tint))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(StudyTheme.panelStrong)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(StudyTheme.hairline, lineWidth: 1)
                    }
                }

                Text("快捷键：回车或任一方向键进入下一步")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(StudyTheme.mutedInk)

                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.automatic)
        .focusable()
        .focusEffectDisabled()
        .focused($flashcardReviewFocus, equals: .workspace)
        .onKeyPress(keys: Self.flashcardAdvanceKeys, phases: .down) { _ in
            advanceFlashcardReviewStep() ? .handled : .ignored
        }
        .onAppear {
            focusCurrentFlashcardReviewStep()
            scheduleAutomaticVocabularySpeech(force: true)
            prepareFlashcardMnemonics()
        }
        .onDisappear {
            pendingVocabularySpeechTask?.cancel()
            pendingVocabularySpeechTask = nil
            vocabularySpeech.stop()
            lastAutoSpokenWordID = nil
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: reviewMode) { _, _ in
            resetReviewCard(index: 0)
        }
        .onChange(of: activeReviewWord?.id) { _, _ in
            scheduleAutomaticVocabularySpeech()
            prepareFlashcardMnemonics()
        }
        .onChange(of: showsCardBack) { _, _ in prepareFlashcardMnemonics() }
        .onChange(of: vocabularySpeech.isAutoPlayEnabled) { _, isEnabled in
            if isEnabled {
                scheduleAutomaticVocabularySpeech(force: true)
            } else {
                pendingVocabularySpeechTask?.cancel()
                pendingVocabularySpeechTask = nil
                vocabularySpeech.stop()
            }
        })
    }

    @ViewBuilder
    private func flashcardFrontMnemonic(for word: VocabularyWord) -> some View {
        let key = VocabularyBanishment01.key(for: word.word)
        if let hint = verifiedFrontMnemonic(for: word) {
            Text("助记  \(hint)")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(StudyTheme.secondaryInk)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 22)
        } else if let error = failedFrontMnemonics[key] {
            Button("重试生成助记", systemImage: "arrow.clockwise") {
                failedFrontMnemonics.removeValue(forKey: key)
                prepareFlashcardMnemonics(preferScene: true)
            }
            .buttonStyle(GoalsButtonStyle(.compact))
            .disabled(isGeneratingFrontMnemonics)
            .help(error)
        } else {
            Text("正在生成助记…")
                .font(.system(size: 13))
                .foregroundStyle(StudyTheme.secondaryInk)
        }
    }

    private func verifiedFrontMnemonic(for word: VocabularyWord) -> String? {
        let key = VocabularyBanishment01.key(for: word.word)
        guard let hint = frontMnemonics[key] else { return nil }
        return FlashcardMnemonic.validated(hint, meaning: word.needsMeaning ? "" : word.meaning)
    }

    private func prepareFlashcardMnemonics(preferScene: Bool = false) {
        guard selectedCategory == .flashcards, !isGeneratingFrontMnemonics,
              let active = activeReviewWord, verifiedFrontMnemonic(for: active) == nil,
              failedFrontMnemonics[VocabularyBanishment01.key(for: active.word)] == nil,
              FlashcardMnemonic.shouldShow(level: reviewProgressByWordID[active.id]?.level ?? 0, showingAnswer: showsCardBack) else {
            return
        }
        let upcoming = reviewWords.drop(while: { $0.id != active.id }).dropFirst()
        let batch = (preferScene ? [active] : [active] + upcoming.prefix(16))
            .filter { word in
                (reviewProgressByWordID[word.id]?.level ?? 0) <= 4
                    && verifiedFrontMnemonic(for: word) == nil
                    && failedFrontMnemonics[VocabularyBanishment01.key(for: word.word)] == nil
            }
            .prefix(FlashcardMnemonic.batchSize)
            .map(FlashcardMnemonic.Input.init)
        isGeneratingFrontMnemonics = true
        Task {
            defer {
                isGeneratingFrontMnemonics = false
                prepareFlashcardMnemonics()
            }
            do {
                let hints = try await DeepSeekPlanService().generateFlashcardMnemonics(batch, preferScene: preferScene)
                frontMnemonics.merge(hints) { _, new in new }
                if !hints.isEmpty { FlashcardMnemonicStore.save(frontMnemonics) }
                for word in batch where hints[word.word] == nil {
                    failedFrontMnemonics[word.word] = "这条助记没有通过检查，可以重试。"
                }
            } catch {
                for word in batch {
                    failedFrontMnemonics[word.word] = error.localizedDescription
                }
            }
        }
    }

    private var mistakeWorkspace: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                GoalsSegmentedControl(
                    title: "错词分类",
                    selection: $mistakeMode,
                    options: MistakeMode.allCases.map { ($0, $0.title) }
                )
                .frame(width: 330)

                TextField("搜索错词", text: $mistakeSearch)
                    .font(.system(size: 15))
                    .foregroundStyle(StudyTheme.ink)
                    .goalsInput(minHeight: 36)

                if mistakeMode == .banished {
                    Text("\(banishedWordRecords.count) 个已斩词")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                }
            }

            ScrollView {
                if mistakeMode == .banished {
                    if filteredBanishedWordRecords.isEmpty {
                        emptyPanel(
                            banishedWordRecords.isEmpty ? "还没有已斩词" : "没有匹配的已斩词",
                            hint: banishedWordRecords.isEmpty ? "在闪卡中点击“斩”后，单词会保存在这里，随时可以恢复学习。" : "可以换个关键词搜索。"
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredBanishedWordRecords) { record in
                                banishedWordRow(record)
                            }
                        }
                    }
                } else if mistakeWords.isEmpty {
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

    private var filteredBanishedWordRecords: [BanishedVocabularyRecord01] {
        let query = mistakeSearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return banishedWordRecords }

        return banishedWordRecords.filter { record in
            record.word.word.lowercased().contains(query)
                || record.word.meaning.lowercased().contains(query)
                || record.word.partOfSpeech.lowercased().contains(query)
                || record.word.tag.lowercased().contains(query)
        }
    }

    private func banishedWordRow(_ record: BanishedVocabularyRecord01) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "scissors")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(StudyTheme.cinnabar)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(record.word.word)
                        .font(StudyTheme.heading(size: 18, weight: .bold))
                        .foregroundStyle(StudyTheme.ink)
                    if !record.word.phonetic.isEmpty {
                        Text(record.word.phonetic)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(StudyTheme.secondaryInk)
                    }
                    Text(record.word.tag)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                }
                Text(record.word.meaning)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StudyTheme.ink)
                Text(record.isLegacyFallback ? "旧记录：斩除时间未保留" : "斩除于 \(Self.displayDate(record.banishedAt))")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StudyTheme.secondaryInk)
                if record.isLegacyFallback {
                    Text("旧记录未保留原释义；恢复后将作为新词加入词书。")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(StudyTheme.secondaryInk)
                }
            }

            Spacer()

            Button {
                restoreBanishedWord(record)
            } label: {
                Label("恢复学习", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(GoalsButtonStyle(tint: StudyCategory.mistakes.tint))
            .help("恢复到斩除前的学习状态；旧记录会作为新词恢复")
        }
        .padding(14)
        .background(StudyTheme.panelStrong)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(StudyTheme.hairline, lineWidth: 1)
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
                        .font(StudyTheme.heading(size: 18, weight: .bold))
                        .foregroundStyle(StudyTheme.ink)
                    Text(word.tag)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(StudyCategory.mistakes.tint)
                }
                Text(word.meaning)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(StudyTheme.ink)
                Text(word.example)
                    .font(StudyTheme.heading(size: 13))
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
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(GoalsButtonStyle(.icon))
                .accessibilityLabel(favoriteWordIDs.contains(word.id) ? "移出错词收藏" : "加入错词收藏")
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
        customWords.filter {
            !deletedWordIDs.contains($0.id)
                && !VocabularyBanishment01.isBanished($0.word, banishedKeys: banishedWordKeys)
        }
    }

    private var reviewWords: [VocabularyWord] {
        switch reviewMode {
        case .due:
            let now = Date()
            let due = allWords
                .filter {
                    reviewProgressByWordID[$0.id] != nil
                        && FlashcardReviewQueue01.isEligibleForDueReview(
                            progress: reviewProgressByWordID[$0.id],
                            isDismissed: reviewDismissedWordIDs.contains($0.id),
                            now: now
                        )
                }
                .sorted {
                    (reviewProgressByWordID[$0.id]?.nextReview ?? .distantPast)
                        < (reviewProgressByWordID[$1.id]?.nextReview ?? .distantPast)
                }
            let newWords = allWords.filter {
                reviewProgressByWordID[$0.id] == nil
                    && !reviewDismissedWordIDs.contains($0.id)
            }
            return due + newWords
        case .all:
            return allWords
        case .favorites:
            return allWords.filter { favoriteWordIDs.contains($0.id) }
        case .hard:
            return allWords.filter { $0.difficulty >= 4 }
        }
    }

    private var activeReviewWord: VocabularyWord? {
        if let reviewedWordID, reviewJudgment != nil,
           let reviewedWord = allWords.first(where: { $0.id == reviewedWordID }) {
            return reviewedWord
        }
        guard !reviewWords.isEmpty else { return nil }
        return reviewWords[reviewIndex % reviewWords.count]
    }

    private var dueReviewCount: Int {
        let now = Date()
        return allWords.filter {
            FlashcardReviewQueue01.isEligibleForDueReview(
                progress: reviewProgressByWordID[$0.id],
                isDismissed: reviewDismissedWordIDs.contains($0.id),
                now: now
            )
        }.count
    }

    private var startedReviewCount: Int {
        allWords.filter { reviewProgressByWordID[$0.id] != nil }.count
    }

    private var masteredReviewCount: Int {
        allWords.filter { (reviewProgressByWordID[$0.id]?.level ?? 0) >= 5 }.count
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
        case .banished:
            source = []
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
        guard !title.isEmpty else { return }

        let mode = newGoalMode.trimmingCharacters(in: .whitespacesAndNewlines)
        let focus = newGoalFocus.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = GoalPlanSheet(title: "计划表01", planText: "")
        let goal = GoalPlan(title: title, mode: mode.isEmpty ? "生活目标" : mode, focus: focus, plans: [plan])
        let updatedGoals = goals + [goal]

        do {
            try GoalPlanStore01.save(updatedGoals)
            goals = updatedGoals
            newGoalTitle = ""
            newGoalMode = "生活目标"
            newGoalFocus = ""
            newGoalError = nil
            showsNewGoal = false
            selectedGoalID = goal.id
            selectedPlanID = plan.id
            planWorkspaceMode = .manual
            selectedCategory = .plan
            goalStatus = ""
        } catch {
            newGoalError = "创建失败：\(error.localizedDescription)"
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

        let plan = GoalPlanSheet(title: title, planText: "")
        var updatedGoals = goals
        updatedGoals[goalIndex].plans.append(plan)

        do {
            try GoalPlanStore01.save(updatedGoals)
            goals = updatedGoals
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
        if let goal = todayTaskGoal {
            store.addTaskForToday(quickTaskTitle, goalID: goal.id, goalTitle: goal.title)
        } else {
            store.addTaskForToday(quickTaskTitle, goalID: "unassigned", goalTitle: "未归类")
        }
        quickTaskTitle = ""
    }

    private func importImageWords(_ rawWords: [String]) {
        let library = Self.mergeWords(customWords + Self.loadCustomWords())
        var existing = Set(library.filter { !deletedWordIDs.contains($0.id) }
            .map { VocabularyBanishment01.key(for: $0.word) })
        let previousWords = Dictionary(library.map {
            (VocabularyBanishment01.key(for: $0.word), $0)
        }, uniquingKeysWith: { first, _ in first })
        let additions: [VocabularyWord] = rawWords.compactMap { raw in
            guard let literal = MarkedVocabularyImage.cleanWord(raw),
                  let word = Self.customWord(from: literal),
                  !banishedWordKeys.contains(literal),
                  !banishedWordKeys.contains(word.word),
                  existing.insert(word.word).inserted else { return nil }
            return previousWords[word.word] ?? word
        }

        if !additions.isEmpty {
            let addedKeys = Set(additions.map { VocabularyBanishment01.key(for: $0.word) })
            customWordsLoadGeneration += 1
            isLoadingCustomWords = false
            deletedWordIDs.subtract(additions.map(\.id))
            customWords = additions + library.filter { !addedKeys.contains(VocabularyBanishment01.key(for: $0.word)) }
            wordSearch = ""
        }
        let skipped = rawWords.count - additions.count
        wordBankStatus = "已从图片加入 \(additions.count) 个单词"
        if skipped > 0 { wordBankStatus += "，跳过 \(skipped) 个重复或已斩词" }
    }

    private func completeMissingMeanings(_ words: [VocabularyWord]) {
        guard completingMeaningIDs.isEmpty, !isCompletingWord else { return }
        let requested = words.filter(\.needsMeaning)
        guard !requested.isEmpty else { return }
        completingMeaningIDs = Set(requested.map(\.id))
        wordBankStatus = "正在补全 \(requested.count) 个词的释义…"

        Task {
            var completed = 0
            defer { completingMeaningIDs = [] }
            do {
                let service = try DeepSeekPlanService()
                let batchSize = DeepSeekPlanService.vocabularyBatchSize
                for start in stride(from: 0, to: requested.count, by: batchSize) {
                    let stillMissing = Set(allWords.filter(\.needsMeaning).map(\.id))
                    let batch = requested[start..<min(start + batchSize, requested.count)]
                        .filter { stillMissing.contains($0.id) }
                    guard !batch.isEmpty else { continue }
                    let results = try await service.completeExistingVocabulary(batch.map(\.word))
                    completed += applyCompletedMeanings(results, to: Set(batch.map(\.id)))
                }
                let remaining = requested.count - completed
                wordBankStatus = remaining == 0
                    ? "已补全 \(completed) 个词的释义"
                    : "已补全 \(completed) 个词，还有 \(remaining) 个未补全"
            } catch {
                wordBankStatus = "已补全 \(completed) 个词。补全中断：\(error.localizedDescription)"
            }
        }
    }

    private func applyCompletedMeanings(_ results: [String: WordLookupResult], to requestedIDs: Set<String>) -> Int {
        guard !results.isEmpty else { return 0 }
        let library = Self.mergeWords(Self.loadCustomWords() + customWords)
        var completed = 0
        let updated = library.map { word in
            let key = VocabularyBanishment01.key(for: word.word)
            guard requestedIDs.contains(word.id), word.needsMeaning,
                  !deletedWordIDs.contains(word.id), !banishedWordKeys.contains(key),
                  let result = results[key] else { return word }
            completed += 1
            return word.fillingMeaning(from: result)
        }
        if completed > 0 {
            customWordsLoadGeneration += 1
            isLoadingCustomWords = false
            customWords = updated
        }
        return completed
    }

    private func addCustomWord() {
        guard !isCompletingWord, completingMeaningIDs.isEmpty else { return }
        guard let newWord = Self.customWord(from: newWordText) else {
            wordBankStatus = "请输入一个英文单词"
            return
        }

        if let existing = allWords.first(where: {
            $0.id == newWord.id || $0.word.caseInsensitiveCompare(newWord.word) == .orderedSame
        }) {
            newWordText = ""
            if existing.needsMeaning {
                completeMissingMeanings([existing])
            } else {
                wordBankStatus = "\(newWord.word) 已在单词本里"
            }
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
                    if insertCustomWord(completedWord) {
                        wordBankStatus = "已补全并加入 \(completedWord.word)"
                    }
                    isCompletingWord = false
                }
            } catch {
                await MainActor.run {
                    if insertCustomWord(newWord) {
                        wordBankStatus = "API 补全失败，已先加入 \(newWord.word)：\(error.localizedDescription)"
                    }
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
                    if insertCustomWord(completedWord) {
                        wordBankStatus = "已补全并加入 \(completedWord.word)"
                    }
                    writingStatus = wordBankStatus
                }
            } catch {
                await MainActor.run {
                    if insertCustomWord(newWord) {
                        wordBankStatus = "API 补全失败，已先加入 \(newWord.word)：\(error.localizedDescription)"
                    }
                    writingStatus = wordBankStatus
                }
            }
        }
    }

    private func insertCustomWord(_ word: VocabularyWord) -> Bool {
        guard !VocabularyBanishment01.isBanished(word.word, banishedKeys: banishedWordKeys) else {
            wordBankStatus = "\(word.word) 已被斩，不会重新加入词书"
            return false
        }
        guard !allWords.contains(where: { $0.id == word.id || $0.word.caseInsensitiveCompare(word.word) == .orderedSame }) else {
            wordBankStatus = "\(word.word) 已在单词本里"
            return false
        }

        deletedWordIDs.remove(word.id)
        customWords.insert(word, at: 0)
        return true
    }

    private func deleteWord(_ word: VocabularyWord) {
        expandedWordIDs.remove(word.id)
        customWords.removeAll { $0.id == word.id }
        favoriteWordIDs.remove(word.id)
        reviewProgressByWordID.removeValue(forKey: word.id)
        reviewDismissedWordIDs.remove(word.id)
        Self.saveReviewDismissedWordIDs(reviewDismissedWordIDs)
        deletedWordIDs.insert(word.id)
        reviewIndex = min(reviewIndex, max(reviewWords.count - 1, 0))
        wordBankStatus = "已删除 \(word.word)"
    }

    private func banishWord(_ word: VocabularyWord) {
        guard !isJudgingReviewAnswer else { return }

        let banishedKey = VocabularyBanishment01.key(for: word.word)
        guard !banishedKey.isEmpty else { return }
        let matchingWords = customWords.filter { candidate in
            VocabularyBanishment01.key(for: candidate.word) == banishedKey
        }
        let matchingIDs = Set(matchingWords.map(\.id)).union([word.id])
        let matchingCustomWords = customWords.filter {
            VocabularyBanishment01.key(for: $0.word) == banishedKey
        }
        let record = BanishedVocabularyRecord01(
            key: banishedKey,
            word: matchingCustomWords.first ?? matchingWords.first ?? word,
            customSnapshots: matchingCustomWords,
            originalWordIDs: Array(matchingIDs),
            previousProgress: matchingIDs.compactMap { reviewProgressByWordID[$0] },
            favoriteWordIDs: matchingIDs.filter { favoriteWordIDs.contains($0) },
            dismissedWordIDs: matchingIDs.filter { reviewDismissedWordIDs.contains($0) }
        )
        var updatedRecords = banishedWordRecords.filter { $0.key != banishedKey }
        updatedRecords.append(record)

        do {
            try BanishedVocabularyStore01.save(updatedRecords)
        } catch {
            reviewStatus = "斩除失败：无法保存恢复记录。"
            return
        }

        banishedWordKeys.insert(banishedKey)
        Self.saveBanishedWordKeys(banishedWordKeys)
        banishedWordRecords = updatedRecords.sorted { $0.banishedAt > $1.banishedAt }
        customWords.removeAll { VocabularyBanishment01.key(for: $0.word) == banishedKey }
        favoriteWordIDs.subtract(matchingIDs)
        reviewDismissedWordIDs.subtract(matchingIDs)
        Self.saveReviewDismissedWordIDs(reviewDismissedWordIDs)
        for wordID in matchingIDs {
            reviewProgressByWordID.removeValue(forKey: wordID)
        }
        deletedWordIDs.formUnion(matchingIDs)

        let nextIndex = min(reviewIndex, max(reviewWords.count - 1, 0))
        resetReviewCard(index: nextIndex)
        reviewStatus = "已斩 \(word.word)：已移入“已斩”词库，可随时恢复。"
        wordBankStatus = "已斩 \(word.word)"
        offerBanishUndo(for: record)
    }

    private func restoreBanishedWord(_ record: BanishedVocabularyRecord01) {
        guard banishedWordRecords.contains(where: { $0.key == record.key }) else { return }
        let updatedRecords = banishedWordRecords.filter { $0.key != record.key }

        do {
            try BanishedVocabularyStore01.save(updatedRecords)
        } catch {
            reviewStatus = "恢复失败：无法更新已斩词库。"
            return
        }

        banishedWordRecords = updatedRecords
        banishedWordKeys.remove(record.key)
        Self.saveBanishedWordKeys(banishedWordKeys)
        let restoredCustomWords = record.customSnapshots.isEmpty ? [record.word] : record.customSnapshots
        customWords = Self.mergeWords(restoredCustomWords + customWords)

        let restoredIDs = Set(record.originalWordIDs + restoredCustomWords.map(\.id) + [record.word.id])
        deletedWordIDs.subtract(restoredIDs)
        favoriteWordIDs.formUnion(record.favoriteWordIDs)
        reviewDismissedWordIDs.formUnion(record.dismissedWordIDs)
        Self.saveReviewDismissedWordIDs(reviewDismissedWordIDs)
        for progress in record.previousProgress {
            reviewProgressByWordID[progress.wordID] = progress
        }

        banishUndoTask?.cancel()
        lastBanishedRecord = nil
        reviewIndex = min(reviewIndex, max(reviewWords.count - 1, 0))
        if selectedCategory == .flashcards {
            resetReviewCard(index: reviewIndex)
        }
        let restoreHint = record.previousProgress.isEmpty ? "已作为新词恢复到待复习。" : "已恢复斩除前的学习状态。"
        reviewStatus = "已恢复 \(record.word.word)：\(restoreHint)"
        wordBankStatus = "已恢复 \(record.word.word)"
    }

    private func offerBanishUndo(for record: BanishedVocabularyRecord01) {
        banishUndoTask?.cancel()
        lastBanishedRecord = record
        banishUndoTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(10))
            guard !Task.isCancelled, lastBanishedRecord?.key == record.key else { return }
            lastBanishedRecord = nil
        }
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
            reviewDismissedWordIDs.insert(word.id)
        } else {
            favoriteWordIDs.insert(word.id)
            reviewDismissedWordIDs.remove(word.id)
        }
        Self.saveReviewDismissedWordIDs(reviewDismissedWordIDs)
    }

    private func nextCard() {
        let nextIndex: Int
        if reviewMode == .due {
            nextIndex = 0
        } else {
            let total = max(reviewWords.count, 1)
            nextIndex = (reviewIndex + 1) % total
        }
        resetReviewCard(index: nextIndex)
    }

    private func previousCard() {
        let total = max(reviewWords.count, 1)
        resetReviewCard(index: (reviewIndex - 1 + total) % total)
    }

    private func skipCurrentCard() {
        let total = max(reviewWords.count, 1)
        resetReviewCard(index: (reviewIndex + 1) % total)
    }

    private func scheduleAutomaticVocabularySpeech(force: Bool = false) {
        pendingVocabularySpeechTask?.cancel()
        pendingVocabularySpeechTask = nil

        guard let word = activeReviewWord else { return }
        let previousWordID = force ? nil : lastAutoSpokenWordID
        guard VocabularyAutoSpeechGate01.shouldSpeak(
            wordID: word.id,
            lastSpokenWordID: previousWordID,
            isEnabled: vocabularySpeech.isAutoPlayEnabled
        ) else { return }

        let wordID = word.id
        let spokenWord = word.word
        pendingVocabularySpeechTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled,
                  selectedCategory == .flashcards,
                  activeReviewWord?.id == wordID,
                  vocabularySpeech.isAutoPlayEnabled else { return }

            vocabularySpeech.speak(spokenWord)
            lastAutoSpokenWordID = wordID
            pendingVocabularySpeechTask = nil
        }
    }

    private func resetReviewCard(index: Int) {
        reviewIndex = index
        showsCardBack = false
        reviewAnswer = ""
        reviewJudgment = nil
        reviewedWordID = nil
        reviewCorrectionAnswer = ""
        hasCompletedReviewCorrection = false
        reviewStatus = "输入一个核心中文含义；输入 、 可直接标记为不认识。"
        isJudgingReviewAnswer = false
        focusCurrentFlashcardReviewStep()
    }

    private func toggleCardFavorite(_ word: VocabularyWord) {
        let wasFavorite = favoriteWordIDs.contains(word.id)
        toggleFavorite(word)
        if wasFavorite, reviewJudgment == nil {
            resetReviewCard(index: reviewIndex)
        }
    }

    private func submitReviewAnswer(for word: VocabularyWord) {
        let answer = reviewAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !answer.isEmpty, !isJudgingReviewAnswer, reviewJudgment == nil else { return }

        if FlashcardReviewFlow01.isUnknownAnswer(answer) {
            applyReviewJudgment(
                VocabularyAnswerJudgment(isCorrect: false, reason: "你已用 、 标记为不认识，本次未调用 AI 判分。"),
                to: word
            )
            return
        }

        isJudgingReviewAnswer = true
        reviewStatus = "正在按核心义项判分..."

        if Self.localVocabularyAnswerMatches(answer, expectedMeaning: word.meaning) {
            applyReviewJudgment(
                VocabularyAnswerJudgment(isCorrect: true, reason: "已命中标准释义中的核心义项。"),
                to: word
            )
            return
        }

        Task {
            do {
                let service = try DeepSeekPlanService()
                let judgment = try await service.judgeVocabularyAnswer(
                    word: word.word,
                    expectedMeaning: word.meaning,
                    userAnswer: answer
                )
                await MainActor.run {
                    applyReviewJudgment(judgment, to: word)
                }
            } catch {
                await MainActor.run {
                    applyReviewJudgment(
                        VocabularyAnswerJudgment(
                            isCorrect: false,
                            reason: "AI 判分不可用，本地也未匹配到核心义项；本词已按不熟处理。"
                        ),
                        to: word
                    )
                }
            }
        }
    }

    private func applyReviewJudgment(_ judgment: VocabularyAnswerJudgment, to word: VocabularyWord) {
        let now = Date()
        reviewedWordID = word.id
        reviewDismissedWordIDs.remove(word.id)
        Self.saveReviewDismissedWordIDs(reviewDismissedWordIDs)
        reviewProgressByWordID[word.id] = FlashcardReviewScheduler01.record(
            wordID: word.id,
            existing: reviewProgressByWordID[word.id],
            isCorrect: judgment.isCorrect,
            now: now
        )
        if !judgment.isCorrect {
            favoriteWordIDs.insert(word.id)
        }
        reviewJudgment = judgment
        showsCardBack = true
        isJudgingReviewAnswer = false
        reviewCorrectionAnswer = ""
        hasCompletedReviewCorrection = judgment.isCorrect

        if judgment.isCorrect, let nextReview = reviewProgressByWordID[word.id]?.nextReview {
            reviewStatus = "下次复习：\(Self.displayReviewDate(nextReview))"
        } else {
            reviewStatus = "等级已重置为 0，并加入错词收藏；先复述一个正确含义，再立即回炉。"
        }
        focusCurrentFlashcardReviewStep()
    }

    private func confirmReviewCorrection(for word: VocabularyWord) {
        guard Self.localVocabularyAnswerMatches(reviewCorrectionAnswer, expectedMeaning: word.meaning) else {
            reviewStatus = "还没有命中卡片中的核心含义，请再看一遍后复述。"
            flashcardReviewFocus = .correction
            return
        }
        hasCompletedReviewCorrection = true
        reviewStatus = "复述完成；点击继续后，这个词会立即回炉。"
        focusCurrentFlashcardReviewStep()
    }

    @discardableResult
    private func advanceFlashcardReviewStep() -> Bool {
        guard let word = activeReviewWord else { return false }

        let action = FlashcardReviewFlow01.advanceAction(
            isBusy: isJudgingReviewAnswer,
            hasJudgment: reviewJudgment != nil,
            isCorrect: reviewJudgment?.isCorrect,
            hasCompletedCorrection: hasCompletedReviewCorrection,
            answer: reviewAnswer,
            correction: reviewCorrectionAnswer
        )

        switch action {
        case .none:
            focusCurrentFlashcardReviewStep()
            return false
        case .skipCard:
            skipCurrentCard()
        case .submitAnswer:
            submitReviewAnswer(for: word)
        case .confirmCorrection:
            confirmReviewCorrection(for: word)
        case .nextCard:
            nextCard()
        }
        return true
    }

    private func focusCurrentFlashcardReviewStep() {
        let target: FlashcardReviewFocus01
        if reviewJudgment == nil {
            target = .answer
        } else if reviewJudgment?.isCorrect == false, !hasCompletedReviewCorrection {
            target = .correction
        } else {
            target = .workspace
        }

        Task { @MainActor in
            await Task.yield()
            flashcardReviewFocus = target
        }
    }

    private var reviewAdvanceButtonTitle: String {
        if reviewJudgment == nil { return "跳过" }
        if reviewJudgment?.isCorrect == false, !hasCompletedReviewCorrection { return "先复述" }
        return "继续"
    }

    private func reviewMetric(title: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(StudyTheme.heading(size: 18, weight: .bold))
                .foregroundStyle(StudyCategory.flashcards.tint)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(StudyTheme.secondaryInk)
        }
        .frame(minWidth: 58)
    }

    private func reviewQueueLabel(for word: VocabularyWord, queue: [VocabularyWord]) -> String {
        if reviewJudgment != nil, reviewedWordID == word.id, !queue.contains(where: { $0.id == word.id }) {
            return "本词已完成"
        }
        guard !queue.isEmpty else { return "0 / 0" }
        return "\(reviewIndex % queue.count + 1) / \(queue.count)"
    }

    nonisolated static func localVocabularyAnswerMatches(_ answer: String, expectedMeaning: String) -> Bool {
        let normalizedAnswer = normalizedVocabularyMeaning(answer)
        guard !normalizedAnswer.isEmpty else { return false }

        let meanings = expectedMeaning
            .components(separatedBy: CharacterSet(charactersIn: "；;、,，/|"))
            .map(normalizedVocabularyMeaning)
            .filter { !$0.isEmpty }

        return meanings.contains { meaning in
            meaning == normalizedAnswer
                || (normalizedAnswer.count >= 2 && meaning.contains(normalizedAnswer))
                || (meaning.count >= 2 && normalizedAnswer.contains(meaning))
        }
    }

    nonisolated private static func normalizedVocabularyMeaning(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: #"[\s。.!！?？:：\-—_()（）\[\]【】\"“”'‘’]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func displayReviewDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.isDateInToday(date) ? "今天 HH:mm" : "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    private static let flashcardDirectionKeys: Set<KeyEquivalent> = [
        .upArrow,
        .downArrow,
        .leftArrow,
        .rightArrow
    ]

    private static let flashcardAdvanceKeys: Set<KeyEquivalent> = flashcardDirectionKeys.union([.return])

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
        guard let word = extractSingleEnglishWord(from: String(first)) else { return nil }
        let normalized = EnglishHeadword.baseForm(word)
        let meaning = parts.count > 1
            ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            : VocabularyWord.pendingMeaning

        return VocabularyWord(
            id: "custom-\(normalized)",
            word: normalized,
            phonetic: "",
            partOfSpeech: "未标注",
            meaning: meaning.isEmpty ? VocabularyWord.pendingMeaning : meaning,
            example: VocabularyWord.starterExample(for: normalized),
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

    private static func loadBanishmentMigrationCatalog() -> [VocabularyWord] {
        let folderURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("CET-6", isDirectory: true)
            .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
        let files = ((try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: nil
        )) ?? [])
            .filter { $0.lastPathComponent.range(of: #"^custom_words\d+\.json$"#, options: .regularExpression) != nil }
            .sorted(by: numberedFileSort)

        var catalog = files.flatMap { fileURL -> [VocabularyWord] in
            guard let data = try? Data(contentsOf: fileURL),
                  let words = try? JSONDecoder().decode([VocabularyWord].self, from: data) else {
                return []
            }
            return words
        }
        if let defaultsData = UserDefaults.standard.data(forKey: customWordsKey),
           let defaultsWords = try? JSONDecoder().decode([VocabularyWord].self, from: defaultsData) {
            catalog.append(contentsOf: defaultsWords)
        }
        return mergeWords(catalog)
    }

    static func prepareBanishedVocabularyLibrary() -> (
        records: [BanishedVocabularyRecord01],
        keys: Set<String>
    ) {
        let legacyBanishedKeys = loadBanishedWordKeys()
        let records = BanishedVocabularyStore01.migratingLegacyKeys(
            existingRecords: BanishedVocabularyStore01.load(),
            legacyKeys: legacyBanishedKeys,
            customCatalog: loadBanishmentMigrationCatalog(),
            standardCatalog: []
        )
        try? BanishedVocabularyStore01.save(records)
        let keys = Set(records.map(\.key)).union(legacyBanishedKeys)
        saveBanishedWordKeys(keys)
        return (records, keys)
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

    private static func loadReviewDismissedWordIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: reviewDismissedWordsKey) ?? [])
    }

    private static func saveReviewDismissedWordIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: reviewDismissedWordsKey)
    }

    private static func loadDeletedWordIDs() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: deletedWordsKey) ?? [])
    }

    private static func saveDeletedWordIDs(_ ids: Set<String>) {
        UserDefaults.standard.set(Array(ids).sorted(), forKey: deletedWordsKey)
    }

    private static func loadBanishedWordKeys() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: banishedWordsKey) ?? [])
    }

    private static func saveBanishedWordKeys(_ keys: Set<String>) {
        UserDefaults.standard.set(Array(keys).sorted(), forKey: banishedWordsKey)
    }

    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter.string(from: date)
    }

    nonisolated private static let customWordsKey = "CET6DesktopWidget.customWords"
    private static let favoriteWordsKey = "CET6DesktopWidget.favoriteWordIDs"
    private static let reviewDismissedWordsKey = "CET6DesktopWidget.reviewDismissedWordIDs"
    private static let deletedWordsKey = "CET6DesktopWidget.deletedWordIDs"
    private static let banishedWordsKey = "CET6DesktopWidget.banishedVocabularyKeys01"
    private static let translationRecordsKey = "CET6DesktopWidget.translationRecords"
    private static let writingRecordsKey = "CET6DesktopWidget.writingRecords"

    static let defaultPlanText = ""
    private static let roots: [RootItem] = []

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
