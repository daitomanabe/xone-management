import CoreMIDI
import Darwin
import Foundation

let defaultThresholds: [Double] = [0.08, 0.22, 0.45, 0.7]
let buttons = ["A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P"]
let colors = ["red", "amber", "green"]

let notesByButton: [String: [String: UInt8]] = [
    "A": ["red": 36, "amber": 72, "green": 108],
    "B": ["red": 37, "amber": 73, "green": 109],
    "C": ["red": 38, "amber": 74, "green": 110],
    "D": ["red": 39, "amber": 75, "green": 111],
    "E": ["red": 32, "amber": 68, "green": 104],
    "F": ["red": 33, "amber": 69, "green": 105],
    "G": ["red": 34, "amber": 70, "green": 106],
    "H": ["red": 35, "amber": 71, "green": 107],
    "I": ["red": 28, "amber": 64, "green": 100],
    "J": ["red": 29, "amber": 65, "green": 101],
    "K": ["red": 30, "amber": 66, "green": 102],
    "L": ["red": 31, "amber": 67, "green": 103],
    "M": ["red": 24, "amber": 60, "green": 96],
    "N": ["red": 25, "amber": 61, "green": 97],
    "O": ["red": 26, "amber": 62, "green": 98],
    "P": ["red": 27, "amber": 63, "green": 99]
]

let meterColumns: [String: [String]] = [
    "low": ["M", "I", "E", "A"],
    "mid": ["N", "J", "F", "B"],
    "high": ["O", "K", "G", "C"]
]

let beatButtons: [Int: String] = [1: "D", 2: "H", 3: "L", 4: "P"]
let levelColors = ["green", "green", "amber", "red"]
let beatColors: [Int: String] = [1: "red", 2: "amber", 3: "amber", 4: "amber"]

struct Options {
    var command = "start"
    var channel = 15
    var gain = 1.0
    var host = "127.0.0.1"
    var midi = "XONE:K2"
    var oscPort = 9123
    var beatMs = 170
    var thresholds = defaultThresholds
    var logMidi = false
    var help = false
    var positionals: [String] = []
}

enum AppError: Error, CustomStringConvertible {
    case missingOptionValue(String)
    case invalidOption(String)
    case invalidChannel(Int)
    case invalidThresholds(String)
    case midiStatus(OSStatus, String)
    case midiOutputNotFound(String, [MidiPort])
    case invalidButton(String)
    case invalidColor(String)
    case socket(String)

    var description: String {
        switch self {
        case .missingOptionValue(let option):
            return "Missing value for \(option)"
        case .invalidOption(let option):
            return "Unknown option: \(option)"
        case .invalidChannel(let channel):
            return "MIDI channel must be an integer from 1 to 16. Received: \(channel)"
        case .invalidThresholds(let value):
            return "--thresholds must be four comma-separated numbers. Received: \(value)"
        case .midiStatus(let status, let operation):
            return "\(operation) failed with CoreMIDI status \(status)"
        case .midiOutputNotFound(let match, let ports):
            let names = ports.map { "  \($0.index): \($0.name)" }.joined(separator: "\n")
            return "MIDI output matching \"\(match)\" was not found.\nAvailable outputs:\n\(names.isEmpty ? "  <none>" : names)"
        case .invalidButton(let button):
            return "Unknown K2 button \"\(button)\". Expected A-P."
        case .invalidColor(let color):
            return "Unknown K2 LED color \"\(color)\". Expected red, amber, green, or off."
        case .socket(let message):
            return message
        }
    }
}

struct MidiPort {
    let index: Int
    let name: String
    let endpoint: MIDIEndpointRef
}

enum OSCArg {
    case int(Int)
    case float(Double)
    case string(String)
    case bool(Bool)

    var number: Double? {
        switch self {
        case .int(let value):
            return Double(value)
        case .float(let value):
            return value
        case .string(let value):
            return Double(value)
        case .bool(let value):
            return value ? 1 : 0
        }
    }

    var text: String? {
        switch self {
        case .int(let value):
            return String(value)
        case .float(let value):
            return String(value)
        case .string(let value):
            return value
        case .bool(let value):
            return value ? "true" : "false"
        }
    }
}

struct OSCMessage {
    let address: String
    let args: [OSCArg]
}

