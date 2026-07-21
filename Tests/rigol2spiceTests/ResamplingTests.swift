@testable import rigol2spice
import Foundation
import Testing

struct ResamplingTests {
    @Test
    func `parses directional resampling with linear defaults`() throws {
        #expect(try Transformation.parseList("Downsample 2") == [
            .downsample(factor: 2, interpolation: .linear),
        ])
        #expect(try Transformation.parseList("Downsample 2, sinc") == [
            .downsample(factor: 2, interpolation: .sinc),
        ])
        #expect(try Transformation.parseList("Upsample 4") == [
            .upsample(factor: 4, interpolation: .linear),
        ])
        #expect(try Transformation.parseList("Upsample 4, PCHIP") == [
            .upsample(factor: 4, interpolation: .pchip),
        ])
        #expect(try Transformation.parseList("Upsample 4, sinc") == [
            .upsample(factor: 4, interpolation: .sinc),
        ])
    }

    @Test
    func `rejects old resample invalid factors and unsupported methods`() {
        #expect(throws: TransformationParseError.unknownOperation(name: "Resample")) {
            try Transformation.parseList("Resample 1n")
        }
        #expect(throws: TransformationParseError.invalidResamplingFactor(
            operation: "Downsample",
            value: "1",
        )) {
            try Transformation.parseList("Downsample 1")
        }
        #expect(throws: TransformationParseError.invalidInterpolation(
            operation: "Downsample",
            value: "pchip",
            allowed: "linear, sinc",
        )) {
            try Transformation.parseList("Downsample 2, pchip")
        }
        #expect(throws: TransformationParseError.invalidInterpolation(
            operation: "Upsample",
            value: "cubic",
            allowed: "linear, pchip, sinc",
        )) {
            try Transformation.parseList("Upsample 2, cubic")
        }
    }

    @Test
    func `downsample factor halves point count and preserves time endpoints`() throws {
        let points = linearPoints(count: 10)
        let result = try Transformation.downsample(factor: 2, interpolation: .linear)
            .applying(to: points)

        #expect(result.count == 5)
        #expect(result.first == points.first)
        #expect(result.last == points.last)
        #expect(result.map(\.value) == result.map(\.time).map { 2 * $0 })
    }

    @Test
    func `upsample factor quadruples point count and preserves time endpoints`() throws {
        let points = linearPoints(count: 6)
        let result = try Transformation.upsample(factor: 4, interpolation: .linear)
            .applying(to: points)

        #expect(result.count == 24)
        #expect(result.first == points.first)
        #expect(result.last == points.last)
        #expect(result.map(\.value) == result.map(\.time).map { 2 * $0 })
    }

    @Test
    func `fractional factors round final point count to nearest integer`() throws {
        let points = linearPoints(count: 10)
        let downsampled = try Transformation.downsample(factor: 1.5, interpolation: .linear)
            .applying(to: points)
        let upsampled = try Transformation.upsample(factor: 1.5, interpolation: .linear)
            .applying(to: points)

        #expect(downsampled.count == 7)
        #expect(upsampled.count == 15)
    }

    @Test
    func `PCHIP upsampling is smooth and does not overshoot monotonic data`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 0.2),
            Point(time: 2, value: 1),
            Point(time: 3, value: 1.1),
        ]
        let result = try Transformation.upsample(factor: 4, interpolation: .pchip)
            .applying(to: points)

        #expect(result.count == 16)
        #expect(result.allSatisfy { $0.value >= 0 && $0.value <= 1.1 })
        #expect(zip(result, result.dropFirst()).allSatisfy { $0.value <= $1.value })
    }

    @Test
    func `windowed sinc upsampling reconstructs a sine more accurately than linear`() throws {
        let count = 33
        let points = (0 ..< count).map { index in
            let time = Double(index) / Double(count - 1)
            return Point(time: time, value: sin(4 * Double.pi * time))
        }
        let linear = try Transformation.upsample(factor: 4, interpolation: .linear)
            .applying(to: points)
        let sinc = try Transformation.upsample(factor: 4, interpolation: .sinc)
            .applying(to: points)

        #expect(sinc.count == count * 4)
        #expect(rmse(sinc) < rmse(linear))
    }

    private func linearPoints(count: Int) -> [Point] {
        (0 ..< count).map { Point(time: Double($0), value: 2 * Double($0)) }
    }

    private func rmse(_ points: [Point]) -> Double {
        // Exclude the finite sinc kernel's capture-boundary transient.
        let margin = 32
        let slice = points.dropFirst(margin).dropLast(margin)
        let sumSquares = slice.reduce(0.0) {
            let error = $1.value - sin(4 * Double.pi * $1.time)
            return $0 + error * error
        }
        return sqrt(sumSquares / Double(slice.count))
    }
}
