import Foundation

struct CentaurusCSVParser: CSVFormatParser {
    let encoding = String.Encoding.isoLatin1

    func parseHeader(from reader: CSVCharacterReader) throws -> CSVHeader {
        guard let headerLine = try reader.nextLine() else {
            throw ParseError.insufficientLines
        }

        let headerFields = csvFields(in: headerLine)
        guard headerFields.count >= 2 else {
            throw ParseError.invalidFileFormat
        }

        let channels = headerFields.dropFirst().enumerated().compactMap { offset, name -> CSVChannel? in
            guard !name.isEmpty else {
                return nil
            }
            return CSVChannel(name: name, columnIndex: offset + 1)
        }

        return CSVHeader(channels: channels, sampleInterval: nil)
    }

    func alternativeNames(for channel: CSVChannel) -> [String] {
        guard channel.name.count > 1 else {
            return []
        }
        return [String(channel.name.dropLast())]
    }

    func normalize(_ points: inout [Point]) {
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

    func sampleInterval(from _: CSVHeader, points: [Point]) -> Double? {
        guard points.count >= 2 else {
            return nil
        }
        return points[points.count - 1].time - points[points.count - 2].time
    }
}
