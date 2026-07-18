import Foundation

// MARK: - RigolWFMFamily

/// Rigol-only WFM signatures and family dispatch. The layouts follow the
/// Kaitai Struct schemas pinned in Reference/RigolWFM.
enum RigolWFMFamily: Equatable {
    case ds1000B
    case ds1000C
    case ds1000DE
    case ds1000Z
    case ds2000
    case ds4000

    var magic: [UInt8] {
        switch self {
        case .ds1000B: [0xA5, 0xA5, 0xA4, 0x01]
        case .ds1000C,
             .ds1000DE: [0xA5, 0xA5, 0x00, 0x00]
        case .ds1000Z: [0x01, 0xFF, 0xFF, 0xFF]
        case .ds2000,
             .ds4000: [0xA5, 0xA5, 0x38, 0x00]
        }
    }

    var displayName: String {
        switch self {
        case .ds1000B: "DS1000B"
        case .ds1000C: "DS1000C"
        case .ds1000DE: "DS1000D/E"
        case .ds1000Z: "DS1000Z"
        case .ds2000: "DS2000/MSO2000"
        case .ds4000: "DS4000/MSO4000"
        }
    }

    static func detect(in data: Data) -> RigolWFMFamily? {
        guard data.count >= 4 else {
            return nil
        }

        let magic = Array(data.prefix(4))
        if magic == RigolWFMFamily.ds1000B.magic {
            return .ds1000B
        }
        if magic == RigolWFMFamily.ds1000Z.magic {
            return .ds1000Z
        }
        if magic[1...] == [0xA5, 0x00, 0x00], magic[0] == 0xA1 {
            return .ds1000C
        }
        if magic == RigolWFMFamily.ds1000DE.magic {
            return distinguishDS1000CFromDE(data)
        }
        if magic == RigolWFMFamily.ds2000.magic,
           let model = try? WFMByteReader(data).ascii(at: 4, count: 20) {
            let upper = model.uppercased()
            if upper.hasPrefix("DS2") || upper.hasPrefix("MSO2") {
                return .ds2000
            }
            if upper.hasPrefix("DS4") || upper.hasPrefix("MSO4") {
                return .ds4000
            }
        }
        return nil
    }

    private static func distinguishDS1000CFromDE(_ data: Data) -> RigolWFMFamily {
        let reader = WFMByteReader(data)
        guard let points = try? reader.uint32(at: 28), points > 0,
              let ch1 = try? reader.uint8(at: 49),
              let ch2 = try? reader.uint8(at: 73) else {
            return .ds1000DE
        }

        let channelCount = (ch1 != 0 ? 1 : 0) + (ch2 != 0 ? 1 : 0)
        guard channelCount > 0 else {
            return .ds1000DE
        }
        let payloadSize = channelCount * Int(points)
        if data.count == 256 + payloadSize || data.count == 272 + payloadSize {
            return .ds1000C
        }
        return .ds1000DE
    }
}

// MARK: - RigolWFMParser

struct RigolWFMParser: CaptureParser {
    func parse(_ data: Data, channel: String?) throws -> Capture {
        guard let family = RigolWFMFamily.detect(in: data) else {
            throw ParseError.invalidFileFormat
        }

        switch family {
        case .ds1000Z:
            return try DS1000ZWFMParser().parse(data, channel: channel)
        default:
            return try AdditionalRigolWFMParser(family: family).parse(data, channel: channel)
        }
    }
}

// MARK: - AdditionalRigolWFMParser

private struct AdditionalRigolWFMParser: CaptureParser {
    let family: RigolWFMFamily

