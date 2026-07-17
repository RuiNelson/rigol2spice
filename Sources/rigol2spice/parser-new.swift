import Foundation

struct CentaurusCSVParser: CaptureParser {
    private struct Channel {
        let name: String
        let columnIndex: Int
    }

    func parse(_ data: Data, channel requestedChannel: String?) throws -> Capture {
        guard let input = String(data: data, encoding: .isoLatin1) else {
            throw ParseError.invalidFileFormat
        }

        var lines = input.split(whereSeparator: \.isNewline)
        guard lines.count >= 2 else {
            throw ParseError.insufficientLines
        }

        let headerFields = fields(in: String(lines.removeFirst()))
        guard headerFields.count >= 2 else {
            throw ParseError.invalidFileFormat
        }

        let channels = headerFields.dropFirst().enumerated().map {
            Channel(name: $0.element, columnIndex: $0.offset + 1)
        }
        guard !channels.isEmpty else {
            throw ParseError.noChannelsDetected
        }

        let channelNames = channels.map(\.name)
        guard let requestedChannel else {
            return Capture(channels: channelNames, selectedChannel: nil, points: [], sampleInterval: nil)
        }

        guard let selectedChannel = selectChannel(named: requestedChannel, from: channels) else {
            throw ParseError.channelNotFound(channelLabel: requestedChannel)
        }

        var points = try lines.map {
            try parsePoint(String($0), valueColumnIndex: selectedChannel.columnIndex)
        }
        normalizeTimes(in: &points)

        return Capture(
            channels: channelNames,
            selectedChannel: selectedChannel.name,
            points: points,
            sampleInterval: sampleInterval(in: points),
        )
    }

    private func selectChannel(named requestedName: String, from channels: [Channel]) -> Channel? {
        channels.first { $0.name == requestedName }
            ?? channels.first { $0.name.caseInsensitiveCompare(requestedName) == .orderedSame }
            ?? channels.first { String($0.name.dropLast()) == requestedName }
            ?? channels.first { String($0.name.dropLast()).caseInsensitiveCompare(requestedName) == .orderedSame }
    }

    private func parsePoint(_ line: String, valueColumnIndex: Int) throws -> Point {
        let columns = fields(in: line)
        guard columns.indices.contains(0),
              columns.indices.contains(valueColumnIndex),
              let time = Double(columns[0]),
              let value = Double(columns[valueColumnIndex]) else {
            throw ParseError.invalidLine(line: line)
        }

        return Point(time: time, value: value)
    }

    private func normalizeTimes(in points: inout [Point]) {
        guard points.count >= 2 else {
            return
        }

        points.sort { $0.time < $1.time }
        guard let firstTime = points.first?.time, firstTime < 0 else {
            return
        }

        for index in points.indices {
            points[index].time -= firstTime
        }
    }

    private func sampleInterval(in points: [Point]) -> Double? {
        guard points.count >= 2 else {
            return nil
        }
        return points[points.count - 1].time - points[points.count - 2].time
    }

    private func fields(in line: String) -> [String] {
        line.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }
}
