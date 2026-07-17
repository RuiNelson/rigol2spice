import Foundation
import Progress

extension String {
    var withoutLastCharacter: String {
        var copy = self
        copy.removeLast()
        return copy
    }
}

// MARK: - CentaurusParser

class CentaurusParser {
    static func parseCsv(
        _ data: Data,
        forChannel channelLabel: String,
        listChannelsOnly: Bool,
    ) throws -> [Point] {
        // ---- Data preparation
        guard let string = String(data: data, encoding: .isoLatin1) else {
            throw ParseError.invalidFileFormat
        }

        var lines = string.split(whereSeparator: \.isNewline)

        var lastLine: String {
            String(lines.last!)
        }

        while lastLine.isEmpty {
            lines.removeLast()
        }

        guard lines.count > 2 else {
            throw ParseError.insufficientLines
        }

        // ---- Extract header information

        let headerLine = String(lines.removeFirst())
        let pointLines = lines

        let headerColumns = headerLine.split(separator: ",").map { String($0) }

        guard headerColumns.count >= 2 else {
            throw ParseError.invalidFileFormat
        }

        var channelNames = headerColumns
        channelNames.removeFirst()

        guard channelNames.isEmpty == false else {
            throw ParseError.noChannelsDetected
        }

        // Print channels
        printI(1, "Channels")
        for channelName in channelNames {
            printI(2, " - \(channelName)")
        }

        guard listChannelsOnly == false else {
            return []
        }

        // ---- Find which column the channel is in
        var columnIndexOfSelectedChannel: Int?

        // 1. case-sensitive correspondence
        // 2.  "  -insensitive       "
        // 3. case-sensitive correspondence removing last letter
        // 4.  "  -insensitive       "          "     "     "

        // 1
        columnIndexOfSelectedChannel = headerColumns.firstIndex {
            $0 == channelLabel
        }

        let chanenelLabelLowercased = channelLabel.lowercased()

        // 2
        if columnIndexOfSelectedChannel == nil {
            columnIndexOfSelectedChannel = headerColumns.firstIndex {
                $0.lowercased() == chanenelLabelLowercased
            }
        }

        // 3
        if columnIndexOfSelectedChannel == nil {
            columnIndexOfSelectedChannel = headerColumns.firstIndex {
                $0.withoutLastCharacter == channelLabel
            }
        }

        // 4
        if columnIndexOfSelectedChannel == nil {
            columnIndexOfSelectedChannel = headerColumns.firstIndex {
                $0.withoutLastCharacter.lowercased() == chanenelLabelLowercased
            }
        }

        guard let columnIndexOfSelectedChannel else {
            throw ParseError.channelNotFound(channelLabel: channelLabel)
        }

        // ---- Extract points

        var progress = ProgressBar(count: pointLines.count)

        // Convert each line into a Point by:
        // 1. Split line into columns by comma
        // 2. Extract time from first column and value from selected channel's column
        // 3. Convert strings to doubles
        // 4. Create Point with time and value
        var points: [Point] = try pointLines.map { line in
            let lineColumns = line.split(separator: ",")

            guard lineColumns.count > columnIndexOfSelectedChannel else {
                throw ParseError.invalidFileFormat
            }

            let timeColumn = lineColumns[0]
            let valueColumn = lineColumns[columnIndexOfSelectedChannel]

            let timeString = String(timeColumn)
            let valueString = String(valueColumn)

            let timeDouble = Double(timeString)
            let valueDouble = Double(valueString)

            guard let timeDouble, let valueDouble else {
                throw ParseError.invalidFileFormat
            }

            progress.next()

            return Point(time: timeDouble, value: valueDouble)
        }

        // --- Make sure points are sorted from the earliest to the latest and
        //     that the first point begins with time 0

        // Early exit for less than 2 points
        guard points.count > 1 else {
            return points
        }

        // Sort points from the latest to the earliest
        points = points.sorted(by: { before, after in
            after.time > before.time
        })

        // Apply time offset, so the first point is at time 0 seconds.
        let miniumTime = points.first!.time

        if miniumTime < 0 {
            let offset = 0 - miniumTime

            points = points.map {
                .init(time: $0.time + offset, value: $0.value)
            }
        }

        // make sure the first point is positive, this error can happen due to floating point errors
        if points[0].time < 0 {
            points[0].time = 0
        }

        return points
    }
}
