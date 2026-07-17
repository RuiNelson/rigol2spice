import Foundation

struct LegacyCSVParser: CSVFormatParser {
    let encoding = String.Encoding.ascii

    func parseHeader(from reader: CSVCharacterReader) throws -> CSVHeader {
        guard let namesLine = try reader.nextLine(), let valuesLine = try reader.nextLine() else {
            throw ParseError.insufficientLines
        }

        let names = csvFields(in: namesLine)
        let values = csvFields(in: valuesLine)
        var channels: [CSVChannel] = []
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
                channels.append(CSVChannel(name: name, columnIndex: index))
            }
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

        return CSVHeader(
            channels: channels,
            sampleInterval: sampleInterval,
            timeScale: sampleInterval,
        )
    }
}
