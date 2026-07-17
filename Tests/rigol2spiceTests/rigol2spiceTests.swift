@testable import rigol2spice
import Foundation
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
    func `gate zeros values below the threshold`() throws {
        #expect(try Transformation.parseList("Gate 0.6") == [.gate(0.6)])

        let points = [
            Point(time: 0, value: 0.5),
            Point(time: 1, value: 0.6),
            Point(time: 2, value: 1.2),
            Point(time: 3, value: -0.1),
        ]
        let gated = try Transformation.gate(0.6).applying(to: points)

        #expect(gated.map(\.value) == [0, 0.6, 1.2, 0])
        #expect(gated.map(\.time) == [0, 1, 2, 3])
    }

    @Test
    func `dB scales amplitude using voltage decibels`() throws {
        #expect(try Transformation.parseList("dB 6") == [.db(6)])
        #expect(try Transformation.parseList("DB -20") == [.db(-20)])

        let points = [Point(time: 0, value: 1), Point(time: 1, value: -2)]
        let plusSix = try Transformation.db(6).applying(to: points)
        let minusTwenty = try Transformation.db(-20).applying(to: points)
        let unity = try Transformation.db(0).applying(to: points)

        let sixFactor = pow(10.0, 6.0 / 20.0)
        #expect(abs(plusSix[0].value - sixFactor) < 1e-12)
        #expect(abs(plusSix[1].value - (-2 * sixFactor)) < 1e-12)
        #expect(abs(minusTwenty[0].value - 0.1) < 1e-12)
        #expect(abs(minusTwenty[1].value - (-0.2)) < 1e-12)
        #expect(unity.map(\.value) == [1, -2])
    }

    @Test
    func `dBmW and dBW multiply by absolute power voltage at 50 ohm`() throws {
        #expect(
            try Transformation.parseList("dBmW 0")
                == [.dbmW(level: 0, resistance: 50)],
        )
        #expect(
            try Transformation.parseList("dBm 10")
                == [.dbmW(level: 10, resistance: 50)],
        )
        #expect(
            try Transformation.parseList("dBW -10")
                == [.dbW(level: -10, resistance: 50)],
        )
        #expect(
            try Transformation.parseList("dBmW 0, 75")
                == [.dbmW(level: 0, resistance: 75)],
        )
        #expect(
            try Transformation.parseList("dBW 0, 75")
                == [.dbW(level: 0, resistance: 75)],
        )

        let points = [Point(time: 0, value: 1), Point(time: 1, value: 2)]

        let zeroDBm = try Transformation.dbmW(level: 0, resistance: 50).applying(to: points)
        let expectedZeroDBm = sqrt(1e-3 * 50) // ≈ 0.22360679775
        #expect(abs(zeroDBm[0].value - expectedZeroDBm) < 1e-12)
        #expect(abs(zeroDBm[1].value - 2 * expectedZeroDBm) < 1e-12)

        let zeroDBW = try Transformation.dbW(level: 0, resistance: 50).applying(to: points)
        let expectedZeroDBW = sqrt(50.0)
        #expect(abs(zeroDBW[0].value - expectedZeroDBW) < 1e-12)

        // 30 dBmW == 0 dBW
        let thirtyDBm = try Transformation.dbmW(level: 30, resistance: 50).applying(to: points)
        #expect(abs(thirtyDBm[0].value - expectedZeroDBW) < 1e-12)

        // 0 dBW == 30 dBmW voltage; relative offset of -30 dBW matches 0 dBmW
        let minus30DBW = try Transformation.dbW(level: -30, resistance: 50).applying(to: points)
        #expect(abs(minus30DBW[0].value - expectedZeroDBm) < 1e-12)

        let seventyFiveOhm = try Transformation.dbmW(level: 0, resistance: 75).applying(to: points)
        #expect(abs(seventyFiveOhm[0].value - sqrt(1e-3 * 75)) < 1e-12)

        #expect(throws: (any Error).self) {
            try Transformation.parseList("dBmW 0, 0")
        }
        #expect(throws: (any Error).self) {
            try Transformation.parseList("dBW 0, -50")
        }
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
    func `cut before discards samples before the timestamp`() throws {
        #expect(try Transformation.parseList("CutBefore 2") == [.cutBefore(2)])

        let points = (0 ... 4).map { Point(time: Double($0), value: Double($0)) }
        let result = try Transformation.cutBefore(2).applying(to: points)

        #expect(result.map(\.time) == [2, 3, 4])
        #expect(result.map(\.value) == [2, 3, 4])
    }

    @Test
    func `trim keeps samples inside the half open window`() throws {
        #expect(try Transformation.parseList("Trim 1m, 10m") == [.trim(start: 1e-3, end: 10e-3)])
        #expect(throws: (any Error).self) {
            try Transformation.parseList("Trim 2, 1")
        }

        let points = (0 ... 5).map { Point(time: Double($0), value: Double($0)) }
        let result = try Transformation.trim(start: 2, end: 5).applying(to: points)

        #expect(result.map(\.time) == [2, 3, 4])
    }

    @Test
    func `vertical transforms preserve times and transform values`() {
        let points = [Point(time: 0, value: -1), Point(time: 1, value: 2), Point(time: 2, value: 5)]

        #expect(multiplyValueOfPoints(points, factor: 2).map(\.value) == [-2, 4, 10])
        #expect(offsetPoints(points, offset: 0.5).map(\.value) == [-0.5, 2.5, 5.5])
        #expect(clamp(points, lowerLimit: 0, upperLimit: 3).map(\.value) == [0, 2, 3])
        #expect(offsetPoints(points, offset: 1).map(\.time) == [0, 1, 2])
    }

    @Test
    func `invert multiplies every value by negative one`() throws {
        #expect(try Transformation.parseList("Invert") == [.invert])
        #expect(throws: (any Error).self) {
            try Transformation.parseList("Invert 1")
        }

        let points = [Point(time: 0, value: -1), Point(time: 1, value: 2)]
        let inverted = try Transformation.invert.applying(to: points)
        let viaMultiply = try Transformation.multiply(-1).applying(to: points)

        #expect(inverted.map(\.value) == [1, -2])
        #expect(inverted == viaMultiply)
        #expect(inverted.map(\.time) == [0, 1])
    }

    @Test
    func `abs takes the absolute value of every sample`() throws {
        #expect(try Transformation.parseList("Abs") == [.abs])

        let points = [Point(time: 0, value: -1.5), Point(time: 1, value: 2), Point(time: 2, value: 0)]
        let result = try Transformation.abs.applying(to: points)

        #expect(result.map(\.value) == [1.5, 2, 0])
        #expect(result.map(\.time) == [0, 1, 2])
    }

    @Test
    func `rectify zeros negative samples`() throws {
        #expect(try Transformation.parseList("Rectify") == [.rectify])

        let points = [Point(time: 0, value: -1.5), Point(time: 1, value: 2), Point(time: 2, value: 0)]
        let result = try Transformation.rectify.applying(to: points)

        #expect(result.map(\.value) == [0, 2, 0])
        #expect(result.map(\.time) == [0, 1, 2])
    }

    @Test
    func `normalize scales peak absolute value to one`() throws {
        #expect(try Transformation.parseList("Normalize") == [.normalize])

        let points = [Point(time: 0, value: -2), Point(time: 1, value: 1)]
        let result = try Transformation.normalize.applying(to: points)

        #expect(result.map(\.value) == [-1, 0.5])
        #expect(try Transformation.normalize.applying(to: [Point(time: 0, value: 0)]).map(\.value) == [0])
    }

    @Test
    func `peakTo scales peak absolute value to the target`() throws {
        #expect(try Transformation.parseList("PeakTo 3.3") == [.peakTo(3.3)])
        #expect(throws: (any Error).self) {
            try Transformation.parseList("PeakTo 0")
        }

        let points = [Point(time: 0, value: -2), Point(time: 1, value: 1)]
        let result = try Transformation.peakTo(3.3).applying(to: points)

        #expect(abs(result[0].value - (-3.3)) < 1e-12)
        #expect(abs(result[1].value - 1.65) < 1e-12)
    }

    @Test
    func `scaleTo is an alias of peakTo`() throws {
        #expect(try Transformation.parseList("ScaleTo 2") == [.scaleTo(2)])

        let points = [Point(time: 0, value: -2), Point(time: 1, value: 1)]
        let peakTo = try Transformation.peakTo(2).applying(to: points)
        let scaleTo = try Transformation.scaleTo(2).applying(to: points)

        #expect(scaleTo == peakTo)
    }

    @Test
    func `moving average smooths with a centered window`() throws {
        #expect(try Transformation.parseList("MovingAverage 3") == [.movingAverage(3)])
        #expect(throws: (any Error).self) {
            try Transformation.parseList("MovingAverage 0")
        }
        #expect(throws: (any Error).self) {
            try Transformation.parseList("MovingAverage 1.5")
        }

        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 3),
            Point(time: 2, value: 6),
            Point(time: 3, value: 9),
        ]
        let result = try Transformation.movingAverage(3).applying(to: points)

        #expect(result.map(\.value) == [1.5, 3, 6, 7.5])
        #expect(result.map(\.time) == [0, 1, 2, 3])
    }

    @Test
    func `diff computes numerical derivative`() throws {
        #expect(try Transformation.parseList("Diff") == [.diff])

        // v = 2t → dv/dt = 2
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 2),
            Point(time: 2, value: 4),
            Point(time: 3, value: 6),
        ]
        let result = try Transformation.diff.applying(to: points)

        #expect(result.map(\.value) == [2, 2, 2, 2])
        #expect(result.map(\.time) == [0, 1, 2, 3])
    }

    @Test
    func `integrate accumulates with the trapezoid rule`() throws {
        #expect(try Transformation.parseList("Integrate") == [.integrate])

        // constant 2 over time → ramp 2t
        let points = [
            Point(time: 0, value: 2),
            Point(time: 1, value: 2),
            Point(time: 2, value: 2),
            Point(time: 3, value: 2),
        ]
        let result = try Transformation.integrate.applying(to: points)

        #expect(result.map(\.value) == [0, 2, 4, 6])
        #expect(result.map(\.time) == [0, 1, 2, 3])
    }

    @Test
    func `legacy parser reads a real oscilloscope capture`() throws {
        let capture = try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "ch2")

        #expect(capture.channels == ["CH1", "CH2"])
        #expect(capture.selectedChannel == "CH2")
        #expect(capture.sampleInterval == 2e-06)
        #expect(capture.points.count == 1200)
        #expect(capture.points.first == Point(time: 0, value: 7.6e-03))
        #expect(abs((capture.points.last?.time ?? 0) - 2.398e-03) < 1e-15)
        #expect(capture.points.last?.value == -1.2e-03)
    }

    @Test
    func `legacy parser can inspect channels without parsing points`() throws {
        let capture = try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: nil)

        #expect(capture.channels == ["CH1", "CH2"])
        #expect(capture.selectedChannel == nil)
        #expect(capture.points.isEmpty)
    }

    @Test
    func `centaurus parser reads a real oscilloscope capture`() throws {
        let capture = try CentaurusCSVParser().parse(sampleData(named: "Centaurus"), channel: "ch4")

        #expect(capture.channels == ["CH4V"])
        #expect(capture.selectedChannel == "CH4V")
        #expect(capture.points.count == 1000)
        #expect(capture.points.first?.time == 0)
        #expect(abs((capture.points.last?.time ?? 0) - 0.999) < 1e-12)
        #expect(abs((capture.sampleInterval ?? 0) - 0.001) < 1e-12)
        #expect(capture.points.first?.value == -9.733333e-03)
        #expect(capture.points.last?.value == 5.2e-02)
    }

    @Test
    func `parsers report missing channels consistently`() {
        #expect(throws: ParseError.channelNotFound(channelLabel: "CH9")) {
            try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "CH9")
        }
        #expect(throws: ParseError.channelNotFound(channelLabel: "CH9")) {
            try CentaurusCSVParser().parse(sampleData(named: "Centaurus"), channel: "CH9")
        }
    }

    @Test
    func `PWL writer serializes points atomically`() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let points = [Point(time: 0, value: 1), Point(time: 0.5, value: -2)]
        let byteCount = try PWLWriter().write(points, to: outputURL)
        let data = try Data(contentsOf: outputURL)

        #expect(byteCount == data.count)
        #expect(String(data: data, encoding: .ascii) == "0\t1\r\n0.5\t-2\r\n")
    }

    private func sampleData(named name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(
                forResource: name,
                withExtension: "csv",
                subdirectory: "SampleFiles",
            ),
        )
        return try Data(contentsOf: url)
    }
}