    func parse(_ data: Data, channel requestedChannel: String?) throws -> Capture {
        let decoded = try decode(data)
        guard !decoded.channels.isEmpty else {
            throw ParseError.noChannelsDetected
        }

        let channelNames = decoded.channels.map(\.name)
        let metadata = decoded.metadata
        guard let requestedChannel else {
            return Capture(
                channels: channelNames,
                selectedChannel: nil,
                points: [],
                sampleInterval: decoded.sampleInterval,
                metadata: metadata,
            )
        }

        let expression: ChannelExpression
        do {
            expression = try parseChannelExpression(requestedChannel)
        }
        catch let error as ChannelExpressionError {
            throw ParseError.invalidChannelExpression(error.errorDescription ?? String(describing: error))
        }

        let channelsByName = Dictionary(
            uniqueKeysWithValues: decoded.channels.map { ($0.name.lowercased(), $0) },
        )
        for name in expression.channelNames where channelsByName[name.lowercased()] == nil {
            throw ParseError.channelNotFound(channelLabel: name)
        }

        let selectedLabel: String
        let pointCount: Int
        if case let .channel(name) = expression,
           let selected = channelsByName[name.lowercased()] {
            selectedLabel = selected.name
            pointCount = selected.layout.pointCount
        }
        else {
            selectedLabel = requestedChannel.trimmingCharacters(in: .whitespacesAndNewlines)
            pointCount = expression.channelNames.compactMap {
                channelsByName[$0.lowercased()]?.layout.pointCount
            }.min() ?? 0
        }

        var points: [Point] = []
        points.reserveCapacity(pointCount)
        for index in 0 ..< pointCount {
            let value: Double
            do {
                value = try expression.evaluate { name in
                    guard let selected = channelsByName[name.lowercased()] else {
                        return nil
                    }
                    return selected.voltage(at: index, in: data)
                }
            }
            catch ChannelExpressionError.divisionByZero {
                throw ParseError.divisionByZero
            }
            points.append(Point(time: Double(index) * decoded.sampleInterval, value: value))
        }

        return Capture(
            channels: channelNames,
            selectedChannel: selectedLabel,
            points: points,
            sampleInterval: decoded.sampleInterval,
            metadata: metadata,
        )
    }

    private func decode(_ data: Data) throws -> DecodedRigolWFM {
        switch family {
        case .ds1000B: try decodeDS1000B(data)
        case .ds1000C: try decodeDS1000C(data)
        case .ds1000DE: try decodeDS1000DE(data)
        case .ds2000: try decodeDS2000(data)
        case .ds4000: try decodeDS4000(data)
        case .ds1000Z: throw ParseError.invalidFileFormat
        }
    }

    private func decodeDS1000B(_ data: Data) throws -> DecodedRigolWFM {
        let reader = WFMByteReader(data)
        guard try reader.bytes(at: 0, count: 4) == family.magic else {
            throw ParseError.invalidFileFormat
        }

        let points = try Int(reader.uint32(at: 60))
        let sampleRate = try Double(reader.float32(at: 180))
        let sampleInterval = try validatedSampleInterval(sampleRate: sampleRate)
        let timeScale = try Double(reader.uint64(at: 164)) * 1e-12
        let timeOffset = try Double(reader.int64(at: 172)) * 1e-12
        let coupling12 = try reader.uint8(at: 216)
        let coupling34 = try reader.uint8(at: 217)

        var channels: [DecodedWFMChannel] = []
        for index in 0 ..< 4 {
            let base = 68 + index * 24
            guard try reader.uint8(at: base + 14) != 0 else {
                continue
            }
            let probe = try Double(reader.float32(at: base + 8))
            let inverted = try reader.uint8(at: base + 15) != 0
            let measuredScale = try Double(reader.int32(at: base + 16)) * 1e-6 * probe
            let signedScale = inverted ? -measuredScale : measuredScale
            let voltageScale = signedScale / 25
            let displayedOffset = try Double(reader.int16(at: base + 20)) * voltageScale
            let conversionOffset = displayedOffset + 1.12 * signedScale
            let couplingByte = index < 2 ? coupling12 : coupling34
            let couplingMask: UInt8 = index.isMultiple(of: 2) ? 0xC0 : 0x0C
            let coupling = couplingByte & couplingMask == couplingMask ? "DC" : "AC"
            let layout = WFMRawLayout.contiguous(offset: 420 + index * points, count: points)
            try layout.validate(in: data)
            channels.append(
                decodedChannel(
                    number: index + 1,
                    layout: layout,
                    coupling: coupling,
                    probe: probe,
                    voltsPerDivision: abs(measuredScale),
                    verticalOffset: displayedOffset,
                    inverted: inverted,
                    coefficient: voltageScale,
                    conversionOffset: conversionOffset,
                ),
            )
        }

        return try decodedFile(
            family: family,
            model: reader.ascii(at: 4, count: 8),
            firmware: "unknown",
            fileVersion: 0,
            structureVersion: 0,
            acquisitionMode: acquisitionName(reader.uint8(at: 56)),
            timeMode: "Y-T",
            horizontalScale: timeScale,
            horizontalOffset: timeOffset,
            memoryDepth: points,
            rawDataOffset: 420,
            channels: channels,
            sampleInterval: sampleInterval,
            conversion: "DS1000B: inverted 8-bit ADC, 25 counts/div with family bias correction",
        )
    }

