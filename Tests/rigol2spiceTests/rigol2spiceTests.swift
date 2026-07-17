@testable import rigol2spice
import Testing

struct Rigol2spiceTests {
    @Test
    func `parses operations in description order`() throws {
        let transformations = try Transformation.parseList(
            "RemoveDC; ClampMax 0.7; ClampMin 3n; Offset -1.2",
        )

        try #require(transformations.count == 4)
        #expect(transformations[0] == .removeDC)
        #expect(transformations[1] == .clampMax(0.7))
        guard case let .clampMin(clampMinimum) = transformations[2] else {
            Issue.record("Expected ClampMin as the third transformation")
            return
        }
        #expect(abs(clampMinimum - 3e-9) < 1e-20)
        #expect(transformations[3] == .offset(-1.2))
    }

    @Test
    func `operation names are case insensitive`() throws {
        #expect(
            try Transformation.parseList("removedc; TIMESHiFT -5e-3; cutafter 7.5m")
                == [.removeDC, .timeShift(-5e-3), .cutAfter(7.5e-3)],
        )
    }

    @Test
    func `repeat accepts integer and fractional scalars`() throws {
        #expect(try Transformation.parseList("Repeat 3e0") == [.repeat(3)])
        #expect(try Transformation.parseList("Repeat 2k") == [.repeat(2000)])
        #expect(try Transformation.parseList("Repeat 2.5") == [.repeat(2.5)])
    }

    @Test
    func `repeat rejects non positive values`() {
        do {
            _ = try Transformation.parseList("Repeat 0")
            Issue.record("Expected Repeat 0 to fail")
        }
        catch let error as TransformationParseError {
            #expect(error == .invalidPositiveScalar(operation: "Repeat", value: "0"))
        }
        catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(throws: (any Error).self) {
            try Transformation.parseList("Repeat -0.5")
        }
    }

    @Test
    func `rejects legacy negative prefix`() {
        do {
            _ = try Transformation.parseList("Offset N1.2")
            Issue.record("Expected the legacy negative prefix to fail")
        }
        catch let error as TransformationParseError {
            #expect(error == .invalidScalar(operation: "Offset", value: "N1.2"))
        }
        catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func `rejects unknown operations and invalid arity`() {
        #expect(throws: (any Error).self) {
            try Transformation.parseList("Shift 1m")
        }
        #expect(throws: (any Error).self) {
            try Transformation.parseList("RemoveDC 1")
        }
        #expect(throws: (any Error).self) {
            try Transformation.parseList("ClampMin 1, 2")
        }
    }

    @Test
    func `transformations apply in description order`() throws {
        let points = [Point(time: 0, value: 1), Point(time: 1, value: 2)]

        let offsetThenMultiply = try Transformation.parseList("Offset 1; Multiply 2")
            .reduce(points) { try $1.applying(to: $0) }
        let multiplyThenOffset = try Transformation.parseList("Multiply 2; Offset 1")
            .reduce(points) { try $1.applying(to: $0) }

        #expect(offsetThenMultiply.map(\.value) == [4, 6])
        #expect(multiplyThenOffset.map(\.value) == [3, 5])
    }

    @Test
    func `clamp limits values on the correct side`() throws {
        let points = [Point(time: 0, value: -1), Point(time: 1, value: 2)]

        let clampedMinimum = try Transformation.clampMin(0).applying(to: points)
        let clampedMaximum = try Transformation.clampMax(1).applying(to: points)

        #expect(clampedMinimum.map(\.value) == [0, 2])
        #expect(clampedMaximum.map(\.value) == [-1, 1])
    }

    @Test
    func `fractional repeat appends full and partial copies`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 10),
            Point(time: 2, value: 20),
            Point(time: 3, value: 30),
        ]

        let repeated = try Transformation.repeat(2.5).applying(to: points)

        #expect(repeated.map(\.time) == Array(0 ... 14).map(Double.init))
        #expect(repeated.map(\.value) == [0, 10, 20, 30, 0, 10, 20, 30, 0, 10, 20, 30, 0, 10, 20])
    }

    @Test
    func `fractional repeat interpolates its final point`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 10),
            Point(time: 2, value: 20),
            Point(time: 3, value: 30),
        ]

        let repeated = try Transformation.repeat(0.375).applying(to: points)

        #expect(repeated.last?.time == 5.5)
        #expect(repeated.last?.value == 15)
    }

    @Test
    func `remove redundant preserves plateau endpoints`() {
        let points = [
            Point(time: 0, value: 1),
            Point(time: 1, value: 1),
            Point(time: 2, value: 1),
            Point(time: 3, value: 2),
            Point(time: 4, value: 2),
            Point(time: 5, value: 2),
        ]

        let compacted = removeRedundant(points)

        #expect(compacted.map(\.time) == [0, 2, 3, 5])
        #expect(compacted.map(\.value) == [1, 1, 2, 2])
    }

    @Test
    func `downsample keeps every nth point starting at zero`() {
        let points = (0 ..< 7).map { Point(time: Double($0), value: Double($0)) }

        #expect(downsamplePoints(points, interval: 3).map(\.time) == [0, 3, 6])
    }

    @Test
    func `time shift filters negative timestamps`() {
        let points = (0 ... 3).map { Point(time: Double($0), value: Double($0)) }

        #expect(timeShiftPoints(points, value: -1.5).map(\.time) == [0.5, 1.5])
        #expect(timeShiftPoints(points, value: 2).map(\.time) == [2, 3, 4, 5])
    }

    @Test
    func `cut after excludes the boundary`() {
        let points = (0 ... 4).map { Point(time: Double($0), value: Double($0)) }

        #expect(cutPointsAfter(points, after: 2).map(\.time) == [0, 1])
    }

    @Test
    func `vertical transforms preserve times and transform values`() {
        let points = [Point(time: 0, value: -1), Point(time: 1, value: 2), Point(time: 2, value: 5)]

        #expect(multiplyValueOfPoints(points, factor: 2).map(\.value) == [-2, 4, 10])
        #expect(offsetPoints(points, offset: 0.5).map(\.value) == [-0.5, 2.5, 5.5])
        #expect(calculateDC(points) == 2)
        #expect(clamp(points, lowerLimit: 0, upperLimit: 3).map(\.value) == [0, 2, 3])
        #expect(offsetPoints(points, offset: 1).map(\.time) == [0, 1, 2])
    }
}
