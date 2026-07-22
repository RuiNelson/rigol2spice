import Foundation

// MARK: - DecodeCommandError

enum DecodeCommandError: LocalizedError, Equatable {
    case unsupportedProtocol(String)
    case malformedArgument(String)
    case duplicateArgument(String)
    case unknownArgument(String)
    case missingArgument(String)
    case invalidArgument(name: String, value: String)

    var errorDescription: String? {
        switch self {
        case let .unsupportedProtocol(name): "Unsupported decoder protocol: \(name)"
        case let .malformedArgument(argument):
            "Malformed decoder argument: \(argument) (expected name=value)"
        case let .duplicateArgument(name): "Duplicate decoder argument: \(name)"
        case let .unknownArgument(name): "Unknown decoder argument: \(name)"
        case let .missingArgument(name): "Missing required decoder argument: \(name)"
        case let .invalidArgument(name, value): "Invalid decoder argument \(name)=\(value)"
        }
    }
}

// MARK: - DecodeRequest

enum DecodeRequest: Equatable {
    case uart(UARTDecodeRequest)
    case i2c(I2CDecodeRequest)
    case spi(SPIDecodeRequest)

    var channels: [String] {
        switch self {
        case let .uart(request): [request.channel]
        case let .i2c(request): [request.sdaChannel, request.sclChannel]
        case let .spi(request):
            [request.clockChannel, request.mosiChannel, request.misoChannel, request.chipSelectChannel]
                .compactMap(\.self)
        }
    }

    var primaryChannel: String {
        channels[0]
    }

    static func parse(_ source: String) throws -> DecodeRequest {
        let command = try ParsedDecodeCommand(source)
        switch command.protocolName {
        case "uart": return try .uart(UARTDecodeRequest(command: command))
        case "i2c",
             "i²c": return try .i2c(I2CDecodeRequest(command: command))
        case "spi": return try .spi(SPIDecodeRequest(command: command))
        default: throw DecodeCommandError.unsupportedProtocol(command.protocolName)
        }
    }
}

// MARK: - UARTDecodeRequest

struct UARTDecodeRequest: Equatable {
    let channel: String
    let configuration: UARTDecoder.Configuration

    static func parse(_ source: String) throws -> UARTDecodeRequest {
        guard case let .uart(request) = try DecodeRequest.parse(source) else {
            throw try DecodeCommandError.unsupportedProtocol(ParsedDecodeCommand(source).protocolName)
        }
        return request
    }

    fileprivate init(command: ParsedDecodeCommand) throws {
        var values = command.values
        try values.applyAliases(["databits": "data", "stopbits": "stop"])
        try values.validateKeys(["rx", "baud", "threshold", "hysteresis", "data", "parity", "stop", "inverted"])

        self.channel = try values.required("rx")
        let rawBaud = try values.required("baud")
        if rawBaud.lowercased() == "auto" {
            self.configuration = try Self.configuration(values: values, baudRate: .automatic)
        }
        else if let baud = parseEngineeringNotation(rawBaud), baud.isFinite, baud > 0 {
            self.configuration = try Self.configuration(values: values, baudRate: .explicit(baud))
        }
        else {
            throw DecodeCommandError.invalidArgument(name: "baud", value: rawBaud)
        }
    }

    private static func configuration(
        values: [String: String],
        baudRate: UARTBaudRate,
    ) throws -> UARTDecoder.Configuration {
        let threshold = try values.scalar("threshold")
        let hysteresis = try values.nonnegativeScalar("hysteresis", default: 0)
        let dataBits = try values.integer("data", default: 8, range: 5 ... 9)
        let rawParity = values["parity"]?.lowercased() ?? "none"
        guard let parity = UARTParity(rawValue: rawParity) else {
            throw DecodeCommandError.invalidArgument(name: "parity", value: rawParity)
        }
        let stopBits = try values.scalar("stop", default: 1)
        guard [1.0, 1.5, 2.0].contains(stopBits) else {
            throw DecodeCommandError.invalidArgument(name: "stop", value: values["stop"] ?? String(stopBits))
        }
        return try UARTDecoder.Configuration(
            baudRate: baudRate,
            threshold: threshold,
            hysteresis: hysteresis,
            dataBits: dataBits,
            parity: parity,
            stopBits: stopBits,
            inverted: values.boolean("inverted", default: false),
        )
    }
}

// MARK: - I2CDecodeRequest

struct I2CDecodeRequest: Equatable {
    let sdaChannel: String
    let sclChannel: String
    let configuration: I2CDecoder.Configuration

    fileprivate init(command: ParsedDecodeCommand) throws {
        var values = command.values
        try values.applyAliases(["sdathreshold": "sda-threshold", "sclthreshold": "scl-threshold"])
        try values.validateKeys(["sda", "scl", "threshold", "sda-threshold", "scl-threshold", "hysteresis"])
        self.sdaChannel = try values.required("sda")
        self.sclChannel = try values.required("scl")
        let sharedThreshold = try values.optionalScalar("threshold")
        guard let sdaThreshold = try values.optionalScalar("sda-threshold") ?? sharedThreshold else {
            throw DecodeCommandError.missingArgument("threshold")
        }
        guard let sclThreshold = try values.optionalScalar("scl-threshold") ?? sharedThreshold else {
            throw DecodeCommandError.missingArgument("threshold")
        }
        self.configuration = try I2CDecoder.Configuration(
            sdaThreshold: sdaThreshold,
            sclThreshold: sclThreshold,
            hysteresis: values.nonnegativeScalar("hysteresis", default: 0),
        )
    }
}

