import Foundation

// MARK: - CSVCharacterReader

final class CSVCharacterReader {
    private let data: Data
    private let encoding: String.Encoding
    private var index: Data.Index
    private var shouldSkipLineFeed = false

    init(_ data: Data, encoding: String.Encoding) {
        self.data = data
        self.encoding = encoding
        self.index = data.startIndex
    }

    func nextLine() throws -> String? {
        while let line = try readLine() {
            if !line.isEmpty {
                return line
            }
        }
        return nil
    }

    private func readLine() throws -> String? {
        var bytes: [UInt8] = []

        while let byte = nextByte() {
            if shouldSkipLineFeed {
                shouldSkipLineFeed = false
                if byte == 0x0A {
                    continue
                }
            }

            switch byte {
            case 0x0A:
                return try decode(bytes)
            case 0x0D:
                shouldSkipLineFeed = true
                return try decode(bytes)
            default:
                bytes.append(byte)
            }
        }

        guard !bytes.isEmpty else {
            return nil
        }
        return try decode(bytes)
    }

    private func nextByte() -> UInt8? {
        guard index < data.endIndex else {
            return nil
        }

        defer { data.formIndex(after: &index) }
        return data[index]
    }

    private func decode(_ bytes: [UInt8]) throws -> String {
        guard let line = String(bytes: bytes, encoding: encoding) else {
            throw ParseError.invalidFileFormat
        }
        return line
    }
}

// MARK: - CSVChannel

struct CSVChannel {
    let name: String
    let columnIndex: Int
}

// MARK: - CSVHeader

struct CSVHeader {
    let channels: [CSVChannel]
    let sampleInterval: Double?
    let timeScale: Double

    init(channels: [CSVChannel], sampleInterval: Double?, timeScale: Double = 1) {
        self.channels = channels
        self.sampleInterval = sampleInterval
        self.timeScale = timeScale
    }
}

// MARK: - CSVFormatParser

protocol CSVFormatParser: CaptureParser {
    var encoding: String.Encoding { get }

    func parseHeader(from reader: CSVCharacterReader) throws -> CSVHeader
    func alternativeNames(for channel: CSVChannel) -> [String]
    func normalize(_ points: inout [Point])
    func sampleInterval(from header: CSVHeader, points: [Point]) -> Double?
}

extension CSVFormatParser {
    func parse(_ data: Data, channel requestedChannel: String?) throws -> Capture {
        let reader = CSVCharacterReader(data, encoding: encoding)
        let header = try parseHeader(from: reader)
        guard !header.channels.isEmpty else {
            throw ParseError.noChannelsDetected
        }

        let channelNames = header.channels.map(\.name)
        guard let requestedChannel else {
            return Capture(
                channels: channelNames,
                selectedChannel: nil,
                points: [],
                sampleInterval: sampleInterval(from: header, points: []),
            )
        }

        let expression: ChannelExpression
        do {
            expression = try parseChannelExpression(requestedChannel)
        }
        catch let error as ChannelExpressionError {
            throw ParseError.invalidChannelExpression(error.errorDescription ?? String(describing: error))
        }

        var resolvedChannels: [String: CSVChannel] = [:]
        for name in expression.channelNames {
            guard let channel = selectChannel(named: name, from: header.channels) else {
                throw ParseError.channelNotFound(channelLabel: name)
            }
            resolvedChannels[name] = channel
        }

        let selectedLabel: String = if case let .channel(name) = expression, let only = resolvedChannels[name] {
            only.name
        }
        else {
            requestedChannel.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var points: [Point] = []
        while let line = try reader.nextLine() {
            try points.append(
                parsePoint(
                    line,
                    expression: expression,
                    channels: resolvedChannels,
                    header: header,
                ),
            )
        }
        normalize(&points)

        return Capture(
            channels: channelNames,
            selectedChannel: selectedLabel,
            points: points,
            sampleInterval: sampleInterval(from: header, points: points),
        )
    }

    func alternativeNames(for _: CSVChannel) -> [String] {
        []
    }

    func normalize(_: inout [Point]) {}

    func sampleInterval(from header: CSVHeader, points _: [Point]) -> Double? {
        header.sampleInterval
    }

    private func selectChannel(named requestedName: String, from channels: [CSVChannel]) -> CSVChannel? {
        channels.first { $0.name == requestedName }
            ?? channels.first { $0.name.caseInsensitiveCompare(requestedName) == .orderedSame }
            ?? channels.first { alternativeNames(for: $0).contains(requestedName) }
            ?? channels.first {
                alternativeNames(for: $0).contains {
                    $0.caseInsensitiveCompare(requestedName) == .orderedSame
                }
            }
    }

    private func parsePoint(
        _ line: String,
        expression: ChannelExpression,
        channels: [String: CSVChannel],
        header: CSVHeader,
    ) throws -> Point {
        let columns = csvFields(in: line)
        guard columns.indices.contains(0),
              let rawTime = Double(columns[0]) else {
            throw ParseError.invalidLine(line: line)
        }

        var values: [String: Double] = [:]
        values.reserveCapacity(channels.count)
        for (name, channel) in channels {
            guard columns.indices.contains(channel.columnIndex),
                  let value = Double(columns[channel.columnIndex]) else {
                throw ParseError.invalidLine(line: line)
            }
            values[name] = value
        }

        let value: Double
        do {
            value = try expression.evaluate(channels: values)
        }
        catch ChannelExpressionError.divisionByZero {
            throw ParseError.divisionByZero
        }
        catch {
            throw ParseError.invalidLine(line: line)
        }

        return Point(time: rawTime * header.timeScale, value: value)
    }
}

func csvFields(in line: String) -> [String] {
    line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
}
