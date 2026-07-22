import Foundation

// MARK: - DecodeOutputError

enum DecodeOutputError: LocalizedError, Equatable {
    case binaryWordTooWide(dataBits: Int)

    var errorDescription: String? {
        switch self {
        case let .binaryWordTooWide(dataBits):
            "Cannot write a \(dataBits)-bit decoded word to bin output; only words up to 8 bits are supported"
        }
    }
}

// MARK: - DecodeWriter

struct DecodeWriter {
    func data(for result: UARTDecodeResult, format: DecodeFormat) throws -> Data {
        try data(for: .uart(result), format: format)
    }

    func data(for result: ProtocolDecodeResult, format: DecodeFormat) throws -> Data {
        switch format {
        case .text: Data(renderText(result).utf8)
        case .csv: Data(renderCSV(result).utf8)
        case .bin: try renderBinary(result)
        }
    }

    @discardableResult
    func write(_ result: UARTDecodeResult, format: DecodeFormat, to outputURL: URL) throws -> Int {
        try write(.uart(result), format: format, to: outputURL)
    }

    @discardableResult
    func write(_ result: ProtocolDecodeResult, format: DecodeFormat, to outputURL: URL) throws -> Int {
        let output = try data(for: result, format: format)
        try output.write(to: outputURL, options: .atomic)
        return output.count
    }