// MARK: - SPIDecodeRequest

struct SPIDecodeRequest: Equatable {
    let clockChannel: String
    let mosiChannel: String?
    let misoChannel: String?
    let chipSelectChannel: String?
    let configuration: SPIDecoder.Configuration

    fileprivate init(command: ParsedDecodeCommand) throws {
        var values = command.values
        try values.applyAliases(["clock": "clk", "bitorder": "order", "csactive": "cs-active"])
        try values.validateKeys([
            "clk", "mosi", "miso", "cs", "mode", "bits", "order", "threshold", "hysteresis", "cs-active",
        ])
        self.clockChannel = try values.required("clk")
        self.mosiChannel = values["mosi"]
        self.misoChannel = values["miso"]
        self.chipSelectChannel = values["cs"]
        guard mosiChannel != nil || misoChannel != nil else {
            throw DecodeCommandError.missingArgument("mosi or miso")
        }
        let rawOrder = values["order"]?.lowercased() ?? "msb"
        guard let bitOrder = SPIBitOrder(rawValue: rawOrder) else {
            throw DecodeCommandError.invalidArgument(name: "order", value: rawOrder)
        }
        let rawCSActive = values["cs-active"]?.lowercased() ?? "low"
        guard ["low", "high"].contains(rawCSActive) else {
            throw DecodeCommandError.invalidArgument(name: "cs-active", value: rawCSActive)
        }
        self.configuration = try SPIDecoder.Configuration(
            mode: values.integer("mode", default: 0, range: 0 ... 3),
            bitCount: values.integer("bits", default: 8, range: 1 ... 64),
            bitOrder: bitOrder,
            threshold: values.scalar("threshold"),
            hysteresis: values.nonnegativeScalar("hysteresis", default: 0),
            chipSelectActiveHigh: rawCSActive == "high",
        )
    }
}

// MARK: - ParsedDecodeCommand

private struct ParsedDecodeCommand {
    let protocolName: String
    let values: [String: String]

    init(_ source: String) throws {
        let components = source.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
        guard let name = components.first else { throw DecodeCommandError.unsupportedProtocol("") }
        self.protocolName = name.lowercased()
        let argumentText = components.count == 2 ? String(components[1]) : ""
        var parsed: [String: String] = [:]
        for rawArgument in argumentText.split(separator: ",", omittingEmptySubsequences: false) {
            let argument = rawArgument.trimmingCharacters(in: .whitespacesAndNewlines)
            let pair = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2, !pair[0].isEmpty, !pair[1].isEmpty else {
                throw DecodeCommandError.malformedArgument(argument)
            }
            let key = pair[0].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = pair[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard parsed[key] == nil else { throw DecodeCommandError.duplicateArgument(key) }
            parsed[key] = value
        }
        self.values = parsed
    }
}

private extension [String: String] {
    mutating func applyAliases(_ aliases: [String: String]) throws {
        for (alias, canonical) in aliases where self[alias] != nil {
            guard self[canonical] == nil else { throw DecodeCommandError.duplicateArgument(canonical) }
            self[canonical] = removeValue(forKey: alias)
        }
    }

    func validateKeys(_ supported: Set<String>) throws {
        if let unknown = keys.first(where: { !supported.contains($0) }) {
            throw DecodeCommandError.unknownArgument(unknown)
        }
    }

    func required(_ name: String) throws -> String {
        guard let value = self[name] else { throw DecodeCommandError.missingArgument(name) }
        return value
    }

    func optionalScalar(_ name: String) throws -> Double? {
        guard let raw = self[name] else { return nil }
        guard let value = parseEngineeringNotation(raw), value.isFinite else {
            throw DecodeCommandError.invalidArgument(name: name, value: raw)
        }
        return value
    }

    func scalar(_ name: String, default defaultValue: Double? = nil) throws -> Double {
        if let value = try optionalScalar(name) { return value }
        if let defaultValue { return defaultValue }
        throw DecodeCommandError.missingArgument(name)
    }

    func nonnegativeScalar(_ name: String, default defaultValue: Double) throws -> Double {
        let value = try scalar(name, default: defaultValue)
        guard value >= 0 else {
            throw DecodeCommandError.invalidArgument(name: name, value: self[name] ?? String(value))
        }
        return value
    }

    func integer(_ name: String, default defaultValue: Int, range: ClosedRange<Int>) throws -> Int {
        guard let raw = self[name] else { return defaultValue }
        guard let value = Int(raw), range.contains(value) else {
            throw DecodeCommandError.invalidArgument(name: name, value: raw)
        }
        return value
    }

    func boolean(_ name: String, default defaultValue: Bool) throws -> Bool {
        guard let raw = self[name]?.lowercased() else { return defaultValue }
        switch raw {
        case "true",
             "yes",
             "1": return true
        case "false",
             "no",
             "0": return false
        default: throw DecodeCommandError.invalidArgument(name: name, value: raw)
        }
    }
}
