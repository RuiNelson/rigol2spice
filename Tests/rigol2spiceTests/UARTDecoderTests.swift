@testable import rigol2spice
import Testing

// MARK: - UARTDecoderTests

struct UARTDecoderTests {
    @Test
    func `digital signal interpolates threshold crossings and applies hysteresis`() throws {
        let points = [
            Point(time: 0, value: 0),
            Point(time: 1, value: 0.4),
            Point(time: 2, value: 1.6),
            Point(time: 3, value: 2.4),
            Point(time: 4, value: 1.4),
            Point(time: 5, value: 0.4),
        ]

        let signal = try DigitalSignal.from(points: points, threshold: 1.5, hysteresis: 1)

        #expect(signal.initialLevel == .low)
        #expect(signal.edges.count == 2)
        #expect(abs(signal.edges[0].time - 2.5) < 1e-12)
        #expect(abs(signal.edges[1].time - 4.4) < 1e-12)
        #expect(signal.level(at: 3) == .high)
        #expect(signal.level(at: 5) == .low)
    }

    @Test
    func `decodes explicit baud 8N1 frames with timestamps`() throws {
        let baud = 9600.0
        let points = uartPoints(bytes: [0x55, 0xA3], baudRate: baud)
        let decoder = UARTDecoder(configuration: .init(baudRate: .explicit(baud), threshold: 1.5))

        let result = try decoder.decode(points: points)

        #expect(result.baudRate == baud)
        #expect(result.frames.map(\.byte) == [0x55, 0xA3])
        #expect(result.frames.allSatisfy { !$0.framingError && !$0.parityError })
        #expect(abs(result.frames[0].startTime - 2 / baud) < 1 / baud / 8)
        #expect(abs(result.frames[0].endTime - 12 / baud) < 1 / baud / 8)
    }

    @Test
    func `automatically detects baud and decodes bytes`() throws {
        let baud = 115_200.0
        let points = uartPoints(bytes: [0x55, 0xA6, 0x31, 0xD3], baudRate: baud, samplesPerBit: 20)
        let decoder = UARTDecoder(configuration: .init(baudRate: .automatic, threshold: 1.5))

        let result = try decoder.decode(points: points)

        #expect(abs(result.baudRate - baud) / baud < 0.02)
        #expect(result.frames.map(\.byte) == [0x55, 0xA6, 0x31, 0xD3])
    }

    @Test
    func `reports parity and framing errors`() throws {
        let baud = 19200.0
        let points = uartPoints(
            bytes: [0x03, 0x07],
            baudRate: baud,
            parity: .even,
            badParityFrames: [0],
            badStopFrames: [1],
        )
        let decoder = UARTDecoder(configuration: .init(
            baudRate: .explicit(baud),
            threshold: 1.5,
            parity: .even,
        ))

        let result = try decoder.decode(points: points)

        #expect(result.frames.map(\.byte) == [0x03, 0x07])
        #expect(result.frames.map(\.parityError) == [true, false])
        #expect(result.frames.map(\.framingError) == [false, true])
    }
}

private func uartPoints(
    bytes: [UInt8],
    baudRate: Double,
    samplesPerBit: Int = 16,
    parity: UARTParity = .none,
    badParityFrames: Set<Int> = [],
    badStopFrames: Set<Int> = [],
) -> [Point] {
    var bits = [true, true]
    for (frameIndex, byte) in bytes.enumerated() {
        bits.append(false)
        var ones = 0
        for bitIndex in 0 ..< 8 {
            let high = byte & (1 << bitIndex) != 0
            bits.append(high)
            if high { ones += 1 }
        }
        if parity != .none {
            var parityHigh = parity == .even ? ones % 2 == 1 : ones % 2 == 0
            if badParityFrames.contains(frameIndex) { parityHigh.toggle() }
            bits.append(parityHigh)
        }
        bits.append(!badStopFrames.contains(frameIndex))
    }
    bits.append(contentsOf: [true, true])

    let sampleInterval = 1 / baudRate / Double(samplesPerBit)
    return (0 ..< bits.count * samplesPerBit).map { sampleIndex in
        let bitIndex = sampleIndex / samplesPerBit
        return Point(
            time: Double(sampleIndex) * sampleInterval,
            value: bits[bitIndex] ? 3.0 : 0.0,
        )
    }
}
