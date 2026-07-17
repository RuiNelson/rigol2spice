import Foundation

// MARK: - ParseError

enum ParseError: LocalizedError, Equatable {
    case invalidFileFormat
    case insufficientLines
    case noChannelsDetected
    case channelNotFound(channelLabel: String)
    case incrementNotFound
    case invalidIncrementValue(value: String)
    case invalidLine(line: String)

    var errorDescription: String? {
        switch self {
        case .invalidFileFormat: "Invalid file format"
        case .insufficientLines: "No header or values found"
        case .noChannelsDetected: "No channels found"
        case let .channelNotFound(channelLabel): "Specified channel \"\(channelLabel)\" not found in file"
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

    var serialize: String {
        let serializedTime = spiceFormatter.string(for: time)!
        let serializedValue = spiceFormatter.string(for: value)!
        return "\(serializedTime)\t\(serializedValue)"
    }
}

// MARK: - Capture

struct Capture: Equatable {
    let channels: [String]
    let selectedChannel: String?
    let points: [Point]
    let sampleInterval: Double?

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

enum CaptureFormat {
    case legacy
    case centaurus

    var parser: any CaptureParser {
        switch self {
        case .legacy: LegacyCSVParser()
        case .centaurus: CentaurusCSVParser()
        }
    }
}
