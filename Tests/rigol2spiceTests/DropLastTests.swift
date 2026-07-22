@testable import rigol2spice
import Testing

struct DropLastTests {
    @Test
    func `drop last parses a positive duration`() throws {
        #expect(try Transformation.parseList("DropLast 5m") == [.dropLast(5e-3)])
        #expect(throws: (any Error).self) { try Transformation.parseList("DropLast") }
        #expect(throws: (any Error).self) { try Transformation.parseList("DropLast 0") }
        #expect(throws: (any Error).self) { try Transformation.parseList("DropLast -1m") }
    }

    @Test
    func `drop last points parses a positive integer`() throws {
        #expect(try Transformation.parseList("DropLastPoints 5") == [.dropLastPoints(5)])
        #expect(try Transformation.parseList("droplastpoints 2e0") == [.dropLastPoints(2)])
        #expect(throws: (any Error).self) { try Transformation.parseList("DropLastPoints") }
        #expect(throws: (any Error).self) { try Transformation.parseList("DropLastPoints 0") }
        #expect(throws: (any Error).self) { try Transformation.parseList("DropLastPoints 2.5") }
    }

    @Test
    func `drop last removes a duration measured back from the final timestamp`() throws {
        let points = [0.0, 0.5, 2, 3, 5].map { Point(time: $0, value: $0 * 10) }
        let result = try Transformation.dropLast(2).applying(to: points)

        #expect(result.map(\.time) == [0, 0.5, 2, 3])
        #expect(result.map(\.value) == [0, 5, 20, 30])
    }

    @Test
    func `drop last points removes an exact number from the end`() throws {
        let points = (0 ... 4).map { Point(time: Double($0), value: Double($0)) }
        let result = try Transformation.dropLastPoints(2).applying(to: points)

        #expect(result.map(\.time) == [0, 1, 2])
        #expect(droppingLastPoints(points, count: 5).isEmpty)
        #expect(droppingLastPoints(points, count: 10).isEmpty)
    }
}
