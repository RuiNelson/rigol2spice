@testable import rigol2spice
import Foundation
import Testing

struct AnalysisRobustnessTests {
    @Test
    func `overshoot and undershoot follow the documented formulas`() {
        var points = (0 ..< 100).map { index in
            Point(time: Double(index), value: index < 50 ? 0 : 1)
        }
        points[10].value = -0.2
        points[80].value = 1.3

        guard case let .scalar(base) = Analysis.base.evaluate(on: points),
              case let .scalar(top) = Analysis.top.evaluate(on: points),
              case let .scalar(overshoot) = Analysis.overshoot.evaluate(on: points),
              case let .scalar(undershoot) = Analysis.undershoot.evaluate(on: points) else {
            Issue.record("Expected scalar analysis results")
            return
        }

        let expectedOvershoot = (1.3 - top) / (top - base)
        let expectedUndershoot = (base + 0.2) / (top - base)
        #expect(abs(overshoot - expectedOvershoot) < 1e-12)
        #expect(abs(undershoot - expectedUndershoot) < 1e-12)
    }

    @Test
    func `jitter measures nonzero population standard deviation`() {
        // Interpolated crossing times: 0.5, 1.5, 2.6, 3.7, 4.9, 6.1.
        // Complete periods are therefore 2.1 and 2.3 seconds.
        let times = [0.0, 1, 2, 3.2, 4.2, 5.6, 6.6]
        let points = times.enumerated().map { index, time in
            Point(time: time, value: index.isMultiple(of: 2) ? -1 : 1)
        }

        guard case let .scalar(jitter) = Analysis.jitter(threshold: 0).evaluate(on: points) else {
            Issue.record("Expected scalar jitter")
            return
        }
        #expect(abs(jitter - 0.1) < 1e-12)
    }

    @Test
    func `integral and energy honor irregular sample intervals`() {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 2),
            Point(time: 3, value: 2),
        ]

        #expect(Analysis.integral.evaluate(on: points) == .scalar(5))
        #expect(Analysis.energy.evaluate(on: points) == .scalar(10))
    }

    @Test
    func `dbm calculation evaluates non default resistance`() {
        let points = [Point(time: 0, value: 1), Point(time: 1, value: 1)]
        guard case let .scalar(measured) = Analysis.dbm(resistance: 75).evaluate(on: points) else {
            Issue.record("Expected scalar dBm result")
            return
        }
        let expected = 10 * log10((1.0 / 75.0) / 0.001)

        #expect(abs(measured - expected) < 1e-12)
    }

    @Test
    func `fft requested window is taken from the center`() throws {
        let points = (0 ..< 20).map { index in
            Point(time: Double(index) * 1e-3, value: Double(index * index - 3 * index))
        }
        let centeredPoints = Array(points[6 ..< 14])

        let limited = try #require(computeFFTSpectrum(points: points, requestedPointCount: 8))
        let explicitCenter = try #require(computeFFTSpectrum(points: centeredPoints, requestedPointCount: 8))

        #expect(abs(limited.centerFrequency - explicitCenter.centerFrequency) < 1e-12)
        #expect(abs(limited.centerMagnitude - explicitCenter.centerMagnitude) < 1e-12)
        #expect(limited.usedPointCount == explicitCenter.usedPointCount)
    }

    @Test
    func `thd combines multiple documented harmonics in quadrature`() {
        let fundamental = 64.0
        let sampleRate = 8192.0
        let count = 4096
        let points = (0 ..< count).map { index -> Point in
            let time = Double(index) / sampleRate
            let value = sin(2 * .pi * fundamental * time)
                + 0.1 * sin(2 * .pi * 2 * fundamental * time)
                + 0.2 * sin(2 * .pi * 3 * fundamental * time)
                + 0.05 * sin(2 * .pi * 10 * fundamental * time)
            return Point(time: time, value: value)
        }

        guard case let .scalar(measured) = Analysis.thd(pointCount: count).evaluate(on: points) else {
            Issue.record("Expected scalar THD result")
            return
        }
        let expected = sqrt(0.1 * 0.1 + 0.2 * 0.2 + 0.05 * 0.05)
        #expect(abs(measured - expected) < 0.03)
    }
}
