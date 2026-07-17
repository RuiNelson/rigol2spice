import Foundation

struct LegacyCSVParser: CaptureParser {
    private struct Channel {
        let name: String
        let columnIndex: Int
    }

    private struct Header {
        let channels: [Channel]
        let sampleInterval: Double
    }

    func parse(_ data: Data, channel requestedChannel: String?) throws -> Capture {
        guard let input = String(data: data, encoding: .ascii) else {
            throw ParseError.invalidFileFormat
        }

        var lines = input.split(whereSeparator: \.isNewline)
        guard lines.count >= 3 else {
            throw ParseError.insufficientLines
        }

        let header = try parseHeader(
            fieldNames: String(lines.removeFirst()),
            fieldValues: String(lines.removeFirst()),
        )
        let channelNames = header.channels.map(\.name)

        guard let requestedChannel else {
            return Capture(
                channels: channelNames,
                selectedChannel: nil,
                points: [],
                sampleInterval: header.sampleInterval,
            )
        }

        guard let selectedChannel = selectChannel(named: requestedChannel, from: header.channels) else {
            throw ParseError.channelNotFound(channelLabel: requestedChannel)
        }

        let points = try lines.map {
            try parsePoint(
                String($0),
                sampleInterval: header.sampleInterval,
                valueColumnIndex: selectedChannel.columnIndex,
            )
        }

        return Capture(
            channels: channelNames,
            selectedChannel: selectedChannel.name,
            points: points,
            sampleInterval: header.sampleInterval,
        )
    }

    private func parseHeader(fieldNames: String, fieldValues: String) throws -> Header {
        let names = fields(in: fieldNames)
        let values = fields(in: fieldValues)
        var channels: [Channel] = []
        var incrementColumnIndex: Int?

        for (index, name) in names.enumerated() {
            switch name.lowercased() {
            case "",
                 "x",
                 "start":
                continue
            case "increment":
                incrementColumnIndex = index
            default:
                channels.append(Channel(name: name, columnIndex: index))
            }
        }

        guard !channels.isEmpty else {
            throw ParseError.noChannelsDetected
        }
        guard let incrementColumnIndex else {
            throw ParseError.incrementNotFound
        }
        guard values.indices.contains(incrementColumnIndex) else {
            throw ParseError.invalidFileFormat
        }

        let intervalSource = values[incrementColumnIndex]
        guard let sampleInterval = Double(intervalSource) else {
            throw ParseError.invalidIncrementValue(value: intervalSource)
        }

        return Header(channels: channels, sampleInterval: sampleInterval)
    }

    private func selectChannel(named requestedName: String, from channels: [Channel]) -> Channel? {
        channels.first { $0.name == requestedName }
            ?? channels.first { $0.name.caseInsensitiveCompare(requestedName) == .orderedSame }
    }

    private func parsePoint(
        _ line: String,
        sampleInterval: Double,
        valueColumnIndex: Int,
    ) throws -> Point {
        let columns = fields(in: line)
        guard columns.indices.contains(0),
              columns.indices.contains(valueColumnIndex),
              let discreteTime = Double(columns[0]),
              let value = Double(columns[valueColumnIndex]) else {
            throw ParseError.invalidLine(line: line)
        }

        return Point(time: discreteTime * sampleInterval, value: value)
    }

    private func fields(in line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }
}
