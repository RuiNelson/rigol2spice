import Foundation

// MARK: - WAVEncoding

enum WAVEncoding: Equatable {
    case float32
    case pcm16

    var formatTag: UInt16 {
        switch self {
        case .float32: 3 // WAVE_FORMAT_IEEE_FLOAT
        case .pcm16: 1 // WAVE_FORMAT_PCM
        }
    }

    var bitsPerSample: UInt16 {
        switch self {
        case .float32: 32
        case .pcm16: 16
        }
    }

    var bytesPerSample: UInt16 {
        bitsPerSample / 8
    }
}

// MARK: - WAVWriterError

enum WAVWriterError: LocalizedError, Equatable {
    case insufficientSamples
    case invalidTimestamp(index: Int, value: Double)
    case nonIncreasingTimestamps(index: Int)
    case nonIntegralSampleRate(estimated: Double, suggested: UInt32?)
    case nonUniformTimestamps(index: Int, suggestedRate: UInt32)
    case sampleRateOutOfRange(estimated: Double)
    case sampleOutOfRange(index: Int, value: Double)
    case nonFiniteSample(index: Int)
    case fileTooLarge

    var errorDescription: String? {
        switch self {
        case .insufficientSamples:
            "WAV output requires at least two samples. Adjust the transformations to retain more points."
        case let .invalidTimestamp(index, value):
            "WAV output requires finite timestamps, but sample \(index) has timestamp \(value). Use ResampleF to create a valid sampling grid."
        case let .nonIncreasingTimestamps(index):
            "WAV output requires strictly increasing timestamps (failed at sample \(index)). Use ResampleF to create a uniform sampling grid."
        case let .nonIntegralSampleRate(estimated, suggested):
            if let suggested {
                "WAV requires a whole-number sampling rate, but the processed signal is approximately \(estimated) Sa/s. Add `ResampleF \(suggested)` as the final transformation."
            }
            else {
                "WAV requires a whole-number sampling rate, but the processed signal is approximately \(estimated) Sa/s. Add ResampleF as the final transformation."
            }
        case let .nonUniformTimestamps(index, suggestedRate):
            "WAV requires uniformly spaced samples, but timestamp \(index) is off the sampling grid. Add `ResampleF \(suggestedRate)` as the final transformation."
        case let .sampleRateOutOfRange(estimated):
            "WAV sampling rate \(estimated) Sa/s is outside the supported 32-bit range. Add ResampleF with a lower whole-number frequency."
        case let .sampleOutOfRange(index, value):
            "WAV samples must be within -1...1, but sample \(index) is \(value). Normalize explicitly, for example with `PeakTo 1`."
        case let .nonFiniteSample(index):
            "WAV samples must be finite, but sample \(index) is not. Adjust the transformation pipeline before WAV conversion."
        case .fileTooLarge:
            "WAV output exceeds the 4 GiB RIFF size limit. Downsample the signal before conversion."
        }
    }
}

// MARK: - WAVWriter

struct WAVWriter {
    let encoding: WAVEncoding

