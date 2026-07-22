@testable import rigol2spice
import Testing

// MARK: - ProtocolDecoderTests

struct ProtocolDecoderTests {
    @Test
    func `I2C decodes address direction ACK and payload`() throws {
        let capture = i2cCapture(bytes: [0xA0, 0x33], acknowledgements: [true, false])
        let result = try I2CDecoder(configuration: .init(threshold: 1.5)).decode(
            sdaPoints: capture.sda,
            sclPoints: capture.scl,
        )

        #expect(result.transactions.count == 1)
        #expect(result.frames.map(\.value) == [0xA0, 0x33])
        #expect(result.frames.map(\.acknowledged) == [true, false])
        #expect(result.frames[0].isAddress)
        #expect(result.frames[0].address == 0x50)
        #expect(result.frames[0].read == false)
        #expect(!result.frames[1].isAddress)
    }

    @Test
    func `I2C separates repeated start transactions`() throws {
        let capture = i2cRepeatedStartCapture()
        let result = try I2CDecoder(configuration: .init(threshold: 1.5)).decode(
            sdaPoints: capture.sda,
            sclPoints: capture.scl,
        )

        #expect(result.transactions.count == 2)
        #expect(!result.transactions[0].repeatedStart)
        #expect(result.transactions[1].repeatedStart)
        #expect(result.transactions[1].frames[0].address == 0x50)
        #expect(result.transactions[1].frames[0].read == true)
    }

    @Test(arguments: [0, 1, 2, 3])
    func `SPI decodes modes zero through three`(mode: Int) throws {
        let capture = spiCapture(bytes: [0xA5, 0x3C], mode: mode)
        let result = try SPIDecoder(configuration: .init(
            mode: mode,
            bitCount: 8,
            bitOrder: .msb,
            threshold: 1.5,
            hysteresis: 0,
            chipSelectActiveHigh: false,
        )).decode(
            clockPoints: capture.clock,
            mosiPoints: capture.mosi,
            misoPoints: nil,
            chipSelectPoints: capture.cs,
        )

        #expect(result.frames.map(\.mosi) == [0xA5, 0x3C])
    }

    @Test
    func `SPI supports LSB first and MISO-only capture`() throws {
        let capture = spiCapture(bytes: [0x96], mode: 0, order: .lsb)
        let result = try SPIDecoder(configuration: .init(
            mode: 0,
            bitCount: 8,
            bitOrder: .lsb,
            threshold: 1.5,
            hysteresis: 0,
            chipSelectActiveHigh: false,
        )).decode(
            clockPoints: capture.clock,
            mosiPoints: nil,
            misoPoints: capture.mosi,
            chipSelectPoints: capture.cs,
        )

        #expect(result.frames.map(\.miso) == [0x96])
    }

    @Test
    func `SPI chip select discards incomplete words`() throws {
        var states: [(Bool, Bool, Bool)] = []
        func append(_ clock: Bool, _ data: Bool, _ cs: Bool) {
            states.append(contentsOf: repeatElement((clock, data, cs), count: 3))
        }
        func bits(_ values: [Bool]) {
            for bit in values {
                append(false, bit, false)
                append(true, bit, false)
                append(false, bit, false)
            }
        }
        append(false, false, true)
        append(false, false, false)
        bits([true, false, true, false])
        append(false, false, true)
        append(false, false, false)
        bits((0 ..< 8).map { UInt8(0x5A) & (1 << (7 - $0)) != 0 })
        append(false, false, true)
        let capture = logicPoints(states)

        let result = try SPIDecoder(configuration: .init(
            mode: 0, bitCount: 8, bitOrder: .msb, threshold: 1.5,
            hysteresis: 0, chipSelectActiveHigh: false,
        )).decode(
            clockPoints: capture.clock,
            mosiPoints: capture.mosi,
            misoPoints: nil,
            chipSelectPoints: capture.cs,
        )

        #expect(result.frames.map(\.mosi) == [0x5A])
    }
}

private func i2cCapture(
    bytes: [UInt8],
    acknowledgements: [Bool],
) -> (sda: [Point], scl: [Point]) {
    var states: [(Bool, Bool)] = []
    func append(_ sda: Bool, _ scl: Bool) {
        states.append(contentsOf: repeatElement((sda, scl), count: 3))
    }
    append(true, true)
    append(false, true) // START
    for (index, byte) in bytes.enumerated() {
        let bits = (0 ..< 8).map { byte & (1 << (7 - $0)) != 0 } + [!acknowledgements[index]]
        for bit in bits {
            append(bit, false)
            append(bit, true)
        }
    }
    append(false, false)
    append(false, true)
    append(true, true) // STOP
    return logicPoints(states)
}

private func i2cRepeatedStartCapture() -> (sda: [Point], scl: [Point]) {
    var states: [(Bool, Bool)] = []
    func append(_ sda: Bool, _ scl: Bool) {
        states.append(contentsOf: repeatElement((sda, scl), count: 3))
    }
    func byte(_ value: UInt8) {
        for bit in (0 ..< 8).map({ value & (1 << (7 - $0)) != 0 }) + [false] {
            append(bit, false)
            append(bit, true)
        }
    }
    append(true, true)
    append(false, true)
    byte(0xA0)
    append(true, false)
    append(true, true)
    append(false, true) // repeated START
    byte(0xA1)
    byte(0x5A)
    append(false, false)
    append(false, true)
    append(true, true)
    return logicPoints(states)
}

private func spiCapture(
    bytes: [UInt8],
    mode: Int,
    order: SPIBitOrder = .msb,
) -> (clock: [Point], mosi: [Point], cs: [Point]) {
    let idle = mode >= 2
    let cpha = mode % 2
    var states: [(Bool, Bool, Bool)] = []
    func append(_ clock: Bool, _ data: Bool, _ cs: Bool) {
        states.append(contentsOf: repeatElement((clock, data, cs), count: 3))
    }
    append(idle, false, true)
    append(idle, false, false)
    for byte in bytes {
        for bitIndex in 0 ..< 8 {
            let shift = order == .msb ? 7 - bitIndex : bitIndex
            let bit = byte & (1 << shift) != 0
            if cpha == 0 {
                append(idle, bit, false)
                append(!idle, bit, false)
                append(idle, bit, false)
            }
            else {
                append(!idle, false, false)
                append(!idle, bit, false)
                append(idle, bit, false)
            }
        }
    }
    append(idle, false, true)
    return logicPoints(states)
}

private func logicPoints(_ states: [(Bool, Bool)]) -> (sda: [Point], scl: [Point]) {
    let sda = states.enumerated().map { Point(time: Double($0.offset), value: $0.element.0 ? 3 : 0) }
    let scl = states.enumerated().map { Point(time: Double($0.offset), value: $0.element.1 ? 3 : 0) }
    return (sda, scl)
}

private func logicPoints(_ states: [(Bool, Bool, Bool)]) -> (clock: [Point], mosi: [Point], cs: [Point]) {
    let clock = states.enumerated().map { Point(time: Double($0.offset), value: $0.element.0 ? 3 : 0) }
    let mosi = states.enumerated().map { Point(time: Double($0.offset), value: $0.element.1 ? 3 : 0) }
    let cs = states.enumerated().map { Point(time: Double($0.offset), value: $0.element.2 ? 3 : 0) }
    return (clock, mosi, cs)
}
