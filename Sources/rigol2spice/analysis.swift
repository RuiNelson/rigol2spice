import Foundation

// MARK: - AnalysisParseError

enum AnalysisParseError: LocalizedError, Equatable {
    case emptyCommand(index: Int)
    case unknownOperation(name: String)
    case invalidArgumentCount(operation: String, expected: Int, actual: Int)
    case invalidScalar(operation: String, value: String)
    case invalidPositiveInteger(operation: String, value: String)
    case invalidPercentPair(operation: String, low: Double, high: Double)

    var errorDescription: String? {
        switch self {
        case let .emptyCommand(index):
            "Analysis command \(index) is empty"
        case let .unknownOperation(name):
            "Unknown analysis operation: \(name)"
        case let .invalidArgumentCount(operation, expected, actual):
            "\(operation) expects \(expected) argument(s), but received \(actual)"
        case let .invalidScalar(operation, value):
            "Invalid scalar for \(operation): \(value)"
        case let .invalidPositiveInteger(operation, value):
            "\(operation) expects a positive integer point count, but received: \(value)"
        case let .invalidPercentPair(operation, low, high):
            "\(operation) expects 0 ≤ low < high ≤ 100, but received \(low), \(high)"
        }
    }
}

// MARK: - Analysis

/// Independent signal measurements printed to the console (do not alter the capture).
/// Unlike transformations, evaluation order is irrelevant; they always run after transforms.
enum Analysis: Equatable {
    case max
    case min
    case avg
    case dc
    case crossing(Double)
    case frequency
    case rms
    case pkPk
    /// Real FFT over a centered window of up to `pointCount` samples (Hann + zero-pad to 2ⁿ).
    /// `pointCount == nil` means use every sample in the capture.
    case fft(pointCount: Int?)
    case duration
    case points
    case sampleRate
    case interval
    case start
    case end
    case peak
    case amplitude
    case mid
    case acRms
    case stdDev
    case crest
    case median
    case top
    case base
    case overshoot
    case undershoot
    case riseTime(lowPercent: Double, highPercent: Double)
    case fallTime(lowPercent: Double, highPercent: Double)
    case pulseWidth(threshold: Double?)
    case duty(threshold: Double?)
    case period
    case edgeCount(threshold: Double?)
    case jitter(threshold: Double?)
    case integral
    case energy
    case dbm(resistance: Double)



    static func parseList(_ source: String) throws -> [Analysis] {
        let commands = source.split(separator: ";", omittingEmptySubsequences: false)

        return try commands.enumerated().map { index, rawCommand in
            let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                throw AnalysisParseError.emptyCommand(index: index + 1)
            }

            let components = command.split(maxSplits: 1, whereSeparator: \Character.isWhitespace)
            let operation = String(components[0])
            let argumentText = components.count == 2
                ? components[1].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            let arguments = argumentText.isEmpty
                ? []
                : argumentText.split(separator: ",", omittingEmptySubsequences: false).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }

            func requireArgumentCount(_ expected: Int) throws {
                guard arguments.count == expected else {
                    throw AnalysisParseError.invalidArgumentCount(
                        operation: operation,
                        expected: expected,
                        actual: arguments.count,
                    )
                }
            }

            func parseScalarArgument(_ argument: String) throws -> Double {
                guard !argument.contains(where: \Character.isWhitespace),
                      let value = parseEngineeringNotation(argument), value.isFinite else {
                    throw AnalysisParseError.invalidScalar(operation: operation, value: argument)
                }
                return value
            }

            func parseOptionalThreshold() throws -> Double? {
                if arguments.isEmpty {
                    return nil
                }
                try requireArgumentCount(1)
                return try parseScalarArgument(arguments[0])
            }

            func parsePercentPair(defaultLow: Double, defaultHigh: Double) throws -> (Double, Double) {
                if arguments.isEmpty {
                    return (defaultLow, defaultHigh)
                }
                try requireArgumentCount(2)
                let low = try parseScalarArgument(arguments[0])
                let high = try parseScalarArgument(arguments[1])
                guard low >= 0, high <= 100, low < high else {
                    throw AnalysisParseError.invalidPercentPair(operation: operation, low: low, high: high)
                }
                return (low, high)
            }

