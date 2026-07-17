import Foundation

struct PWLWriter {
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
            let pointTimeStr = spiceFormatter.string(for: point.time)!
            let pointValueStr = spiceFormatter.string(for: point.value)!
            let pointLine = "\(pointTimeStr)\t\(pointValueStr)\r\n"
            let pointData = pointLine.data(using: .ascii)!

            data.append(pointData)
        }

        try data.write(to: outputURL, options: .atomic)
        return data.count
    }
}
