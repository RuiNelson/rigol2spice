import Foundation

// MARK: - ProtocolDecodeResult

enum ProtocolDecodeResult: Equatable {
    case uart(UARTDecodeResult)
    case i2c(I2CDecodeResult)
    case spi(SPIDecodeResult)
}

// MARK: - I2CFrame

struct I2CFrame: Equatable {
    let transaction: Int
    let index: Int
    let startTime: Double
    let endTime: Double
    let value: UInt8
    let acknowledged: Bool
    let isAddress: Bool
    let address: UInt8?
    let read: Bool?
}

// MARK: - I2CTransaction

struct I2CTransaction: Equatable {
    let index: Int
    let startTime: Double
    let endTime: Double?
    let repeatedStart: Bool
    let frames: [I2CFrame]
}

// MARK: - I2CDecodeResult

struct I2CDecodeResult: Equatable {
    let transactions: [I2CTransaction]

    var frames: [I2CFrame] {
        transactions.flatMap(\.frames)
    }
}

// MARK: - I2CDecodeError

enum I2CDecodeError: LocalizedError, Equatable {
    case noTransactions

    var errorDescription: String? {
        switch self {
        case .noTransactions: "No complete I2C transactions were found"
        }
    }
}

// MARK: - I2CDecoder

struct I2CDecoder {
    struct Configuration: Equatable {
        var sdaThreshold: Double
        var sclThreshold: Double
        var hysteresis: Double

        init(threshold: Double, hysteresis: Double = 0) {
            self.sdaThreshold = threshold
            self.sclThreshold = threshold
            self.hysteresis = hysteresis
        }

        init(sdaThreshold: Double, sclThreshold: Double, hysteresis: Double = 0) {
            self.sdaThreshold = sdaThreshold
            self.sclThreshold = sclThreshold
            self.hysteresis = hysteresis
        }
    }

    let configuration: Configuration

    func decode(sdaPoints: [Point], sclPoints: [Point]) throws -> I2CDecodeResult {
        let sda = try DigitalSignal.from(
            points: sdaPoints,
            threshold: configuration.sdaThreshold,
            hysteresis: configuration.hysteresis,
        )
        let scl = try DigitalSignal.from(
            points: sclPoints,
            threshold: configuration.sclThreshold,
            hysteresis: configuration.hysteresis,
        )

        enum EventKind { case sda(DigitalLogicLevel), sclRise }
        struct Event { let time: Double; let kind: EventKind }
        var events = sda.edges.map { Event(time: $0.time, kind: .sda($0.level)) }
        events += scl.edges.compactMap { edge in
            edge.level == .high ? Event(time: edge.time, kind: .sclRise) : nil
        }
        events.sort { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            if case .sda = lhs.kind { return true }
            return false
        }

        struct PendingTransaction {
            var index: Int
            var startTime: Double
            var repeatedStart: Bool
            var frames: [I2CFrame]
            var bits: [Bool]
            var byteStart: Double?
        }

        var completed: [I2CTransaction] = []
        var pending: PendingTransaction?
        var nextIndex = 0

        func finish(_ current: PendingTransaction, at time: Double?) -> I2CTransaction {
            I2CTransaction(
                index: current.index,
                startTime: current.startTime,
                endTime: time,
                repeatedStart: current.repeatedStart,
                frames: current.frames,
            )
        }

        for event in events {
            switch event.kind {
            case let .sda(level):
                guard scl.level(at: event.time) == .high else { continue }
                if level == .low { // START or repeated START
                    if let current = pending {
                        completed.append(finish(current, at: event.time))
                    }
                    pending = PendingTransaction(
                        index: nextIndex,
                        startTime: event.time,
                        repeatedStart: pending != nil,
                        frames: [],
                        bits: [],
                        byteStart: nil,
                    )
                    nextIndex += 1
                }
                else if let current = pending { // STOP
                    completed.append(finish(current, at: event.time))
                    pending = nil
                }

            case .sclRise:
                guard var current = pending else { continue }
                if current.bits.isEmpty { current.byteStart = event.time }
                current.bits.append(sda.level(at: event.time) == .high)
                if current.bits.count == 9 {
                    var value: UInt8 = 0
                    for bit in current.bits.prefix(8) {
                        value = (value << 1) | (bit ? 1 : 0)
                    }
                    let isAddress = current.frames.isEmpty
                    current.frames.append(I2CFrame(
                        transaction: current.index,
                        index: current.frames.count,
                        startTime: current.byteStart ?? event.time,
                        endTime: event.time,
                        value: value,
                        acknowledged: !current.bits[8],
                        isAddress: isAddress,
                        address: isAddress ? value >> 1 : nil,
                        read: isAddress ? value & 1 == 1 : nil,
                    ))
                    current.bits.removeAll(keepingCapacity: true)
                    current.byteStart = nil
                }
                pending = current
            }
        }
        if let current = pending, !current.frames.isEmpty {
            completed.append(finish(current, at: nil))
        }
        let result = I2CDecodeResult(transactions: completed.filter { !$0.frames.isEmpty })
        guard !result.transactions.isEmpty else { throw I2CDecodeError.noTransactions }
        return result
    }
}

