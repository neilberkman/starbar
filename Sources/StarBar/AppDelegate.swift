import Cocoa

public class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // Create menu bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "star", accessibilityDescription: "StarBar")
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem?.menu = menu

        print("StarBar started")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        print("StarBar shutting down")
    }
}