    private func decodeDS1000C(_ data: Data) throws -> DecodedRigolWFM {
        let reader = WFMByteReader(data)
        guard try reader.bytes(at: 1, count: 3) == [0xA5, 0x00, 0x00] else {
            throw ParseError.invalidFileFormat
        }

        let points = try Int(reader.uint32(at: 28))
        let sampleRate = try Double(reader.float32(at: 100))
        let sampleInterval = try validatedSampleInterval(sampleRate: sampleRate)
        let timeScale = try Double(reader.uint64(at: 84)) * 1e-12
        let timeOffset = try Double(reader.int64(at: 92)) * 1e-12
        var dataOffset = try reader.uint8(at: 0) == 0xA5 ? 272 : 256
        let firstDataOffset = dataOffset
        var channels: [DecodedWFMChannel] = []

        for index in 0 ..< 2 {
            let base = 36 + index * 24
            guard try reader.uint8(at: base + 13) != 0 else {
                continue
            }
            let probe = try Double(reader.float32(at: base + 8))
            let inverted = try reader.uint8(at: base + 14) != 0
            let measuredScale = try Double(reader.int32(at: base + 16)) * 1e-6 * probe
            let signedScale = inverted ? -measuredScale : measuredScale
            let voltageScale = signedScale / 25
            let displayedOffset = try Double(reader.int16(at: base + 20)) * voltageScale
            let layout = WFMRawLayout.contiguous(offset: dataOffset, count: points)
            try layout.validate(in: data)
            dataOffset += points
            channels.append(
                decodedChannel(
                    number: index + 1,
                    layout: layout,
                    probe: probe,
                    voltsPerDivision: abs(measuredScale),
                    verticalOffset: displayedOffset,
                    inverted: inverted,
                    coefficient: voltageScale,
                    conversionOffset: displayedOffset,
                    midpoint: 125,
                ),
            )
        }

        return try decodedFile(
            family: family,
            model: "DS1000C family",
            firmware: "unknown",
            acquisitionMode: "Unknown",
            timeMode: "Y-T",
            horizontalScale: timeScale,
            horizontalOffset: timeOffset,
            memoryDepth: points,
            rawDataOffset: firstDataOffset,
            channels: channels,
            sampleInterval: sampleInterval,
            conversion: "DS1000C: inverted 8-bit ADC, 25 counts/div and midpoint 125",
        )
    }

