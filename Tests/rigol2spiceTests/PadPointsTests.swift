@testable import rigol2spice
import Testing

struct PadPointsTests {
    @Test
    func `pad points and hold last points parse as the same transformation`() throws {
        let expected = [Transformation.padPoints(count: 3, value: nil)]
        #expect(try Transformation.parseList("PadPoints 3") == expected)
        #expect(try Transformation.parseList("HoldLastPoints 3") == expected)
        #expect(
            try Transformation.parseList("PadPoints 2, 0")
                == [.padPoints(count: 2, value: 0)],
        )
        #expect(throws: (any Error).self) { try Transformation.parseList("PadPoints 0") }
        #expect(throws: (any Error).self) { try Transformation.parseList("PadPoints 2.5") }
    }

    @Test
    func `pad points appends an exact count on the sampling grid`() throws {
        let points = [
            Point(time: 0, value: 1),
            Point(time: 0.25, value: 2),
            Point(time: 0.5, value: 3),
        ]
        let result = try Transformation.padPoints(count: 3, value: nil).applying(to: points)

        #expect(result.count == 6)
        #expect(result.map(\.time) == [0, 0.25, 0.5, 0.75, 1, 1.25])
        #expect(result.map(\.value) == [1, 2, 3, 3, 3, 3])
    }

    @Test
    func `pad points accepts a specified level and sample interval`() throws {
        let points = [Point(time: 2, value: 4)]
        let result = try Transformation.padPoints(count: 2, value: -1)
            .applying(to: points, sampleInterval: 0.5)

        #expect(result == [
            Point(time: 2, value: 4),
            Point(time: 2.5, value: -1),
            Point(time: 3, value: -1),
        ])
    }
}
