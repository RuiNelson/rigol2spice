@testable import rigol2spice
import Foundation
import Testing

struct DecodeWriterTests {
    @Test
    func `decode format accepts the three command line values`() {
        #expect(DecodeFormat(argument: "text") == .text)
        #expect(DecodeFormat(argument: "csv") == .csv)
        #expect(DecodeFormat(argument: "bin") == .bin)
        #expect(DecodeFormat(argument: "json") == nil)
    }

    @Test
    func `text contains baud timing data width and errors`() throws {
        let output = try DecodeWriter().data(for: sampleResult, format: .text)
        let text = try #require(String(data: output, encoding: .utf8))

        #expect(text == """
        UART baud=115200.0
        start=0.0001 end=0.0002 byte=0x41 decimal=65 dataBits=8 parityError=false framingError=false
        start=0.0003 end=0.0004 byte=0x0A decimal=10 dataBits=8 parityError=true framingError=true

        """)
    }

    @Test
    func `csv contains the same frame metadata`() throws {
        let output = try DecodeWriter().data(for: sampleResult, format: .csv)
        let text = try #require(String(data: output, encoding: .utf8))

        #expect(text == """
        protocol,baud,start_time_s,end_time_s,byte_hex,byte_decimal,data_bits,parity_error,framing_error\r
        UART,115200.0,0.0001,0.0002,0x41,65,8,false,false\r
        UART,115200.0,0.0003,0.0004,0x0A,10,8,true,true\r

        """)
    }

    @Test
    func `bin contains only valid decoded bytes`() throws {
        let output = try DecodeWriter().data(for: sampleResult, format: .bin)

        #expect(output == Data([0x41]))
    }

    @Test
    func `bin rejects words wider than one byte`() {
        let result = UARTDecodeResult(
            baudRate: 9600,
            frames: [
                UARTFrame(
                    startTime: 0,
                    endTime: 1,
                    value: 0x1FF,
                    dataBits: 9,
                    parityError: false,
                    framingError: false,
                ),
            ],
        )

        #expect(throws: DecodeOutputError.binaryWordTooWide(dataBits: 9)) {
            try DecodeWriter().data(for: result, format: .bin)
        }
    }

    @Test
    func `writer atomically creates the requested file`() throws {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("rigol2spice-decode-\(UUID().uuidString).bin")
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let byteCount = try DecodeWriter().write(sampleResult, format: .bin, to: outputURL)

        #expect(byteCount == 1)
        #expect(try Data(contentsOf: outputURL) == Data([0x41]))
    }

    @Test
    func `I2C text CSV and bin preserve protocol semantics`() throws {
        let address = I2CFrame(
            transaction: 0, index: 0, startTime: 1, endTime: 2, value: 0xA0,
            acknowledged: true, isAddress: true, address: 0x50, read: false,
        )
        let payload = I2CFrame(
            transaction: 0, index: 1, startTime: 3, endTime: 4, value: 0x42,
            acknowledged: false, isAddress: false, address: nil, read: nil,
        )
        let result = ProtocolDecodeResult.i2c(I2CDecodeResult(transactions: [
            I2CTransaction(index: 0, startTime: 0, endTime: 5, repeatedStart: false, frames: [address, payload]),
        ]))

        let text = try #require(String(data: DecodeWriter().data(for: result, format: .text), encoding: .utf8))
        let csv = try #require(String(data: DecodeWriter().data(for: result, format: .csv), encoding: .utf8))
        #expect(text.contains("address=0x50 direction=write"))
        #expect(text.contains("repeatedStart=false"))
        #expect(text.contains("byte=0x42"))
        #expect(csv.contains(",0xA0,160,address,0x50,write,true"))
        #expect(try DecodeWriter().data(for: result, format: .bin) == Data([0x42]))
    }

    @Test
    func `SPI output contains MOSI and MISO and bin prefers MOSI`() throws {
        let result = ProtocolDecodeResult.spi(SPIDecodeResult(
            mode: 2,
            bitOrder: .msb,
            frames: [SPIFrame(index: 0, startTime: 1, endTime: 2, bitCount: 8, mosi: 0x12, miso: 0x34)],
        ))

        let text = try #require(String(data: DecodeWriter().data(for: result, format: .text), encoding: .utf8))
        let csv = try #require(String(data: DecodeWriter().data(for: result, format: .csv), encoding: .utf8))
        #expect(text.contains("SPI mode=2 order=msb"))
        #expect(text.contains("mosi=0x12 miso=0x34"))
        #expect(csv.contains("SPI,2,msb,0,1.0,2.0,8,0x12,0x34"))
        #expect(try DecodeWriter().data(for: result, format: .bin) == Data([0x12]))
    }

    private var sampleResult: UARTDecodeResult {
        UARTDecodeResult(
            baudRate: 115_200,
            frames: [
                UARTFrame(
                    startTime: 0.0001,
                    endTime: 0.0002,
                    value: 0x41,
                    dataBits: 8,
                    parityError: false,
                    framingError: false,
                ),
                UARTFrame(
                    startTime: 0.0003,
                    endTime: 0.0004,
                    value: 0x0A,
                    dataBits: 8,
                    parityError: true,
                    framingError: true,
                ),
            ],
        )
    }
}
