import Foundation
import Progress

// MARK: - ParseError

public enum ParseError: LocalizedError {
    case invalidFileFormat
    case insufficientLines
    case noChannelsDetected
    case channelNotFound(channelLabel: String)
    case incrementNotFound
    case invalidIncrementValue(value: String)
    case invalidLine(line: String)

    public var errorDescription: String? {
        switch self {
        case .invalidFileFormat: "Invalid file format"
        case .insufficientLines: "No header or values found"
        case .noChannelsDetected: "No channels found"
        case let .channelNotFound(channelLabel: channel): "Specified channel \"\(channel)\" not found in file"
        case .incrementNotFound: "Time increment not found"
        case let .invalidIncrementValue(value: valueStr): "Time increment value is not valid: \(valueStr)"
        case let .invalidLine(line: line): "Invalid line: \(line)"
        }
    }
}

// MARK: - Point

public struct Point {
    var time: Double
    var value: Double

    var serialize: String {
        let time = spiceFormatter.string(for: time)!
        let value = spiceFormatter.string(for: value)!

        return [time, "\t", value].joined()
    }
}

// MARK: - CSVParser

class CSVParser {
    struct HeaderInfo {
        var channels: [Channel]
        var increment: Double?
    }

    struct Channel {
        var name: String
        var row: Int
    }

    private static func parseFirstAndSecondLines(_ line1: String, _ line2: String) throws -> HeaderInfo {
        var channels: [Channel] = []
        var incrementIndex: Int?

        // First Line
        let line1Fields = line1.split(separator: ",")

        for line1Field in line1Fields.enumerated() {
            let index = line1Field.offset
            let text = String(line1Field.element)

            if text.lowercased() == "x" {
                // no matter
                ()
            }
            else if text.lowercased() == "start" {
                // discard this value
                ()
            }
            else if text.lowercased() == "increment" {
                incrementIndex = index
            }
            else {
                // it's a channel!
                let newChannel = Channel(name: text, row: index)
                channels.append(newChannel)
            }
        }

        guard !channels.isEmpty else {
            throw ParseError.noChannelsDetected
        }

        guard let incrementIndex else {
            throw ParseError.incrementNotFound
        }

        // Second Line
        let line2Fields = line2.split(separator: ",")

        let incrementString = line2Fields[incrementIndex]
        guard let increment = Double(incrementString) else {
            throw ParseError.invalidIncrementValue(value: String(incrementString))
        }

        return HeaderInfo(channels: channels, increment: increment)
    }

    private static func parsePoint(_ line: String, incrementTime: Double, row: Int) throws -> Point {
        let fields = line.split(separator: ",")
        let timeField = fields[0]
        let valueField = fields[row]

        guard let timeDiscrete = Double(String(timeField)), let value = Double(String(valueField)) else {
            throw ParseError.invalidLine(line: line)
        }

        return Point(time: timeDiscrete * incrementTime, value: value)
    }

    static func parseCsv(_ data: Data,
                         forChannel channelLabel: String,
                         listChannelsOnly: Bool) throws -> (header: HeaderInfo,
                                                            selectedChannel: Channel?,
                                                            points: [Point]) {
        // Convert to string
        guard let input = String(data: data, encoding: .ascii) else {
            throw ParseError.invalidFileFormat
        }

        // Split lines
        var lines = input.split(whereSeparator: \.isNewline)

        guard lines.count > 2 else {
            throw ParseError.insufficientLines
        }

        // Trim empty lines at the end
        while String(lines.last!).isEmpty {
            lines.removeLast()
        }

        // Process Header
        let headerInfo = try parseFirstAndSecondLines(String(lines.removeFirst()),
                                                      String(lines.removeFirst()))

        // print header info:
        printI(1, "Channels:")
        for channel in headerInfo.channels {
            printI(2, " - \(channel.name)")
        }
        if let increment = headerInfo.increment {
            let incrementStr = engineeringFormatter.string(increment)

            let incrementInverted = 1 / increment
            let incrementInvertedStr = engineeringFormatter.string(incrementInverted)
            printI(1, "Time Increment: \(incrementStr)s \t (frequency: \(incrementInvertedStr)Hz)")
        }

        var progress = ProgressBar(count: lines.count)
        progress.next()
        progress.next()

        // Header load
        guard !listChannelsOnly else {
            return (headerInfo, nil, [])
        }

        let timeIncrement = headerInfo.increment
        let channels = headerInfo.channels

        guard let timeIncrement else {
            throw ParseError.incrementNotFound
        }

        // Select channel
        var selectedChannel: Channel?

        selectedChannel = channels.first(where: { $0.name == channelLabel })

        if selectedChannel == nil {
            selectedChannel = channels.first(where: {
                $0.name.lowercased() == channelLabel.lowercased()
            })
        }

        guard let selectedChannel else {
            throw ParseError.channelNotFound(channelLabel: channelLabel)
        }

        let channelRow = selectedChannel.row

        print("  " + "Selected channel: \(selectedChannel.name)")

        // Process points

        let points: [Point] = try lines.map {
            try parsePoint(String($0), incrementTime: timeIncrement, row: channelRow)
        }

        return (headerInfo, selectedChannel, points)
    }
}
