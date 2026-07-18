import Foundation

// MARK: - DS1000ZWFMParser

// The DS1000Z layout and voltage conversion implemented here follow the
// reverse-engineered RigolWFM schema:
// https://github.com/scottprahl/RigolWFM/blob/1.5.0/ksy/rigol_1000z_wfm.ksy

struct DS1000ZWFMParser: CaptureParser {
    func parse(_ data: Data, channel requestedChannel: String?) throws -> Capture {
        let reader = WFMByteReader(data)
        let header = try parseHeader(reader)
        let enabledChannels = header.channels.filter(\.enabled)
        guard !enabledChannels.isEmpty else {
            throw ParseError.noChannelsDetected
        }

        let recordStride = enabledChannels.count == 3 ? 4 : enabledChannels.count
        guard header.memoryDepth > 0,
              header.memoryDepth.isMultiple(of: recordStride),
              header.sampleRate > 0,
              header.sampleRate.isFinite else {
            throw ParseError.invalidFileFormat
        }

        let pointCount = header.memoryDepth / recordStride
        let dataOffset = try checkedSum(header.horizontalOffset, header.horizontalSize)
        let dataEnd = try checkedSum(dataOffset, header.memoryDepth)
        guard dataEnd <= data.count else {
            throw ParseError.invalidFileFormat
        }

        let channelNames = enabledChannels.map(\.name)
        let metadata = CaptureMetadata(
            format: "Rigol DS1000Z WFM",
            model: header.model,
            firmware: header.firmware,
            fileVersion: header.fileVersion,
            structureVersion: header.structureVersion,
            acquisitionMode: header.acquisitionMode,
            timeMode: header.timeMode,
            horizontalScale: header.horizontalScale,
            horizontalOffset: header.horizontalOffsetSeconds,
            memoryDepth: header.memoryDepth,
            rawDataOffset: dataOffset,
            channels: enabledChannels.map(\.metadata),
            voltageConversion: "DS1000Z empirical: volts/div ÷ 20 with firmware-dependent offset",
        )

        guard let requestedChannel else {
            return Capture(
                channels: channelNames,
                selectedChannel: nil,
                points: [],
                sampleInterval: 1 / header.sampleRate,
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

        let enabledByName = Dictionary(
            uniqueKeysWithValues: enabledChannels.map { ($0.name.lowercased(), $0) },
        )
        for name in expression.channelNames {
            guard enabledByName[name.lowercased()] != nil else {
                throw ParseError.channelNotFound(channelLabel: name)
            }
        }

        let rawPayload = Array(data[dataOffset ..< dataEnd])
        let decodedChannels = Dictionary(
            uniqueKeysWithValues: enabledChannels.map { channel in
                let lane = laneOffset(
                    for: channel.number,
                    enabledChannelNumbers: enabledChannels.map(\.number),
                    stride: recordStride,
                )
                let raw = Swift.stride(from: lane, to: rawPayload.count, by: recordStride).map { rawPayload[$0] }
                return (channel.name.lowercased(), WFMDecodedChannel(header: channel, raw: raw))
            },
        )

        let sampleInterval = 1 / header.sampleRate
        let selectedLabel: String
        let points: [Point]
        if case let .channel(name) = expression,
           let selected = decodedChannels[name.lowercased()] {
            selectedLabel = selected.header.name
            points = selected.raw.enumerated().map { index, raw in
                Point(
                    time: Double(index) * sampleInterval,
                    value: selected.header.voltage(
                        for: raw,
                        firmware: header.firmware,
                        enabledChannelCount: enabledChannels.count,
                    ),
                )
            }
        }
        else {
            selectedLabel = requestedChannel.trimmingCharacters(in: .whitespacesAndNewlines)
            var evaluated: [Point] = []
            evaluated.reserveCapacity(pointCount)

            for index in 0 ..< pointCount {
                do {
                    let value = try expression.evaluate { name in
                        guard let decoded = decodedChannels[name.lowercased()] else {
                            return nil
                        }
                        return decoded.header.voltage(
                            for: decoded.raw[index],
                            firmware: header.firmware,
                            enabledChannelCount: enabledChannels.count,
                        )
                    }
                    evaluated.append(Point(time: Double(index) * sampleInterval, value: value))
                }
                catch ChannelExpressionError.divisionByZero {
                    throw ParseError.divisionByZero
                }
            }
            points = evaluated
        }

        return Capture(
            channels: channelNames,
            selectedChannel: selectedLabel,
            points: points,
            sampleInterval: sampleInterval,
            metadata: metadata,
        )
    }

    private func parseHeader(_ reader: WFMByteReader) throws -> WFMHeader {
        guard try reader.bytes(at: 0, count: 4) == CaptureFormat.ds1000ZWFMRequestMagic,
              try [0xA5A5, 0xA5A6].contains(reader.uint16(at: 4)),
              try reader.uint16(at: 6) == 0x38,
              try reader.bytes(at: 0x30, count: 2) == [0x01, 0x00],
              try reader.uint16(at: 0x54) == 0x00D8 else {
            throw ParseError.invalidFileFormat
        }

        let enabledMask = try reader.uint8(at: 0x58)
        let channelHeaders = try (0 ..< 4).map { index in
            let offset = 0x7C + index * 28
            return try WFMChannelHeader(
                number: index + 1,
                enabled: enabledMask & (1 << index) != 0,
                couplingCode: reader.uint8(at: offset + 1),
                bandwidthCode: reader.uint8(at: offset + 2),
                probeCode: reader.uint8(at: offset + 4),
                scale: Double(reader.float32(at: offset + 8)),
                shift: Double(reader.float32(at: offset + 12)),
                inverted: reader.uint8(at: offset + 16) != 0,
                unitCode: reader.uint8(at: offset + 17),
            )
        }

        let sampleRateGHz = try Double(reader.float32(at: 0x78))
        let picosecondsPerDivision = try reader.uint64(at: 0x40)
        let picosecondsOffset = try Int64(bitPattern: reader.uint64(at: 0x48))

        return try WFMHeader(
            model: reader.ascii(at: 0x08, count: 20),
            firmware: reader.ascii(at: 0x1C, count: 20),
            fileVersion: reader.uint16(at: 0x32),
            structureVersion: reader.uint16(at: 0x56),
            acquisitionMode: acquisitionModeName(reader.uint8(at: 0x70)),
            timeMode: timeModeName(reader.uint8(at: 0x73)),
            horizontalScale: Double(picosecondsPerDivision) * 1e-12,
            horizontalOffsetSeconds: Double(picosecondsOffset) * 1e-12,
            memoryDepth: Int(reader.uint32(at: 0x74)),
            sampleRate: sampleRateGHz * 1e9,
            horizontalSize: Int(reader.uint32(at: 0x100)),
            horizontalOffset: Int(reader.uint32(at: 0x104)),
            channels: channelHeaders,
        )
    }

    private func checkedSum(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow, result >= 0 else {
            throw ParseError.invalidFileFormat
        }
        return result
    }

    private func laneOffset(
        for channelNumber: Int,
        enabledChannelNumbers: [Int],
        stride: Int,
    ) -> Int {
        switch stride {
        case 1:
            0
        case 2:
            enabledChannelNumbers.sorted(by: >).firstIndex(of: channelNumber) ?? 0
        default:
            // Four-lane records are always CH4, CH3, CH2, CH1; disabled lanes
            // remain present when exactly three channels are enabled.
            4 - channelNumber
        }
    }

    private func acquisitionModeName(_ code: UInt8) -> String {
        switch code {
        case 0: "Normal"
        case 1: "Peak detect"
        case 2: "Average"
        case 3: "High resolution"
        default: "Unknown (\(code))"
        }
    }

    private func timeModeName(_ code: UInt8) -> String {
        switch code {
        case 0: "Y-T"
        case 1: "X-Y"
        case 2: "Roll"
        default: "Unknown (\(code))"
        }
    }
}

// MARK: - WFMHeader

private struct WFMHeader {
    let model: String
    let firmware: String
    let fileVersion: UInt16
    let structureVersion: UInt16
    let acquisitionMode: String
    let timeMode: String
    let horizontalScale: Double
    let horizontalOffsetSeconds: Double
    let memoryDepth: Int
    let sampleRate: Double
    let horizontalSize: Int
    let horizontalOffset: Int
    let channels: [WFMChannelHeader]
}

// MARK: - WFMChannelHeader

private struct WFMChannelHeader {
    let number: Int
    let enabled: Bool
    let couplingCode: UInt8
    let bandwidthCode: UInt8
    let probeCode: UInt8
    let scale: Double
    let shift: Double
    let inverted: Bool
    let unitCode: UInt8

    var name: String {
        "CH\(number)"
    }

    var coupling: String {
        switch couplingCode {
        case 0: "DC"
        case 1: "AC"
        case 2: "GND"
        default: "Unknown (\(couplingCode))"
        }
    }

    var bandwidth: String {
        switch bandwidthCode {
        case 0: "20 MHz"
        case 1: "No limit"
        default: "Unknown (\(bandwidthCode))"
        }
    }

    var probeRatio: Double {
        let values = [0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]
        guard values.indices.contains(Int(probeCode)) else {
            return 1
        }
        return values[Int(probeCode)]
    }

    var unit: String {
        switch unitCode {
        case 0: "W"
        case 1: "A"
        case 2: "V"
        default: "unknown"
        }
    }

    var metadata: CaptureChannelMetadata {
        CaptureChannelMetadata(
            name: name,
            coupling: coupling,
            bandwidth: bandwidth,
            probeRatio: probeRatio,
            voltsPerDivision: scale,
            verticalOffset: shift,
            inverted: inverted,
            unit: unit,
        )
    }

    func voltage(for raw: UInt8, firmware: String, enabledChannelCount: Int) -> Double {
        let voltsPerDivision = inverted ? -scale : scale
        let verticalBias: Double = if firmware == "00.04.04.SP3", enabledChannelCount == 2 {
            shift < 0 ? voltsPerDivision / 5 : 0
        }
        else {
            voltsPerDivision
        }
        let yScale = -voltsPerDivision / 20
        let yOffset = shift - verticalBias
        return yScale * (127 - Double(raw)) - yOffset
    }
}

// MARK: - WFMDecodedChannel

private struct WFMDecodedChannel {
    let header: WFMChannelHeader
    let raw: [UInt8]
}

// MARK: - WFMByteReader

private struct WFMByteReader {
    private let data: Data

    init(_ data: Data) {
        self.data = data
    }

    func uint8(at offset: Int) throws -> UInt8 {
        guard offset >= 0, offset < data.count else {
            throw ParseError.invalidFileFormat
        }
        return data[data.index(data.startIndex, offsetBy: offset)]
    }

    func uint16(at offset: Int) throws -> UInt16 {
        let bytes = try bytes(at: offset, count: 2)
        return UInt16(bytes[0]) | UInt16(bytes[1]) << 8
    }

    func uint32(at offset: Int) throws -> UInt32 {
        let bytes = try bytes(at: offset, count: 4)
        return bytes.enumerated().reduce(0) { result, item in
            result | UInt32(item.element) << UInt32(item.offset * 8)
        }
    }

    func uint64(at offset: Int) throws -> UInt64 {
        let bytes = try bytes(at: offset, count: 8)
        return bytes.enumerated().reduce(0) { result, item in
            result | UInt64(item.element) << UInt64(item.offset * 8)
        }
    }

    func float32(at offset: Int) throws -> Float {
        try Float(bitPattern: uint32(at: offset))
    }

    func bytes(at offset: Int, count: Int) throws -> [UInt8] {
        guard offset >= 0, count >= 0 else {
            throw ParseError.invalidFileFormat
        }
        let (end, overflow) = offset.addingReportingOverflow(count)
        guard !overflow, end <= data.count else {
            throw ParseError.invalidFileFormat
        }
        return Array(data[offset ..< end])
    }

    func ascii(at offset: Int, count: Int) throws -> String {
        let source = try bytes(at: offset, count: count)
        let terminated = source.prefix { $0 != 0 }
        guard terminated.allSatisfy({ $0 < 0x80 }) else {
            throw ParseError.invalidFileFormat
        }
        return String(decoding: terminated, as: UTF8.self)
    }
}
