@testable import rigol2spice
import Foundation
import Testing

struct TCNForecastTests {
    @Test
    func `tcn appends the requested duration on the sampling grid`() throws {
        let points = (0 ..< 40).map { index in
            Point(time: Double(index) * 0.25, value: sin(Double(index) * 0.2))
        }

        let result = try Transformation.tcn(duration: 1, sampleCount: nil).applying(
            to: points,
            sampleInterval: 0.25,
        )

        #expect(result.count == 44)
        #expect(result.prefix(points.count).elementsEqual(points))
        #expect(result.suffix(4).map(\.time) == [10, 10.25, 10.5, 10.75])
        for point in result.suffix(4) {
            #expect(point.value.isFinite)
        }
    }

    @Test
    func `tcn appends an exact requested sample count over the duration`() throws {
        let points = (0 ..< 40).map { index in
            Point(time: Double(index) * 0.25, value: sin(Double(index) * 0.2))
        }
        let result = try Transformation.tcn(duration: 1, sampleCount: 7).applying(
            to: points,
            sampleInterval: 0.25,
        )

        #expect(result.count == 47)
        #expect(result.last?.time == 10.75)
    }

    @Test
    func `tcn continues a constant signal exactly`() throws {
        let points = (0 ..< 12).map { Point(time: Double($0), value: 3.3) }
        let result = try tcnForecastPoints(points, duration: 3)

        #expect(result.map(\.value) == Array(repeating: 3.3, count: 15))
        #expect(result.map(\.time) == Array(0 ... 14).map(Double.init))
    }

    @Test
    func `tcn extrapolates a dominant linear trend`() throws {
        let points = (0 ..< 100).map { index in
            Point(time: Double(index) * 2e-6, value: 0.25 * Double(index) - 2)
        }
        let result = try tcnForecastPoints(points, duration: 1e-3)

        #expect(result.count == 600)
        #expect(abs(result[100].value - 23) < 1e-10)
        #expect(abs(result[599].value - 147.75) < 1e-10)
        #expect(abs(result[599].time - 1.198e-3) < 1e-15)
    }

    @Test
    func `tcn learns a clean periodic continuation`() throws {
        let period = 16
        let points = (0 ..< 128).map { index in
            Point(
                time: Double(index) * 1e-3,
                value: sin(2 * .pi * Double(index) / Double(period)),
            )
        }
        let result = try tcnForecastPoints(points, duration: 16e-3)
        let forecast = result.suffix(period)

        for (offset, point) in forecast.enumerated() {
            let expected = sin(2 * .pi * Double(128 + offset) / Double(period))
            #expect(abs(point.value - expected) < 0.02)
        }
    }

    @Test
    func `tcn detects a period beyond its local receptive field`() throws {
        let period = 100
        let points = (0 ..< 300).map { index in
            let phase = index % period
            let value = phase < 25 ? 0.0 : phase < 75 ? 3.0 : 0.0
            return Point(time: Double(index), value: value)
        }
        let result = try tcnForecastPoints(points, duration: Double(period))

        #expect(result.count == 400)
        for offset in 0 ..< period {
            #expect(abs(result[300 + offset].value - points[200 + offset].value) < 0.02)
        }
    }

    @Test
    func `tcn forecasts one millisecond of the legacy sample without collapsing to its mean`() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "Legacy",
                withExtension: "csv",
                subdirectory: "SampleFiles",
            ),
        )
        let capture = try LegacyCSVParser().parse(Data(contentsOf: url), channel: "CH1")
        let forecast = try tcnForecast(
            capture.points,
            duration: 1e-3,
            sampleInterval: capture.sampleInterval,
        )
        let result = forecast.points

        try #require(result.count == 1700)
        let predicted = result[1200 ..< 1700].map(\.value)
        let previousCycle = capture.points[700 ..< 1200].map(\.value)
        let meanAbsoluteError = zip(predicted, previousCycle)
            .reduce(0.0) { $0 + abs($1.0 - $1.1) } / Double(predicted.count)

        #expect(meanAbsoluteError < 0.02)
        #expect((predicted.min() ?? 1) < 0.1)
        #expect((predicted.max() ?? 0) > 2.9)
        #expect(forecast.method == .seasonal(period: 500))
        #expect(forecast.confidence > 0.9)
    }

    @Test
    func `tcn reports low confidence for an unpredictable capture`() throws {
        var state: UInt64 = 0x1234_5678
        let points = (0 ..< 256).map { index in
            state = state &* 6_364_136_223_846_793_005 &+ 1
            let value = Double(state >> 11) / Double(UInt64.max >> 11) * 2 - 1
            return Point(time: Double(index), value: value)
        }
        let forecast = try tcnForecast(points, duration: 64)

        #expect(forecast.points.count == 320)
        #expect(forecast.confidence < 0.25)
        #expect(forecast.method == .mean || forecast.method == .holdLast)
    }

    @Test
    func `tcn rejects short non finite and irregular inputs`() {
        #expect(throws: TCNForecastError.notEnoughSamples(actual: 7, minimum: 8)) {
            try tcnForecastPoints((0 ..< 7).map { Point(time: Double($0), value: 0) }, duration: 1)
        }

        var nonFinite = (0 ..< 8).map { Point(time: Double($0), value: 0) }
        nonFinite[4].value = .nan
        #expect(throws: TCNForecastError.nonFiniteSample(index: 4)) {
            try tcnForecastPoints(nonFinite, duration: 1)
        }

        var irregular = (0 ..< 8).map { Point(time: Double($0), value: Double($0)) }
        irregular[5].time += 0.1
        #expect(throws: TCNForecastError.nonUniformSampling(index: 5)) {
            try tcnForecastPoints(irregular, duration: 1)
        }
    }
}
