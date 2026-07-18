@testable import rigol2spice
import Foundation
import Testing

struct AnalysisTests {
    @Test
    func `parses analyses with aliases`() throws {
        let analyses = try Analysis.parseList(
            "Max; Min; HiPeak; LowPeak; Avg; DC; Crossing 1.5; ZeroCrossing; Frequency; RMS; PkPk",
        )

        #expect(analyses == [
            .max,
            .min,
            .max,
            .min,
            .avg,
            .dc,
            .crossing(1.5),
            .crossing(0),
            .frequency,
            .rms,
            .pkPk,
        ])
    }

    @Test
    func `operation names are case insensitive`() throws {
        #expect(
            try Analysis.parseList("max; HIPEAK; zerocrossing; pkpk")
                == [.max, .max, .crossing(0), .pkPk],
        )
    }

    @Test
    func `crossing accepts engineering notation`() throws {
        let nano = try Analysis.parseList("Crossing 3n")
        guard case let .crossing(value) = nano.first else {
            Issue.record("Expected Crossing")
            return
        }
        #expect(abs(value - 3e-9) < 1e-20)
        #expect(try Analysis.parseList("Crossing -1.2") == [.crossing(-1.2)])
    }

    @Test
    func `rejects unknown operations and invalid arity`() {
        #expect(throws: (any Error).self) {
            try Analysis.parseList("Peak")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("Max 1")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("Crossing")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("Crossing 1, 2")
        }
        #expect(throws: (any Error).self) {
            try Analysis.parseList("ZeroCrossing 0")
        }
    }

    @Test
    func `rejects empty commands in the list`() {
        do {
            _ = try Analysis.parseList("Max;;Min")
            Issue.record("Expected empty command to fail")
        }
        catch let error as AnalysisParseError {
            #expect(error == .emptyCommand(index: 2))
        }
        catch {
            Issue.record("Unexpected error: \(error)")
        }
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

        let zero = Analysis.crossing(0).evaluate(on: points)
        guard case let .periodAndFrequency(period, frequency) = zero else {
            Issue.record("Expected period/frequency, got \(zero)")
            return
        }
        #expect(abs(period - 2) < 1e-12)
        #expect(abs(frequency - 0.5) < 1e-12)

        #expect(Analysis.zeroCrossingAlias.evaluate(on: points) == zero)

        // Three level crossings → exactly one complete wave
        let oneWave = Array(points.prefix(4)) // crossings at 0.5, 1.5, 2.5
        guard case let .periodAndFrequency(onePeriod, _) = Analysis.crossing(0).evaluate(on: oneWave)
        else {
            Issue.record("Expected one complete wave from 3 crossings")
            return
        }
        #expect(abs(onePeriod - 2) < 1e-12)

        // Two crossings → incomplete wave only
        let short = Array(points.prefix(3)) // crossings at 0.5, 1.5
        #expect(Analysis.crossing(0).evaluate(on: short) == .insufficientCrossings)
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

        guard case let .periodAndFrequency(period, frequency) = Analysis.crossing(0).evaluate(on: points)
        else {
            Issue.record("Expected period/frequency from complete waves only")
            return
        }
        #expect(abs(period - 2) < 1e-12)
        #expect(abs(frequency - 0.5) < 1e-12)

        // Four crossings → one complete wave; trailing half-wave dropped
        let withTrailingHalf = Array(points.prefix(6)) // crossings 1.5, 2.5, 3.5, 4.5
        guard case let .periodAndFrequency(partialEndPeriod, _) =
            Analysis.crossing(0).evaluate(on: withTrailingHalf)
        else {
            Issue.record("Expected one complete wave when a trailing half-wave remains")
            return
        }
        #expect(abs(partialEndPeriod - 2) < 1e-12)
    }

    @Test
    func `frequency uses average value as crossing threshold`() {
        // Values alternate around mean 1: -1 and 3, mean = 1
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1, value: 3),
            Point(time: 2, value: -1),
            Point(time: 3, value: 3),
            Point(time: 4, value: -1),
            Point(time: 5, value: 3),
        ]

        let mean = averageValue(points)
        #expect(abs(mean - 1) < 1e-12)

        let fromFrequency = Analysis.frequency.evaluate(on: points)
        let fromCrossing = Analysis.crossing(mean).evaluate(on: points)
        #expect(fromFrequency == fromCrossing)

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
}

private extension Analysis {
    /// Convenience for tests: ZeroCrossing parses to `.crossing(0)`.
    static var zeroCrossingAlias: Analysis { .crossing(0) }
}
