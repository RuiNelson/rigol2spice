@testable import rigol2spice
import Foundation
import Testing

struct AnalogModulationTests {
    @Test
    func `parses modulation and demodulation operations and aliases`() throws {
        #expect(try Transformation.parseList("AM 2k, 0.8") == [
            .am(carrier: 2000, depth: 0.8, amplitude: 1),
        ])
        #expect(try Transformation.parseList("ModulateFM 2k, 250, 2") == [
            .fm(carrier: 2000, sensitivity: 250, amplitude: 2),
        ])
        #expect(try Transformation.parseList("PM 2k, 1.2, 500m") == [
            .pm(carrier: 2000, sensitivity: 1.2, amplitude: 0.5),
        ])
        #expect(try Transformation.parseList("DemodAM 2k, 0.8, 400") == [
            .demodAM(carrier: 2000, depth: 0.8, cutoff: 400),
        ])
        #expect(try Transformation.parseList("FMDemod 2k, 250, 400") == [
            .demodFM(carrier: 2000, sensitivity: 250, cutoff: 400),
        ])
        #expect(try Transformation.parseList("PMDemod 2k, 1.2, 400") == [
            .demodPM(carrier: 2000, sensitivity: 1.2, cutoff: 400),
        ])
    }

    @Test
    func `rejects non-positive modulation parameters`() {
        #expect(throws: TransformationParseError.invalidPositiveScalar(operation: "AM", value: "0")) {
            try Transformation.parseList("AM 0, 0.8")
        }
        #expect(throws: TransformationParseError.invalidPositiveScalar(operation: "FM", value: "0")) {
            try Transformation.parseList("FM 2k, 0")
        }
        #expect(throws: TransformationParseError.invalidPositiveScalar(operation: "DemodPM", value: "0")) {
            try Transformation.parseList("DemodPM 2k, 1, 0")
        }
    }

    @Test
    func `modulators preserve timestamps and sample count`() throws {
        let signal = messageSignal()
        let transforms: [Transformation] = [
            .am(carrier: 2000, depth: 0.7, amplitude: 1.5),
            .fm(carrier: 2000, sensitivity: 50, amplitude: 1.5),
            .pm(carrier: 2000, sensitivity: 0.2, amplitude: 1.5),
        ]

        for transformation in transforms {
            let result = try transformation.applying(to: signal, sampleInterval: sampleInterval)
            #expect(result.count == signal.count)
            #expect(result.map(\.time) == signal.map(\.time))
        }
    }

    @Test
    func `AM round trip recovers the baseband message`() throws {
        let signal = messageSignal()
        let modulated = try Transformation.am(carrier: 2000, depth: 0.7, amplitude: 1.5)
            .applying(to: signal, sampleInterval: sampleInterval)
        let recovered = try Transformation.demodAM(carrier: 2000, depth: 0.7, cutoff: 450)
            .applying(to: modulated, sampleInterval: sampleInterval)

        #expect(correlation(signal, recovered) > 0.99)
        #expect(recovered.map(\.time) == signal.map(\.time))
    }

    @Test
    func `FM sensitivity uses raw input units and round trip preserves DC`() throws {
        let signal = messageSignal()
        let modulated = try Transformation.fm(carrier: 2000, sensitivity: 50, amplitude: 1.5)
            .applying(to: signal, sampleInterval: sampleInterval)
        let recovered = try Transformation.demodFM(carrier: 2000, sensitivity: 50, cutoff: 450)
            .applying(to: modulated, sampleInterval: sampleInterval)

        #expect(correlation(signal, recovered) > 0.97)
        #expect(abs(centralMean(recovered) - centralMean(signal)) < 0.05)
        #expect(rootMeanSquareError(signal, recovered) < 0.15)
    }

    @Test
    func `PM sensitivity uses raw input units and round trip preserves DC`() throws {
        let signal = messageSignal()
        let modulated = try Transformation.pm(carrier: 2000, sensitivity: 0.2, amplitude: 1.5)
            .applying(to: signal, sampleInterval: sampleInterval)
        let recovered = try Transformation.demodPM(carrier: 2000, sensitivity: 0.2, cutoff: 450)
            .applying(to: modulated, sampleInterval: sampleInterval)

        #expect(correlation(signal, recovered) > 0.99)
        #expect(abs(centralMean(recovered) - centralMean(signal)) < 0.05)
        #expect(rootMeanSquareError(signal, recovered) < 0.1)
    }

    @Test
    func `validates instantaneous FM frequency and demodulator cutoff against sampling rate`() {
        let signal = messageSignal()
        #expect(throws: AnalogModulationError.carrierOutOfRange(
            operation: "AM",
            carrier: 5000,
            nyquist: 5000,
        )) {
            try Transformation.am(carrier: 5000, depth: 0.5, amplitude: 1)
                .applying(to: signal, sampleInterval: sampleInterval)
        }
        #expect(throws: AnalogModulationError.instantaneousFrequencyOutOfRange(
            operation: "FM",
            minimum: 4500,
            maximum: 6300,
            nyquist: 5000,
        )) {
            try Transformation.fm(carrier: 4800, sensitivity: 300, amplitude: 1)
                .applying(to: signal, sampleInterval: sampleInterval)
        }
        #expect(throws: AnalogModulationError.cutoffOutOfRange(
            operation: "DemodAM",
            cutoff: 2000,
            maximum: 2000,
        )) {
            try Transformation.demodAM(carrier: 2000, depth: 0.5, cutoff: 2000)
                .applying(to: signal, sampleInterval: sampleInterval)
        }
    }

    private let sampleRate = 10000.0
    private var sampleInterval: Double {
        1 / sampleRate
    }

    private func messageSignal() -> [Point] {
        (0 ..< 2000).map { index in
            let time = Double(index) * sampleInterval
            return Point(time: time, value: 2 + 3 * sin(2 * Double.pi * 100 * time))
        }
    }

    private func correlation(_ expected: [Point], _ actual: [Point]) -> Double {
        let margin = 300
        let indices = margin ..< (min(expected.count, actual.count) - margin)
        let expectedMean = indices.reduce(0.0) { $0 + expected[$1].value } / Double(indices.count)
        let actualMean = indices.reduce(0.0) { $0 + actual[$1].value } / Double(indices.count)
        var numerator = 0.0
        var expectedEnergy = 0.0
        var actualEnergy = 0.0
        for index in indices {
            let x = expected[index].value - expectedMean
            let y = actual[index].value - actualMean
            numerator += x * y
            expectedEnergy += x * x
            actualEnergy += y * y
        }
        return numerator / sqrt(expectedEnergy * actualEnergy)
    }

    private func centralMean(_ points: [Point]) -> Double {
        let values = points.dropFirst(300).dropLast(300).map(\.value)
        return values.reduce(0, +) / Double(values.count)
    }

    private func rootMeanSquareError(_ expected: [Point], _ actual: [Point]) -> Double {
        let indices = 300 ..< (min(expected.count, actual.count) - 300)
        let sumSquares = indices.reduce(0.0) {
            let error = expected[$1].value - actual[$1].value
            return $0 + error * error
        }
        return sqrt(sumSquares / Double(indices.count))
    }
}
