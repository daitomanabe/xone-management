import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var bridgeProcess: Process?
    private let bridgeName = "Xone K2 OSC LED Bridge"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        startBridge(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopBridge(nil)
        runBridgeCommand(["all-off"])
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "K2"
        item.button?.toolTip = bridgeName

        let menu = NSMenu()
        let title = NSMenuItem(title: bridgeName, action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Start Bridge", action: #selector(startBridge(_:)), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Stop Bridge", action: #selector(stopBridge(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "All LEDs Off", action: #selector(allOff(_:)), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        updateStatusTitle(running: false)
    }

    private func bridgeExecutableURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("osc-led-bridge")
    }

    private func updateStatusTitle(running: Bool) {
        statusItem?.button?.title = running ? "K2 On" : "K2"
    }

    @objc private func startBridge(_ sender: Any?) {
        if let process = bridgeProcess, process.isRunning {
            updateStatusTitle(running: true)
            return
        }

        guard let executableURL = bridgeExecutableURL() else {
            NSLog("Missing osc-led-bridge resource")
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["start"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { handle in
            if let text = String(data: handle.availableData, encoding: .utf8), !text.isEmpty {
                NSLog("%@", text.trimmingCharacters(in: .newlines))
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.updateStatusTitle(running: false)
                self?.bridgeProcess = nil
            }
        }

        do {
            try process.run()
            bridgeProcess = process
            updateStatusTitle(running: true)
        } catch {
            NSLog("Failed to start bridge: %@", "\(error)")
        }
    }

    @objc private func stopBridge(_ sender: Any?) {
        guard let process = bridgeProcess else {
            updateStatusTitle(running: false)
            return
        }
        if process.isRunning {
            process.terminate()
        }
        bridgeProcess = nil
        updateStatusTitle(running: false)
    }

    @objc private func allOff(_ sender: Any?) {
        runBridgeCommand(["all-off"])
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func runBridgeCommand(_ arguments: [String]) {
        guard let executableURL = bridgeExecutableURL() else {
            NSLog("Missing osc-led-bridge resource")
            return
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            NSLog("Failed to run bridge command %@: %@", arguments.joined(separator: " "), "\(error)")
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