            func parseOptionalPointCount() throws -> Int? {
                if arguments.isEmpty {
                    return nil
                }
                try requireArgumentCount(1)
                let raw = arguments[0]
                let value = try parseScalarArgument(raw)
                guard value >= 1,
                      value <= Double(Int.max),
                      value == value.rounded(.towardZero) || abs(value - value.rounded()) < 1e-12 else {
                    throw AnalysisParseError.invalidPositiveInteger(operation: operation, value: raw)
                }
                return Int(value.rounded())
            }


            switch operation.lowercased() {
            case "max", "hipeak":
                try requireArgumentCount(0)
                return .max
            case "min", "lowpeak":
                try requireArgumentCount(0)
                return .min
            case "avg":
                try requireArgumentCount(0)
                return .avg
            case "dc":
                try requireArgumentCount(0)
                return .dc
            case "crossing":
                try requireArgumentCount(1)
                return .crossing(try parseScalarArgument(arguments[0]))
            case "zerocrossing":
                try requireArgumentCount(0)
                return .crossing(0)
            case "frequency":
                try requireArgumentCount(0)
                return .frequency
            case "rms":
                try requireArgumentCount(0)
                return .rms
            case "pkpk":
                try requireArgumentCount(0)
                return .pkPk
            case "fft":
                return .fft(pointCount: try parseOptionalPointCount())
            case "duration":
                try requireArgumentCount(0)
                return .duration
            case "points":
                try requireArgumentCount(0)
                return .points
            case "samplerate":
                try requireArgumentCount(0)
                return .sampleRate
            case "interval":
                try requireArgumentCount(0)
                return .interval
            case "start":
                try requireArgumentCount(0)
                return .start
            case "end":
                try requireArgumentCount(0)
                return .end
            case "peak":
                try requireArgumentCount(0)
                return .peak
            case "amplitude":
                try requireArgumentCount(0)
                return .amplitude
            case "mid":
                try requireArgumentCount(0)
                return .mid
            case "acrms":
                try requireArgumentCount(0)
                return .acRms
            case "stddev", "stdev":
                try requireArgumentCount(0)
                return .stdDev
            case "crest":
                try requireArgumentCount(0)
                return .crest
            case "median":
                try requireArgumentCount(0)
                return .median
            case "top":
                try requireArgumentCount(0)
                return .top
            case "base":
                try requireArgumentCount(0)
                return .base
            case "overshoot":
                try requireArgumentCount(0)
                return .overshoot
            case "undershoot":
                try requireArgumentCount(0)
                return .undershoot
            case "risetime":
                let pair = try parsePercentPair(defaultLow: 10, defaultHigh: 90)
                return .riseTime(lowPercent: pair.0, highPercent: pair.1)
            case "falltime":
                let pair = try parsePercentPair(defaultLow: 10, defaultHigh: 90)
                return .fallTime(lowPercent: pair.0, highPercent: pair.1)
            case "pulsewidth":
                return .pulseWidth(threshold: try parseOptionalThreshold())
            case "duty":
                return .duty(threshold: try parseOptionalThreshold())
            case "period":
                try requireArgumentCount(0)
                return .period
            case "edgecount":
                return .edgeCount(threshold: try parseOptionalThreshold())
            case "jitter", "periodstd":
                return .jitter(threshold: try parseOptionalThreshold())
            case "integral":
                try requireArgumentCount(0)
                return .integral
            case "energy":
                try requireArgumentCount(0)
                return .energy
            case "dbm":
                if arguments.isEmpty {
                    return .dbm(resistance: powerReferenceResistance)
                }
                try requireArgumentCount(1)
                let resistance = try parseScalarArgument(arguments[0])
                guard resistance > 0 else {
                    throw AnalysisParseError.invalidScalar(operation: operation, value: arguments[0])
                }
                return .dbm(resistance: resistance)

            default:
                throw AnalysisParseError.unknownOperation(name: operation)
            }

        }
    }


    var label: String {
        switch self {
        case .max: "Max"
        case .min: "Min"
        case .avg: "Avg"
        case .dc: "DC"
        case let .crossing(value):
            if value == 0 {
                "ZeroCrossing"
            }
            else {
                "Crossing \(analysisFormatter.string(value))"
            }
        case .frequency: "Frequency"
        case .rms: "RMS"
        case .pkPk: "PkPk"
        case let .fft(pointCount):
            if let pointCount {
                "FFT \(pointCount)"
            }
            else {
                "FFT"
            }
        case .duration: "Duration"
        case .points: "Points"
        case .sampleRate: "SampleRate"
        case .interval: "Interval"
        case .start: "Start"
        case .end: "End"
        case .peak: "Peak"
        case .amplitude: "Amplitude"
        case .mid: "Mid"
        case .acRms: "ACRms"
        case .stdDev: "StdDev"
        case .crest: "Crest"
        case .median: "Median"
        case .top: "Top"
        case .base: "Base"
        case .overshoot: "Overshoot"
        case .undershoot: "Undershoot"
        case let .riseTime(low, high):
            if low == 10, high == 90 {
                "RiseTime"
            }
            else {
                "RiseTime \(analysisFormatter.string(low)), \(analysisFormatter.string(high))"
            }
        case let .fallTime(low, high):
            if low == 10, high == 90 {
                "FallTime"
            }
            else {
                "FallTime \(analysisFormatter.string(low)), \(analysisFormatter.string(high))"
            }
        case let .pulseWidth(threshold):
            if let threshold {
                "PulseWidth \(analysisFormatter.string(threshold))"
            }
            else {
                "PulseWidth"
            }
        case let .duty(threshold):
            if let threshold {
                "Duty \(analysisFormatter.string(threshold))"
            }
            else {
                "Duty"
            }
        case .period: "Period"
        case let .edgeCount(threshold):
            if let threshold {
                "EdgeCount \(analysisFormatter.string(threshold))"
            }
            else {
                "EdgeCount"
            }
        case let .jitter(threshold):
            if let threshold {
                "Jitter \(analysisFormatter.string(threshold))"
            }
            else {
                "Jitter"
            }
        case .integral: "Integral"
        case .energy: "Energy"
        case let .dbm(resistance):
            if resistance == powerReferenceResistance {
                "dBm"
            }
            else {
                "dBm \(analysisFormatter.string(resistance))"
            }
        }
    }
}

