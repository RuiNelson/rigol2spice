import Foundation

// MARK: - DigitalLogicLevel

enum DigitalLogicLevel: Int, Equatable {
    case low = 0
    case high = 1
}

// MARK: - DigitalEdge

struct DigitalEdge: Equatable {
    let time: Double
    let level: DigitalLogicLevel
}

// MARK: - DigitalSignal

/// An edge-based representation of an analogue waveform.
///
/// Threshold crossings are linearly interpolated, so decoding does not add a
/// complete sample interval of timing error. A non-zero hysteresis uses
/// `threshold - hysteresis / 2` and `threshold + hysteresis / 2` as the falling
/// and rising thresholds respectively.
struct DigitalSignal: Equatable {
    let initialLevel: DigitalLogicLevel
    let edges: [DigitalEdge]
    let startTime: Double
    let endTime: Double

    static func from(
        points: [Point],
        threshold: Double,
        hysteresis: Double = 0,
        inverted: Bool = false,
    ) throws -> DigitalSignal {
        guard threshold.isFinite, hysteresis.isFinite, hysteresis >= 0 else {
            throw UARTDecodeError.invalidThreshold
        }
        guard let first = points.first, let last = points.last else {
            throw UARTDecodeError.insufficientSamples
        }
        guard points.allSatisfy({ $0.time.isFinite && $0.value.isFinite }) else {
            throw UARTDecodeError.nonFiniteSample
        }
        guard zip(points, points.dropFirst()).allSatisfy({ $0.time < $1.time }) else {
            throw UARTDecodeError.nonIncreasingTime
        }

        let lower = threshold - hysteresis / 2
        let upper = threshold + hysteresis / 2
        var level: DigitalLogicLevel = first.value >= threshold ? .high : .low
        let initialLevel = inverted ? level.inverted : level
        var edges: [DigitalEdge] = []
        var previous = first

        for point in points.dropFirst() {
            let crossingThreshold: Double? = switch level {
            case .low where point.value >= upper:
                upper
            case .high where point.value <= lower:
                lower
            default:
                nil
            }

            if let crossingThreshold {
                let valueSpan = point.value - previous.value
                let fraction = valueSpan == 0 ? 1 : (crossingThreshold - previous.value) / valueSpan
                let clampedFraction = min(1, max(0, fraction))
                let crossingTime = previous.time + clampedFraction * (point.time - previous.time)
                level = level == .low ? .high : .low
                edges.append(DigitalEdge(time: crossingTime, level: inverted ? level.inverted : level))
            }
            previous = point
        }

        return DigitalSignal(
            initialLevel: initialLevel,
            edges: edges,
            startTime: first.time,
            endTime: last.time,
        )
    }

    func level(at time: Double) -> DigitalLogicLevel {
        var low = 0
        var high = edges.count
        while low < high {
            let middle = (low + high) / 2
            if edges[middle].time <= time {
                low = middle + 1
            }
            else {
                high = middle
            }
        }
        return low == 0 ? initialLevel : edges[low - 1].level
    }
}

private extension DigitalLogicLevel {
    var inverted: DigitalLogicLevel {
        self == .low ? .high : .low
    }
}

// MARK: - UARTParity

enum UARTParity: String, Equatable {
    case none
    case even
    case odd
}

// MARK: - UARTBaudRate

enum UARTBaudRate: Equatable {
    case explicit(Double)
    case automatic
}

// MARK: - UARTFrame

struct UARTFrame: Equatable {
    let startTime: Double
    let endTime: Double
    let value: UInt16
    let dataBits: Int
    let parityError: Bool
    let framingError: Bool

    var byte: UInt8? {
        guard dataBits <= 8, value <= UInt8.max else { return nil }
        return UInt8(value)
    }
}

// MARK: - UARTDecodeResult

struct UARTDecodeResult: Equatable {
    let baudRate: Double
    let frames: [UARTFrame]
}

