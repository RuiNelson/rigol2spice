@testable import rigol2spice
import Foundation
import Testing

struct QuickAnalysisTests {
    @Test
    func `analysis reports combine engineering prefixes with physical units`() {
        func line(_ analysis: Analysis, _ value: Double) -> String {
            AnalysisReport(analysis: analysis, outcome: .scalar(value)).displayLine
        }

        #expect(line(.duration, 2e-3) == "Duration: 2ms")
        #expect(line(.max, 3.3e-3) == "Max: 3.3mV")
        #expect(line(.sampleRate, 2500) == "SampleRate: 2.5kSa/s")
        #expect(line(.slewRise(lowPercent: 10, highPercent: 90), 1.2e6) == "SlewRise: 1.2MV/s")
        #expect(line(.integral, 3e-3) == "Integral: 3mV·s")
        #expect(line(.power(resistance: 50), 2e-3) == "Power: 2mW")
        #expect(line(.energy(resistance: 1), 4e-6) == "Energy: 4uJ")
        #expect(line(.dbm(resistance: 50), 10) == "dBm: 10dBm")
        #expect(line(.points, 42) == "Points: 42 samples")
        #expect(line(.riseCount(threshold: nil), 3) == "RiseCount: 3 edges")
        #expect(line(.duty(threshold: nil), 0.25) == "Duty: 25.0%")
        #expect(line(.thd, 0.012) == "THD: 1.2%")
        #expect(line(.sineWaveType, 99.96) == "SineWaveType: 100.0%")
        #expect(line(.crest, 1.4) == "Crest: 1.4×")

        let fundamental = AnalysisReport(
            analysis: .fundamental,
            outcome: .frequencyAndAmplitude(frequency: 1000, amplitude: 0.5),
        )
        #expect(fundamental.displayLine == "Fundamental: f=1kHz  A=500mV")
    }

    @Test
    func `parses quick measurements and optional arguments`() throws {
        #expect(
            try Analysis.parseList(
                "PeakTime; MinTime; MeanAbs; RiseCount; RiseCount 0; FallCount; "
                    + "PeriodMin; PeriodMax 0; PeriodPkPk; Power; Power 75; "
                    + "Energy; Energy 50; FFT 1k, middle; Fundamental; "
                    + "Harmonic 3; Harmonic 2",
            ) == [
                .peakTime,
                .minTime,
                .meanAbs,
                .riseCount(threshold: nil),
                .riseCount(threshold: 0),
                .fallCount(threshold: nil),
                .periodMin(threshold: nil),
                .periodMax(threshold: 0),
                .periodPkPk(threshold: nil),
                .power(resistance: 50),
                .power(resistance: 75),
                .energy(resistance: 1),
                .energy(resistance: 50),
                .fft(pointCount: 1000, position: .middle),
                .fundamental,
                .harmonic(number: 3),
                .harmonic(number: 2),
            ],
        )
    }

    @Test
    func `rejects invalid power energy and harmonic arguments`() {
        for source in [
            "Power 0",
            "Energy -1",
            "Harmonic",
            "Harmonic 0",
            "Harmonic 1.5",
            "Harmonic 2, 0",
            "Harmonic 2, 1024, 3",
        ] {
            #expect(throws: (any Error).self) {
                try Analysis.parseList(source)
            }
        }
    }

    @Test
    func `peak times use first extrema and mean abs averages magnitudes`() {
        let points = [
            Point(time: -1, value: -2),
            Point(time: 1, value: 3),
            Point(time: 2, value: 3),
            Point(time: 4, value: 0),
        ]

        #expect(Analysis.peakTime.evaluate(on: points) == .scalar(1))
        #expect(Analysis.minTime.evaluate(on: points) == .scalar(-1))
        #expect(Analysis.meanAbs.evaluate(on: points) == .scalar(2))
        #expect(Analysis.peakTime.evaluate(on: []) == .unavailable)
        #expect(Analysis.minTime.evaluate(on: []) == .unavailable)
        #expect(Analysis.meanAbs.evaluate(on: []) == .scalar(0))
    }

    @Test
    func `directed counts and period range share interpolated crossings`() {
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1, value: 1),
            Point(time: 2, value: -1),
            Point(time: 4, value: 1),
            Point(time: 7, value: -1),
            Point(time: 11, value: 1),
        ]

        #expect(Analysis.riseCount(threshold: nil).evaluate(on: points) == .scalar(3))
        #expect(Analysis.fallCount(threshold: nil).evaluate(on: points) == .scalar(2))
        #expect(Analysis.periodMin(threshold: nil).evaluate(on: points) == .scalar(2.5))
        #expect(Analysis.periodMax(threshold: nil).evaluate(on: points) == .scalar(6))
        #expect(Analysis.periodPkPk(threshold: nil).evaluate(on: points) == .scalar(3.5))

        let incomplete = Array(points.prefix(2))
        #expect(Analysis.periodMin(threshold: 0).evaluate(on: incomplete) == .unavailable)
    }

    @Test
    func `power and energy honor resistance defaults and overrides`() throws {
        let points = [
            Point(time: 0, value: 2),
            Point(time: 1, value: 2),
            Point(time: 2, value: 2),
        ]

        #expect(Analysis.power(resistance: 50).evaluate(on: points) == .scalar(0.08))
        #expect(Analysis.energy(resistance: 1).evaluate(on: points) == .scalar(8))
        #expect(Analysis.energy(resistance: 50).evaluate(on: points) == .scalar(0.16))
        #expect(Analysis.power(resistance: 0).evaluate(on: points) == .unavailable)
        #expect(Analysis.energy(resistance: 0).evaluate(on: points) == .unavailable)

        #expect(try Analysis.parseList("Power; Energy") == [
            .power(resistance: 50),
            .energy(resistance: 1),
        ])
    }

    @Test
    func `fundamental and harmonic report hann corrected peak amplitudes`() {
        let sampleRate = 4096.0
        let count = 4096
        let frequency = 64.0
        let points = (0 ..< count).map { index -> Point in
            let time = Double(index) / sampleRate
            let fundamental = 2 * sin(2 * Double.pi * frequency * time)
            let third = 0.5 * sin(2 * Double.pi * 3 * frequency * time)
            return Point(time: time, value: fundamental + third)
        }

        let spectrum = computeFFTSpectrum(points: points, requestedPointCount: count)
        guard case let .frequencyAndAmplitude(measuredFrequency, measuredAmplitude) =
            Analysis.fundamental.evaluate(on: points, using: spectrum),
            case let .scalar(thirdAmplitude) =
            Analysis.harmonic(number: 3).evaluate(on: points, using: spectrum) else {
            Issue.record("Expected spectral measurements")
            return
        }

        #expect(abs(measuredFrequency - frequency) < 0.1)
        #expect(abs(measuredAmplitude - 2) < 0.02)
        #expect(abs(thirdAmplitude - 0.5) < 0.02)
        #expect(Analysis.harmonic(number: 100).evaluate(on: points, using: spectrum) == .unavailable)

        let report = AnalysisReport(
            analysis: .fundamental,
            outcome: .frequencyAndAmplitude(frequency: measuredFrequency, amplitude: measuredAmplitude),
        )
        #expect(report.displayLine.contains("Hz"))
        #expect(report.displayLine.contains("A="))
    }
}
