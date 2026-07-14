import AppKit
import SwiftUI

@MainActor
final class WidgetVisibilityController: ObservableObject {
    @Published var isVisible: Bool {
        didSet {
            guard oldValue != isVisible else { return }
            userDefaults.set(isVisible, forKey: Self.userDefaultsKey)
            onVisibilityChange?(isVisible)
        }
    }

    var onVisibilityChange: ((Bool) -> Void)?

    private static let userDefaultsKey = "floatingWidgetIsVisible"
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.isVisible = userDefaults.object(forKey: Self.userDefaultsKey) as? Bool ?? true
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var widgetWindow: DraggableWidgetWindow?
    private var studyWindow: NSWindow?
    private var dateRolloverTimer: Timer?
    private var lastKnownDateKey = DateKey.today()
    private let store = TaskStore()
    private let widgetVisibility = WidgetVisibilityController()
    private lazy var dailyVocabularyImporter = DailyVocabularyImporter01(store: store)

    func applicationDidFinishLaunching(_ notification: Notification) {
        let goals = GoalPlanStore01.load(defaultPlanText: StudyWindowView.defaultPlanText)
        store.refreshPlanTasks(from: goals) { plan in
            plan.generatedSchedule ?? StudyWindowView.generateSchedule(from: plan.planText, anchorDateKey: DateKey.from(plan.createdAt))
        }
        store.advancePlanDatesIfNeeded(from: goals)
        dailyVocabularyImporter.start()
        startDateRolloverMonitor()
        widgetVisibility.onVisibilityChange = { [weak self] isVisible in
            self?.setWidgetWindowVisible(isVisible)
        }

        let contentView = DesktopWidgetView(store: store) { [weak self] in
            self?.openStudyWindow()
        }
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.appearance = NSAppearance(named: .aqua)

        let window = DraggableWidgetWindow(
            contentRect: NSRect(x: 120, y: 500, width: 360, height: 330),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.contentView = hostingView
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .normal
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        window.hidesOnDeactivate = false
        window.isFloatingPanel = false
        window.isMovableByWindowBackground = true
        self.widgetWindow = window
        setWidgetWindowVisible(widgetVisibility.isVisible)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openStudyWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        dailyVocabularyImporter.stop()
        dateRolloverTimer?.invalidate()
    }

    private func startDateRolloverMonitor() {
        dateRolloverTimer?.invalidate()
        dateRolloverTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.advancePlanDatesAfterDateChange()
            }
        }
    }

    private func advancePlanDatesAfterDateChange() {
        let today = DateKey.today()
        guard today != lastKnownDateKey else { return }

        lastKnownDateKey = today
        let goals = GoalPlanStore01.load(defaultPlanText: StudyWindowView.defaultPlanText)
        store.refreshPlanTasks(from: goals) { plan in
            plan.generatedSchedule ?? StudyWindowView.generateSchedule(from: plan.planText, anchorDateKey: DateKey.from(plan.createdAt))
        }
        store.advancePlanDatesIfNeeded(from: goals)
    }

    private func openStudyWindow() {
        if let studyWindow {
            studyWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = StudyWindowView(store: store, widgetVisibility: widgetVisibility)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.appearance = NSAppearance(named: .aqua)
        let window = NSWindow(
            contentRect: NSRect(x: 180, y: 140, width: 1040, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "目标计划中心"
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.86)
        window.isOpaque = false
        window.titlebarAppearsTransparent = false
        window.contentMinSize = NSSize(width: 900, height: 560)
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.studyWindow = window
    }

    private func setWidgetWindowVisible(_ isVisible: Bool) {
        guard let widgetWindow else { return }

        if isVisible {
            widgetWindow.orderFrontRegardless()
        } else {
            widgetWindow.orderOut(nil)
        }
    }
}