// MARK: - SPIBitOrder

enum SPIBitOrder: String, Equatable {
    case msb
    case lsb
}

// MARK: - SPIFrame

struct SPIFrame: Equatable {
    let index: Int
    let startTime: Double
    let endTime: Double
    let bitCount: Int
    let mosi: UInt64?
    let miso: UInt64?
}

// MARK: - SPIDecodeResult

struct SPIDecodeResult: Equatable {
    let mode: Int
    let bitOrder: SPIBitOrder
    let frames: [SPIFrame]
}

// MARK: - SPIDecodeError

enum SPIDecodeError: LocalizedError, Equatable {
    case missingDataSignal
    case invalidMode
    case invalidBitCount
    case noFrames

    var errorDescription: String? {
        switch self {
        case .missingDataSignal: "SPI requires MOSI and/or MISO"
        case .invalidMode: "SPI mode must be between 0 and 3"
        case .invalidBitCount: "SPI word size must be between 1 and 64 bits"
        case .noFrames: "No complete SPI words were found"
        }
    }
}

// MARK: - SPIDecoder

struct SPIDecoder {
    struct Configuration: Equatable {
        var mode: Int
        var bitCount: Int
        var bitOrder: SPIBitOrder
        var threshold: Double
        var hysteresis: Double
        var chipSelectActiveHigh: Bool
    }

    let configuration: Configuration

    func decode(
        clockPoints: [Point],
        mosiPoints: [Point]?,
        misoPoints: [Point]?,
        chipSelectPoints: [Point]?,
    ) throws -> SPIDecodeResult {
        guard (0 ... 3).contains(configuration.mode) else { throw SPIDecodeError.invalidMode }
        guard (1 ... 64).contains(configuration.bitCount) else { throw SPIDecodeError.invalidBitCount }
        guard mosiPoints != nil || misoPoints != nil else { throw SPIDecodeError.missingDataSignal }

        let clock = try DigitalSignal.from(
            points: clockPoints,
            threshold: configuration.threshold,
            hysteresis: configuration.hysteresis,
        )
        let mosi = try mosiPoints.map {
            try DigitalSignal.from(points: $0, threshold: configuration.threshold, hysteresis: configuration.hysteresis)
        }
        let miso = try misoPoints.map {
            try DigitalSignal.from(points: $0, threshold: configuration.threshold, hysteresis: configuration.hysteresis)
        }
        let chipSelect = try chipSelectPoints.map {
            try DigitalSignal.from(points: $0, threshold: configuration.threshold, hysteresis: configuration.hysteresis)
        }

        let clockIdleHigh = configuration.mode >= 2
        let sampleLeadingEdge = configuration.mode.isMultiple(of: 2)
        let sampleLevel: DigitalLogicLevel = if sampleLeadingEdge {
            clockIdleHigh ? .low : .high
        }
        else {
            clockIdleHigh ? .high : .low
        }

        func selected(_ level: DigitalLogicLevel) -> Bool {
            let high = level == .high
            return configuration.chipSelectActiveHigh ? high : !high
        }

        enum EventKind { case clock(DigitalEdge), chipSelect(DigitalLogicLevel) }
        struct Event { let time: Double; let kind: EventKind }
        var events = clock.edges.map { Event(time: $0.time, kind: .clock($0)) }
        if let chipSelect {
            events += chipSelect.edges.map { Event(time: $0.time, kind: .chipSelect($0.level)) }
        }
        events.sort { lhs, rhs in
            if lhs.time != rhs.time { return lhs.time < rhs.time }
            if case .chipSelect = lhs.kind { return true }
            return false
        }

        var frames: [SPIFrame] = []
        var sampledBits = 0
        var mosiValue: UInt64 = 0
        var misoValue: UInt64 = 0
        var wordStart: Double?
        var isSelected = chipSelect.map { selected($0.initialLevel) } ?? true

        for event in events {
            if case let .chipSelect(level) = event.kind {
                isSelected = selected(level)
                sampledBits = 0
                mosiValue = 0
                misoValue = 0
                wordStart = nil
                continue
            }
            guard case let .clock(edge) = event.kind, isSelected else { continue }
            guard edge.level == sampleLevel else { continue }
            if wordStart == nil { wordStart = edge.time }

            func append(_ high: Bool, to value: inout UInt64) {
                switch configuration.bitOrder {
                case .msb: value = (value << 1) | (high ? 1 : 0)
                case .lsb where high: value |= UInt64(1) << UInt64(sampledBits)
                case .lsb: break
                }
            }
            if let mosi { append(mosi.level(at: edge.time) == .high, to: &mosiValue) }
            if let miso { append(miso.level(at: edge.time) == .high, to: &misoValue) }
            sampledBits += 1

            if sampledBits == configuration.bitCount {
                frames.append(SPIFrame(
                    index: frames.count,
                    startTime: wordStart ?? edge.time,
                    endTime: edge.time,
                    bitCount: configuration.bitCount,
                    mosi: mosi == nil ? nil : mosiValue,
                    miso: miso == nil ? nil : misoValue,
                ))
                sampledBits = 0
                mosiValue = 0
                misoValue = 0
                wordStart = nil
            }
        }

        guard !frames.isEmpty else { throw SPIDecodeError.noFrames }
        return SPIDecodeResult(mode: configuration.mode, bitOrder: configuration.bitOrder, frames: frames)
    }
}