    func write(_ points: [Point], to outputURL: URL) throws -> Int {
        let sampleRate = try Self.sampleRate(for: points)
        try Self.validateSamples(points)

        let bytesPerSample = Int(encoding.bytesPerSample)
        let (sampleDataSize, dataSizeOverflow) = points.count.multipliedReportingOverflow(by: bytesPerSample)
        guard !dataSizeOverflow, sampleDataSize <= Int(UInt32.max) else {
            throw WAVWriterError.fileTooLarge
        }

        let formatChunkSize = encoding == .float32 ? 18 : 16
        let factChunkSize = encoding == .float32 ? 12 : 0
        let (fileSize, fileSizeOverflow) = 12
            .addingReportingOverflow(8 + formatChunkSize + factChunkSize + 8 + sampleDataSize)
        guard !fileSizeOverflow, fileSize - 8 <= Int(UInt32.max) else {
            throw WAVWriterError.fileTooLarge
        }

        let blockAlign = encoding.bytesPerSample
        let (byteRate, byteRateOverflow) = sampleRate.multipliedReportingOverflow(by: UInt32(blockAlign))
        guard !byteRateOverflow else {
            throw WAVWriterError.sampleRateOutOfRange(estimated: Double(sampleRate))
        }

        var data = Data()
        data.reserveCapacity(fileSize)
        data.appendASCII("RIFF")
        data.appendLittleEndian(UInt32(fileSize - 8))
        data.appendASCII("WAVE")

        data.appendASCII("fmt ")
        data.appendLittleEndian(UInt32(formatChunkSize))
        data.appendLittleEndian(encoding.formatTag)
        data.appendLittleEndian(UInt16(1))
        data.appendLittleEndian(sampleRate)
        data.appendLittleEndian(byteRate)
        data.appendLittleEndian(blockAlign)
        data.appendLittleEndian(encoding.bitsPerSample)
        if encoding == .float32 {
            data.appendLittleEndian(UInt16(0))
            data.appendASCII("fact")
            data.appendLittleEndian(UInt32(4))
            data.appendLittleEndian(UInt32(points.count))
        }

        data.appendASCII("data")
        data.appendLittleEndian(UInt32(sampleDataSize))
        for point in points {
            switch encoding {
            case .float32:
                data.appendLittleEndian(Float32(point.value).bitPattern)
            case .pcm16:
                let scale = point.value < 0 ? 32768.0 : 32767.0
                data.appendLittleEndian(Int16((point.value * scale).rounded()))
            }
        }

        try data.write(to: outputURL, options: .atomic)
        return data.count
    }

    static func sampleRate(for points: [Point]) throws -> UInt32 {
        guard points.count >= 2 else {
            throw WAVWriterError.insufficientSamples
        }
        for (index, point) in points.enumerated() where !point.time.isFinite {
            throw WAVWriterError.invalidTimestamp(index: index, value: point.time)
        }
        for index in 1 ..< points.count where points[index].time <= points[index - 1].time {
            throw WAVWriterError.nonIncreasingTimestamps(index: index)
        }

        let duration = points[points.count - 1].time - points[0].time
        let estimatedRate = Double(points.count - 1) / duration
        guard estimatedRate.isFinite, estimatedRate >= 1, estimatedRate <= Double(UInt32.max) else {
            throw WAVWriterError.sampleRateOutOfRange(estimated: estimatedRate)
        }

        let roundedRate = estimatedRate.rounded()
        let rateTolerance = max(1e-6, abs(estimatedRate) * 1e-6)
        guard abs(estimatedRate - roundedRate) <= rateTolerance else {
            let suggested = roundedRate >= 1 && roundedRate <= Double(UInt32.max) ? UInt32(roundedRate) : nil
            throw WAVWriterError.nonIntegralSampleRate(estimated: estimatedRate, suggested: suggested)
        }

        let sampleRate = UInt32(roundedRate)
        let interval = 1 / Double(sampleRate)
        let scale = max(abs(points[0].time), abs(points[points.count - 1].time), duration, interval)
        let timestampTolerance = max(interval * 1e-5, scale * Double.ulpOfOne * 64)
        for index in points.indices {
            let expected = points[0].time + Double(index) * interval
            if abs(points[index].time - expected) > timestampTolerance {
                throw WAVWriterError.nonUniformTimestamps(index: index, suggestedRate: sampleRate)
            }
        }
        return sampleRate
    }

    private static func validateSamples(_ points: [Point]) throws {
        for (index, point) in points.enumerated() {
            guard point.value.isFinite else {
                throw WAVWriterError.nonFiniteSample(index: index)
            }
            guard point.value >= -1, point.value <= 1 else {
                throw WAVWriterError.sampleOutOfRange(index: index, value: point.value)
            }
        }
    }
}

private extension Data {
    mutating func appendASCII(_ string: String) {
        append(contentsOf: string.utf8)
    }

    mutating func appendLittleEndian(_ value: some FixedWidthInteger) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { bytes in
            append(contentsOf: bytes)
        }
    }
}
