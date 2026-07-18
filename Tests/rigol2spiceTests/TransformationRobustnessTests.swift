@testable import rigol2spice
import Foundation
import Testing

struct TransformationRobustnessTests {
    @Test
    func `remove dc ignores non finite samples`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: .nan),
            Point(time: 2, value: 10),
            Point(time: 3, value: .infinity),
            Point(time: 4, value: 0),
            Point(time: 5, value: 10),
        ]

        let estimate = estimateDC(points)
        #expect(estimate.value.isFinite)
        #expect(abs(estimate.value - 5) < 1e-12)

        let corrected = try Transformation.removeDC(.dc).applying(to: points)
        #expect(abs(corrected[0].value + 5) < 1e-12)
        #expect(abs(corrected[2].value - 5) < 1e-12)
    }

    @Test
    func `schmitt thresholds work in either argument order`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 0.7),
            Point(time: 2, value: 1.2),
            Point(time: 3, value: 0.8),
            Point(time: 4, value: 0.3),
        ]

        let ascending = try Transformation.digitize(
            lowThreshold: 0.4,
            highThreshold: 1,
            lowOut: -1,
            highOut: 3,
        ).applying(to: points)
        let descending = try Transformation.digitize(
            lowThreshold: 1,
            highThreshold: 0.4,
            lowOut: -1,
            highOut: 3,
        ).applying(to: points)

        #expect(ascending.map(\.value) == [-1, -1, 3, 3, -1])
        #expect(descending == ascending)
    }

    @Test
    func `fade out leaves the beginning unchanged and reaches zero`() throws {
        let points = (0 ... 4).map { Point(time: Double($0), value: 10) }
        let result = try Transformation.fade(inDuration: 0, outDuration: 2).applying(to: points)

        #expect(result.map(\.value) == [10, 10, 10, 5, 0])
        #expect(result.map(\.time) == points.map(\.time))
    }

    @Test
    func `calculus uses irregular timestamps`() throws {
        // v = 3t + 1, sampled at deliberately irregular intervals.
        let linear = [0.0, 0.25, 1.5, 4].map { time in
            Point(time: time, value: 3 * time + 1)
        }
        let derivative = try Transformation.diff.applying(to: linear)
        #expect(derivative.allSatisfy { abs($0.value - 3) < 1e-12 })

        // Trapezoids: [0,1] contributes 1; [1,3] contributes 4.
        let integralInput = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 2),
            Point(time: 3, value: 2),
        ]
        let integrated = try Transformation.integrate.applying(to: integralInput)
        #expect(integrated.map(\.value) == [0, 1, 5])
    }

    @Test
    func `slew limit accounts for each elapsed interval`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 0.25, value: 10),
            Point(time: 1.25, value: 10),
            Point(time: 1.75, value: -10),
        ]
        let result = try Transformation.slewLimit(2).applying(to: points)

        #expect(result.map(\.value) == [0, 0.5, 2.5, 1.5])
    }
}
