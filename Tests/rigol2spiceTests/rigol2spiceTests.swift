@testable import rigol2spice
import XCTest

final class rigol2spiceTests: XCTestCase {
    func testParsesOperationsInDescriptionOrder() throws {
        let transformations = try Transformation.parseList(
            "RemoveDC; ClampMax 0.7; ClampMin 3n; Offset -1.2"
        )

        XCTAssertEqual(transformations.count, 4)
        XCTAssertEqual(transformations[0], .removeDC)
        XCTAssertEqual(transformations[1], .clampMax(0.7))
        guard case let .clampMin(clampMinimum) = transformations[2] else {
            return XCTFail("Expected ClampMin as the third transformation")
        }
        XCTAssertEqual(clampMinimum, 3e-9, accuracy: 1e-20)
        XCTAssertEqual(transformations[3], .offset(-1.2))
    }

    func testOperationNamesAreCaseInsensitive() throws {
        XCTAssertEqual(
            try Transformation.parseList("removedc; TIMESHiFT -5e-3; cutafter 7.5m"),
            [.removeDC, .timeShift(-5e-3), .cutAfter(7.5e-3)]
        )
    }

    func testRepeatAcceptsIntegerAndFractionalScalars() throws {
        XCTAssertEqual(try Transformation.parseList("Repeat 3e0"), [.repeat(3)])
        XCTAssertEqual(try Transformation.parseList("Repeat 2k"), [.repeat(2000)])
        XCTAssertEqual(try Transformation.parseList("Repeat 2.5"), [.repeat(2.5)])
    }

    func testRepeatRejectsNonPositiveValues() {
        XCTAssertThrowsError(try Transformation.parseList("Repeat 0")) { error in
            XCTAssertEqual(
                error as? TransformationParseError,
                .invalidPositiveScalar(operation: "Repeat", value: "0")
            )
        }
        XCTAssertThrowsError(try Transformation.parseList("Repeat -0.5"))
    }

    func testRejectsLegacyNegativePrefix() {
        XCTAssertThrowsError(try Transformation.parseList("Offset N1.2")) { error in
            XCTAssertEqual(
                error as? TransformationParseError,
                .invalidScalar(operation: "Offset", value: "N1.2")
            )
        }
    }

    func testRejectsUnknownOperationsAndInvalidArity() {
        XCTAssertThrowsError(try Transformation.parseList("Shift 1m"))
        XCTAssertThrowsError(try Transformation.parseList("RemoveDC 1"))
        XCTAssertThrowsError(try Transformation.parseList("ClampMin 1, 2"))
    }

    func testTransformationsApplyInDescriptionOrder() throws {
        let points = [Point(time: 0, value: 1), Point(time: 1, value: 2)]

        let offsetThenMultiply = try Transformation.parseList("Offset 1; Multiply 2")
            .reduce(points) { try $1.applying(to: $0) }
        let multiplyThenOffset = try Transformation.parseList("Multiply 2; Offset 1")
            .reduce(points) { try $1.applying(to: $0) }

        XCTAssertEqual(offsetThenMultiply.map(\.value), [4, 6])
        XCTAssertEqual(multiplyThenOffset.map(\.value), [3, 5])
    }

    func testClampLimitsValuesOnTheCorrectSide() throws {
        let points = [Point(time: 0, value: -1), Point(time: 1, value: 2)]

        let clampedMinimum = try Transformation.clampMin(0).applying(to: points)
        let clampedMaximum = try Transformation.clampMax(1).applying(to: points)

        XCTAssertEqual(clampedMinimum.map(\.value), [0, 2])
        XCTAssertEqual(clampedMaximum.map(\.value), [-1, 1])
    }

    func testFractionalRepeatAppendsCompleteCopiesAndAPartialCopy() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 10),
            Point(time: 2, value: 20),
            Point(time: 3, value: 30),
        ]

        let repeated = try Transformation.repeat(2.5).applying(to: points)

        XCTAssertEqual(repeated.map(\.time), Array(0 ... 14).map(Double.init))
        XCTAssertEqual(repeated.map(\.value), [0, 10, 20, 30, 0, 10, 20, 30, 0, 10, 20, 30, 0, 10, 20])
    }

    func testFractionalRepeatInterpolatesItsFinalPoint() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 10),
            Point(time: 2, value: 20),
            Point(time: 3, value: 30),
        ]

        let repeated = try Transformation.repeat(0.375).applying(to: points)

        XCTAssertEqual(repeated.last?.time, 5.5)
        XCTAssertEqual(repeated.last?.value, 15)
    }
}