    private func renderText(_ result: ProtocolDecodeResult) -> String {
        let lines = switch result {
        case let .uart(result):
            ["UART baud=\(number(result.baudRate))"] + result.frames.map { frame in
                var fields = [
                    "start=\(number(frame.startTime))", "end=\(number(frame.endTime))",
                    "byte=\(hexadecimal(frame.value, bits: frame.dataBits))", "decimal=\(frame.value)",
                ]
                if let ascii = decodedASCII(UInt64(frame.value), bitCount: frame.dataBits) {
                    fields.append("ascii=\"\(ascii)\"")
                }
                fields += [
                    "dataBits=\(frame.dataBits)", "parityError=\(frame.parityError)",
                    "framingError=\(frame.framingError)",
                ]
                return fields.joined(separator: " ")
            }
        case let .i2c(result):
            ["I2C transactions=\(result.transactions.count)"] + result.transactions.flatMap { transaction in
                let transactionLine = [
                    "transaction=\(transaction.index)", "start=\(number(transaction.startTime))",
                    "end=\(transaction.endTime.map(number) ?? "open")",
                    "repeatedStart=\(transaction.repeatedStart)",
                ].joined(separator: " ")
                let frameLines = transaction.frames.map { frame in
                    var fields = [
                        "transaction=\(frame.transaction)", "index=\(frame.index)",
                        "start=\(number(frame.startTime))", "end=\(number(frame.endTime))",
                        "byte=\(hexadecimal(UInt16(frame.value), bits: 8))", "decimal=\(frame.value)",
                        "ack=\(frame.acknowledged)", "type=\(frame.isAddress ? "address" : "data")",
                    ]
                    if let address = frame.address {
                        fields.append("address=\(hexadecimal(UInt16(address), bits: 7))")
                    }
                    else if let ascii = decodedASCII(UInt64(frame.value)) {
                        fields.append("ascii=\"\(ascii)\"")
                    }
                    if let read = frame.read { fields.append("direction=\(read ? "read" : "write")") }
                    return fields.joined(separator: " ")
                }
                return [transactionLine] + frameLines
            }
        case let .spi(result):
            ["SPI mode=\(result.mode) order=\(result.bitOrder.rawValue)"] + result.frames.map { frame in
                var fields = [
                    "index=\(frame.index)", "start=\(number(frame.startTime))", "end=\(number(frame.endTime))",
                    "bits=\(frame.bitCount)",
                ]
                if let mosi = frame.mosi {
                    fields.append("mosi=\(hexadecimal(mosi, bits: frame.bitCount))")
                    if let ascii = decodedASCII(mosi, bitCount: frame.bitCount) {
                        fields.append("mosiASCII=\"\(ascii)\"")
                    }
                }
                if let miso = frame.miso {
                    fields.append("miso=\(hexadecimal(miso, bits: frame.bitCount))")
                    if let ascii = decodedASCII(miso, bitCount: frame.bitCount) {
                        fields.append("misoASCII=\"\(ascii)\"")
                    }
                }
                return fields.joined(separator: " ")
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func renderCSV(_ result: ProtocolDecodeResult) -> String {
        let lines = switch result {
        case let .uart(result):
            ["protocol,baud,start_time_s,end_time_s,byte_hex,byte_decimal,ascii,data_bits,parity_error,framing_error"]
                + result.frames.map { frame in
                    csv([
                        "UART", number(result.baudRate), number(frame.startTime), number(frame.endTime),
                        hexadecimal(frame.value, bits: frame.dataBits), String(frame.value),
                        decodedASCII(UInt64(frame.value), bitCount: frame.dataBits) ?? "",
                        String(frame.dataBits), String(frame.parityError), String(frame.framingError),
                    ])
                }
        case let .i2c(result):
            [
                "protocol,transaction,transaction_start_s,transaction_end_s,repeated_start,index,start_time_s,end_time_s,byte_hex,byte_decimal,ascii,type,address_hex,direction,ack",
            ]
                + result.transactions.flatMap { transaction in
                    transaction.frames.map { frame in
                        csv([
                            "I2C", String(frame.transaction), number(transaction.startTime),
                            transaction.endTime.map(number) ?? "", String(transaction.repeatedStart),
                            String(frame.index), number(frame.startTime), number(frame.endTime),
                            hexadecimal(UInt16(frame.value), bits: 8), String(frame.value),
                            frame.isAddress ? "" : decodedASCII(UInt64(frame.value)) ?? "",
                            frame.isAddress ? "address" : "data",
                            frame.address.map { hexadecimal(UInt16($0), bits: 7) } ?? "",
                            frame.read.map { $0 ? "read" : "write" } ?? "", String(frame.acknowledged),
                        ])
                    }
                }
        case let .spi(result):
            ["protocol,mode,bit_order,index,start_time_s,end_time_s,bits,mosi_hex,mosi_ascii,miso_hex,miso_ascii"]
                + result.frames.map { frame in
                    csv([
                        "SPI", String(result.mode), result.bitOrder.rawValue, String(frame.index),
                        number(frame.startTime), number(frame.endTime), String(frame.bitCount),
                        frame.mosi.map { hexadecimal($0, bits: frame.bitCount) } ?? "",
                        frame.mosi.flatMap { decodedASCII($0, bitCount: frame.bitCount) } ?? "",
                        frame.miso.map { hexadecimal($0, bits: frame.bitCount) } ?? "",
                        frame.miso.flatMap { decodedASCII($0, bitCount: frame.bitCount) } ?? "",
                    ])
                }
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private func renderBinary(_ result: ProtocolDecodeResult) throws -> Data {
        switch result {
        case let .uart(result):
            for frame in result.frames where frame.dataBits > 8 {
                throw DecodeOutputError.binaryWordTooWide(dataBits: frame.dataBits)
            }
            return Data(result.frames.compactMap { frame in
                guard !frame.parityError, !frame.framingError else { return nil }
                return frame.byte
            })
        case let .i2c(result):
            return Data(result.frames.filter { !$0.isAddress }.map(\.value))
        case let .spi(result):
            guard let bitCount = result.frames.first?.bitCount, bitCount <= 8 else {
                throw DecodeOutputError.binaryWordTooWide(dataBits: result.frames.first?.bitCount ?? 0)
            }
            return Data(result.frames.compactMap { frame in
                (frame.mosi ?? frame.miso).map(UInt8.init)
            })
        }
    }

    private func number(_ value: Double) -> String {
        String(value)
    }

    private func hexadecimal(_ value: some BinaryInteger, bits: Int) -> String {
        let digitCount = max(1, (bits + 3) / 4)
        return "0x" + String(value, radix: 16, uppercase: true)
            .leftPadding(toLength: digitCount, withPad: "0")
    }

    private func csv(_ fields: [String]) -> String {
        fields.map(csvField).joined(separator: ",")
    }

    private func csvField(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }) else {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}

private extension String {
    func leftPadding(toLength: Int, withPad pad: Character) -> String {
        guard count < toLength else { return self }
        return String(repeating: String(pad), count: toLength - count) + self
    }
}
