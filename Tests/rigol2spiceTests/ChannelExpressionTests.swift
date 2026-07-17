@testable import rigol2spice
import Foundation
import Testing

struct ChannelExpressionTests {
    @Test
    func `parses single channel and basic binary operators`() throws {
        #expect(try parseChannelExpression("CH1") == .channel("CH1"))
        #expect(
            try parseChannelExpression("CH1+CH2")
                == .binary(.add, .channel("CH1"), .channel("CH2")),
        )
        #expect(
            try parseChannelExpression(" ch1 - ch2 ")
                == .binary(.subtract, .channel("ch1"), .channel("ch2")),
        )
        #expect(
            try parseChannelExpression("CH1*CH2")
                == .binary(.multiply, .channel("CH1"), .channel("CH2")),
        )
        #expect(
            try parseChannelExpression("CH1/CH2")
                == .binary(.divide, .channel("CH1"), .channel("CH2")),
        )
    }

    @Test
    func `respects precedence and parentheses`() throws {
        // CH1 + CH2 * CH3  =>  CH1 + (CH2 * CH3)
        #expect(
            try parseChannelExpression("CH1+CH2*CH3")
                == .binary(
                    .add,
                    .channel("CH1"),
                    .binary(.multiply, .channel("CH2"), .channel("CH3")),
                ),
        )

        #expect(
            try parseChannelExpression("(CH1+CH2)/CH3")
                == .binary(
                    .divide,
                    .binary(.add, .channel("CH1"), .channel("CH2")),
                    .channel("CH3"),
                ),
        )
    }

    @Test
    func `supports unary minus`() throws {
        #expect(try parseChannelExpression("-CH1") == .unaryMinus(.channel("CH1")))
        #expect(
            try parseChannelExpression("CH1*-CH2")
                == .binary(.multiply, .channel("CH1"), .unaryMinus(.channel("CH2"))),
        )
    }

    @Test
    func `rejects numeric literals`() {
        #expect(throws: ChannelExpressionError.unexpectedCharacter("2")) {
            try parseChannelExpression("CH1*2")
        }
        #expect(throws: ChannelExpressionError.unexpectedCharacter("2")) {
            try parseChannelExpression("(CH1+CH2)/2")
        }
    }

    @Test
    func `evaluates expressions with channel values`() throws {
        let expression = try parseChannelExpression("(CH1-CH2)/CH3")
        let value = try expression.evaluate(channels: ["CH1": 4, "CH2": 2, "CH3": 2])
        #expect(value == 1)
    }

    @Test
    func `rejects division by zero when evaluating`() throws {
        let expression = try parseChannelExpression("CH1/CH2")
        #expect(throws: ChannelExpressionError.divisionByZero) {
            try expression.evaluate(channels: ["CH1": 1, "CH2": 0])
        }
    }

    @Test
    func `legacy parser evaluates multi channel expressions`() throws {
        let sum = try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "CH1+CH2")
        #expect(sum.selectedChannel == "CH1+CH2")
        #expect(sum.points.first == Point(time: 0, value: 4.00e-02 + 7.60e-03))

        let difference = try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "CH1-CH2")
        #expect(abs((difference.points.first?.value ?? 0) - (4.00e-02 - 7.60e-03)) < 1e-15)

        let product = try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "CH1*CH2")
        #expect(abs((product.points.first?.value ?? 0) - (4.00e-02 * 7.60e-03)) < 1e-15)

        let single = try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "ch2")
        #expect(single.selectedChannel == "CH2")
        #expect(single.points.first?.value == 7.6e-03)
    }

    @Test
    func `legacy parser reports missing channels inside expressions`() {
        #expect(throws: ParseError.channelNotFound(channelLabel: "CH9")) {
            try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "CH1+CH9")
        }
    }

    @Test
    func `legacy parser reports division by zero in expressions`() {
        #expect(throws: ParseError.divisionByZero) {
            try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "CH1/CH2")
        }
    }

    @Test
    func `rejects invalid channel expressions`() {
        #expect(throws: ParseError.invalidChannelExpression("Channel expression is empty")) {
            try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "   ")
        }
        #expect(throws: (any Error).self) {
            try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "CH1+")
        }
        #expect(throws: (any Error).self) {
            try LegacyCSVParser().parse(sampleData(named: "Legacy"), channel: "CH1*2")
        }
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
