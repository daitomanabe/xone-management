import AppKit
import CoreMIDI
import Foundation

final class DotView: NSView {
    var color: NSColor = .systemGray {
        didSet { needsDisplay = true }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 12, height: 12)
    }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).fill()
    }
}

final class StatusRow: NSStackView {
    private let dot = DotView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    init(title: String) {
        super.init(frame: .zero)
        orientation = .horizontal
        alignment = .centerY
        spacing = 10

        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.widthAnchor.constraint(equalToConstant: 116).isActive = true

        detailLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail

        addArrangedSubview(dot)
        addArrangedSubview(titleLabel)
        addArrangedSubview(detailLabel)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(color: NSColor, detail: String) {
        dot.color = color
        detailLabel.stringValue = detail
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var window: NSWindow?
    private var bridgeProcess: Process?
    private var bridgeOutputBuffer = ""
    private var timer: Timer?

    private let bridgeName = "Xone K2 OSC LED Bridge"
    private let midiMatch = "XONE:K2"
    private let oscPort = 9123

    private let bridgeRow = StatusRow(title: "Bridge")
    private let midiRow = StatusRow(title: "K2 MIDI")
    private let oscRow = StatusRow(title: "OSC Input")
    private let abletonRow = StatusRow(title: "Ableton Beat")
    private let levelsLabel = NSTextField(labelWithString: "Levels: low --  mid --  high --")
    private let logView = NSTextView()

    private var lastOSCTime: Date?
    private var lastBeatTime: Date?
    private var lastOSCAddress = "-"
    private var lastBeat = "-"
    private var lastLevels = "low --  mid --  high --"
    private var logLines: [String] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        configureStatusItem()
        configureWindow()
        startTimers()
        startBridge(nil)
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        stopBridge(nil)
        runBridgeCommand(["all-off"])
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
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
        menu.addItem(NSMenuItem(title: "Show Status", action: #selector(showWindow(_:)), keyEquivalent: "w"))
        menu.addItem(NSMenuItem(title: "Start Bridge", action: #selector(startBridge(_:)), keyEquivalent: "s"))
        menu.addItem(NSMenuItem(title: "Stop Bridge", action: #selector(stopBridge(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "All LEDs Off", action: #selector(allOff(_:)), keyEquivalent: "o"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        updateStatusTitle(running: false)
    }

    private func configureWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 500, height: 380)
        let window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = bridgeName
        window.center()
        window.delegate = self

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 14
        root.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Xone:K2 OSC LED Bridge")
        title.font = .systemFont(ofSize: 18, weight: .semibold)

        let subtitle = NSTextField(labelWithString: "OSC 127.0.0.1:\(oscPort)  |  MIDI \(midiMatch)  |  Channel 15")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor

        levelsLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        levelsLabel.textColor = .secondaryLabelColor

        let buttonRow = NSStackView()
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.addArrangedSubview(button(title: "Start", action: #selector(startBridge(_:))))
        buttonRow.addArrangedSubview(button(title: "Stop", action: #selector(stopBridge(_:))))
        buttonRow.addArrangedSubview(button(title: "All LEDs Off", action: #selector(allOff(_:))))

        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textColor = .secondaryLabelColor
        logView.backgroundColor = .textBackgroundColor
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.documentView = logView
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 116).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 452).isActive = true

        root.addArrangedSubview(title)
        root.addArrangedSubview(subtitle)
        root.addArrangedSubview(bridgeRow)
        root.addArrangedSubview(midiRow)
        root.addArrangedSubview(oscRow)
        root.addArrangedSubview(abletonRow)
        root.addArrangedSubview(levelsLabel)
        root.addArrangedSubview(buttonRow)
        root.addArrangedSubview(scroll)

        let content = NSView()
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18)
        ])

        window.contentView = content
        self.window = window
        updateUI()
    }

    private func button(title: String, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        return button
    }

    private func startTimers() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUI()
        }
    }

    private func bridgeExecutableURL() -> URL? {
        Bundle.main.resourceURL?.appendingPathComponent("osc-led-bridge")
    }

    private func fallbackBridgeExecutableURL() -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("scripts/osc-led-bridge")
    }

    private func resolvedBridgeExecutableURL() -> URL {
        let bundled = bridgeExecutableURL()
        if let bundled, FileManager.default.isExecutableFile(atPath: bundled.path) {
            return bundled
        }
        return fallbackBridgeExecutableURL()
    }

    private func updateStatusTitle(running: Bool) {
        statusItem?.button?.title = running ? "K2 On" : "K2"
    }

    @objc private func showWindow(_ sender: Any?) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func startBridge(_ sender: Any?) {
        if let process = bridgeProcess, process.isRunning {
            updateStatusTitle(running: true)
            updateUI()
            return
        }

        let process = Process()
        process.executableURL = resolvedBridgeExecutableURL()
        process.arguments = ["start"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let self else { return }
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self.consumeBridgeOutput(text)
            }
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.appendLog("Bridge process stopped")
                self?.updateStatusTitle(running: false)
                self?.bridgeProcess = nil
                self?.updateUI()
            }
        }

        do {
            try process.run()
            bridgeProcess = process
            appendLog("Bridge process started")
            updateStatusTitle(running: true)
            updateUI()
        } catch {
            appendLog("Failed to start bridge: \(error)")
            updateUI()
        }
    }

    @objc private func stopBridge(_ sender: Any?) {
        guard let process = bridgeProcess else {
            updateStatusTitle(running: false)
            updateUI()
            return
        }
        if process.isRunning {
            process.terminate()
        }
        bridgeProcess = nil
        updateStatusTitle(running: false)
        updateUI()
    }

    @objc private func allOff(_ sender: Any?) {
        runBridgeCommand(["all-off"])
        appendLog("All LEDs Off requested")
    }

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func runBridgeCommand(_ arguments: [String]) {
        let process = Process()
        process.executableURL = resolvedBridgeExecutableURL()
        process.arguments = arguments
        do {
            try process.run()
        } catch {
            appendLog("Failed to run bridge command \(arguments.joined(separator: " ")): \(error)")
        }
    }

    private func consumeBridgeOutput(_ text: String) {
        bridgeOutputBuffer += text
        while let newlineRange = bridgeOutputBuffer.range(of: "\n") {
            let line = String(bridgeOutputBuffer[..<newlineRange.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            bridgeOutputBuffer.removeSubrange(...newlineRange.lowerBound)
            guard !line.isEmpty else { continue }
            handleBridgeLine(line)
        }
    }

    private func handleBridgeLine(_ line: String) {
        appendLog(line)
        guard line.hasPrefix("EVENT ") else {
            updateUI()
            return
        }

        let event = String(line.dropFirst(6))
        if event.hasPrefix("osc ") {
            lastOSCTime = Date()
            if let address = value(for: "address", in: event) {
                lastOSCAddress = address
            }
        } else if event.hasPrefix("beat ") {
            lastBeatTime = Date()
            if let beat = value(for: "value", in: event) {
                lastBeat = beat
            }
        } else if event.hasPrefix("levels ") {
            let low = value(for: "low", in: event) ?? "--"
            let mid = value(for: "mid", in: event) ?? "--"
            let high = value(for: "high", in: event) ?? "--"
            lastLevels = "low \(low)  mid \(mid)  high \(high)"
        }
        updateUI()
    }

    private func value(for key: String, in line: String) -> String? {
        let prefix = "\(key)="
        return line.split(separator: " ")
            .map(String.init)
            .first(where: { $0.hasPrefix(prefix) })?
            .dropFirst(prefix.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private func appendLog(_ line: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logLines.append("[\(stamp)] \(line)")
        if logLines.count > 80 {
            logLines.removeFirst(logLines.count - 80)
        }
        logView.string = logLines.suffix(14).joined(separator: "\n")
        logView.scrollToEndOfDocument(nil)
    }

    private func updateUI() {
        let running = bridgeProcess?.isRunning == true
        bridgeRow.update(color: running ? .systemGreen : .systemRed, detail: running ? "running" : "stopped")
        updateStatusTitle(running: running)

        if let port = midiOutputMatching(midiMatch) {
            midiRow.update(color: .systemGreen, detail: "output \(port.index): \(port.name)")
        } else {
            midiRow.update(color: .systemRed, detail: "not found")
        }

        if let lastOSCTime {
            let age = Date().timeIntervalSince(lastOSCTime)
            let color: NSColor = age < 3 ? .systemGreen : .systemOrange
            oscRow.update(color: color, detail: "\(lastOSCAddress)  \(formatAge(age)) ago")
        } else {
            oscRow.update(color: .systemGray, detail: "waiting on 127.0.0.1:\(oscPort)")
        }

        if let lastBeatTime {
            let age = Date().timeIntervalSince(lastBeatTime)
            let color: NSColor = age < 3 ? .systemGreen : .systemOrange
            abletonRow.update(color: color, detail: "beat \(lastBeat)  \(formatAge(age)) ago")
        } else {
            abletonRow.update(color: .systemGray, detail: "waiting for /xone/beat")
        }

        levelsLabel.stringValue = "Levels: \(lastLevels)"
    }

    private func formatAge(_ age: TimeInterval) -> String {
        if age < 1 {
            return "<1s"
        }
        if age < 60 {
            return "\(Int(age))s"
        }
        return "\(Int(age / 60))m"
    }

    private func midiOutputMatching(_ text: String) -> (index: Int, name: String)? {
        let lower = text.lowercased()
        for index in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(index)
            var unmanagedName: Unmanaged<CFString>?
            let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &unmanagedName)
            guard status == noErr, let name = unmanagedName?.takeRetainedValue() as String? else {
                continue
            }
            if name.lowercased().contains(lower) {
                return (index, name)
            }
        }
        return nil
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