    private func decodeDS1000DE(_ data: Data) throws -> DecodedRigolWFM {
        let reader = WFMByteReader(data)
        guard try reader.bytes(at: 0, count: 4) == family.magic else {
            throw ParseError.invalidFileFormat
        }

        let ch1Depth = try Int(reader.uint32(at: 28))
        let rollStop = try Int(reader.uint32(at: 20))
        let skipped = rollStop == 0 ? 0 : rollStop + 2
        let sampleRate = try Double(reader.float32(at: 100))
        let sampleInterval = try validatedSampleInterval(sampleRate: sampleRate)
        let timeScale = try Double(reader.int64(at: 104)) * 1e-12
        let timeOffset = try Double(reader.int64(at: 112)) * 1e-12
        let ch2StoredDepth = try Int(reader.uint32(at: 231))
        var dataOffset = 276
        var channels: [DecodedWFMChannel] = []
        var maximumDepth = ch1Depth

        for index in 0 ..< 2 {
            let base = 34 + index * 24
            guard try reader.uint8(at: base + 15) != 0 else {
                continue
            }
            let probe = try Double(reader.float32(at: base + 10))
            let inverted = try reader.uint8(at: base + 16) != 0
            let measuredScale = try Double(reader.int32(at: base + 18)) * 1e-6 * probe
            let voltageScale = measuredScale / 25
            let displayedOffset = try Double(reader.int16(at: base + 22)) * voltageScale
            let depth = index == 0 ? ch1Depth : (ch2StoredDepth == 0 ? ch1Depth : ch2StoredDepth)
            guard depth >= skipped else {
                throw ParseError.invalidFileFormat
            }
            maximumDepth = max(maximumDepth, depth)
            let layout = WFMRawLayout.contiguous(offset: dataOffset, count: depth - skipped)
            try layout.validate(in: data)
            dataOffset += depth
            channels.append(
                decodedChannel(
                    number: index + 1,
                    layout: layout,
                    probe: probe,
                    voltsPerDivision: abs(measuredScale),
                    verticalOffset: displayedOffset,
                    inverted: inverted,
                    coefficient: voltageScale,
                    conversionOffset: displayedOffset,
                    midpoint: 125,
                ),
            )
        }

        return try decodedFile(
            family: family,
            model: "DS1000D/E family",
            firmware: "unknown",
            acquisitionMode: acquisitionName(reader.uint8(at: 16)),
            timeMode: "Y-T",
            horizontalScale: timeScale,
            horizontalOffset: timeOffset,
            memoryDepth: maximumDepth,
            rawDataOffset: 276,
            channels: channels,
            sampleInterval: sampleInterval,
            conversion: "DS1000D/E: inverted 8-bit ADC, 25 counts/div and midpoint 125",
        )
    }

