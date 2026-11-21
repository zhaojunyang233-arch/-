import AppKit

@main
@MainActor
final class ClipboardHistoryApp: NSObject, NSApplicationDelegate {
    private var menuBarController: MenuBarController?
    private var history: ClipboardHistory?

    static func main() {
        let application = NSApplication.shared
        let delegate = ClipboardHistoryApp()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let history = ClipboardHistory(pasteboard: .general)
        let controller = MenuBarController(history: history)
        self.history = history
        menuBarController = controller
        history.start()
        controller.showLaunchWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        menuBarController?.showLaunchWindow()
        return false
    }

    func applicationWillTerminate(_ notification: Notification) {
        menuBarController?.stop()
        history?.stop()
    }
}
