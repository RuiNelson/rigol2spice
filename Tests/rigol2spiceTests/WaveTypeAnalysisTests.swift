@testable import rigol2spice
import Foundation
import Testing

struct WaveTypeAnalysisTests {
    @Test
    func `parses individual wave types and WaveType preset after FFT`() throws {
        #expect(try Analysis.parseList("FFT; WaveType") == [
            .fft(pointCount: nil, position: .start),
            .sineWaveType,
            .squareWaveType,
            .sawtoothWaveType,
            .triangleWaveType,
        ])
        #expect(try Analysis.parseList(
            "FFT 1k, middle; SineWaveType; SquareWaveType; SawWaveType; TriangleWaveType",
        ) == [
            .fft(pointCount: 1000, position: .middle),
            .sineWaveType,
            .squareWaveType,
            .sawtoothWaveType,
            .triangleWaveType,
        ])
    }

    @Test
    func `wave type analyses require a preceding FFT`() {
        for operation in [
            "WaveType",
            "SineWaveType",
            "SquareWaveType",
            "SawtoothWaveType",
            "TriangleWaveType",
        ] {
            #expect(throws: AnalysisParseError.fftRequired(operation: operation)) {
                try Analysis.parseList(operation)
            }
        }
    }

    @Test(arguments: [
        WaveShape.sine,
        .square,
        .sawtooth,
        .triangle,
    ])
    func `ideal periodic wave has the highest matching harmonic score`(_ shape: WaveShape) throws {
        let spectrum = try #require(computeFFTSpectrum(
            points: wave(shape),
            requestedPointCount: sampleCount,
        ))
        let percentages = try #require(waveTypePercentages(spectrum: spectrum))
        let scores = [
            percentages.sine,
            percentages.square,
            percentages.sawtooth,
            percentages.triangle,
        ]

        #expect(scores[shape.rawValue] == scores.max())
        #expect(scores[shape.rawValue] > 60)
    }

    @Test
    func `WaveType preset reports four percentages from the retained FFT`() throws {
        let analyses = try Analysis.parseList("FFT 4096; RMS; WaveType")
        let reports = AnalysisReport.reports(for: analyses, on: wave(.triangle))
        let waveReports = Array(reports.suffix(4))
        let values = waveReports.compactMap { report -> Double? in
            guard case let .scalar(value) = report.outcome else {
                return nil
            }
            return value
        }

        #expect(values.count == 4)
        #expect(waveReports.allSatisfy { $0.displayLine.hasSuffix("%") })
        #expect(values[WaveShape.triangle.rawValue] == values.max())
    }

    @Test
    func `wave type percentages are independent rather than normalized`() throws {
        let spectrum = try #require(computeFFTSpectrum(
            points: wave(.sine),
            requestedPointCount: sampleCount,
        ))
        let percentages = try #require(waveTypePercentages(spectrum: spectrum))
        let total = percentages.sine + percentages.square + percentages.sawtooth + percentages.triangle

        #expect(percentages.sine > 99)
        #expect(abs(total - 100) > 1e-6)
    }

    @Test
    func `sine wave type is one hundred percent minus THD`() throws {
        let spectrum = try #require(computeFFTSpectrum(
            points: wave(.square),
            requestedPointCount: sampleCount,
        ))
        let percentages = try #require(waveTypePercentages(spectrum: spectrum))
        let thd = try #require(thdFraction(spectrum: spectrum))

        #expect(abs(percentages.sine - 100 * max(0, 1 - thd)) < 1e-9)
    }

    @Test
    func `non coherent square capture remains a strong square match`() throws {
        let count = 4096
        let sampleRate = 10000.0
        let frequency = 123.45
        let points = (0 ..< count).map { index in
            let time = Double(index) / sampleRate
            let value = sin(2 * Double.pi * frequency * time) >= 0 ? 1.0 : -1.0
            return Point(time: time, value: value)
        }
        let spectrum = try #require(computeFFTSpectrum(points: points, requestedPointCount: count))
        let percentages = try #require(waveTypePercentages(spectrum: spectrum))

        #expect(percentages.square > 70)
        #expect(percentages.square > percentages.sine)
        #expect(percentages.square > percentages.sawtooth)
        #expect(percentages.square > percentages.triangle)
    }

    private let sampleRate = 8192.0
    private let sampleCount = 4096
    private let frequency = 64.0

    private func wave(_ shape: WaveShape) -> [Point] {
        (0 ..< sampleCount).map { index in
            let time = Double(index) / sampleRate
            let phase = frequency * time
            let sine = sin(2 * Double.pi * phase)
            let value: Double = switch shape {
            case .sine:
                sine
            case .square:
                sine >= 0 ? 1 : -1
            case .sawtooth:
                2 * (phase - floor(phase + 0.5))
            case .triangle:
                2 / Double.pi * asin(sine)
            }
            return Point(time: time, value: value)
        }
    }

    enum WaveShape: Int, CaseIterable, CustomTestStringConvertible {
        case sine
        case square
        case sawtooth
        case triangle

        var testDescription: String {
            String(describing: self)
        }
    }
}
