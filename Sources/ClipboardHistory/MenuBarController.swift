import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private let title = "剪贴板历史"
    private let history: ClipboardHistory
    private let statusItem = NSStatusBar.system.statusItem(withLength: 24)
    private let popover = NSPopover()
    private var shortcut: GlobalShortcut?
    private lazy var launchWindow: NSWindow = makeWindow(
        titled: title,
        showing: HistoryView(
            history: history,
            showsHeading: false,
            shortcutActive: shortcut != nil,
            openSettings: { [weak self] in self?.showSettings() },
            close: { [weak self] in self?.launchWindow.close() }
        )
    )
    private lazy var settingsWindow: NSWindow = makeWindow(
        titled: "剪贴板历史设置",
        showing: SettingsView(
            history: history,
            showMenuBarIcon: { [weak self] in self?.statusItem.isVisible = true },
            close: { [weak self] in self?.settingsWindow.close() }
        )
    )

    init(history: ClipboardHistory) {
        self.history = history
        super.init()

        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: HistoryView(
                history: history,
                openSettings: { [weak self] in self?.showSettings() },
                close: { [weak self] in self?.popover.performClose(nil) }
            )
        )

        statusItem.autosaveName = "ClipboardHistory"
        if let button = statusItem.button {
            let icon = NSImage(systemSymbolName: "list.clipboard", accessibilityDescription: title)
            icon?.isTemplate = true
            button.image = icon
            button.title = icon == nil ? "剪" : ""
            button.toolTip = title
            button.setAccessibilityLabel(title)
            button.target = self
            button.action = #selector(toggleHistory(_:))
        }
        shortcut = GlobalShortcut { [weak self] in self?.showFromShortcut() }
    }

    func stop() {
        shortcut?.stop()
    }

    func showLaunchWindow() {
        if popover.isShown {
            popover.performClose(nil)
        }
        NSApplication.shared.activate()
        launchWindow.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        if popover.isShown {
            popover.performClose(nil)
        }
        NSApplication.shared.activate()
        settingsWindow.makeKeyAndOrderFront(nil)
    }

    @objc private func toggleHistory(_ button: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(button)
            return
        }

        showPopover(from: button)
    }

    private func showFromShortcut() {
        guard !popover.isShown else { return }
        if statusItem.isVisible, let button = statusItem.button,
           button.window?.occlusionState.contains(.visible) == true {
            showPopover(from: button)
        } else {
            showLaunchWindow()
        }
    }

    private func showPopover(from button: NSStatusBarButton) {
        launchWindow.orderOut(nil)
        NSApplication.shared.activate()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makeWindow<Content: View>(titled title: String, showing view: Content) -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.styleMask = [.titled, .closable]
        window.title = title
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}
