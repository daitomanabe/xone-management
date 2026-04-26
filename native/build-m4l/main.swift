import Foundation

struct AppVersion: Encodable {
    let major: Int
    let minor: Int
    let revision: Int
    let architecture: String
    let modernui: Int
}

struct Box: Encodable {
    let id: String
    let maxclass: String
    let numinlets: Int
    let numoutlets: Int
    let patching_rect: [Double]
    let text: String?
}

struct BoxEntry: Encodable {
    let box: Box
}

struct Patchline: Encodable {
    let source: [PatchEndpoint]
    let destination: [PatchEndpoint]
}

enum PatchEndpoint: Encodable {
    case string(String)
    case int(Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }
}

struct LineEntry: Encodable {
    let patchline: Patchline
}

struct Patcher: Encodable {
    let fileversion: Int
    let appversion: AppVersion
    let classnamespace: String
    let rect: [Double]
    let openrect: [Double]
    let default_fontsize: Double
    let default_fontface: Int
    let default_fontname: String
    let gridonopen: Int
    let gridsize: [Double]
    let toolbarvisible: Int
    let boxes: [BoxEntry]
    let lines: [LineEntry]
}

struct PatcherFile: Encodable {
    let patcher: Patcher
}

final class PatcherBuilder {
    private var nextId = 1
    private(set) var boxes: [BoxEntry] = []
    private(set) var lines: [LineEntry] = []

    @discardableResult
    func addBox(
        maxclass: String,
        text: String?,
        x: Double,
        y: Double,
        width: Double = 120,
        height: Double = 22,
        numinlets: Int = 1,
        numoutlets: Int = 1
    ) -> String {
        let id = "obj-\(nextId)"
        nextId += 1

        boxes.append(BoxEntry(box: Box(
            id: id,
            maxclass: maxclass,
            numinlets: numinlets,
            numoutlets: numoutlets,
            patching_rect: [x, y, width, height],
            text: text
        )))

        return id
    }

    @discardableResult
    func addComment(_ text: String, _ x: Double, _ y: Double, width: Double = 260) -> String {
        addBox(maxclass: "comment", text: text, x: x, y: y, width: width, height: 20, numoutlets: 0)
    }

    @discardableResult
    func addNewObj(_ text: String, _ x: Double, _ y: Double, width: Double = 130, outlets: Int = 1) -> String {
        addBox(maxclass: "newobj", text: text, x: x, y: y, width: width, height: 22, numoutlets: outlets)
    }

    @discardableResult
    func addMessage(_ text: String, _ x: Double, _ y: Double, width: Double = 90) -> String {
        addBox(maxclass: "message", text: text, x: x, y: y, width: width, height: 22)
    }

    func connect(_ source: String, _ sourceOutlet: Int, _ destination: String, _ destinationInlet: Int = 0) {
        lines.append(LineEntry(patchline: Patchline(
            source: [.string(source), .int(sourceOutlet)],
            destination: [.string(destination), .int(destinationInlet)]
        )))
    }

    func addAnalysisChain(
        label: String,
        source: String,
        filterText: String,
        filterOutlet: Int,
        x: Double,
        y: Double,
        pak: String,
        pakInlet: Int
    ) {
        addComment(label, x, y - 24, width: 130)
        let filter = addNewObj(filterText, x, y, width: 120, outlets: 4)
        let abs = addNewObj("abs~", x, y + 40, width: 70)
        let slide = addNewObj("slide~ 64 2205", x, y + 80, width: 115)
        let snapshot = addNewObj("snapshot~ 33", x, y + 120, width: 105)
        let gain = addNewObj("* 4.", x, y + 160, width: 60)
        let clip = addNewObj("clip 0. 1.", x, y + 200, width: 85)

        connect(source, 0, filter)
        connect(filter, filterOutlet, abs)
        connect(abs, 0, slide)
        connect(slide, 0, snapshot)
        connect(snapshot, 0, gain)
        connect(gain, 0, clip)
        connect(clip, 0, pak, pakInlet)
    }