// MARK: - AnalysisOutcome


enum AnalysisOutcome: Equatable {
    case scalar(Double)
    case periodAndFrequency(period: Double, frequency: Double)
    case insufficientCrossings
    case fft(FFTSpectrum)
    case fftUnavailable
    case unavailable
}

// MARK: - AnalysisReport

/// One evaluated analysis, shared by console output and the SVG plot footer.

struct AnalysisReport: Equatable {
    let analysis: Analysis
    let outcome: AnalysisOutcome

    var label: String { analysis.label }

    var fftSpectrum: FFTSpectrum? {
        if case let .fft(spectrum) = outcome {
            return spectrum
        }
        return nil
    }

    var displayLine: String {
        switch outcome {
        case let .scalar(value):
            return "\(label): \(analysisFormatter.string(value))"
        case let .periodAndFrequency(period, frequency):
            return "\(label): T=\(analysisFormatter.string(period))s  f=\(analysisFormatter.string(frequency))Hz"
        case .insufficientCrossings:
            return "\(label): no complete wave (need ≥ 3 level crossings)"
        case let .fft(spectrum):
            let freq = analysisFormatter.string(spectrum.centerFrequency)
            if spectrum.usedPointCount < spectrum.requestedPointCount {
                return "FFT \(spectrum.usedPointCount): \(freq)Hz (requested \(spectrum.requestedPointCount))"
            }
            return "FFT \(spectrum.usedPointCount): \(freq)Hz"
        case .fftUnavailable:
            return "\(label): unavailable"
        case .unavailable:
            return "\(label): unavailable"
        }
    }

    static func reports(for analyses: [Analysis], on points: [Point]) -> [AnalysisReport] {
        analyses.map { analysis in
            AnalysisReport(analysis: analysis, outcome: analysis.evaluate(on: points))
        }
    }
}


