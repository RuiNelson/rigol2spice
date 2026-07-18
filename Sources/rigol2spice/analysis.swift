import Foundation

// MARK: - AnalysisParseError

enum AnalysisParseError: LocalizedError, Equatable {
    case emptyCommand(index: Int)
    case unknownOperation(name: String)
    case invalidArgumentCount(operation: String, expected: Int, actual: Int)
    case invalidScalar(operation: String, value: String)
    case invalidPositiveInteger(operation: String, value: String)

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
                if arguments.isEmpty {
                    return .fft(pointCount: nil)
                }
                guard arguments.count == 1 else {
                    throw AnalysisParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 1,
                        actual: arguments.count,
                    )
                }
                let raw = arguments[0]
                let value = try parseScalarArgument(raw)
                guard value >= 1,
                      value <= Double(Int.max),
                      value == value.rounded(.towardZero) || abs(value - value.rounded()) < 1e-12 else {
                    throw AnalysisParseError.invalidPositiveInteger(operation: operation, value: raw)
                }
                return .fft(pointCount: Int(value.rounded()))
            default:
                throw AnalysisParseError.unknownOperation(name: operation)
            }
        }
    }

    /// Display name used in console output.
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
}

// MARK: - AnalysisReport

/// One evaluated analysis, shared by console output and the SVG plot footer.
struct AnalysisReport: Equatable {
    let analysis: Analysis
    let outcome: AnalysisOutcome

    var label: String { analysis.label }

    /// Spectrum payload when this report is a successful FFT analysis.
    var fftSpectrum: FFTSpectrum? {
        if case let .fft(spectrum) = outcome {
            return spectrum
        }
        return nil
    }

    /// Console / plot line using the analysis engineering formatter (1 decimal).
    /// FFT reports only the dominant (center) frequency; the N shown is samples actually used
    /// (capped to the capture length when the request exceeds available points).
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
            // N is samples actually used (capped to capture length when the request is larger).
            if spectrum.usedPointCount < spectrum.requestedPointCount {
                return "FFT \(spectrum.usedPointCount): \(freq)Hz (requested \(spectrum.requestedPointCount))"
            }
            return "FFT \(spectrum.usedPointCount): \(freq)Hz"
        case .fftUnavailable:
            return "\(label): unavailable"
        }
    }

    /// Evaluate every analysis on `points` (order preserved only for display).
    static func reports(for analyses: [Analysis], on points: [Point]) -> [AnalysisReport] {
        analyses.map { analysis in
            AnalysisReport(analysis: analysis, outcome: analysis.evaluate(on: points))
        }
    }
}

extension Analysis {
    /// Evaluate using the same measurement helpers as amplitude transforms / period extract.
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
            // Bare `FFT` → every sample; `FFT N` → up to N (capped to available).
            let requested = pointCount ?? points.count
            guard let spectrum = computeFFTSpectrum(points: points, requestedPointCount: requested) else {
                return .fftUnavailable
            }
            return .fft(spectrum)
        }
    }

    private func periodFrequencyOutcome(
        _ points: [Point],
        threshold: Double,
    ) -> AnalysisOutcome {
        // Level crossings (rise + fall); only complete waves contribute to T/f.
        let crossings = levelCrossingTimes(points, threshold: threshold)
        guard let result = averagePeriodAndFrequency(from: crossings) else {
            return .insufficientCrossings
        }
        return .periodAndFrequency(period: result.period, frequency: result.frequency)
    }
}