// MARK: - UARTDecodeError

enum UARTDecodeError: LocalizedError, Equatable {
    case insufficientSamples
    case nonFiniteSample
    case nonIncreasingTime
    case invalidThreshold
    case invalidBaudRate
    case invalidDataBits
    case invalidStopBits
    case baudRateDetectionFailed

    var errorDescription: String? {
        switch self {
        case .insufficientSamples: "Not enough samples to decode UART"
        case .nonFiniteSample: "UART input contains a non-finite sample"
        case .nonIncreasingTime: "UART sample times must be strictly increasing"
        case .invalidThreshold: "UART threshold and hysteresis must be finite, and hysteresis cannot be negative"
        case .invalidBaudRate: "UART baud rate must be finite and greater than zero"
        case .invalidDataBits: "UART data bits must be between 5 and 9"
        case .invalidStopBits: "UART stop bits must be 1, 1.5, or 2"
        case .baudRateDetectionFailed: "Unable to detect the UART baud rate"
        }
    }
}

// MARK: - UARTDecoder

struct UARTDecoder {
    struct Configuration: Equatable {
        var baudRate: UARTBaudRate
        var threshold: Double
        var hysteresis: Double
        var dataBits: Int
        var parity: UARTParity
        var stopBits: Double
        var inverted: Bool

        init(
            baudRate: UARTBaudRate = .automatic,
            threshold: Double,
            hysteresis: Double = 0,
            dataBits: Int = 8,
            parity: UARTParity = .none,
            stopBits: Double = 1,
            inverted: Bool = false,
        ) {
            self.baudRate = baudRate
            self.threshold = threshold
            self.hysteresis = hysteresis
            self.dataBits = dataBits
            self.parity = parity
            self.stopBits = stopBits
            self.inverted = inverted
        }
    }

    let configuration: Configuration

    func decode(points: [Point]) throws -> UARTDecodeResult {
        try validateConfiguration()
        let signal = try DigitalSignal.from(
            points: points,
            threshold: configuration.threshold,
            hysteresis: configuration.hysteresis,
            inverted: configuration.inverted,
        )
        let baudRate: Double = switch configuration.baudRate {
        case let .explicit(value):
            value
        case .automatic:
            try detectBaudRate(signal: signal, points: points)
        }
        return UARTDecodeResult(baudRate: baudRate, frames: decode(signal: signal, baudRate: baudRate))
    }

    private func validateConfiguration() throws {
        if case let .explicit(value) = configuration.baudRate,
           !value.isFinite || value <= 0 {
            throw UARTDecodeError.invalidBaudRate
        }
        guard (5 ... 9).contains(configuration.dataBits) else {
            throw UARTDecodeError.invalidDataBits
        }
        guard [1.0, 1.5, 2.0].contains(configuration.stopBits) else {
            throw UARTDecodeError.invalidStopBits
        }
    }

