import Foundation

struct MATLABWriter {
    func write(
        _ points: [Point],
        to outputURL: URL,
    ) throws -> Int {
        var data = Data("points = [\r\n".utf8)
        let (estimatedCapacity, overflow) = points.count.multipliedReportingOverflow(by: 20)
        if !overflow {
            data.reserveCapacity(data.count + estimatedCapacity)
        }

        for point in points {
            let pointValue = spiceFormatter.string(for: point.value)!
            data.append(contentsOf: "\(pointValue);\r\n".utf8)
        }

        data.append(contentsOf: "];\r\n".utf8)
        try data.write(to: outputURL, options: .atomic)
        return data.count
    }
}