    private func decodeDS2000(_ data: Data) throws -> DecodedRigolWFM {
        let reader = WFMByteReader(data)
        guard try reader.bytes(at: 0, count: 4) == family.magic else {
            throw ParseError.invalidFileFormat
        }

        let serial = try reader.ascii(at: 4, count: 20)
        guard serial.uppercased().hasPrefix("DS2") || serial.uppercased().hasPrefix("MSO2") else {
            throw ParseError.invalidFileFormat
        }
        let firmware = try reader.ascii(at: 24, count: 20)
        let sampleRate = try Double(reader.float32(at: 96))
        let sampleInterval = try validatedSampleInterval(sampleRate: sampleRate)
        let storedTimeOffset = try Double(reader.int64(at: 112)) * 1e-12
        let storageDepth = try Int(reader.uint32(at: 244))
        let windowOffset = try Int(reader.uint32(at: 248))
        let pointCount = try Int(reader.uint32(at: 252))
        let enabledMask = try reader.uint8(at: 64)
        let interwoven = try reader.uint8(at: 65) & 1 != 0
        let channelOffsets = try (0 ..< 4).map { try Int(reader.uint32(at: 68 + $0 * 4)) }
        let rawDepth = interwoven ? pointCount / 2 : pointCount
        var channels: [DecodedWFMChannel] = []

        for index in 0 ..< 4 {
            let base = 120 + index * 28
            let enabled = try reader.uint8(at: base) != 0
                && enabledMask & (1 << index) != 0
                && channelOffsets[index] > 0
            guard enabled else {
                continue
            }

            let layout: WFMRawLayout
            if interwoven {
                guard channelOffsets[0] > 0, channelOffsets[1] > 0 else {
                    throw ParseError.invalidFileFormat
                }
                layout = .interwoven(
                    firstOffset: channelOffsets[0] + windowOffset,
                    secondOffset: channelOffsets[1] + windowOffset,
                    count: pointCount,
                )
            }
            else {
                layout = .contiguous(offset: channelOffsets[index] + windowOffset, count: rawDepth)
            }
            try layout.validate(in: data)
            try channels.append(decodeModernChannel(reader, base: base, number: index + 1, layout: layout, divisor: 25))
        }

        let rawOffset = try minimumRawOffset(channels)
        return try decodedFile(
            family: family,
            model: "DS2000/MSO2000 family",
            serialNumber: serial,
            firmware: firmware,
            fileVersion: reader.uint16(at: 46),
            structureVersion: reader.uint16(at: 62),
            acquisitionMode: acquisitionName(reader.uint16(at: 84)),
            timeMode: timeModeName(reader.uint16(at: 102)),
            horizontalScale: Double(reader.uint64(at: 104)) * 1e-12,
            horizontalOffset: storedTimeOffset,
            memoryDepth: storageDepth,
            rawDataOffset: rawOffset,
            channels: channels,
            sampleInterval: sampleInterval,
            conversion: "DS2000: normal-polarity 8-bit ADC, 25 counts/div",
        )
    }

    private func decodeDS4000(_ data: Data) throws -> DecodedRigolWFM {
        let reader = WFMByteReader(data)
        guard try reader.bytes(at: 0, count: 4) == family.magic else {
            throw ParseError.invalidFileFormat
        }

        let serial = try reader.ascii(at: 4, count: 20)
        guard serial.uppercased().hasPrefix("DS4") || serial.uppercased().hasPrefix("MSO4") else {
            throw ParseError.invalidFileFormat
        }
        let firmware = try reader.ascii(at: 24, count: 20)
        let sampleRate = try Double(reader.float32(at: 100))
        let sampleInterval = try validatedSampleInterval(sampleRate: sampleRate)
        let pointCount = try Int(reader.uint32(at: 268))
        let enabledMask = try reader.uint8(at: 64)
        let channelOffsets = try (0 ..< 4).map { try Int(reader.uint32(at: 68 + $0 * 4)) }
        var channels: [DecodedWFMChannel] = []

        for index in 0 ..< 4 {
            let base = 124 + index * 28
            let enabled = try reader.uint8(at: base) != 0
                && enabledMask & (1 << index) != 0
                && channelOffsets[index] > 0
            guard enabled else {
                continue
            }
            let layout = WFMRawLayout.contiguous(offset: channelOffsets[index], count: pointCount)
            try layout.validate(in: data)
            try channels.append(decodeModernChannel(reader, base: base, number: index + 1, layout: layout, divisor: 32))
        }

        let rawOffset = try minimumRawOffset(channels)
        return try decodedFile(
            family: family,
            model: "DS4000/MSO4000 family",
            serialNumber: serial,
            firmware: firmware,
            acquisitionMode: "Unknown",
            timeMode: "Y-T",
            horizontalScale: Double(reader.uint32(at: 544)) * 1e-12,
            horizontalOffset: Double(reader.int64(at: 568)) * 1e-12,
            memoryDepth: pointCount,
            rawDataOffset: rawOffset,
            channels: channels,
            sampleInterval: sampleInterval,
            conversion: "DS4000: normal-polarity 8-bit ADC, 32 counts/div",
        )
    }

