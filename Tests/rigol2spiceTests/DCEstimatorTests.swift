@testable import rigol2spice
import Foundation
import Testing

// MARK: - DCEstimatorTests

struct DCEstimatorTests {
    @Test
    func `uses the outer centroids of three clusters`() {
        let values = Array(repeating: 0.0, count: 80) + Array(repeating: 10.0, count: 20)
        let points = values.enumerated().map { index, value in
            Point(time: Double(index), value: value)
        }

        let estimate = estimateDC(points)

        #expect(estimate.centroids == [0, 0, 10])
        #expect(estimate.value == 5)
    }

    @Test
    func `uses the constant value without iterating`() {
        let points = (0 ..< 10).map { Point(time: Double($0), value: 3) }

        let estimate = estimateDC(points)

        #expect(estimate.value == 3)
        #expect(estimate.centroids == [3, 3, 3])
        #expect(estimate.iterations == 0)
    }

    @Test
    func `returns zero for an empty capture`() {
        let estimate = estimateDC([])

        #expect(estimate.value == 0)
        #expect(estimate.centroids == [0, 0, 0])
        #expect(estimate.iterations == 0)
    }

    @Test
    func `estimates a sine wave DC from complete periods`() throws {
        let expectedDC = 1.25
        let points = sineCapture(
            dc: expectedDC,
            amplitude: 3,
            frequency: 50,
            sampleRate: 20000,
            phase: 0.43,
            periods: 5,
        )

        let estimate = estimateDC(points)
        let correctedPoints = try Transformation.removeDC(.dc).applying(to: points)
        let estimateRelativeError = relativeError(estimate.value, comparedTo: expectedDC)
        let correctedRelativeError = abs(estimateDC(correctedPoints).value / expectedDC)

        #expect(estimateRelativeError < 0.001)
        #expect(correctedRelativeError < 1e-12)
    }

    @Test
    func `remove dc avg subtracts the sample average`() throws {
        let points = [
            Point(time: 0, value: 1),
            Point(time: 1, value: 2),
            Point(time: 2, value: 3),
            Point(time: 3, value: 6),
        ]
        // Mean = 3
        let estimate = estimateDC(points, method: .avg)
        #expect(estimate.value == 3)
        #expect(estimate.method == .avg)

        let corrected = try Transformation.removeDC(.avg).applying(to: points)
        #expect(corrected.map(\.value) == [-2, -1, 0, 3])
        #expect(abs(averageValue(corrected)) < 1e-12)
    }

    @Test
    func `remove dc median and mid match analysis helpers`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 1),
            Point(time: 2, value: 10),
            Point(time: 3, value: 100),
        ]

        let medianEstimate = estimateDC(points, method: .median)
        #expect(medianEstimate.value == medianValue(points))
        #expect(medianEstimate.value == 5.5)

        let midEstimate = estimateDC(points, method: .mid)
        #expect(midEstimate.value == midValue(points))
        #expect(midEstimate.value == 50)

        let afterMedian = try Transformation.removeDC(.median).applying(to: points)
        #expect(afterMedian.map(\.value) == [-5.5, -4.5, 4.5, 94.5])

        let afterMid = try Transformation.removeDC(.mid).applying(to: points)
        #expect(afterMid.map(\.value) == [-50, -49, -40, 50])
    }

    @Test
    func `estimates a sine wave DC from incomplete periods`() {
        let expectedDC = 1.25
        let amplitude = 3.0
        let points = sineCapture(
            dc: expectedDC,
            amplitude: amplitude,
            frequency: 50,
            sampleRate: 20000,
            phase: 0.5,
            periods: 5.3,
        )

        let estimate = estimateDC(points)
        let sampleAverage = points.map(\.value).reduce(0, +) / Double(points.count)
        let estimateRelativeError = relativeError(estimate.value, comparedTo: expectedDC)
        let sampleAverageRelativeError = relativeError(sampleAverage, comparedTo: expectedDC)

        #expect(estimateRelativeError < 0.05)
        #expect(estimateRelativeError < sampleAverageRelativeError)
    }

    @Test
    func `estimates a noisy sine wave DC from complete periods`() {
        let expectedDC = 1.25
        let points = sineCapture(
            dc: expectedDC,
            amplitude: 3,
            frequency: 50,
            sampleRate: 20000,
            phase: 0.43,
            periods: 5,
            noiseAmplitude: 3 * 0.1,
        )

        let estimate = estimateDC(points)

        let estimateRelativeError = relativeError(estimate.value, comparedTo: expectedDC)

        #expect(estimateRelativeError < 0.05)
    }

    @Test
    func `estimates a noisy sine wave DC from incomplete periods`() {
        let expectedDC = 1.25
        let points = sineCapture(
            dc: expectedDC,
            amplitude: 3,
            frequency: 50,
            sampleRate: 20000,
            phase: 0.43,
            periods: 5.37,
            noiseAmplitude: 3 * 0.1,
        )

        let estimate = estimateDC(points)

        let estimateRelativeError = relativeError(estimate.value, comparedTo: expectedDC)

        #expect(estimateRelativeError < 0.05)
    }

    @Test
    func `estimates a noisy sine wave DC from incomplete periods - no DC`() {
        let expectedDC = 0.0
        let amplitude = 3.0
        let points = sineCapture(
            dc: expectedDC,
            amplitude: amplitude,
            frequency: 50,
            sampleRate: 20000,
            phase: 0.43,
            periods: 5.37,
            noiseAmplitude: amplitude * 0.1,
        )

        let estimate = estimateDC(points)
        let amplitudeRelativeError = abs(estimate.value - expectedDC) / amplitude

        #expect(amplitudeRelativeError < 0.05)
    }

    private func relativeError(_ actual: Double, comparedTo expected: Double) -> Double {
        abs((actual - expected) / expected)
    }

    private func sineCapture(
        dc: Double,
        amplitude: Double,
        frequency: Double,
        sampleRate: Double,
        phase: Double,
        periods: Double,
        noiseAmplitude: Double = 0,
    ) -> [Point] {
        let sampleCount = Int((periods / frequency * sampleRate).rounded(.down))
        return (0 ... sampleCount).map { index in
            let time = Double(index) / sampleRate
            // Deterministic, approximately uniform sequence in [-noiseAmplitude, noiseAmplitude].
            // Keeping synthetic noise reproducible prevents statistical test flakiness.
            let hash = sin(Double(index) * 12.9898 + 78.233) * 43758.5453
            let unitNoise = hash - floor(hash)
            let noise = noiseAmplitude.isZero ? .zero : noiseAmplitude * (2 * unitNoise - 1)
            return Point(
                time: time,
                value: dc + amplitude * sin(2 * .pi * frequency * time + phase) + noise,
            )
        }
    }
}
