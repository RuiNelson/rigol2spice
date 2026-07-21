@testable import rigol2spice
import Foundation
import Testing

struct DigitalFilterTests {
    @Test
    func `parses filter operations`() throws {
        #expect(try Transformation.parseList("LowPass 1k") == [.lowPass(1000)])
        #expect(try Transformation.parseList("highpass 100") == [.highPass(100)])
        #expect(
            try Transformation.parseList("BandPass 900,1.1k")
                == [.bandPass(low: 900, high: 1100)],
        )
        #expect(
            try Transformation.parseList("BandPass 900, 1.1k")
                == [.bandPass(low: 900, high: 1100)],
        )
        #expect(
            try Transformation.parseList("BandStop 48,52")
                == [.bandStop(low: 48, high: 52)],
        )
        #expect(
            try Transformation.parseList("BandStop 48, 52")
                == [.bandStop(low: 48, high: 52)],
        )
    }

    @Test
    func `rejects invalid filter arguments`() {
        #expect(throws: TransformationParseError.invalidPositiveScalar(operation: "LowPass", value: "0")) {
            try Transformation.parseList("LowPass 0")
        }
        #expect(throws: TransformationParseError.invalidArgumentCount(operation: "LowPass", expected: 1, actual: 0)) {
            try Transformation.parseList("LowPass")
        }
        #expect(throws: TransformationParseError.invalidArgumentCount(operation: "BandPass", expected: 2, actual: 1)) {
            try Transformation.parseList("BandPass 1k")
        }
        #expect(
            throws: TransformationParseError.invalidFrequencyBand(operation: "BandPass", low: "2k", high: "1k"),
        ) {
            try Transformation.parseList("BandPass 2k,1k")
        }
    }

    @Test
    func `rejects frequencies at or above Nyquist`() {
        let points = sineWave(frequency: 100, sampleRate: 10000, count: 2000)
        #expect(
            throws: DigitalFilterError.frequencyOutOfRange(
                operation: "LowPass",
                frequency: 5000,
                nyquist: 5000,
            ),
        ) {
            _ = try Transformation.lowPass(5000).applying(to: points, sampleInterval: 1 / 10000)
        }
    }

    @Test
    func `low pass preserves low frequency and attenuates high frequency`() throws {
        let sampleRate = 20000.0
        let interval = 1 / sampleRate
        let count = 4000

        let low = sineWave(frequency: 200, sampleRate: sampleRate, count: count)
        let high = sineWave(frequency: 4000, sampleRate: sampleRate, count: count)

        let filteredLow = try Transformation.lowPass(1000).applying(to: low, sampleInterval: interval)
        let filteredHigh = try Transformation.lowPass(1000).applying(to: high, sampleInterval: interval)

        let lowGain = rms(filteredLow) / rms(low)
        let highGain = rms(filteredHigh) / rms(high)

        #expect(lowGain > 0.9)
        #expect(highGain < 0.05)
    }

    @Test
    func `zero phase cutoff is approximately minus three decibels`() throws {
        let sampleRate = 20000.0
        let interval = 1 / sampleRate
        let cutoff = sineWave(frequency: 1000, sampleRate: sampleRate, count: 20000)

        let lowPassed = try Transformation.lowPass(1000).applying(to: cutoff, sampleInterval: interval)
        let highPassed = try Transformation.highPass(1000).applying(to: cutoff, sampleInterval: interval)
        let expectedGain = 1 / sqrt(2.0)

        #expect(abs(rms(lowPassed) / rms(cutoff) - expectedGain) < 0.02)
        #expect(abs(rms(highPassed) / rms(cutoff) - expectedGain) < 0.02)
    }

    @Test
    func `high order response is steep close to the cutoff`() throws {
        let sampleRate = 20000.0
        let interval = 1 / sampleRate
        let count = 20000
        let pass = sineWave(frequency: 800, sampleRate: sampleRate, count: count)
        let stop = sineWave(frequency: 1200, sampleRate: sampleRate, count: count)

        let filteredPass = try Transformation.lowPass(1000).applying(to: pass, sampleInterval: interval)
        let filteredStop = try Transformation.lowPass(1000).applying(to: stop, sampleInterval: interval)

        #expect(rms(filteredPass) / rms(pass) > 0.99)
        #expect(rms(filteredStop) / rms(stop) < 0.01)
    }

    @Test
    func `high pass preserves high frequency and attenuates low frequency`() throws {
        let sampleRate = 20000.0
        let interval = 1 / sampleRate
        let count = 4000

        let low = sineWave(frequency: 100, sampleRate: sampleRate, count: count)
        let high = sineWave(frequency: 4000, sampleRate: sampleRate, count: count)

        let filteredLow = try Transformation.highPass(1000).applying(to: low, sampleInterval: interval)
        let filteredHigh = try Transformation.highPass(1000).applying(to: high, sampleInterval: interval)

        #expect(rms(filteredLow) / rms(low) < 0.05)
        #expect(rms(filteredHigh) / rms(high) > 0.9)
    }

    @Test
    func `band pass keeps in band energy`() throws {
        let sampleRate = 20000.0
        let interval = 1 / sampleRate
        let count = 4000

        let inBand = sineWave(frequency: 1000, sampleRate: sampleRate, count: count)
        let outOfBand = sineWave(frequency: 4000, sampleRate: sampleRate, count: count)

        let filteredIn = try Transformation.bandPass(low: 700, high: 1300)
            .applying(to: inBand, sampleInterval: interval)
        let filteredOut = try Transformation.bandPass(low: 700, high: 1300)
            .applying(to: outOfBand, sampleInterval: interval)

        #expect(rms(filteredIn) / rms(inBand) > 0.85)
        #expect(rms(filteredOut) / rms(outOfBand) < 0.05)
    }

    @Test
    func `band stop attenuates the stop band`() throws {
        let sampleRate = 20000.0
        let interval = 1 / sampleRate
        let count = 4000

        let stop = sineWave(frequency: 1000, sampleRate: sampleRate, count: count)
        let pass = sineWave(frequency: 200, sampleRate: sampleRate, count: count)

        let filteredStop = try Transformation.bandStop(low: 700, high: 1300)
            .applying(to: stop, sampleInterval: interval)
        let filteredPass = try Transformation.bandStop(low: 700, high: 1300)
            .applying(to: pass, sampleInterval: interval)

        #expect(rms(filteredStop) / rms(stop) < 0.05)
        #expect(rms(filteredPass) / rms(pass) > 0.9)
    }

    @Test
    func `band stop edges are approximately minus three decibels`() throws {
        let sampleRate = 20000.0
        let interval = 1 / sampleRate
        let lowEdge = sineWave(frequency: 700, sampleRate: sampleRate, count: 20000)
        let highEdge = sineWave(frequency: 1300, sampleRate: sampleRate, count: 20000)

        let filteredLow = try Transformation.bandStop(low: 700, high: 1300)
            .applying(to: lowEdge, sampleInterval: interval)
        let filteredHigh = try Transformation.bandStop(low: 700, high: 1300)
            .applying(to: highEdge, sampleInterval: interval)
        let expectedGain = 1 / sqrt(2.0)

        #expect(abs(rms(filteredLow) / rms(lowEdge) - expectedGain) < 0.08)
        #expect(abs(rms(filteredHigh) / rms(highEdge) - expectedGain) < 0.08)
    }

    @Test
    func `band stop response is steep inside and outside its edges`() throws {
        let sampleRate = 20000.0
        let interval = 1 / sampleRate
        let count = 20000
        let inside = sineWave(frequency: 900, sampleRate: sampleRate, count: count)
        let outside = sineWave(frequency: 500, sampleRate: sampleRate, count: count)

        let filteredInside = try Transformation.bandStop(low: 700, high: 1300)
            .applying(to: inside, sampleInterval: interval)
        let filteredOutside = try Transformation.bandStop(low: 700, high: 1300)
            .applying(to: outside, sampleInterval: interval)

        #expect(rms(filteredInside) / rms(inside) < 0.1)
        #expect(rms(filteredOutside) / rms(outside) > 0.99)
    }

    @Test
    func `group delay compensation keeps impulse peak aligned`() throws {
        let sampleRate = 10000.0
        let interval = 1 / sampleRate
        let count = 1001
        var points = (0 ..< count).map { Point(time: Double($0) * interval, value: 0) }
        let peakIndex = count / 2
        points[peakIndex].value = 1

        let filtered = try Transformation.lowPass(1000).applying(to: points, sampleInterval: interval)
        let maxIndex = try #require(filtered.indices.max(by: { filtered[$0].value < filtered[$1].value }))

        #expect(abs(maxIndex - peakIndex) <= 2)
        #expect(filtered.map(\.time) == points.map(\.time))
    }

    @Test
    func `low pass has unity DC gain`() throws {
        let sampleRate = 10000.0
        let interval = 1 / sampleRate
        let points = (0 ..< 2000).map { Point(time: Double($0) * interval, value: 2.5) }

        let filtered = try Transformation.lowPass(500).applying(to: points, sampleInterval: interval)
        let mid = filtered[filtered.count / 2].value

        #expect(abs(mid - 2.5) < 1e-6)
    }

    @Test
    func `infers sample interval from points when omitted`() throws {
        let points = sineWave(frequency: 100, sampleRate: 5000, count: 1000)
        let filtered = try Transformation.lowPass(200).applying(to: points, sampleInterval: nil)
        #expect(filtered.count == points.count)
    }

    @Test
    func `design uses a fixed number of stable biquad sections`() throws {
        let design = try designDigitalFilter(
            kind: .lowPass(cutoff: 1000),
            sampleRate: 20000,
            sampleCount: 5000,
        )

        #expect(design.sections.count == 8)
        #expect(design.sections.allSatisfy { $0.maximumPoleRadius < 1 })
        #expect(design.settlingTime > 0)
    }

    @Test
    func `section count does not grow for low cutoffs at high sample rates`() throws {
        let design = try designDigitalFilter(
            kind: .lowPass(cutoff: 50),
            sampleRate: 1_000_000,
            sampleCount: 10000,
        )

        #expect(design.sections.count == 8)
    }

    private func sineWave(frequency: Double, sampleRate: Double, count: Int) -> [Point] {
        let interval = 1 / sampleRate
        return (0 ..< count).map { index in
            let time = Double(index) * interval
            return Point(time: time, value: sin(2 * Double.pi * frequency * time))
        }
    }

    private func rms(_ points: [Point]) -> Double {
        // Ignore forward/reverse initialization transients near capture boundaries.
        let margin = min(300, points.count / 10)
        guard points.count > margin * 2 else {
            let sumSquares = points.reduce(0.0) { $0 + $1.value * $1.value }
            return (sumSquares / Double(points.count)).squareRoot()
        }

        var sumSquares = 0.0
        let slice = points[margin ..< (points.count - margin)]
        for point in slice {
            sumSquares += point.value * point.value
        }
        return (sumSquares / Double(slice.count)).squareRoot()
    }
}
