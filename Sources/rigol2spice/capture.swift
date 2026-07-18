import Foundation

// MARK: - ParseError

enum ParseError: LocalizedError, Equatable {
    case invalidFileFormat
    case insufficientLines
    case noChannelsDetected
    case channelNotFound(channelLabel: String)
    case invalidChannelExpression(String)
    case divisionByZero
    case incrementNotFound
    case invalidIncrementValue(value: String)
    case invalidLine(line: String)

    var errorDescription: String? {
        switch self {
        case .invalidFileFormat: "Invalid file format"
        case .insufficientLines: "No header or values found"
        case .noChannelsDetected: "No channels found"
        case let .channelNotFound(channelLabel): "Specified channel \"\(channelLabel)\" not found in file"
        case let .invalidChannelExpression(detail): "Invalid channel expression: \(detail)"
        case .divisionByZero: "Division by zero in channel expression"
        case .incrementNotFound: "Time increment not found"
        case let .invalidIncrementValue(value): "Time increment value is not valid: \(value)"
        case let .invalidLine(line): "Invalid line: \(line)"
        }
    }
}

// MARK: - Point

struct Point: Equatable {
    var time: Double
    var value: Double
}

// MARK: - CaptureChannelMetadata

struct CaptureChannelMetadata: Equatable {
    let name: String
    let coupling: String
    let bandwidth: String
    let probeRatio: Double
    let voltsPerDivision: Double
    let verticalOffset: Double
    let inverted: Bool
    let unit: String
}

// MARK: - CaptureMetadata

struct CaptureMetadata: Equatable {
    let format: String
    let model: String
    let serialNumber: String?
    let firmware: String
    let fileVersion: UInt16
    let structureVersion: UInt16
    let acquisitionMode: String
    let timeMode: String
    let horizontalScale: Double
    let horizontalOffset: Double
    let memoryDepth: Int
    let rawDataOffset: Int
    let channels: [CaptureChannelMetadata]
    let voltageConversion: String?
}

// MARK: - Capture

struct Capture: Equatable {
    let channels: [String]
    let selectedChannel: String?
    let points: [Point]
    let sampleInterval: Double?
    let metadata: CaptureMetadata?

    init(
        channels: [String],
        selectedChannel: String?,
        points: [Point],
        sampleInterval: Double?,
        metadata: CaptureMetadata? = nil,
    ) {
        self.channels = channels
        self.selectedChannel = selectedChannel
        self.points = points
        self.sampleInterval = sampleInterval
        self.metadata = metadata
    }

    var duration: Double? {
        guard let lastPoint = points.last else {
            return nil
        }
        return lastPoint.time + (sampleInterval ?? 0)
    }
}

// MARK: - CaptureParser

protocol CaptureParser {
    func parse(_ data: Data, channel: String?) throws -> Capture
}

// MARK: - CaptureFormat

enum CaptureFormat: Equatable {
    case legacy
    case centaurus
    case rigolWFM
    private static let csvInspectionByteLimit = 4096

    static func detect(in data: Data) -> CaptureFormat {
        if RigolWFMFamily.detect(in: data) != nil {
            return .rigolWFM
        }

        // Rigol's Centaurus CSV starts with a time column (normally `Time(s)`).
        // Legacy CSV instead starts with `X` and advertises `Start` and `Increment`.
        // Only inspect a small prefix so detection does not scale with capture size.
        let prefix = Data(data.prefix(csvInspectionByteLimit))
        guard let text = String(data: prefix, encoding: .isoLatin1),
              let firstLine = text.split(whereSeparator: \Character.isNewline).first else {
            return .legacy
        }

        let fields = csvFields(in: String(firstLine))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if let firstField = fields.first,
           firstField == "time" || firstField.hasPrefix("time(") {
            return .centaurus
        }
        if fields.contains("increment"), fields.contains("start") {
            return .legacy
        }

        // Preserve compatibility with CSV exports predating the known layouts.
        return .legacy
    }

    var displayName: String {
        switch self {
        case .legacy: "Legacy CSV"
        case .centaurus: "Centaurus CSV"
        case .rigolWFM: "Rigol WFM"
        }
    }

    var parser: any CaptureParser {
        switch self {
        case .legacy: LegacyCSVParser()
        case .centaurus: CentaurusCSVParser()
        case .rigolWFM: RigolWFMParser()
        }
    }
}
