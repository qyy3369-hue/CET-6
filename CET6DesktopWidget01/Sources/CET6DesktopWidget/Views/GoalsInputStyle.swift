import SwiftUI

extension View {
    func goalsInput(
        horizontal: CGFloat = 12,
        vertical: CGFloat = 8,
        minHeight: CGFloat = 0,
        radius: CGFloat = 8,
        focused: Bool? = nil
    ) -> some View {
        modifier(GoalsInputStyle(horizontal: horizontal, vertical: vertical, minHeight: minHeight, radius: radius, focused: focused))
    }
}

private struct GoalsInputStyle: ViewModifier {
    let horizontal: CGFloat
    let vertical: CGFloat
    let minHeight: CGFloat
    let radius: CGFloat
    let focused: Bool?
    @FocusState private var inputFocused: Bool

    func body(content: Content) -> some View {
        Group {
            if focused != nil {
                content.focusEffectDisabled()
            } else {
                content.focusEffectDisabled().focused($inputFocused)
            }
        }
        .textFieldStyle(.plain)
        .padding(.horizontal, horizontal)
        .padding(.vertical, vertical)
        .frame(minHeight: minHeight)
        .background(StudyTheme.paper, in: .rect(cornerRadius: radius))
        .overlay {
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder((focused ?? inputFocused) ? StudyTheme.focusBorder : StudyTheme.hairline)
                .allowsHitTesting(false)
        }
    }
}