// MARK: - Plot annotations

extension ProtocolDecodeResult {
    var plotTitle: String {
        switch self {
        case let .uart(result): "UART · \(String(format: "%.12g", result.baudRate)) baud"
        case let .i2c(result): "I2C · \(result.transactions.count) transaction(s)"
        case let .spi(result): "SPI mode \(result.mode) · \(result.bitOrder.rawValue) first"
        }
    }

    var plotAnnotations: [PlotAnnotation] {
        switch self {
        case let .uart(result):
            result.frames.map { frame in
                var suffixes: [String] = []
                if frame.parityError { suffixes.append("PARITY") }
                if frame.framingError { suffixes.append("FRAMING") }
                let suffix = suffixes.isEmpty ? "" : " · " + suffixes.joined(separator: "+")
                let digits = max(1, (frame.dataBits + 3) / 4)
                return PlotAnnotation(
                    startTime: frame.startTime,
                    endTime: frame.endTime,
                    label: "0x\(String(format: "%0*X", digits, frame.value))\(suffix)",
                    isError: frame.parityError || frame.framingError,
                )
            }
        case let .i2c(result):
            result.frames.map { frame in
                let acknowledgement = frame.acknowledged ? "ACK" : "NACK"
                let label = if let address = frame.address, let read = frame.read {
                    "ADDR 0x\(String(format: "%02X", address)) \(read ? "R" : "W") · \(acknowledgement)"
                }
                else {
                    "0x\(String(format: "%02X", frame.value)) · \(acknowledgement)"
                }
                return PlotAnnotation(
                    startTime: frame.startTime,
                    endTime: frame.endTime,
                    label: label,
                    isError: false,
                )
            }
        case let .spi(result):
            result.frames.map { frame in
                let digits = max(1, (frame.bitCount + 3) / 4)
                var fields: [String] = []
                if let mosi = frame.mosi { fields.append("MOSI 0x\(String(format: "%0*llX", digits, mosi))") }
                if let miso = frame.miso { fields.append("MISO 0x\(String(format: "%0*llX", digits, miso))") }
                return PlotAnnotation(
                    startTime: frame.startTime,
                    endTime: frame.endTime,
                    label: fields.joined(separator: " · "),
                    isError: false,
                )
            }
        }
    }
}
