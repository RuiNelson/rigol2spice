@testable import rigol2spice
import Foundation
import Testing

struct DetrendNotchTests {
    @Test
    func `detrend parses without arguments`() throws {
        #expect(try Transformation.parseList("Detrend") == [.detrend])
        #expect(try Transformation.parseList("dEtReNd") == [.detrend])
        #expect(
            throws: TransformationParseError.invalidArgumentCount(
                operation: "Detrend",
                expected: 0,
                actual: 1,
            ),
        ) {
            try Transformation.parseList("Detrend 1")
        }
    }

    @Test
    func `detrend removes least squares offset and slope while preserving timestamps`() throws {
        let points = [
            Point(time: 10, value: 21.5),
            Point(time: 11, value: 22.5),
            Point(time: 13, value: 28.5),
            Point(time: 16, value: 32.5),
        ]

        let result = try Transformation.detrend.applying(to: points)

        #expect(result.map(\.time) == points.map(\.time))
        #expect(abs(result.reduce(0.0) { $0 + $1.value }) < 1e-12)

        let meanTime = result.reduce(0.0) { $0 + $1.time } / Double(result.count)
        let residualTimeCovariance = result.reduce(0.0) {
            $0 + ($1.time - meanTime) * $1.value
        }
        #expect(abs(residualTimeCovariance) < 1e-12)
        #expect(result.contains { abs($0.value) > 0.1 })
    }

    @Test
    func `detrend handles empty singleton and equal-time captures`() throws {
        #expect(try Transformation.detrend.applying(to: []).isEmpty)

        let singleton = try Transformation.detrend.applying(to: [Point(time: 5, value: 12)])
        #expect(singleton == [Point(time: 5, value: 0)])

        let equalTimes = [
            Point(time: 2, value: 1),
            Point(time: 2, value: 3),
        ]
        let centered = try Transformation.detrend.applying(to: equalTimes)
        #expect(centered.map(\.time) == [2, 2])
        #expect(centered.map(\.value) == [-1, 1])
    }

    @Test
    func `notch parses center and width into a band stop filter`() throws {
        #expect(
            try Transformation.parseList("Notch 1k, 200")
                == [.notch(center: 1000, width: 200)],
        )
        #expect(
            Transformation.notch(center: 1000, width: 200).filterKind
                == .bandStop(low: 900, high: 1100),
        )
    }

    @Test
    func `notch rejects invalid center and width`() {
        #expect(
            throws: TransformationParseError.invalidArgumentCount(
                operation: "Notch",
                expected: 2,
                actual: 1,
            ),
        ) {
            try Transformation.parseList("Notch 1k")
        }
        #expect(
            throws: TransformationParseError.invalidNotch(
                operation: "Notch",
                center: "0",
                width: "10",
            ),
        ) {
            try Transformation.parseList("Notch 0, 10")
        }
        #expect(
            throws: TransformationParseError.invalidNotch(
                operation: "Notch",
                center: "50",
                width: "100",
            ),
        ) {
            try Transformation.parseList("Notch 50, 100")
        }
    }

    @Test
    func `notch attenuates its center and preserves distant frequencies`() throws {
        let sampleRate = 20000.0
        let interval = 1 / sampleRate
        let count = 4000
        let stop = sineWave(frequency: 1000, sampleRate: sampleRate, count: count)
        let pass = sineWave(frequency: 200, sampleRate: sampleRate, count: count)

        let filteredStop = try Transformation.notch(center: 1000, width: 600)
            .applying(to: stop, sampleInterval: interval)
        let filteredPass = try Transformation.notch(center: 1000, width: 600)
            .applying(to: pass, sampleInterval: interval)

        #expect(rms(filteredStop) / rms(stop) < 0.05)
        #expect(rms(filteredPass) / rms(pass) > 0.9)
        #expect(filteredStop.map(\.time) == stop.map(\.time))
    }

    private func sineWave(frequency: Double, sampleRate: Double, count: Int) -> [Point] {
        let interval = 1 / sampleRate
        return (0 ..< count).map { index in
            let time = Double(index) * interval
            return Point(time: time, value: sin(2 * Double.pi * frequency * time))
        }
    }

    private func rms(_ points: [Point]) -> Double {
        let margin = min(300, points.count / 10)
        let slice = points[margin ..< (points.count - margin)]
        let sumSquares = slice.reduce(0.0) { $0 + $1.value * $1.value }
        return (sumSquares / Double(slice.count)).squareRoot()
    }
}
