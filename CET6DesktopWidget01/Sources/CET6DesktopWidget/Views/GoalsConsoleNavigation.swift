import SwiftUI

struct ConsoleKeycap: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(StudyTheme.mutedInk)
            .padding(.horizontal, 5)
            .frame(height: 19)
            .background(StudyTheme.field, in: .rect(cornerRadius: 4))
            .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(StudyTheme.hairline) }
    }
}

struct ConsoleCommand: Identifiable {
    let id: String
    let title: String
    let detail: String
    let icon: String
    let action: () -> Void
}

struct ConsoleCommandPalette: View {
    let search: (String) -> [ConsoleCommand]
    let close: () -> Void
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var inputFocused: Bool

    var body: some View {
        let results = search(query)

        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 17))
                    .foregroundStyle(StudyTheme.mutedInk)
                    .accessibilityHidden(true)

                TextField("搜索页面、目标、计划表或单词", text: $query)
                    .font(.system(size: 14))
                    .focused($inputFocused)
                    .goalsInput(horizontal: 9, vertical: 5, minHeight: 33, focused: inputFocused)
                    .onSubmit { run(results) }
                    .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                        guard !results.isEmpty else { return .handled }
                        let offset = press.key == .upArrow ? -1 : 1
                        selection = (selection + offset + results.count) % results.count
                        return .handled
                    }

                Button("esc", action: close)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .buttonStyle(GoalsButtonStyle(.compact))
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("关闭搜索")
            }
            .padding(.horizontal, 16)
            .frame(height: 52)

            Rectangle().fill(StudyTheme.hairline).frame(height: 1)

            if results.isEmpty {
                VStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20))
                        .accessibilityHidden(true)
                    Text("没有匹配结果")
                        .font(.callout)
                }
                .foregroundStyle(StudyTheme.secondaryInk)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 27)
            } else {
                resultList(results)
            }
        }
        .background(StudyTheme.paper, in: .rect(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(StudyTheme.hairline) }
        .shadow(color: .black.opacity(0.2), radius: 24, x: 0, y: 12)
        .task {
            // The field becomes eligible for focus after the overlay enters the window.
            try? await Task.sleep(for: .milliseconds(60))
            if !Task.isCancelled { inputFocused = true }
        }
        .onChange(of: query) { _, _ in selection = 0 }
        .onChange(of: results.map(\.id)) { _, ids in
            selection = min(selection, max(0, ids.count - 1))
        }
    }

    private func resultList(_ results: [ConsoleCommand]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        Button {
                            close()
                            command.action()
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: command.icon)
                                    .frame(width: 18)
                                    .foregroundStyle(StudyTheme.secondaryInk)
                                Text(command.title).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(command.detail)
                                    .font(.system(size: 11))
                                    .foregroundStyle(StudyTheme.mutedInk)
                                    .lineLimit(1)
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .frame(height: 34)
                        }
                        .buttonStyle(GoalsButtonStyle(.row, selected: selection == index))
                        .accessibilityAddTraits(selection == index ? .isSelected : [])
                        .id(index)
                    }
                }
                .padding(6)
            }
            .frame(height: min(CGFloat(results.count) * 36 + 10, 295))
            .onChange(of: selection) { _, value in proxy.scrollTo(value) }
            .onChange(of: query) { _, _ in proxy.scrollTo(0, anchor: .top) }
        }
    }

    private func run(_ results: [ConsoleCommand]) {
        guard results.indices.contains(selection) else { return }
        close()
        results[selection].action()
    }
}
