@testable import rigol2spice
import Testing

struct DecodeCommandTests {
    @Test
    func `UART command parses explicit baud and defaults`() throws {
        let request = try UARTDecodeRequest.parse("UART rx=CH2, baud=115200, threshold=1.65")

        #expect(request.channel == "CH2")
        #expect(request.configuration.baudRate == .explicit(115_200))
        #expect(request.configuration.threshold == 1.65)
        #expect(request.configuration.hysteresis == 0)
        #expect(request.configuration.dataBits == 8)
        #expect(request.configuration.parity == .none)
        #expect(request.configuration.stopBits == 1)
        #expect(!request.configuration.inverted)
    }

    @Test
    func `UART command parses automatic baud and optional framing`() throws {
        let request = try UARTDecodeRequest.parse(
            "uart rx=CH1, baud=auto, threshold=2, hysteresis=200m, data=7, parity=even, stop=2, inverted=yes",
        )

        #expect(request.configuration.baudRate == .automatic)
        #expect(request.configuration.hysteresis == 0.2)
        #expect(request.configuration.dataBits == 7)
        #expect(request.configuration.parity == .even)
        #expect(request.configuration.stopBits == 2)
        #expect(request.configuration.inverted)
    }

    @Test
    func `UART command requires channel baud and threshold`() {
        #expect(throws: DecodeCommandError.missingArgument("rx")) {
            try UARTDecodeRequest.parse("UART baud=auto, threshold=1")
        }
        #expect(throws: DecodeCommandError.missingArgument("baud")) {
            try UARTDecodeRequest.parse("UART rx=CH1, threshold=1")
        }
        #expect(throws: DecodeCommandError.missingArgument("threshold")) {
            try UARTDecodeRequest.parse("UART rx=CH1, baud=9600")
        }
    }

    @Test
    func `UART command rejects unsupported and invalid values`() {
        #expect(throws: DecodeCommandError.unsupportedProtocol("can")) {
            try DecodeRequest.parse("CAN data=CH1")
        }
        #expect(throws: (any Error).self) {
            try UARTDecodeRequest.parse("UART rx=CH1, baud=fast, threshold=1")
        }
        #expect(throws: (any Error).self) {
            try UARTDecodeRequest.parse("UART rx=CH1, baud=9600, threshold=1, parity=mark")
        }
    }

    @Test
    func `I2C command parses channels shared and separate thresholds`() throws {
        let shared = try DecodeRequest.parse("I2C sda=CH1, scl=CH2, threshold=1.65")
        guard case let .i2c(request) = shared else {
            Issue.record("Expected I2C request")
            return
        }
        #expect(request.sdaChannel == "CH1")
        #expect(request.sclChannel == "CH2")
        #expect(request.configuration.sdaThreshold == 1.65)
        #expect(request.configuration.sclThreshold == 1.65)

        let separate = try DecodeRequest.parse(
            "I2C sda=CH1, scl=CH2, sda-threshold=1.2, scl-threshold=2, hysteresis=100m",
        )
        guard case let .i2c(separateRequest) = separate else { return }
        #expect(separateRequest.configuration.sdaThreshold == 1.2)
        #expect(separateRequest.configuration.sclThreshold == 2)
        #expect(separateRequest.configuration.hysteresis == 0.1)
    }

    @Test
    func `SPI command parses mode channels order and defaults`() throws {
        let parsed = try DecodeRequest.parse(
            "SPI clk=CH1, mosi=CH2, miso=CH3, cs=CH4, mode=3, bits=16, order=lsb, threshold=1.5, cs-active=high",
        )
        guard case let .spi(request) = parsed else {
            Issue.record("Expected SPI request")
            return
        }
        #expect(request.clockChannel == "CH1")
        #expect(request.mosiChannel == "CH2")
        #expect(request.misoChannel == "CH3")
        #expect(request.chipSelectChannel == "CH4")
        #expect(request.configuration.mode == 3)
        #expect(request.configuration.bitCount == 16)
        #expect(request.configuration.bitOrder == .lsb)
        #expect(request.configuration.chipSelectActiveHigh)
    }
}