    private func decodeModernChannel(
        _ reader: WFMByteReader,
        base: Int,
        number: Int,
        layout: WFMRawLayout,
        divisor: Double,
    ) throws -> DecodedWFMChannel {
        let enabledValue = try reader.uint8(at: base)
        let couplingCode = try reader.uint8(at: base + 1) >> 6
        let bandwidthCode = try reader.uint8(at: base + 2)
        let rawProbeCode = try reader.uint8(at: base + 4)
        let impedanceCode = try reader.uint8(at: base + 7)
        let legacyLayout = enabledValue == 1
        let probeCode = !legacyLayout && rawProbeCode == 0 && impedanceCode == 0 ? 6 : rawProbeCode
        let voltsPerDivision = try Double(reader.float32(at: base + 8))
        let verticalOffset = try Double(reader.float32(at: base + 12))
        let invertedByte = try reader.uint8(at: base + (legacyLayout ? 16 : 17))
        let unitByte = try reader.uint8(at: base + (legacyLayout ? 17 : 16))
        let inverted = invertedByte != 0
        let signedScale = inverted ? -voltsPerDivision : voltsPerDivision

        return decodedChannel(
            number: number,
            layout: layout,
            coupling: couplingName(couplingCode),
            bandwidth: bandwidthName(bandwidthCode),
            probe: probeRatio(probeCode),
            voltsPerDivision: abs(voltsPerDivision),
            verticalOffset: verticalOffset,
            inverted: inverted,
            unit: unitName(unitByte),
            coefficient: -signedScale / divisor,
            conversionOffset: verticalOffset,
        )
    }

    private func decodedChannel(
        number: Int,
        layout: WFMRawLayout,
        coupling: String = "Unknown",
        bandwidth: String = "Unknown",
        probe: Double,
        voltsPerDivision: Double,
        verticalOffset: Double,
        inverted: Bool,
        unit: String = "V",
        coefficient: Double,
        conversionOffset: Double,
        midpoint: Double = 127,
    ) -> DecodedWFMChannel {
        DecodedWFMChannel(
            number: number,
            layout: layout,
            coefficient: coefficient,
            conversionOffset: conversionOffset,
            midpoint: midpoint,
            metadata: CaptureChannelMetadata(
                name: "CH\(number)",
                coupling: coupling,
                bandwidth: bandwidth,
                probeRatio: probe,
                voltsPerDivision: voltsPerDivision,
                verticalOffset: verticalOffset,
                inverted: inverted,
                unit: unit,
            ),
        )
    }

    private func decodedFile(
        family: RigolWFMFamily,
        model: String,
        serialNumber: String? = nil,
        firmware: String,
        fileVersion: UInt16 = 0,
        structureVersion: UInt16 = 0,
        acquisitionMode: String,
        timeMode: String,
        horizontalScale: Double,
        horizontalOffset: Double,
        memoryDepth: Int,
        rawDataOffset: Int,
        channels: [DecodedWFMChannel],
        sampleInterval: Double,
        conversion: String,
    ) throws -> DecodedRigolWFM {
        guard memoryDepth > 0,
              rawDataOffset >= 0,
              horizontalScale.isFinite,
              horizontalOffset.isFinite else {
            throw ParseError.invalidFileFormat
        }
        return DecodedRigolWFM(
            channels: channels,
            sampleInterval: sampleInterval,
            metadata: CaptureMetadata(
                format: "Rigol \(family.displayName) WFM",
                model: model,
                serialNumber: serialNumber,
                firmware: firmware,
                fileVersion: fileVersion,
                structureVersion: structureVersion,
                acquisitionMode: acquisitionMode,
                timeMode: timeMode,
                horizontalScale: horizontalScale,
                horizontalOffset: horizontalOffset,
                memoryDepth: memoryDepth,
                rawDataOffset: rawDataOffset,
                channels: channels.map(\.metadata),
                voltageConversion: conversion,
            ),
        )
    }

    private func validatedSampleInterval(sampleRate: Double) throws -> Double {
        try sampleInterval(fromWFMSampleRate: sampleRate)
    }

