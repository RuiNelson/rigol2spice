@testable import rigol2spice
import Foundation
import Testing

struct TriggerModesTests {
    @Test
    func `parses every trigger mode and level form`() throws {
        #expect(try Transformation.parseList("Trigger rising, auto") == [
            .triggerLevel(edge: .rising, level: .automatic, after: nil),
        ])
        #expect(try Transformation.parseList("Trigger falling, 25%, 2m") == [
            .triggerLevel(edge: .falling, level: .percent(25), after: 2e-3),
        ])
        #expect(try Transformation.parseList("TriggerSchmitt either, 1, 2, 3m") == [
            .triggerSchmitt(edge: .either, low: 1, high: 2, after: 3e-3),
        ])
        #expect(try Transformation.parseList("TriggerNth rising, auto, 3, 1m") == [
            .triggerNth(edge: .rising, level: .automatic, occurrence: 3, after: 1e-3),
        ])
        #expect(try Transformation.parseList("TriggerCapture falling, 50%, 1m, 2m, 3m") == [
            .triggerCapture(edge: .falling, level: .percent(50), pre: 1e-3, post: 2e-3, after: 3e-3),
        ])
        #expect(try Transformation.parseList("triggerwindow falling, 50%, 1m, 2m, 3m") == [
            .triggerCapture(edge: .falling, level: .percent(50), pre: 1e-3, post: 2e-3, after: 3e-3),
        ])
        #expect(try Transformation.parseList("TriggerBand enter, 1, 2, 1m") == [
            .triggerBand(mode: .enter, low: 1, high: 2, after: 1e-3),
        ])
        #expect(try Transformation.parseList("TriggerSlew rising, 10, 90, 100k") == [
            .triggerSlew(edge: .rising, lowPercent: 10, highPercent: 90, minimumRate: 100e3, maximumRate: nil),
        ])
        #expect(try Transformation.parseList("TriggerDropout either, 50%, 2m, 1m") == [
            .triggerDropout(edge: .either, level: .percent(50), duration: 2e-3, after: 1e-3),
        ])
        guard case let .triggerPulse(highPolarity, highLevel, minimumWidth, nil) =
            try Transformation.parseList("TriggerPulse high, 0.5, 10u").first,
            case let .triggerPulse(lowPolarity, lowLevel, lowMinimum, lowMaximum) =
            try Transformation.parseList("TriggerPulse low, auto, 10u, 20u").first,
            case let .triggerRunt(runtEdge, runtLow, runtHigh, runtDuration) =
            try Transformation.parseList("TriggerRunt falling, 1, 2, 20u").first else {
            Issue.record("Expected pulse and runt trigger cases")
            return
        }
        #expect(highPolarity == .high)
        #expect(highLevel == .value(0.5))
        #expect(abs(minimumWidth - 10e-6) < 1e-18)
        #expect(lowPolarity == .low)
        #expect(lowLevel == .automatic)
        #expect(abs(lowMinimum - 10e-6) < 1e-18)
        #expect(abs((lowMaximum ?? 0) - 20e-6) < 1e-18)
        #expect(runtEdge == .falling)
        #expect(runtLow == 1)
        #expect(runtHigh == 2)
        #expect(abs(runtDuration - 20e-6) < 1e-18)
    }

    @Test
    func `rejects invalid trigger configurations`() {
        for source in [
            "Trigger rising, 101%",
            "TriggerSchmitt rising, 2, 1",
            "TriggerNth rising, 0.5, 0",
            "TriggerCapture rising, 0.5, -1m, 2m",
            "TriggerCapture rising, 0.5, 1m, 0",
            "TriggerPulse high, 0.5, 20u, 10u",
            "TriggerBand sideways, 1, 2",
            "TriggerBand enter, 2, 1",
            "TriggerSlew either, 10, 90, 1k",
            "TriggerSlew rising, 90, 10, 1k",
            "TriggerDropout rising, 0.5, 0",
            "TriggerRunt either, 1, 2, 1m",
        ] {
            #expect(throws: (any Error).self) {
                try Transformation.parseList(source)
            }
        }
    }

    @Test
    func `auto percent and nth triggers align interpolated crossings`() throws {
        let points = [
            Point(time: 0, value: -1),
            Point(time: 1, value: 1),
            Point(time: 2, value: -1),
            Point(time: 3, value: 1),
            Point(time: 4, value: -1),
            Point(time: 5, value: 1),
        ]

        let automatic = try Transformation.triggerLevel(edge: .rising, level: .automatic, after: nil)
            .applying(to: points)
        #expect(automatic.first?.time == 0)
        #expect(abs((automatic.first?.value ?? 10) - 0) < 0.01)

        let percent = try Transformation.triggerLevel(edge: .rising, level: .percent(50), after: nil)
            .applying(to: points)
        #expect(percent.first?.time == 0)
        #expect(abs((percent.first?.value ?? 10) - 0) < 0.01)

        let second = try Transformation.triggerNth(
            edge: .rising,
            level: .value(0),
            occurrence: 2,
            after: nil,
        ).applying(to: points)
        #expect(second.first == Point(time: 0, value: 0))
        #expect(second[1] == Point(time: 0.5, value: 1))
    }

    @Test
    func `schmitt trigger arms at the opposite level before firing`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 1.5),
            Point(time: 2, value: 1.7),
            Point(time: 3, value: 1.3),
            Point(time: 4, value: 2.5),
        ]
        let result = try Transformation.triggerSchmitt(edge: .rising, low: 1, high: 2, after: nil)
            .applying(to: points)
        #expect(result.first == Point(time: 0, value: 2))
        #expect(abs(result[1].time - (4 - 43.0 / 12.0)) < 1e-12)
    }

    @Test
    func `trigger capture retains pre and post event window`() throws {
        let points = (0 ... 10).map { Point(time: Double($0), value: Double($0)) }
        let result = try Transformation.triggerCapture(
            edge: .rising,
            level: .value(5),
            pre: 2,
            post: 3,
            after: nil,
        ).applying(to: points)

        #expect(result.first == Point(time: 0, value: 3))
        #expect(result.contains(Point(time: 2, value: 5)))
        #expect(result.last == Point(time: 5, value: 8))
    }

    @Test
    func `pulse trigger skips widths outside requested range`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 1),
            Point(time: 2, value: 0),
            Point(time: 3, value: 1),
            Point(time: 6, value: 1),
            Point(time: 7, value: 0),
        ]
        let result = try Transformation.triggerPulse(
            polarity: .high,
            level: .value(0.5),
            minimumWidth: 3,
            maximumWidth: 5,
        ).applying(to: points)
        #expect(result.first == Point(time: 0, value: 0.5))
        #expect(result[1] == Point(time: 0.5, value: 1))
    }

    @Test
    func `band triggers distinguish enter exit above and below`() throws {
        let rising = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 1.5),
            Point(time: 2, value: 3),
        ]
        let enter = try Transformation.triggerBand(mode: .enter, low: 1, high: 2, after: nil)
            .applying(to: rising)
        let exit = try Transformation.triggerBand(mode: .exit, low: 1, high: 2, after: nil)
            .applying(to: rising)
        let above = try Transformation.triggerBand(mode: .above, low: 1, high: 2, after: nil)
            .applying(to: rising)
        #expect(enter.first == Point(time: 0, value: 1))
        #expect(exit.first == Point(time: 0, value: 2))
        #expect(above.first == Point(time: 0, value: 2))

        let falling = rising.reversed().enumerated().map { index, point in
            Point(time: Double(index), value: point.value)
        }
        let below = try Transformation.triggerBand(mode: .below, low: 1, high: 2, after: nil)
            .applying(to: falling)
        #expect(below.first == Point(time: 0, value: 1))
    }

    @Test
    func `slew trigger selects first edge inside rate range`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 10, value: 10),
            Point(time: 11, value: 0),
            Point(time: 12, value: 10),
        ]
        let result = try Transformation.triggerSlew(
            edge: .rising,
            lowPercent: 10,
            highPercent: 90,
            minimumRate: 5,
            maximumRate: 20,
        ).applying(to: points)
        #expect(result.first == Point(time: 0, value: 1))
        #expect(abs(result[1].time - 0.9) < 1e-12)
    }

    @Test
    func `dropout aligns the timeout after the last qualifying edge`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 1),
            Point(time: 2, value: 0),
            Point(time: 3, value: 1),
            Point(time: 4, value: 0),
            Point(time: 10, value: 0),
        ]
        let result = try Transformation.triggerDropout(
            edge: .rising,
            level: .value(0.5),
            duration: 3,
            after: nil,
        ).applying(to: points)
        #expect(result.first == Point(time: 0, value: 0))
        #expect(result.last?.time == 4.5)

        let edgeAtDeadline = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 1),
            Point(time: 2, value: 0),
            Point(time: 3, value: 0),
            Point(time: 4, value: 1),
            Point(time: 5, value: 0),
        ]
        #expect(throws: Rigol2SpiceError.triggerEventNotFound(operation: "TriggerDropout")) {
            try Transformation.triggerDropout(
                edge: .rising,
                level: .value(0.5),
                duration: 3,
                after: nil,
            ).applying(to: edgeAtDeadline)
        }
    }

    @Test
    func `runt trigger fires when target level is not reached in time`() throws {
        let runt = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 1.5),
            Point(time: 2, value: 0),
            Point(time: 2.5, value: 3),
            Point(time: 4, value: 3),
        ]
        let result = try Transformation.triggerRunt(
            edge: .rising,
            low: 1,
            high: 2,
            maximumDuration: 2,
        ).applying(to: runt)
        #expect(result.first == Point(time: 0, value: 1))

        let fullEdge = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 3),
            Point(time: 4, value: 3),
        ]
        #expect(throws: Rigol2SpiceError.triggerEventNotFound(operation: "TriggerRunt")) {
            try Transformation.triggerRunt(
                edge: .rising,
                low: 1,
                high: 2,
                maximumDuration: 2,
            ).applying(to: fullEdge)
        }
    }
}
