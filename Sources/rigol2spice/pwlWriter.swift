import Foundation

// MARK: - PWLWriterError

enum PWLWriterError: LocalizedError {
    case nonASCIIOutput

    var errorDescription: String? {
        "Unable to encode PWL output as ASCII"
    }
}

// MARK: - PWLWriter

struct PWLWriter {
    private static let newline = Data("\r\n".utf8)

    func write(
        _ points: [Point],
        to outputURL: URL,
    ) throws -> Int {
        var data = Data()
        let (estimatedCapacity, overflow) = points.count.multipliedReportingOverflow(by: 32)
        if !overflow {
            data.reserveCapacity(estimatedCapacity)
        }

        for point in points {
            guard let pointData = point.serialize.data(using: .ascii) else {
                throw PWLWriterError.nonASCIIOutput
            }
            data.append(pointData)
            data.append(Self.newline)
        }

        try data.write(to: outputURL, options: .atomic)
        return data.count
    }
}
