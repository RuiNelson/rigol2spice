@testable import rigol2spice
import Foundation
import Testing

// MARK: - AnalysisTests

struct AnalysisTests {
    @Test
    func `parses analyses with aliases`() throws {
        let analyses = try Analysis.parseList(
            "Max; Min; HiPeak; LowPeak; Avg; DC; FrequencyAt 1.5; FrequencyAtZero; Frequency; RMS; PkPk",
        )

        #expect(analyses == [
            .max,
            .min,
            .max,
            .min,
            .avg,
            .dc,
            .frequencyAt(1.5),
            .frequencyAt(0),
            .frequency,
            .rms,
            .pkPk,
        ])
    }

    @Test
    func `analysis commands accept semicolon and all conventional line endings`() throws {
        let expected: [Analysis] = [.max, .min, .avg, .rms]

        #expect(try Analysis.parseList("Max;Min\rAvg\nRMS") == expected)
        #expect(try Analysis.parseList("Max\r\nMin\r\nAvg\r\nRMS") == expected)
    }

    @Test
    func `operation names are case insensitive`() throws {
        #expect(
            try Analysis.parseList("max; HIPEAK; frequencyatzero; pkpk")
                == [.max, .max, .frequencyAt(0), .pkPk],
        )
    }

    @Test
    func `presets expand case insensitively in command position`() throws {
        #expect(
            try Analysis.parseList("Max; basic; Min; TIMING; spectrum") == [
                .max,
                .duration, .points, .sampleRate, .interval, .start, .end,
                .max, .min, .pkPk, .peak, .amplitude, .mid, .avg, .dc, .rms,
                .acRms, .stdDev, .crest, .median, .peakTime, .minTime, .meanAbs,
                .top, .base, .overshoot, .undershoot,
                .min,
                .frequencyAt(0),
                .frequency,
                .riseTime(lowPercent: 10, highPercent: 90),
                .fallTime(lowPercent: 10, highPercent: 90),
                .slewRise(lowPercent: 10, highPercent: 90),
                .slewFall(lowPercent: 10, highPercent: 90),
                .pulseWidth(threshold: nil),
                .lowPulseWidth(threshold: nil),
                .duty(threshold: nil),
                .edgeCount(threshold: nil),
                .riseCount(threshold: nil),
                .fallCount(threshold: nil),
                .jitter(threshold: nil),
                .periodMin(threshold: nil),
                .periodMax(threshold: nil),
                .periodPkPk(threshold: nil),
                .fft(pointCount: nil, position: .start),
                .thd,
            ],
        )

        #expect(throws: (any Error).self) {
            try Analysis.parseList("Basic 1")
        }
    }

    @Test
    func `frequency at accepts engineering notation`() throws {
        let nano = try Analysis.parseList("FrequencyAt 3n")
        guard case let .frequencyAt(value) = nano.first else {
            Issue.record("Expected FrequencyAt")
            return
        }
        #expect(abs(value - 3e-9) < 1e-20)
        #expect(try Analysis.parseList("FrequencyAt -1.2") == [.frequencyAt(-1.2)])
    }

    @Test
    func `rejects unknown operations and invalid arity`() {
        #expect(throws: (any Error).self) {
            try Analysis.parseList("NotARealOp")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("Max 1")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("FrequencyAt")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("FrequencyAt 1, 2")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("FrequencyAtZero 0")
        }
        #expect(throws: AnalysisParseError.unknownOperation(name: "Crossing")) {
            try Analysis.parseList("Crossing 0")
        }
        #expect(throws: AnalysisParseError.unknownOperation(name: "ZeroCrossing")) {
            try Analysis.parseList("ZeroCrossing")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("RiseTime 90, 10")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("dBm -50")
        }
    }

    @Test
    func `ignores empty commands in the list`() throws {
        #expect(try Analysis.parseList("Max;;\r\n  ;Min;") == [.max, .min])
        #expect(try Analysis.parseList(";;\r\n  ;\n").isEmpty)
    }

    @Test
    func `max min avg pkpk rms reuse transform measurement helpers`() {
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1, value: 3),
            Point(time: 2, value: 1),
        ]

        #expect(Analysis.max.evaluate(on: points) == .scalar(3))
        #expect(Analysis.min.evaluate(on: points) == .scalar(-1))
        #expect(Analysis.avg.evaluate(on: points) == .scalar(1))
        #expect(Analysis.pkPk.evaluate(on: points) == .scalar(peakToPeakValue(points)))
        #expect(Analysis.rms.evaluate(on: points) == .scalar(rmsValue(points)))
        #expect(Analysis.dc.evaluate(on: points) == .scalar(calculateDC(points)))
    }

    @Test
    func `empty capture yields zero scalars`() {
        #expect(Analysis.max.evaluate(on: []) == .scalar(0))
        #expect(Analysis.min.evaluate(on: []) == .scalar(0))
        #expect(Analysis.avg.evaluate(on: []) == .scalar(0))
        #expect(Analysis.rms.evaluate(on: []) == .scalar(0))
        #expect(Analysis.pkPk.evaluate(on: []) == .scalar(0))
    }

    @Test
    func `crossing measures complete waves from level crossings`() {
        // Square wave period 2: level crossings at 0.5, 1.5, 2.5, 3.5, 4.5
        // Wave 1: 0.5→2.5, wave 2: 2.5→4.5 (boundary crossing shared)
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1, value: 1),
            Point(time: 2, value: -1),
            Point(time: 3, value: 1),
            Point(time: 4, value: -1),
            Point(time: 5, value: 1),
        ]

        let zero = Analysis.frequencyAt(0).evaluate(on: points)
        guard case let .periodAndFrequency(period, frequency) = zero else {
            Issue.record("Expected period/frequency, got \(zero)")
            return
        }
        #expect(abs(period - 2) < 1e-12)
        #expect(abs(frequency - 0.5) < 1e-12)

        #expect(Analysis.frequencyAtZero.evaluate(on: points) == zero)

        // Three level crossings → exactly one complete wave
        let oneWave = Array(points.prefix(4)) // crossings at 0.5, 1.5, 2.5
        guard case let .periodAndFrequency(onePeriod, _) = Analysis.frequencyAt(0).evaluate(on: oneWave) else {
            Issue.record("Expected one complete wave from 3 crossings")
            return
        }
        #expect(abs(onePeriod - 2) < 1e-12)

        // Two crossings → incomplete wave only
        let short = Array(points.prefix(3)) // crossings at 0.5, 1.5
        #expect(Analysis.frequencyAt(0).evaluate(on: short) == .insufficientCrossings)
    }

    @Test
    func `crossing ignores partial waves at the ends`() {
        // Starts mid-high and ends mid-low: incomplete fragments outside complete cycles.
        // Level crossings at 1.5, 2.5, 3.5, 4.5, 5.5 → waves 1.5→3.5 and 3.5→5.5
        let points = [
            Point(time: 0, value: 1),
            Point(time: 1, value: 1),
            Point(time: 2, value: -1),
            Point(time: 3, value: 1),
            Point(time: 4, value: -1),
            Point(time: 5, value: 1),
            Point(time: 6, value: -1),
            Point(time: 7, value: -1),
        ]

        let crossings = levelCrossingTimes(points, threshold: 0)
        #expect(crossings.count == 5)

        guard case let .periodAndFrequency(period, frequency) = Analysis.frequencyAt(0).evaluate(on: points) else {
            Issue.record("Expected period/frequency from complete waves only")
            return
        }
        #expect(abs(period - 2) < 1e-12)
        #expect(abs(frequency - 0.5) < 1e-12)

        // Four crossings → one complete wave; trailing half-wave dropped
        let withTrailingHalf = Array(points.prefix(6)) // crossings 1.5, 2.5, 3.5, 4.5
        guard case let .periodAndFrequency(partialEndPeriod, _) =
            Analysis.frequencyAt(0).evaluate(on: withTrailingHalf) else {
            Issue.record("Expected one complete wave when a trailing half-wave remains")
            return
        }
        #expect(abs(partialEndPeriod - 2) < 1e-12)
    }

    @Test
    func `frequency uses min max midpoint as crossing threshold`() {
        // Midpoint is 1 while the sample average is skewed upward by the final high sample.
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1, value: 3),
            Point(time: 2, value: -1),
            Point(time: 3, value: 3),
            Point(time: 4, value: -1),
            Point(time: 5, value: 3),
            Point(time: 6, value: 3),
        ]

        let midpoint = midValue(points)
        #expect(abs(midpoint - 1) < 1e-12)
        #expect(abs(averageValue(points) - midpoint) > 0.1)

        let fromFrequency = Analysis.frequency.evaluate(on: points)
        let fromFrequencyAt = Analysis.frequencyAt(midpoint).evaluate(on: points)
        #expect(fromFrequency == fromFrequencyAt)

        guard case let .periodAndFrequency(period, frequency) = fromFrequency else {
            Issue.record("Expected period/frequency, got \(fromFrequency)")
            return
        }
        #expect(abs(period - 2) < 1e-12)
        #expect(abs(frequency - 0.5) < 1e-12)
    }

    @Test
    func `rising crossings remain available for extract period`() throws {
        let points = (0 ..< 20).map { index in
            Point(time: Double(index), value: sin(Double(index) * .pi / 4))
        }

        let rising = risingCrossingTimes(points, threshold: 0)
        let level = levelCrossingTimes(points, threshold: 0)
        #expect(rising.count >= 2)
        #expect(level.count >= rising.count)

        let extracted = try extractPeriodPoints(points, threshold: 0)
        #expect(extracted.first?.time == 0)
        #expect(!extracted.isEmpty)
    }

    // MARK: - Capture metadata

    @Test
    func `duration points start end sample rate and interval`() {
        let points = [
            Point(time: 1e-3, value: 0),
            Point(time: 2e-3, value: 1),
            Point(time: 3e-3, value: 0),
        ]

        #expect(Analysis.duration.evaluate(on: points) == .scalar(2e-3))
        #expect(Analysis.points.evaluate(on: points) == .scalar(3))
        #expect(Analysis.start.evaluate(on: points) == .scalar(1e-3))
        #expect(Analysis.end.evaluate(on: points) == .scalar(3e-3))
        #expect(Analysis.sampleRate.evaluate(on: points) == .scalar(1000))
        #expect(Analysis.interval.evaluate(on: points) == .scalar(1e-3))

        #expect(Analysis.sampleRate.evaluate(on: [Point(time: 0, value: 1)]) == .unavailable)
        #expect(Analysis.duration.evaluate(on: []) == .scalar(0))
        #expect(Analysis.points.evaluate(on: []) == .scalar(0))
    }

    @Test
    func `parses capture metadata analyses`() throws {
        #expect(
            try Analysis.parseList("Duration; Points; SampleRate; Interval; Start; End")
                == [.duration, .points, .sampleRate, .interval, .start, .end],
        )
    }

    // MARK: - Amplitude pack

    @Test
    func `peak amplitude mid acrms stddev crest median`() {
        let points = [
            Point(time: 0, value: -2),
            Point(time: 1, value: 4),
            Point(time: 2, value: 0),
        ]

        #expect(Analysis.peak.evaluate(on: points) == .scalar(4))
        #expect(Analysis.amplitude.evaluate(on: points) == .scalar(3)) // pkpk 6 / 2
        #expect(Analysis.mid.evaluate(on: points) == .scalar(1))
        #expect(Analysis.acRms.evaluate(on: points) == .scalar(acRmsValue(points)))
        #expect(Analysis.stdDev.evaluate(on: points) == Analysis.acRms.evaluate(on: points))
        #expect(Analysis.median.evaluate(on: points) == .scalar(0))

        guard case let .scalar(crest) = Analysis.crest.evaluate(on: points) else {
            Issue.record("Expected crest scalar")
            return
        }
        #expect(abs(crest - 4 / rmsValue(points)) < 1e-12)

        #expect(Analysis.crest.evaluate(on: [Point(time: 0, value: 0)]) == .unavailable)
    }

    @Test
    func `parses amplitude analyses`() throws {
        #expect(
            try Analysis.parseList("Peak; Amplitude; Mid; ACRms; StdDev; Stdev; Crest; Median")
                == [.peak, .amplitude, .mid, .acRms, .stdDev, .stdDev, .crest, .median],
        )
    }

    // MARK: - Top / Base / overshoot

    @Test
    func `top base overshoot undershoot on square-like levels`() {
        // Mostly at 0 and 1, with one overshoot spike to 1.2 and undershoot to -0.1
        var points: [Point] = []
        for i in 0 ..< 40 {
            points.append(Point(time: Double(i), value: i < 20 ? 0 : 1))
        }
        points[10] = Point(time: 10, value: -0.1)
        points[30] = Point(time: 30, value: 1.2)

        guard case let .scalar(base) = Analysis.base.evaluate(on: points),
              case let .scalar(top) = Analysis.top.evaluate(on: points) else {
            Issue.record("Expected top/base")
            return
        }
        #expect(base < 0.3)
        #expect(top > 0.7)

        guard case let .scalar(over) = Analysis.overshoot.evaluate(on: points),
              case let .scalar(under) = Analysis.undershoot.evaluate(on: points) else {
            Issue.record("Expected over/under")
            return
        }
        #expect(over > 0)
        #expect(under > 0)
    }

    // MARK: - Timing

    @Test
    func `rise and fall time on linear edges`() throws {
        // Rise 0→1 over 1s from t=1 to t=2; fall 1→0 over 2s from t=4 to t=6
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 0),
            Point(time: 2, value: 1),
            Point(time: 4, value: 1),
            Point(time: 6, value: 0),
        ]

        // 10%→90% of span 0…1 = 0.1→0.9. Rise: levels at t=1.1 and t=1.9 → 0.8s
        guard case let .scalar(rise) = Analysis.riseTime(lowPercent: 10, highPercent: 90).evaluate(on: points) else {
            Issue.record("Expected rise time")
            return
        }
        #expect(abs(rise - 0.8) < 1e-9)

        // Fall: 0.9 at t=4.2, 0.1 at t=5.8 → 1.6s
        guard case let .scalar(fall) = Analysis.fallTime(lowPercent: 10, highPercent: 90).evaluate(on: points) else {
            Issue.record("Expected fall time")
            return
        }
        #expect(abs(fall - 1.6) < 1e-9)

        #expect(try Analysis.parseList("RiseTime") == [.riseTime(lowPercent: 10, highPercent: 90)])
        #expect(try Analysis.parseList("FallTime 20, 80") == [.fallTime(lowPercent: 20, highPercent: 80)])
    }

    @Test
    func `rise and fall slew use positive average slope between percentage levels`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 0),
            Point(time: 2, value: 1),
            Point(time: 4, value: 1),
            Point(time: 6, value: 0),
        ]

        guard case let .scalar(rise) = Analysis.slewRise(lowPercent: 10, highPercent: 90).evaluate(on: points),
              case let .scalar(fall) = Analysis.slewFall(lowPercent: 10, highPercent: 90).evaluate(on: points) else {
            Issue.record("Expected slew rates")
            return
        }
        #expect(abs(rise - 1) < 1e-12)
        #expect(abs(fall - 0.5) < 1e-12)
        #expect(
            try Analysis.parseList("SlewRise; slewfall 20, 80") == [
                .slewRise(lowPercent: 10, highPercent: 90),
                .slewFall(lowPercent: 20, highPercent: 80),
            ],
        )
        #expect(Analysis.slewRise(lowPercent: 10, highPercent: 90).label == "SlewRise")
        #expect(Analysis.slewFall(lowPercent: 20, highPercent: 80).label == "SlewFall 20, 80")
        #expect(
            Analysis.slewRise(lowPercent: 10, highPercent: 90).evaluate(
                on: [Point(time: 0, value: 1)],
            ) == .unavailable,
        )
    }

    @Test
    func `pulse width duty edge count jitter`() throws {
        // 50% duty square, period 2: high 1.0s, low 1.0s
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1, value: 1),
            Point(time: 2, value: -1),
            Point(time: 3, value: 1),
            Point(time: 4, value: -1),
            Point(time: 5, value: 1),
            Point(time: 6, value: -1),
        ]

        guard case let .scalar(width) = Analysis.pulseWidth(threshold: 0).evaluate(on: points) else {
            Issue.record("Expected pulse width")
            return
        }
        #expect(abs(width - 1) < 1e-12)

        guard case let .scalar(duty) = Analysis.duty(threshold: 0).evaluate(on: points) else {
            Issue.record("Expected duty")
            return
        }
        #expect(abs(duty - 0.5) < 1e-12)

        #expect(Analysis.edgeCount(threshold: 0).evaluate(on: points) == .scalar(6))

        // Perfect periods → jitter 0 (need ≥2 complete waves)
        guard case let .scalar(jitter) = Analysis.jitter(threshold: 0).evaluate(on: points) else {
            Issue.record("Expected jitter")
            return
        }
        #expect(abs(jitter) < 1e-12)

        #expect(try Analysis.parseList("PulseWidth; Duty 0.5; EdgeCount; Jitter; PeriodStd")
            == [
                .pulseWidth(threshold: nil),
                .duty(threshold: 0.5),
                .edgeCount(threshold: nil),
                .jitter(threshold: nil),
                .jitter(threshold: nil),
            ])
    }

    @Test
    func `low pulse width averages complete falling to rising pulses`() throws {
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1, value: 1),
            Point(time: 2, value: 1),
            Point(time: 3, value: -1),
            Point(time: 4, value: -1),
            Point(time: 5, value: -1),
            Point(time: 6, value: 1),
            Point(time: 7, value: 1),
            Point(time: 8, value: -1),
            Point(time: 9, value: -1),
            Point(time: 10, value: -1),
            Point(time: 11, value: 1),
        ]

        #expect(Analysis.pulseWidth(threshold: 0).evaluate(on: points) == .scalar(2))
        #expect(Analysis.lowPulseWidth(threshold: 0).evaluate(on: points) == .scalar(3))
        #expect(
            try Analysis.parseList("LowPulseWidth; lowpulsewidth 0.5") == [
                .lowPulseWidth(threshold: nil),
                .lowPulseWidth(threshold: 0.5),
            ],
        )
        #expect(Analysis.lowPulseWidth(threshold: 0.5).label == "LowPulseWidth 500m")
    }

    // MARK: - Integrals / power / THD

    @Test
    func `integral energy and dbm`() throws {
        // v=1 constant from 0 to 2 → ∫v = 2, ∫v² = 2
        let points = [
            Point(time: 0, value: 1),
            Point(time: 1, value: 1),
            Point(time: 2, value: 1),
        ]
        #expect(Analysis.integral.evaluate(on: points) == .scalar(2))
        #expect(Analysis.energy(resistance: 1).evaluate(on: points) == .scalar(2))

        // 0.707 Vrms into 50 Ω ≈ 10 dBm? Vrms=1 → P = 1/50 = 0.02 W = 20 mW → 13.0 dBm
        guard case let .scalar(dbm) = Analysis.dbm(resistance: 50).evaluate(on: points) else {
            Issue.record("Expected dBm")
            return
        }
        #expect(abs(dbm - (10 * log10(0.02 / 0.001))) < 1e-9)

        #expect(try Analysis.parseList("Integral; Energy; dBm; dBm 75")
            == [.integral, .energy(resistance: 1), .dbm(resistance: 50), .dbm(resistance: 75)])
    }

    @Test
    func `thd is low for pure sine and higher with harmonics`() throws {
        let frequency = 50.0
        let sampleRate = 5000.0
        let count = 2048
        let pure = (0 ..< count).map { index -> Point in
            let time = Double(index) / sampleRate
            return Point(time: time, value: sin(2 * Double.pi * frequency * time))
        }
        let distorted = (0 ..< count).map { index -> Point in
            let time = Double(index) / sampleRate
            let fundamental = sin(2 * Double.pi * frequency * time)
            let third = 0.3 * sin(2 * Double.pi * 3 * frequency * time)
            return Point(time: time, value: fundamental + third)
        }

        let pureSpectrum = try #require(computeFFTSpectrum(points: pure, requestedPointCount: count))
        let distortedSpectrum = try #require(computeFFTSpectrum(points: distorted, requestedPointCount: count))
        guard case let .scalar(thdPure) = Analysis.thd.evaluate(on: pure, using: pureSpectrum),
              case let .scalar(thdDist) = Analysis.thd.evaluate(on: distorted, using: distortedSpectrum) else {
            Issue.record("Expected THD scalars")
            return
        }
        #expect(thdPure < 0.05)
        #expect(thdDist > thdPure)
        #expect(abs(thdDist - 0.3) < 0.08)

        #expect(try Analysis.parseList("FFT; THD") == [.fft(pointCount: nil, position: .start), .thd])
        #expect(throws: AnalysisParseError.invalidArgumentCount(operation: "THD", expected: 0, actual: 1)) {
            try Analysis.parseList("FFT; THD 1k")
        }
    }
}

private extension Analysis {
    /// Convenience for tests: FrequencyAtZero parses to `.frequencyAt(0)`.
    static var frequencyAtZero: Analysis {
        .frequencyAt(0)
    }
}