extension Analysis {
    func evaluate(on points: [Point]) -> AnalysisOutcome {
        switch self {
        case .max:
            return .scalar(valueRange(points)?.maximum ?? 0)
        case .min:
            return .scalar(valueRange(points)?.minimum ?? 0)
        case .avg:
            return .scalar(averageValue(points))
        case .dc:
            return .scalar(calculateDC(points))
        case let .crossing(threshold):
            return periodFrequencyOutcome(points, threshold: threshold)
        case .frequency:
            return periodFrequencyOutcome(points, threshold: averageValue(points))
        case .rms:
            return .scalar(rmsValue(points))
        case .pkPk:
            return .scalar(peakToPeakValue(points))
        case let .fft(pointCount):
            let requested = pointCount ?? points.count
            guard let spectrum = computeFFTSpectrum(points: points, requestedPointCount: requested) else {
                return .fftUnavailable
            }
            return .fft(spectrum)
        case .duration:
            return .scalar(captureDuration(points))
        case .points:
            return .scalar(Double(points.count))
        case .sampleRate:
            guard let rate = captureSampleRate(points) else {
                return .unavailable
            }
            return .scalar(rate)
        case .interval:
            guard let interval = captureSampleInterval(points) else {
                return .unavailable
            }
            return .scalar(interval)
        case .start:
            return .scalar(points.first?.time ?? 0)
        case .end:
            return .scalar(points.last?.time ?? 0)
        case .peak:
            return .scalar(peakValue(points))
        case .amplitude:
            return .scalar(amplitudeValue(points))
        case .mid:
            return .scalar(midValue(points))
        case .acRms:
            return .scalar(acRmsValue(points))
        case .stdDev:
            return .scalar(standardDeviationValue(points))
        case .crest:
            guard let crest = crestFactorValue(points) else {
                return .unavailable
            }
            return .scalar(crest)
        case .median:
            return .scalar(medianValue(points))
        case .top:
            guard let levels = topBaseLevels(points) else {
                return .unavailable
            }
            return .scalar(levels.top)
        case .base:
            guard let levels = topBaseLevels(points) else {
                return .unavailable
            }
            return .scalar(levels.base)
        case .overshoot:
            guard let ratio = overshootRatio(points) else {
                return .unavailable
            }
            return .scalar(ratio)
        case .undershoot:
            guard let ratio = undershootRatio(points) else {
                return .unavailable
            }
            return .scalar(ratio)
        case let .riseTime(low, high):
            guard let dt = transitionTime(points, lowPercent: low, highPercent: high, rising: true) else {
                return .unavailable
            }
            return .scalar(dt)
        case let .fallTime(low, high):
            guard let dt = transitionTime(points, lowPercent: low, highPercent: high, rising: false) else {
                return .unavailable
            }
            return .scalar(dt)
        case let .pulseWidth(threshold):
            let level = threshold ?? averageValue(points)
            guard let width = averagePulseWidth(points, threshold: level, high: true) else {
                return .unavailable
            }
            return .scalar(width)
        case let .duty(threshold):
            let level = threshold ?? averageValue(points)
            guard let duty = dutyCycleFraction(points, threshold: level) else {
                return .unavailable
            }
            return .scalar(duty)
        case .period:
            return periodOnlyOutcome(points, threshold: averageValue(points))
        case let .edgeCount(threshold):
            let level = threshold ?? averageValue(points)
            return .scalar(Double(directedLevelCrossings(points, threshold: level).count))
        case let .jitter(threshold):
            let level = threshold ?? averageValue(points)
            let crossings = levelCrossingTimes(points, threshold: level)
            guard let jitter = periodStandardDeviation(from: crossings) else {
                return .unavailable
            }
            return .scalar(jitter)
        case .integral:
            return .scalar(integralValue(points))
        case .energy:
            return .scalar(energyValue(points))
        case let .dbm(resistance):
            guard let dbm = dbmFromRMS(points, resistance: resistance) else {
                return .unavailable
            }
            return .scalar(dbm)

        }
    }

    private func periodFrequencyOutcome(
        _ points: [Point],
        threshold: Double,
    ) -> AnalysisOutcome {
        let crossings = levelCrossingTimes(points, threshold: threshold)
        guard let result = averagePeriodAndFrequency(from: crossings) else {
            return .insufficientCrossings
        }
        return .periodAndFrequency(period: result.period, frequency: result.frequency)
    }

    private func periodOnlyOutcome(
        _ points: [Point],
        threshold: Double,
    ) -> AnalysisOutcome {
        let crossings = levelCrossingTimes(points, threshold: threshold)
        guard let result = averagePeriodAndFrequency(from: crossings) else {
            return .insufficientCrossings
        }
        return .scalar(result.period)
    }
}

