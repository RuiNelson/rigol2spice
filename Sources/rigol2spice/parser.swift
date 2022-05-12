// (C) Rui Carneiro

import Foundation
import Progress

public enum ParseError: LocalizedError {
    case invalidFileFormat
    case insufficientLines
    case noChannelsDetected
    case channelNotFound(channelLabel: String)
    case incrementNotFound
    case invalidIncrementValue(value: String)
    case sequenceNumberNotFoundOrInvalid(line: String)
    case invalidValue(value: String, line: String)

    public var errorDescription: String? {
        switch self {
        case .invalidFileFormat: return "Invalid file format"
        case .insufficientLines: return "No header or values found"
        case .noChannelsDetected: return "No channels found"
        case let .channelNotFound(channelLabel: channel): return "Specified channel \"\(channel)\" not found in file"
        case .incrementNotFound: return "Time increment not found"
        case let .invalidIncrementValue(value: valueStr): return "Time increment value is not valid: \(valueStr)"
        case let .sequenceNumberNotFoundOrInvalid(line: lineStr): return "Couldn't find sequence number in line: \(lineStr)"
        case let .invalidValue(value: val, line: line): return "Invalid decimal number: \"\(val)\" in line: \(line)"
        }
    }
}

public struct Point {
    var time: Double
    var value: Double

    var serialize: String {
        let timeString = timeNF.string(for: time)!
        let valueString = valueNF.string(for: value)!
        return [timeString, valueString].joined(separator: "\t")
    }
}

enum CSVParser {
    public struct HeaderInfo {
        var channels: [Channel]
        var increment: Double?

        var channelsDescription: String {
            var str = ""
            str += "  " + "Channels:"
            for channel in channels {
                str += "\n" + "    " + " - " + channel.description
            }
            if let increment = increment {
                str += "\n"

                let incrementString = engineeringNF.string(increment)
                str += "  " + "Increment: \(incrementString)s"
            }

            return str
        }
    }

    public struct Channel {
        var name: String
        var row: Int
        var unit: String?

        var description: String {
            "\(name) (unit: \(unit ?? "nil"))"
        }
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
            } else if text.lowercased() == "start" {
                // discard this value
                ()
            } else if text.lowercased() == "increment" {
                incrementIndex = index
            } else {
                // it's a channel!
                let newChannel = Channel(name: text, row: index, unit: nil)
                channels.append(newChannel)
            }
        }

        guard !channels.isEmpty else {
            throw ParseError.noChannelsDetected
        }

        guard let incrementIndex = incrementIndex else {
            throw ParseError.incrementNotFound
        }

        // Second Line
        let line2Fields = line2.split(separator: ",")

        let incrementString = line2Fields[incrementIndex]
        guard let increment = Double(incrementString) else {
            throw ParseError.invalidIncrementValue(value: String(incrementString))
        }

        channels = channels.map {
            var copy = $0
            let unit = line2Fields[$0.row]
            copy.unit = String(unit)
            return copy
        }

        return HeaderInfo(channels: channels, increment: increment)
    }

    private static func parsePoint(text: String, incrementTime: Double, row: Int) throws -> Point {
        let fields = text.split(separator: ",").map { String($0) }

        // Time
        guard let firstField = fields.first, let sequence = Int(firstField) else {
            throw ParseError.sequenceNumberNotFoundOrInvalid(line: text)
        }

        let time = incrementTime * Double(sequence)

        // Value

        let valueField = fields[row]

        guard let value = Double(valueField) else {
            throw ParseError.invalidValue(value: valueField, line: text)
        }

        return Point(time: time, value: value)
    }

    public static func parseCsv(_ data: Data,
                                forChannel channelLabel: String,
                                listChannelsOnly: Bool) throws -> (header: HeaderInfo, selectedChannel: Channel?, points: [Point]) {
        // Convert to string
        guard let input = String(data: data, encoding: .ascii) else {
            throw ParseError.invalidFileFormat
        }

        // Split lines
        var lines = input.split(whereSeparator: \.isNewline)

        guard lines.count > 2 else {
            throw ParseError.insufficientLines
        }

        // Process Header
        let headerInfo = try parseFirstAndSecondLines(String(lines.removeFirst()),
                                                      String(lines.removeFirst()))

        print(headerInfo.channelsDescription)

        if listChannelsOnly {
            return (headerInfo, nil, [])
        }

        let increment = headerInfo.increment
        let channels = headerInfo.channels

        guard let increment = increment else {
            throw ParseError.incrementNotFound
        }

        var selectedChannel: Channel?

        selectedChannel = channels.first(where: { $0.name == channelLabel })

        if selectedChannel == nil {
            selectedChannel = channels.first(where: {
                $0.name.lowercased() == channelLabel.lowercased()
            })
        }

        guard let selectedChannel = selectedChannel else {
            throw ParseError.channelNotFound(channelLabel: channelLabel)
        }

        print("  " + "Selected channel: \(selectedChannel.name)")

        let selectedRow = selectedChannel.row

        // Process points
        var linesStr = lines.map { String($0) }
        linesStr = linesStr.filter { !$0.isEmpty }

        var progress = ProgressBar(count: linesStr.count)

        let points: [Point] = try linesStr.map {
            let point = try parsePoint(text: $0, incrementTime: increment, row: selectedRow)
            progress.next()
            return point
        }

        return (headerInfo, selectedChannel, points)
    }
}
