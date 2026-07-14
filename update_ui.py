import sys

file_path = "/Users/yuanmuyou/Documents/CET-6/CET6DesktopWidget01/Sources/CET6DesktopWidget/Views/DesktopWidgetView.swift"

with open(file_path, "r") as f:
    content = f.read()

# Revert picker changes
picker_old = """.pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 170)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.03)))
            .overlay(Capsule().stroke(StudyTheme.hairline, lineWidth: 1))"""

picker_new = """.labelsHidden()
            .frame(width: 170)"""

content = content.replace(picker_old, picker_new)

picker2_old = """.pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 150)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.black.opacity(0.03)))
            .overlay(Capsule().stroke(StudyTheme.hairline, lineWidth: 1))"""

picker2_new = """.labelsHidden()
            .frame(width: 150)"""

content = content.replace(picker2_old, picker2_new)

# Increase corner radius for all panels
content = content.replace("cornerRadius: 5", "cornerRadius: 12")
content = content.replace("cornerRadius: 4", "cornerRadius: 10")

with open(file_path, "w") as f:
    f.write(content)