    func build() -> PatcherFile {
        addComment("Xone:K2 OSC Sender for Ableton Live / Max for Live", 30, 18, width: 420)
        addComment("Sends /xone/levels low mid high and /xone/beat beatNumber to 127.0.0.1:9123.", 30, 42, width: 560)

        let plugin = addNewObj("plugin~", 40, 90, width: 75, outlets: 2)
        let plugout = addNewObj("plugout~", 40, 460, width: 80, outlets: 0)
        let sum = addNewObj("+~", 170, 96, width: 45)
        let mono = addNewObj("*~ 0.5", 170, 132, width: 60)

        connect(plugin, 0, plugout)
        connect(plugin, 1, plugout, 1)
        connect(plugin, 0, sum)
        connect(plugin, 1, sum, 1)
        connect(sum, 0, mono)

        let pak = addNewObj("pak 0. 0. 0.", 385, 392, width: 105)
        let speedlim = addNewObj("speedlim 33", 385, 430, width: 100)
        let oscLevels = addNewObj("prepend /xone/levels", 385, 468, width: 145)
        let udp = addNewObj("udpsend 127.0.0.1 9123", 385, 506, width: 170)

        addAnalysisChain(label: "LOW <180Hz", source: mono, filterText: "svf~ 180. 0.8", filterOutlet: 0, x: 270, y: 130, pak: pak, pakInlet: 0)
        addAnalysisChain(label: "MID around 1.2kHz", source: mono, filterText: "svf~ 1200. 1.1", filterOutlet: 2, x: 420, y: 130, pak: pak, pakInlet: 1)
        addAnalysisChain(label: "HIGH >3.5kHz", source: mono, filterText: "svf~ 3500. 0.8", filterOutlet: 1, x: 580, y: 130, pak: pak, pakInlet: 2)

        connect(pak, 0, speedlim)
        connect(speedlim, 0, oscLevels)
        connect(oscLevels, 0, udp)

        addComment("Live transport beat polling", 40, 555, width: 220)
        let metro = addNewObj("metro 20 @active 1", 40, 585, width: 130)
        let button = addBox(maxclass: "button", text: nil, x: 190, y: 585, width: 22, height: 22)
        let transport = addNewObj("transport", 230, 585, width: 90, outlets: 8)
        let floorBeat = addNewObj("i", 230, 625, width: 40)
        let change = addNewObj("change", 230, 665, width: 70)
        let oscBeat = addNewObj("prepend /xone/beat", 230, 705, width: 130)

        connect(metro, 0, button)
        connect(button, 0, transport)
        connect(transport, 1, floorBeat)
        connect(floorBeat, 0, change)
        connect(change, 0, oscBeat)
        connect(oscBeat, 0, udp)

        let clearMsg = addMessage("/xone/clear", 580, 506, width: 95)
        addComment("Click to clear LEDs", 580, 482, width: 140)
        connect(clearMsg, 0, udp)

        return PatcherFile(patcher: Patcher(
            fileversion: 1,
            appversion: AppVersion(major: 9, minor: 0, revision: 5, architecture: "x64", modernui: 1),
            classnamespace: "box",
            rect: [120.0, 120.0, 780.0, 770.0],
            openrect: [0.0, 0.0, 0.0, 0.0],
            default_fontsize: 12.0,
            default_fontface: 0,
            default_fontname: "Arial",
            gridonopen: 1,
            gridsize: [15.0, 15.0],
            toolbarvisible: 1,
            boxes: boxes,
            lines: lines
        ))
    }
}

struct BuildOptions {
    var rootDir: URL
    var outDir: URL?
    var maxpatPath: URL?
    var amxdPath: URL?
    var skipAmxd = false
}

enum BuildError: Error, CustomStringConvertible {
    case missingValue(String)
    case unknownArgument(String)

    var description: String {
        switch self {
        case .missingValue(let option):
            return "Missing value for \(option)"
        case .unknownArgument(let argument):
            return "Unknown argument: \(argument)"
        }
    }
}

func defaultRootDir() -> URL {
    let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    return executable.deletingLastPathComponent().deletingLastPathComponent()
}

func usage() -> String {
    """
    Usage:
      scripts/build-m4l [--out-dir PATH] [--maxpat PATH] [--amxd PATH] [--skip-amxd]

    Generates xone-k2-osc-sender.maxpat and, unless --skip-amxd is set, a simple .amxd wrapper.
    """
}

func parseOptions() throws -> BuildOptions {
    var options = BuildOptions(rootDir: defaultRootDir())
    let args = Array(CommandLine.arguments.dropFirst())
    var index = 0

    func takeValue(_ option: String) throws -> String {
        guard index + 1 < args.count else { throw BuildError.missingValue(option) }
        index += 1
        return args[index]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--help", "-h":
            print(usage())
            exit(0)
        case "--root":
            options.rootDir = URL(fileURLWithPath: try takeValue(arg), isDirectory: true)
        case "--out-dir":
            options.outDir = URL(fileURLWithPath: try takeValue(arg), isDirectory: true)
        case "--maxpat":
            options.maxpatPath = URL(fileURLWithPath: try takeValue(arg))
        case "--amxd":
            options.amxdPath = URL(fileURLWithPath: try takeValue(arg))
        case "--skip-amxd":
            options.skipAmxd = true
        default:
            throw BuildError.unknownArgument(arg)
        }
        index += 1
    }

    return options
}

func writeLittleEndianUInt32(_ value: UInt32, to data: inout Data) {
    var littleEndian = value.littleEndian
    withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
}

func writeAmxd(patchJson: Data, to destination: URL) throws {
    var patchData = patchJson
    patchData.append(0)

    var data = Data()
    data.append(contentsOf: "ampf".utf8)
    writeLittleEndianUInt32(4, to: &data)
    data.append(contentsOf: "aaaa".utf8)
    data.append(contentsOf: "meta".utf8)
    writeLittleEndianUInt32(4, to: &data)
    writeLittleEndianUInt32(0, to: &data)
    data.append(contentsOf: "ptch".utf8)
    writeLittleEndianUInt32(UInt32(patchData.count), to: &data)
    data.append(patchData)

    try data.write(to: destination)
}

func run() throws {
    let options = try parseOptions()
    let outDir = options.outDir ?? options.rootDir.appendingPathComponent("m4l", isDirectory: true)
    let maxpatPath = options.maxpatPath ?? outDir.appendingPathComponent("xone-k2-osc-sender.maxpat")
    let amxdPath = options.amxdPath ?? outDir.appendingPathComponent("xone-k2-osc-sender.amxd")

    try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

    let patcher = PatcherBuilder().build()
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
    let patchJson = try encoder.encode(patcher)
    var maxpatData = patchJson
    maxpatData.append(0x0A)

    try maxpatData.write(to: maxpatPath)
    print("Wrote \(maxpatPath.path)")

    if !options.skipAmxd {
        try writeAmxd(patchJson: patchJson, to: amxdPath)
        print("Wrote \(amxdPath.path)")
    }
}

do {
    try run()
} catch {
    fputs("\(error)\n\n\(usage())\n", stderr)
    exit(1)
}