func usage() -> String {
    """
    Usage:
      scripts/osc-led-bridge start [--midi XONE:K2] [--channel 15] [--osc-port 9123]
      scripts/osc-led-bridge list
      scripts/osc-led-bridge test
      scripts/osc-led-bridge all-off
      scripts/osc-led-bridge set A red

    OSC:
      /xone/levels <low 0..1> <mid 0..1> <high 0..1>
      /xone/level/low <value 0..1>
      /xone/level/mid <value 0..1>
      /xone/level/high <value 0..1>
      /xone/beat <beat-number-or-step>
      /xone/clear
    """
}

func parseArgs(_ argv: [String]) throws -> Options {
    var args = argv
    var options = Options()

    if let first = args.first, !first.hasPrefix("-") {
        options.command = first
        args.removeFirst()
    }

    func takeValue(_ option: String, _ inline: String?) throws -> String {
        if let inline {
            return inline
        }
        guard !args.isEmpty else {
            throw AppError.missingOptionValue(option)
        }
        return args.removeFirst()
    }

    while !args.isEmpty {
        let token = args.removeFirst()
        if !token.hasPrefix("--") {
            options.positionals.append(token)
            continue
        }

        let parts = token.dropFirst(2).split(separator: "=", maxSplits: 1).map(String.init)
        let key = parts[0]
        let inline = parts.count > 1 ? parts[1] : nil

        switch key {
        case "channel":
            options.channel = Int(try takeValue(token, inline)) ?? options.channel
        case "gain":
            options.gain = Double(try takeValue(token, inline)) ?? options.gain
        case "host":
            options.host = try takeValue(token, inline)
        case "midi":
            options.midi = try takeValue(token, inline)
        case "osc-port":
            options.oscPort = Int(try takeValue(token, inline)) ?? options.oscPort
        case "beat-ms":
            options.beatMs = Int(try takeValue(token, inline)) ?? options.beatMs
        case "thresholds":
            let raw = try takeValue(token, inline)
            let thresholds = raw.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard thresholds.count == 4 else {
                throw AppError.invalidThresholds(raw)
            }
            options.thresholds = thresholds
        case "log-midi":
            options.logMidi = inline.map { $0 != "false" } ?? true
        case "help":
            options.help = true
        default:
            throw AppError.invalidOption(token)
        }
    }

    guard (1...16).contains(options.channel) else {
        throw AppError.invalidChannel(options.channel)
    }
    return options
}

func check(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw AppError.midiStatus(status, operation)
    }
}

func endpointName(_ endpoint: MIDIEndpointRef) -> String {
    var cfName: Unmanaged<CFString>?
    let status = MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &cfName)
    guard status == noErr, let name = cfName?.takeRetainedValue() as String? else {
        return "<unknown>"
    }
    return name
}

func midiOutputs() -> [MidiPort] {
    (0..<MIDIGetNumberOfDestinations()).map { index in
        let endpoint = MIDIGetDestination(index)
        return MidiPort(index: index, name: endpointName(endpoint), endpoint: endpoint)
    }
}

func midiInputs() -> [MidiPort] {
    (0..<MIDIGetNumberOfSources()).map { index in
        let endpoint = MIDIGetSource(index)
        return MidiPort(index: index, name: endpointName(endpoint), endpoint: endpoint)
    }
}

final class K2Controller {
    let port: MidiPort
    let channel: Int
    private let client: MIDIClientRef
    private let outputPort: MIDIPortRef
    private let velocity: UInt8
    private let logMidi: Bool
    private var state = Dictionary(uniqueKeysWithValues: buttons.map { ($0, "off") })

    init(options: Options) throws {
        let outputs = midiOutputs()
        if let index = Int(options.midi), let match = outputs.first(where: { $0.index == index }) {
            port = match
        } else {
            let lower = options.midi.lowercased()
            if let exact = outputs.first(where: { $0.name.lowercased() == lower }) {
                port = exact
            } else if let partial = outputs.first(where: { $0.name.lowercased().contains(lower) }) {
                port = partial
            } else {
                throw AppError.midiOutputNotFound(options.midi, outputs)
            }
        }

        channel = options.channel
        velocity = 127
        logMidi = options.logMidi

        var clientRef = MIDIClientRef()
        try check(MIDIClientCreate("Xone K2 OSC LED Bridge" as CFString, nil, nil, &clientRef), "MIDIClientCreate")
        client = clientRef

        var outputRef = MIDIPortRef()
        try check(MIDIOutputPortCreate(client, "Xone K2 Output" as CFString, &outputRef), "MIDIOutputPortCreate")
        outputPort = outputRef
    }