    private func decode(signal: DigitalSignal, baudRate: Double) -> [UARTFrame] {
        let bitDuration = 1 / baudRate
        let parityBitCount = configuration.parity == .none ? 0 : 1
        let frameDuration = (1 + Double(configuration.dataBits + parityBitCount) + configuration.stopBits) * bitDuration
        let fallingEdges = signal.edges.enumerated().filter { index, edge in
            edge.level == .low && (index > 0 ? signal.edges[index - 1].level : signal.initialLevel) == .high
        }.map(\.element)
        var frames: [UARTFrame] = []
        var unavailableUntil = -Double.infinity

        for edge in fallingEdges where edge.time >= unavailableUntil - bitDuration * 0.1 {
            let startTime = edge.time
            let endTime = startTime + frameDuration
            guard endTime <= signal.endTime + bitDuration * 0.05 else { continue }
            guard signal.level(at: startTime + bitDuration * 0.5) == .low else { continue }

            var value: UInt16 = 0
            var ones = 0
            for bitIndex in 0 ..< configuration.dataBits {
                if signal.level(at: startTime + (1.5 + Double(bitIndex)) * bitDuration) == .high {
                    value |= UInt16(1) << UInt16(bitIndex)
                    ones += 1
                }
            }

            var parityError = false
            if configuration.parity != .none {
                let parityHigh = signal.level(
                    at: startTime + (1.5 + Double(configuration.dataBits)) * bitDuration,
                ) == .high
                let totalIsOdd = (ones + (parityHigh ? 1 : 0)) % 2 == 1
                parityError = configuration.parity == .even ? totalIsOdd : !totalIsOdd
            }

            let stopStart = 1 + Double(configuration.dataBits + parityBitCount)
            let framingError = signal.level(
                at: startTime + (stopStart + configuration.stopBits / 2) * bitDuration,
            ) != .high
            frames.append(UARTFrame(
                startTime: startTime,
                endTime: endTime,
                value: value,
                dataBits: configuration.dataBits,
                parityError: parityError,
                framingError: framingError,
            ))
            unavailableUntil = endTime - bitDuration * 0.1
        }
        return frames
    }

    private func detectBaudRate(signal: DigitalSignal, points: [Point]) throws -> Double {
        let edgeIntervals = zip(signal.edges, signal.edges.dropFirst())
            .map { $1.time - $0.time }
            .filter { $0.isFinite && $0 > 0 }
        guard edgeIntervals.count >= 2 else { throw UARTDecodeError.baudRateDetectionFailed }

        let sampleIntervals = zip(points, points.dropFirst()).map { $1.time - $0.time }.sorted()
        guard let sampleInterval = sampleIntervals.dropFirst(sampleIntervals.count / 2).first else {
            throw UARTDecodeError.baudRateDetectionFailed
        }
        let minimumBitDuration = sampleInterval * 2
        var candidates: [Double] = []
        for interval in edgeIntervals {
            for divisor in 1 ... 12 {
                let candidate = interval / Double(divisor)
                if candidate >= minimumBitDuration {
                    candidates.append(candidate)
                }
            }
        }

        struct Estimate {
            let duration: Double
            let residual: Double
            let coverage: Double
            let validFrames: Int
            let frames: Int
        }
        let estimates = candidates.map { candidate -> Estimate in
            let residuals = edgeIntervals.map { interval -> Double in
                let multiple = min(12, max(1, (interval / candidate).rounded()))
                return abs(interval / candidate - multiple)
            }
            let sortedResiduals = residuals.sorted()
            let medianResidual = sortedResiduals[sortedResiduals.count / 2]
            let coverage = Double(residuals.count(where: { $0 < 0.12 })) / Double(residuals.count)
            let frames = decode(signal: signal, baudRate: 1 / candidate)
            let validFrames = frames.count(where: { !$0.framingError && !$0.parityError })
            return Estimate(
                duration: candidate,
                residual: medianResidual,
                coverage: coverage,
                validFrames: validFrames,
                frames: frames.count,
            )
        }
        let plausible = estimates.filter {
            $0.residual < 0.12 && $0.coverage >= 0.65 && $0.frames > 0 && $0.validFrames > 0
        }
        guard let maximumQuality = plausible.map({ $0.coverage - $0.residual }).max() else {
            throw UARTDecodeError.baudRateDetectionFailed
        }
        // Integer submultiples of the real bit period also quantise edge gaps
        // perfectly. Of similarly good fits, UART's fundamental is the largest
        // period; choosing by decoded-frame count would incorrectly favour those
        // faster harmonics because they manufacture more apparent start bits.
        guard let best = (plausible
            .filter { $0.coverage - $0.residual >= maximumQuality - 0.02 }
            .max(by: { $0.duration < $1.duration })) else {
            throw UARTDecodeError.baudRateDetectionFailed
        }
        return 1 / best.duration
    }
}