    private func minimumRawOffset(_ channels: [DecodedWFMChannel]) throws -> Int {
        guard let result = channels.map(\.layout.firstOffset).min() else {
            throw ParseError.noChannelsDetected
        }
        return result
    }

    private func acquisitionName(_ code: some BinaryInteger) -> String {
        switch Int(code) {
        case 0: "Normal"
        case 1: "Average"
        case 2: "Peak detect"
        case 3: "High resolution"
        default: "Unknown (\(code))"
        }
    }

    private func timeModeName(_ code: UInt16) -> String {
        switch code {
        case 0: "Y-T"
        case 1: "X-Y"
        case 2: "Roll"
        default: "Unknown (\(code))"
        }
    }

    private func couplingName(_ code: UInt8) -> String {
        switch code {
        case 0: "DC"
        case 1: "AC"
        case 2: "GND"
        default: "Unknown (\(code))"
        }
    }

    private func bandwidthName(_ code: UInt8) -> String {
        switch code {
        case 0: "No limit"
        case 1: "20 MHz"
        case 2: "100 MHz"
        case 3: "200 MHz"
        case 4: "250 MHz"
        default: "Unknown (\(code))"
        }
    }

    private func probeRatio(_ code: UInt8) -> Double {
        let values = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]
        guard values.indices.contains(Int(code)) else {
            return 1
        }
        return values[Int(code)]
    }

    private func unitName(_ code: UInt8) -> String {
        switch code {
        case 0: "W"
        case 1: "A"
        case 2: "V"
        default: "unknown"
        }
    }
}

// MARK: - DecodedRigolWFM

private struct DecodedRigolWFM {
    let channels: [DecodedWFMChannel]
    let sampleInterval: Double
    let metadata: CaptureMetadata
}

// MARK: - DecodedWFMChannel

private struct DecodedWFMChannel {
    let number: Int
    let layout: WFMRawLayout
    let coefficient: Double
    let conversionOffset: Double
    let midpoint: Double
    let metadata: CaptureChannelMetadata

    var name: String {
        "CH\(number)"
    }

    func voltage(at index: Int, in data: Data) -> Double? {
        guard let raw = layout.byte(at: index, in: data) else {
            return nil
        }
        return coefficient * (midpoint - Double(raw)) - conversionOffset
    }
}

// MARK: - WFMRawLayout

private enum WFMRawLayout {
    case contiguous(offset: Int, count: Int)
    case interwoven(firstOffset: Int, secondOffset: Int, count: Int)

    var pointCount: Int {
        switch self {
        case let .contiguous(_, count),
             let .interwoven(_, _, count): count
        }
    }

    var firstOffset: Int {
        switch self {
        case let .contiguous(offset, _): offset
        case let .interwoven(firstOffset, secondOffset, _): min(firstOffset, secondOffset)
        }
    }

    func byte(at index: Int, in data: Data) -> UInt8? {
        guard index >= 0, index < pointCount else {
            return nil
        }
        let offset: Int = switch self {
        case let .contiguous(offset, _):
            offset + index
        case let .interwoven(firstOffset, secondOffset, _):
            (index.isMultiple(of: 2) ? firstOffset : secondOffset) + index / 2
        }
        guard offset >= 0, offset < data.count else {
            return nil
        }
        return data[data.index(data.startIndex, offsetBy: offset)]
    }

    func validate(in data: Data) throws {
        let ranges: [(offset: Int, count: Int)] = switch self {
        case let .contiguous(offset, count):
            [(offset, count)]
        case let .interwoven(firstOffset, secondOffset, count):
            [(firstOffset, (count + 1) / 2), (secondOffset, count / 2)]
        }
        for range in ranges {
            let (end, overflow) = range.offset.addingReportingOverflow(range.count)
            guard range.offset >= 0, range.count >= 0, !overflow, end <= data.count else {
                throw ParseError.invalidFileFormat
            }
        }
    }
}