    deinit {
        MIDIPortDispose(outputPort)
        MIDIClientDispose(client)
    }

    private func send(_ status: UInt8, _ note: UInt8, _ value: UInt8) {
        let message: [UInt8] = [status + UInt8(channel - 1), note, value]
        if logMidi {
            print("midi " + message.map { String(format: "%02x", $0) }.joined(separator: " "))
        }

        message.withUnsafeBufferPointer { pointer in
            var packetList = MIDIPacketList()
            let packet = MIDIPacketListInit(&packetList)
            _ = MIDIPacketListAdd(&packetList, MemoryLayout<MIDIPacketList>.size, packet, 0, message.count, pointer.baseAddress!)
            MIDISend(outputPort, port.endpoint, &packetList)
        }
    }

    private func validateButton(_ button: String) throws -> String {
        let normalized = button.uppercased()
        guard notesByButton[normalized] != nil else {
            throw AppError.invalidButton(button)
        }
        return normalized
    }

    private func validateColor(_ color: String) throws -> String {
        let normalized = color.lowercased()
        if normalized == "off" {
            return "off"
        }
        guard colors.contains(normalized) else {
            throw AppError.invalidColor(color)
        }
        return normalized
    }

    func clearButton(_ button: String) {
        guard let colorNotes = notesByButton[button] else { return }
        for color in colors {
            if let note = colorNotes[color] {
                send(0x80, note, 0)
            }
        }
        state[button] = "off"
    }

    func setButton(_ button: String, _ color: String) throws {
        let normalizedButton = try validateButton(button)
        let normalizedColor = try validateColor(color)
        let previous = state[normalizedButton] ?? "off"
        if previous == normalizedColor {
            return
        }

        if previous != "off", let note = notesByButton[normalizedButton]?[previous] {
            send(0x80, note, 0)
        } else {
            clearButton(normalizedButton)
        }

        if normalizedColor != "off", let note = notesByButton[normalizedButton]?[normalizedColor] {
            send(0x90, note, velocity)
        }
        state[normalizedButton] = normalizedColor
    }

    func allOff() {
        for button in buttons {
            clearButton(button)
        }
    }
}

final class Renderer {
    private let k2: K2Controller
    private let gain: Double
    private let thresholds: [Double]
    private let beatMs: Int
    private var levels: [String: Double] = ["low": 0, "mid": 0, "high": 0]
    private var activeBeat = 0
    private var beatWorkItem: DispatchWorkItem?

    init(k2: K2Controller, options: Options) {
        self.k2 = k2
        gain = options.gain
        thresholds = options.thresholds
        beatMs = options.beatMs
    }

    private func clamp01(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(1, max(0, value))
    }

    private func levelToBars(_ value: Double) -> Int {
        thresholds.reduce(0) { count, threshold in value >= threshold ? count + 1 : count }
    }

    private func normalizeBeat(_ value: Double) -> Int {
        let beat = Int(floor(value))
        if beat >= 1 && beat <= 4 { return beat }
        if beat <= 0 { return 1 }
        return ((beat - 1) % 4) + 1
    }

    private func renderMeters() {
        for (band, columnButtons) in meterColumns {
            let bars = levelToBars(clamp01((levels[band] ?? 0) * gain))
            for (index, button) in columnButtons.enumerated() {
                try? k2.setButton(button, index < bars ? levelColors[index] : "off")
            }
        }
    }

    private func renderBeat() {
        for (step, button) in beatButtons {
            try? k2.setButton(button, step == activeBeat ? (beatColors[step] ?? "amber") : "off")
        }
    }

    func setLevels(low: Double? = nil, mid: Double? = nil, high: Double? = nil) {
        if let low { levels["low"] = clamp01(low) }
        if let mid { levels["mid"] = clamp01(mid) }
        if let high { levels["high"] = clamp01(high) }
        renderMeters()
        renderBeat()
    }

    func setLevel(band: String, value: Double) {
        if levels.keys.contains(band) {
            levels[band] = clamp01(value)
            renderMeters()
            renderBeat()
        }
    }

