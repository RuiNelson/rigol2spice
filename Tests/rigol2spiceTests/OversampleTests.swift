@testable import rigol2spice
import Foundation
import Testing

struct OversampleTests {
    @Test
    func `oversample parses an integer factor greater than one`() throws {
        #expect(try Transformation.parseList("Oversample 5") == [.oversample(5)])
        #expect(try Transformation.parseList("oversample 2e0") == [.oversample(2)])
        #expect(throws: (any Error).self) { try Transformation.parseList("Oversample") }
        #expect(throws: (any Error).self) { try Transformation.parseList("Oversample 1") }
        #expect(throws: (any Error).self) { try Transformation.parseList("Oversample 2.5") }
    }

    @Test
    func `oversample averages aligned points from equal segments`() throws {
        let values = [
            1.0, 2, 3, 4, 5,
            3.0, 4, 5, 6, 7,
        ]
        let points = values.enumerated().map { index, value in
            Point(time: 10 + Double(index) * 0.5, value: value)
        }
        let result = try Transformation.oversample(2).applying(
            to: points,
            sampleInterval: 0.5,
        )

        #expect(result.map(\.time) == [0, 0.5, 1, 1.5, 2])
        #expect(result.map(\.value) == [2, 3, 4, 5, 6])
    }

    @Test
    func `oversample reports points and time to remove or add`() throws {
        let points = (0 ..< 12).map { Point(time: Double($0) * 2e-6, value: Double($0)) }

        do {
            _ = try oversamplePoints(points, factor: 5, sampleInterval: 2e-6)
            Issue.record("Expected a non-divisible capture to fail")
        }
        catch let error as OversampleError {
            #expect(error == .pointCountNotDivisible(
                factor: 5,
                pointCount: 12,
                removePoints: 2,
                addPoints: 3,
                sampleInterval: 2e-6,
            ))
            #expect(error.localizedDescription.contains("Remove 2 sample(s) (4us)"))
            #expect(error.localizedDescription.contains("add 3 sample(s) (6us)"))
        }
    }

    @Test
    func `oversample rejects factors larger than the capture`() {
        let short = (0 ..< 4).map { Point(time: Double($0), value: Double($0)) }
        #expect(throws: OversampleError.factorExceedsPointCount(factor: 5, pointCount: 4)) {
            try oversamplePoints(short, factor: 5)
        }
    }

    @Test
    func `oversample aligns by sample position without requiring a uniform time grid`() throws {
        var irregular = (0 ..< 10).map { Point(time: Double($0), value: Double($0)) }
        irregular[6].time += 0.1
        let result = try oversamplePoints(irregular, factor: 2)

        #expect(result.count == 5)
        #expect(result.map(\.value) == [2.5, 3.5, 4.5, 5.5, 6.5])
    }

    @Test
    func `oversample accepts floating point noise on a uniform timestamp grid`() throws {
        let origin = 1e9
        let nominalInterval = 1e-6
        let points = (0 ..< 10).map { index in
            Point(
                time: origin + Double(index) * nominalInterval,
                value: Double(index),
            )
        }
        let result = try oversamplePoints(
            points,
            factor: 2,
            sampleInterval: nominalInterval,
        )

        #expect(result.count == 5)
        #expect(result[0].time == 0)
        #expect(abs((result[1].time - result[0].time) - nominalInterval) < 1e-7)
        #expect(result.map(\.value) == [2.5, 3.5, 4.5, 5.5, 6.5])
    }
}
