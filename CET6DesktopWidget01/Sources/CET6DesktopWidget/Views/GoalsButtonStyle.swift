import SwiftUI

struct GoalsButtonStyle: ButtonStyle {
    enum Kind {
        case primary, secondary, compact, icon, row, card

        var cornerRadius: CGFloat {
            switch self {
            case .primary, .secondary: 10
            case .compact, .row: 7
            case .icon: 8
            case .card: 12
            }
        }
    }

    var kind: Kind
    var selected: Bool
    var tint: Color?

    init(_ kind: Kind = .secondary, selected: Bool = false, tint: Color? = nil) {
        self.kind = kind
        self.selected = selected
        self.tint = tint
    }

    func makeBody(configuration: Configuration) -> some View {
        GoalsButtonFace(
            label: sizedLabel(configuration.label),
            kind: kind,
            selected: selected,
            tint: configuration.role == .destructive ? StudyTheme.cinnabar : tint,
            isDestructive: configuration.role == .destructive,
            isPressed: configuration.isPressed
        )
    }

    @ViewBuilder
    private func sizedLabel(_ label: Configuration.Label) -> some View {
        switch kind {
        case .primary, .secondary:
            label
                .font(.system(size: 13, weight: kind == .primary ? .semibold : .medium))
                .padding(.horizontal, kind == .primary ? 15 : 13)
                .padding(.vertical, 8)
                .frame(minHeight: 34)
        case .compact:
            label.padding(.horizontal, 7).frame(minHeight: 23)
        case .icon:
            label.frame(minWidth: 24, minHeight: 24)
        case .row, .card:
            label
        }
    }
}

struct GoalsButtonFace<Label: View>: View {
    let label: Label
    var kind: GoalsButtonStyle.Kind
    var selected = false
    var tint: Color?
    var isDestructive = false
    var isPressed = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    @State private var origin: CGPoint?

    private static var fillAnimation: Animation {
        .timingCurve(0.16, 1, 0.3, 1, duration: 0.5)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: kind.cornerRadius)
        let isDark = colorScheme == .dark
        // A workspace can hold keyboard focus for its shortcuts. Animate local button interactions.
        let highlighted = isEnabled && (isHovered || isPressed)
        let ink = tint ?? (kind == .row && !selected ? StudyTheme.sidebarInk : StudyTheme.ink)

        label
            .foregroundStyle(ink)
            .background(surface, in: shape)
            .overlay {
                label
                    .foregroundStyle(ink)
                    .environment(\.colorScheme, isDark ? .light : .dark)
                    .colorMultiply(isDark ? Color(white: 0.46) : .white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isDark ? Color(red: 0.64, green: 0.63, blue: 0.61) : Color(white: 0.19))
                    .mask {
                        ButtonOriginFill(origin: origin, progress: highlighted ? 1 : 0)
                            .animation(reduceMotion ? nil : Self.fillAnimation, value: highlighted)
                    }
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
            .clipShape(shape)
            .overlay {
                shape.strokeBorder(border, lineWidth: 0.75).allowsHitTesting(false)
            }
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(isEnabled && isPressed && !reduceMotion ? 0.985 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isPressed)
            .contentShape(shape)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location) where !isHovered:
                    origin = location
                    isHovered = true
                case .ended:
                    isHovered = false
                case .active:
                    break
                }
            }
            .onChange(of: isPressed) { _, pressed in
                if pressed && !isHovered { origin = nil }
            }
    }

    private var surface: Color {
        if selected { return StudyTheme.buttonSelected }
        if isDestructive { return StudyTheme.buttonDestructive }
        switch kind {
        case .primary: return StudyTheme.buttonPrimary
        case .row: return .clear
        case .secondary, .compact, .icon, .card: return StudyTheme.buttonSurface
        }
    }

    private var border: Color {
        if isDestructive { return StudyTheme.cinnabar.opacity(0.55) }
        if selected || kind == .primary { return StudyTheme.buttonBorderStrong }
        return kind == .row ? .clear : StudyTheme.buttonBorder
    }
}

private struct ButtonOriginFill: Shape {
    var origin: CGPoint?
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let center = origin ?? CGPoint(x: rect.midX, y: rect.midY)
        let dx = max(abs(center.x - rect.minX), abs(rect.maxX - center.x))
        let dy = max(abs(center.y - rect.minY), abs(rect.maxY - center.y))
        let radius = (hypot(dx, dy) + 1) * max(0, progress)
        return Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: 2 * radius, height: 2 * radius
        ))
    }
}

struct GoalsSegmentedControl<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [(Selection, String)]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options, id: \.0) { value, label in
                let selected = value == selection
                Button {
                    selection = value
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                        .padding(.horizontal, 6)
                        .frame(maxWidth: .infinity, minHeight: 26)
                }
                .buttonStyle(GoalsButtonStyle(.row, selected: selected))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(3)
        .background(StudyTheme.sidebarBase, in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(StudyTheme.hairline).allowsHitTesting(false) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct GoalsMenuPicker<Selection: Hashable>: View {
    let title: String
    @Binding var selection: Selection
    let options: [(Selection, String)]

    var body: some View {
        let value = options.first { $0.0 == selection }?.1 ?? "—"
        Menu {
            ForEach(options, id: \.0) { option, label in
                Button {
                    selection = option
                } label: {
                    if option == selection {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
            }
        } label: {
            GoalsButtonFace(
                label: HStack(spacing: 8) {
                    Text(value).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9)
                .frame(height: 29),
                kind: .secondary
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .disabled(options.isEmpty)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }
}