    func pulseBeat(_ rawBeat: Double) {
        activeBeat = normalizeBeat(rawBeat)
        renderBeat()
        beatWorkItem?.cancel()

        let item = DispatchWorkItem { [weak self] in
            self?.activeBeat = 0
            self?.renderBeat()
        }
        beatWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(beatMs), execute: item)
    }

    func stop() {
        beatWorkItem?.cancel()
        beatWorkItem = nil
        activeBeat = 0
        k2.allOff()
    }
}

func parseOSCString(_ data: Data, _ offset: inout Int) -> String? {
    guard offset < data.count else { return nil }
    let start = offset
    while offset < data.count && data[offset] != 0 {
        offset += 1
    }
    guard offset < data.count else { return nil }
    let bytes = data[start..<offset]
    offset += 1
    while offset % 4 != 0 { offset += 1 }
    return String(data: bytes, encoding: .utf8)
}

func readInt32(_ data: Data, _ offset: inout Int) -> Int32? {
    guard offset + 4 <= data.count else { return nil }
    let value = data[offset..<offset + 4].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    offset += 4
    return Int32(bitPattern: value)
}

func parseOSCMessage(_ data: Data) -> OSCMessage? {
    var offset = 0
    guard let address = parseOSCString(data, &offset), address.hasPrefix("/") else {
        return parseTextMessage(data)
    }

    guard let tags = parseOSCString(data, &offset), tags.hasPrefix(",") else {
        return OSCMessage(address: address, args: [])
    }

    var args: [OSCArg] = []
    for tag in tags.dropFirst() {
        switch tag {
        case "i":
            if let value = readInt32(data, &offset) {
                args.append(.int(Int(value)))
            }
        case "f":
            if let bits = readInt32(data, &offset) {
                args.append(.float(Double(Float(bitPattern: UInt32(bitPattern: bits)))))
            }
        case "s":
            if let value = parseOSCString(data, &offset) {
                args.append(.string(value))
            }
        case "T":
            args.append(.bool(true))
        case "F":
            args.append(.bool(false))
        default:
            return nil
        }
    }

    return OSCMessage(address: address, args: args)
}

func parseTextMessage(_ data: Data) -> OSCMessage? {
    guard let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !text.isEmpty else {
        return nil
    }
    let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
    guard let address = parts.first, address.hasPrefix("/") else {
        return nil
    }
    return OSCMessage(address: address, args: parts.dropFirst().map { value in
        if let intValue = Int(value) { return .int(intValue) }
        if let doubleValue = Double(value) { return .float(doubleValue) }
        return .string(value)
    })
}

func handle(_ message: OSCMessage, renderer: Renderer, k2: K2Controller) {
    func number(_ index: Int, fallback: Double = 0) -> Double {
        guard index < message.args.count else { return fallback }
        return message.args[index].number ?? fallback
    }

    func text(_ index: Int, fallback: String = "") -> String {
        guard index < message.args.count else { return fallback }
        return message.args[index].text ?? fallback
    }

    switch message.address {
    case "/xone/levels", "/live/levels":
        renderer.setLevels(low: number(0), mid: number(1), high: number(2))
    case "/xone/beat", "/live/beat":
        renderer.pulseBeat(number(0, fallback: 1))
    case "/xone/set":
        try? k2.setButton(text(0), text(1, fallback: "off"))
    case "/xone/clear":
        renderer.stop()
    default:
        if message.address.hasPrefix("/xone/level/") {
            let band = String(message.address.split(separator: "/").last ?? "")
            renderer.setLevel(band: band, value: number(0))
        }
    }
}

func bridgeEvent(_ text: String) {
    if let data = "EVENT \(text)\n".data(using: .utf8) {
        FileHandle.standardOutput.write(data)
    }
}

func emitOSCEvent(_ message: OSCMessage) {
    bridgeEvent("osc address=\(message.address)")

    if message.address == "/xone/beat" || message.address == "/live/beat" {
        let value = message.args.first?.number ?? 1
        bridgeEvent("beat value=\(value)")
    } else if message.address == "/xone/levels" || message.address == "/live/levels" {
        let low = message.args.indices.contains(0) ? (message.args[0].number ?? 0) : 0
        let mid = message.args.indices.contains(1) ? (message.args[1].number ?? 0) : 0
        let high = message.args.indices.contains(2) ? (message.args[2].number ?? 0) : 0
        bridgeEvent(String(format: "levels low=%.3f mid=%.3f high=%.3f", low, mid, high))
    }
}

final class UDPServer {
    private let socketFd: Int32
    private let source: DispatchSourceRead

    init(host: String, port: Int, handler: @escaping (Data) -> Void) throws {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            throw AppError.socket("socket() failed")
        }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(port).bigEndian)
        guard inet_pton(AF_INET, host, &address.sin_addr) == 1 else {
            close(fd)
            throw AppError.socket("Invalid IPv4 host: \(host)")
        }

        let bindStatus = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindStatus == 0 else {
            let error = String(cString: strerror(errno))
            close(fd)
            throw AppError.socket("bind(\(host):\(port)) failed: \(error)")
        }

        let readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue.global(qos: .userInitiated))
        readSource.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 8192)
            let count = recv(fd, &buffer, buffer.count, 0)
            if count > 0 {
                handler(Data(buffer.prefix(count)))
            }
        }
        readSource.setCancelHandler {
            close(fd)
        }
        socketFd = fd
        source = readSource
    }

    func start() {
        source.resume()
    }

    func stop() {
        source.cancel()
    }
}

func printPorts() {
    print("MIDI outputs:")
    for port in midiOutputs() {
        print("  \(port.index): \(port.name)")
    }
    print("\nMIDI inputs:")
    for port in midiInputs() {
        print("  \(port.index): \(port.name)")
    }
}

func runTest(_ options: Options) throws {
    let k2 = try K2Controller(options: options)
    print("Opened MIDI output \(k2.port.index): \(k2.port.name) on channel \(k2.channel)")
    k2.allOff()

    for color in colors {
        for button in buttons {
            try k2.setButton(button, color)
            usleep(45_000)
        }
        usleep(160_000)
        k2.allOff()
    }

    let renderer = Renderer(k2: k2, options: options)
    for value in [0.1, 0.25, 0.5, 0.8, 0.2, 0.0] {
        renderer.setLevels(low: value, mid: value * 0.8, high: value * 0.6)
        usleep(240_000)
    }
    for beat in [1.0, 2, 3, 4, 1, 2, 3, 4] {
        renderer.pulseBeat(beat)
        usleep(180_000)
    }

    renderer.stop()
}

func runAllOff(_ options: Options) throws {
    let k2 = try K2Controller(options: options)
    k2.allOff()
    print("All K2 LEDs off via \(k2.port.name).")
}

func runSet(_ options: Options) throws {
    guard options.positionals.count >= 2 else {
        throw AppError.invalidOption("set requires a button and color: set A red")
    }
    let k2 = try K2Controller(options: options)
    try k2.setButton(options.positionals[0], options.positionals[1])
    print("Set \(options.positionals[0].uppercased()) to \(options.positionals[1]).")
}

func runStart(_ options: Options) throws {
    let k2 = try K2Controller(options: options)
    let renderer = Renderer(k2: k2, options: options)
    var server: UDPServer?
    let lock = NSLock()

    server = try UDPServer(host: options.host, port: options.oscPort) { data in
        guard let message = parseOSCMessage(data) else { return }
        emitOSCEvent(message)
        lock.lock()
        handle(message, renderer: renderer, k2: k2)
        lock.unlock()
    }

    let shutdown: () -> Void = {
        lock.lock()
        renderer.stop()
        lock.unlock()
        server?.stop()
        exit(0)
    }

    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let sigint = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    let sigterm = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    sigint.setEventHandler(handler: shutdown)
    sigterm.setEventHandler(handler: shutdown)
    sigint.resume()
    sigterm.resume()

    k2.allOff()
    server?.start()
    print("Opened MIDI output \(k2.port.index): \(k2.port.name) on channel \(k2.channel)")
    print("Listening for OSC on \(options.host):\(options.oscPort)")
    print("Press Ctrl-C to turn LEDs off and quit.")
    bridgeEvent("ready midi=\"\(k2.port.name)\" channel=\(k2.channel) host=\(options.host) port=\(options.oscPort)")
    dispatchMain()
}

func main() throws {
    let options = try parseArgs(Array(CommandLine.arguments.dropFirst()))
    if options.help {
        print(usage())
        return
    }

    switch options.command {
    case "list":
        printPorts()
    case "test":
        try runTest(options)
    case "all-off":
        try runAllOff(options)
    case "set":
        try runSet(options)
    case "start":
        try runStart(options)
    default:
        throw AppError.invalidOption("Unknown command: \(options.command)\n\(usage())")
    }
}

do {
    try main()
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
