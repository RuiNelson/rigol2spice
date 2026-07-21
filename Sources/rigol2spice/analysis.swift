import Foundation

// MARK: - AnalysisParseError

enum AnalysisParseError: LocalizedError, Equatable {
    case unknownOperation(name: String)
    case invalidArgumentCount(operation: String, expected: Int, actual: Int)
    case invalidScalar(operation: String, value: String)
    case invalidPositiveInteger(operation: String, value: String)
    case invalidPercentPair(operation: String, low: Double, high: Double)
    case invalidFFTWindowPosition(operation: String, value: String)
    case fftRequired(operation: String)

    var errorDescription: String? {
        switch self {
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
        case let .invalidFFTWindowPosition(operation, value):
            "\(operation) window position must be start, middle, or end, but received: \(value)"
        case let .fftRequired(operation):
            "\(operation) requires an FFT analysis earlier in the analysis list"
        }
    }
}

// MARK: - Analysis

/// Signal measurements printed to the console (do not alter the capture).
/// FFT-dependent measurements consume the most recent preceding FFT result.
enum Analysis: Equatable {
    // Existing
    case max
    case min
    case avg
    case dc
    case crossing(Double)
    case frequency
    case rms
    case pkPk
    /// Real FFT over a positioned window of up to `pointCount` samples (Hann + zero-pad to 2ⁿ).
    /// `pointCount == nil` means use every sample in the capture.
    case fft(pointCount: Int?, position: FFTWindowPosition)

    // Capture metadata
    case duration
    case points
    case sampleRate
    case interval
    case start
    case end

    // Amplitude
    case peak
    case amplitude
    case mid
    case acRms
    case stdDev
    case crest
    case median
    /// Timestamp of the first maximum sample.
    case peakTime
    /// Timestamp of the first minimum sample.
    case minTime
    /// Arithmetic mean of absolute sample values.
    case meanAbs
    case top
    case base
    case overshoot
    case undershoot

    /// Timing
    /// Rise time between low/high percent of min/max span (default 10 → 90).
    case riseTime(lowPercent: Double, highPercent: Double)
    /// Fall time between high/low percent of min/max span (default 90 → 10).
    case fallTime(lowPercent: Double, highPercent: Double)
    /// Average rising slew rate between 10% and 90% of the min/max span.
    case slewRise(lowPercent: Double, highPercent: Double)
    /// Average falling slew rate magnitude between 90% and 10% of the min/max span.
    case slewFall(lowPercent: Double, highPercent: Double)
    /// Average high pulse width at threshold (`nil` → sample average).
    case pulseWidth(threshold: Double?)
    /// Average low pulse width at threshold (`nil` → sample average).
    case lowPulseWidth(threshold: Double?)
    /// Duty cycle (0…1) at threshold (`nil` → sample average).
    case duty(threshold: Double?)
    /// Number of level crossings at threshold (`nil` → sample average).
    case edgeCount(threshold: Double?)
    /// Number of rising level crossings at threshold (`nil` → sample average).
    case riseCount(threshold: Double?)
    /// Number of falling level crossings at threshold (`nil` → sample average).
    case fallCount(threshold: Double?)
    /// Std. dev. of complete-wave periods at threshold (`nil` → sample average).
    case jitter(threshold: Double?)
    /// Minimum complete-wave period at threshold (`nil` → sample average).
    case periodMin(threshold: Double?)
    /// Maximum complete-wave period at threshold (`nil` → sample average).
    case periodMax(threshold: Double?)
    /// Complete-wave period range (max − min) at threshold (`nil` → sample average).
    case periodPkPk(threshold: Double?)

    /// Integrals / power / spectrum
    case integral
    /// Mean RMS power in watts into `resistance` ohms (default 50).
    case power(resistance: Double)
    /// Trapezoidal ∫v²/R dt in joules (`resistance` defaults to 1 ohm).
    case energy(resistance: Double)
    /// RMS power in dBm into `resistance` ohms (default 50).
    case dbm(resistance: Double)
    /// THD fraction from the most recent preceding FFT.
    case thd
    /// Dominant AC frequency and Hann-corrected peak amplitude.
    case fundamental
    /// Hann-corrected peak amplitude of a harmonic of the dominant AC component.
    case harmonic(number: Int)
    /// Independent similarity to ideal harmonic magnitude profiles.
    case sineWaveType
    case squareWaveType
    case sawtoothWaveType
    case triangleWaveType

    static func parseList(_ source: String) throws -> [Analysis] {
        let commands = splitCommandList(source)
        var hasFFT = false

        return try commands.flatMap { rawCommand -> [Analysis] in
            let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)

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

            func parsePositiveInteger(_ raw: String) throws -> Int {
                let value = try parseScalarArgument(raw)
                guard value >= 1,
                      value <= Double(Int.max),
                      value == value.rounded(.towardZero) || abs(value - value.rounded()) < 1e-12 else {
                    throw AnalysisParseError.invalidPositiveInteger(operation: operation, value: raw)
                }
                return Int(value.rounded())
            }

            func fftWindowPosition(_ raw: String) throws -> FFTWindowPosition {
                switch raw.lowercased() {
                case "start",
                     "begin",
                     "beginning":
                    return .start
                case "middle",
                     "center",
                     "centre":
                    return .middle
                case "end":
                    return .end
                default:
                    throw AnalysisParseError.invalidFFTWindowPosition(
                        operation: operation,
                        value: raw,
                    )
                }
            }

            func optionalFFTWindowPosition(_ raw: String) -> FFTWindowPosition? {
                switch raw.lowercased() {
                case "start",
                     "begin",
                     "beginning": .start
                case "middle",
                     "center",
                     "centre": .middle
                case "end": .end
                default: nil
                }
            }

            func requirePrecedingFFT() throws {
                guard hasFFT else {
                    throw AnalysisParseError.fftRequired(operation: operation)
                }
            }

            func parseResistance(default defaultResistance: Double) throws -> Double {
                if arguments.isEmpty {
                    return defaultResistance
                }
                try requireArgumentCount(1)
                let resistance = try parseScalarArgument(arguments[0])
                guard resistance > 0 else {
                    throw AnalysisParseError.invalidScalar(operation: operation, value: arguments[0])
                }
                return resistance
            }

            switch operation.lowercased() {
            case "basic":
                try requireArgumentCount(0)
                return [.duration, .points, .min, .max, .pkPk, .avg, .rms]
            case "timing":
                try requireArgumentCount(0)
                return [
                    .frequency,
                    .duty(threshold: nil),
                    .pulseWidth(threshold: nil),
                    .riseTime(lowPercent: 10, highPercent: 90),
                    .fallTime(lowPercent: 10, highPercent: 90),
                ]
            case "spectrum":
                try requireArgumentCount(0)
                hasFFT = true
                return [.fft(pointCount: nil, position: .start), .thd]
            case "wavetype":
                try requireArgumentCount(0)
                try requirePrecedingFFT()
                return [.sineWaveType, .squareWaveType, .sawtoothWaveType, .triangleWaveType]
            case "max",
                 "hipeak":
                try requireArgumentCount(0)
                return [.max]
            case "min",
                 "lowpeak":
                try requireArgumentCount(0)
                return [.min]
            case "avg":
                try requireArgumentCount(0)
                return [.avg]
            case "dc":
                try requireArgumentCount(0)
                return [.dc]
            case "crossing":
                try requireArgumentCount(1)
                return try [.crossing(parseScalarArgument(arguments[0]))]
            case "zerocrossing":
                try requireArgumentCount(0)
                return [.crossing(0)]
            case "frequency":
                try requireArgumentCount(0)
                return [.frequency]
            case "rms":
                try requireArgumentCount(0)
                return [.rms]
            case "pkpk":
                try requireArgumentCount(0)
                return [.pkPk]
            case "fft":
                guard arguments.count <= 2 else {
                    throw AnalysisParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 2,
                        actual: arguments.count,
                    )
                }
                let pointCount: Int?
                let position: FFTWindowPosition
                if arguments.isEmpty {
                    pointCount = nil
                    position = .start
                }
                else if arguments.count == 1, let parsedPosition = optionalFFTWindowPosition(arguments[0]) {
                    pointCount = nil
                    position = parsedPosition
                }
                else {
                    pointCount = try parsePositiveInteger(arguments[0])
                    position = try arguments.count == 2 ? fftWindowPosition(arguments[1]) : .start
                }
                hasFFT = true
                return [.fft(pointCount: pointCount, position: position)]
            case "duration":
                try requireArgumentCount(0)
                return [.duration]
            case "points":
                try requireArgumentCount(0)
                return [.points]
            case "samplerate":
                try requireArgumentCount(0)
                return [.sampleRate]
            case "interval":
                try requireArgumentCount(0)
                return [.interval]
            case "start":
                try requireArgumentCount(0)
                return [.start]
            case "end":
                try requireArgumentCount(0)
                return [.end]
            case "peak":
                try requireArgumentCount(0)
                return [.peak]
            case "amplitude":
                try requireArgumentCount(0)
                return [.amplitude]
            case "mid":
                try requireArgumentCount(0)
                return [.mid]
            case "acrms":
                try requireArgumentCount(0)
                return [.acRms]
            case "stddev",
                 "stdev":
                try requireArgumentCount(0)
                return [.stdDev]
            case "crest":
                try requireArgumentCount(0)
                return [.crest]
            case "median":
                try requireArgumentCount(0)
                return [.median]
            case "peaktime":
                try requireArgumentCount(0)
                return [.peakTime]
            case "mintime":
                try requireArgumentCount(0)
                return [.minTime]
            case "meanabs":
                try requireArgumentCount(0)
                return [.meanAbs]
            case "top":
                try requireArgumentCount(0)
                return [.top]
            case "base":
                try requireArgumentCount(0)
                return [.base]
            case "overshoot":
                try requireArgumentCount(0)
                return [.overshoot]
            case "undershoot":
                try requireArgumentCount(0)
                return [.undershoot]
            case "risetime":
                let pair = try parsePercentPair(defaultLow: 10, defaultHigh: 90)
                return [.riseTime(lowPercent: pair.0, highPercent: pair.1)]
            case "falltime":
                let pair = try parsePercentPair(defaultLow: 10, defaultHigh: 90)
                return [.fallTime(lowPercent: pair.0, highPercent: pair.1)]
            case "slewrise":
                let pair = try parsePercentPair(defaultLow: 10, defaultHigh: 90)
                return [.slewRise(lowPercent: pair.0, highPercent: pair.1)]
            case "slewfall":
                let pair = try parsePercentPair(defaultLow: 10, defaultHigh: 90)
                return [.slewFall(lowPercent: pair.0, highPercent: pair.1)]
            case "pulsewidth":
                return try [.pulseWidth(threshold: parseOptionalThreshold())]
            case "lowpulsewidth":
                return try [.lowPulseWidth(threshold: parseOptionalThreshold())]
            case "duty":
                return try [.duty(threshold: parseOptionalThreshold())]
            case "edgecount":
                return try [.edgeCount(threshold: parseOptionalThreshold())]
            case "risecount":
                return try [.riseCount(threshold: parseOptionalThreshold())]
            case "fallcount":
                return try [.fallCount(threshold: parseOptionalThreshold())]
            case "jitter",
                 "periodstd":
                return try [.jitter(threshold: parseOptionalThreshold())]
            case "periodmin":
                return try [.periodMin(threshold: parseOptionalThreshold())]
            case "periodmax":
                return try [.periodMax(threshold: parseOptionalThreshold())]
            case "periodpkpk":
                return try [.periodPkPk(threshold: parseOptionalThreshold())]
            case "integral":
                try requireArgumentCount(0)
                return [.integral]
            case "power":
                return try [.power(resistance: parseResistance(default: powerReferenceResistance))]
            case "energy":
                return try [.energy(resistance: parseResistance(default: 1))]
            case "dbm":
                return try [.dbm(resistance: parseResistance(default: powerReferenceResistance))]
            case "thd":
                try requireArgumentCount(0)
                try requirePrecedingFFT()
                return [.thd]
            case "fundamental":
                try requireArgumentCount(0)
                try requirePrecedingFFT()
                return [.fundamental]
            case "harmonic":
                try requireArgumentCount(1)
                try requirePrecedingFFT()
                let number = try parsePositiveInteger(arguments[0])
                return [.harmonic(number: number)]
            case "sinewavetype":
                try requireArgumentCount(0)
                try requirePrecedingFFT()
                return [.sineWaveType]
            case "squarewavetype":
                try requireArgumentCount(0)
                try requirePrecedingFFT()
                return [.squareWaveType]
            case "sawtoothwavetype",
                 "sawwavetype":
                try requireArgumentCount(0)
                try requirePrecedingFFT()
                return [.sawtoothWaveType]
            case "trianglewavetype":
                try requireArgumentCount(0)
                try requirePrecedingFFT()
                return [.triangleWaveType]
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
        case let .fft(pointCount, position):
            ["FFT", pointCount.map(String.init), position == .start ? nil : position.rawValue]
                .compactMap(\.self)
                .joined(separator: " ")
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
        case .peakTime: "PeakTime"
        case .minTime: "MinTime"
        case .meanAbs: "MeanAbs"
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
        case let .slewRise(low, high):
            if low == 10, high == 90 {
                "SlewRise"
            }
            else {
                "SlewRise \(analysisFormatter.string(low)), \(analysisFormatter.string(high))"
            }
        case let .slewFall(low, high):
            if low == 10, high == 90 {
                "SlewFall"
            }
            else {
                "SlewFall \(analysisFormatter.string(low)), \(analysisFormatter.string(high))"
            }
        case let .pulseWidth(threshold):
            if let threshold {
                "PulseWidth \(analysisFormatter.string(threshold))"
            }
            else {
                "PulseWidth"
            }
        case let .lowPulseWidth(threshold):
            if let threshold {
                "LowPulseWidth \(analysisFormatter.string(threshold))"
            }
            else {
                "LowPulseWidth"
            }
        case let .duty(threshold):
            if let threshold {
                "Duty \(analysisFormatter.string(threshold))"
            }
            else {
                "Duty"
            }
        case let .edgeCount(threshold):
            if let threshold {
                "EdgeCount \(analysisFormatter.string(threshold))"
            }
            else {
                "EdgeCount"
            }
        case let .riseCount(threshold):
            if let threshold {
                "RiseCount \(analysisFormatter.string(threshold))"
            }
            else {
                "RiseCount"
            }
        case let .fallCount(threshold):
            if let threshold {
                "FallCount \(analysisFormatter.string(threshold))"
            }
            else {
                "FallCount"
            }
        case let .jitter(threshold):
            if let threshold {
                "Jitter \(analysisFormatter.string(threshold))"
            }
            else {
                "Jitter"
            }
        case let .periodMin(threshold):
            threshold.map { "PeriodMin \(analysisFormatter.string($0))" } ?? "PeriodMin"
        case let .periodMax(threshold):
            threshold.map { "PeriodMax \(analysisFormatter.string($0))" } ?? "PeriodMax"
        case let .periodPkPk(threshold):
            threshold.map { "PeriodPkPk \(analysisFormatter.string($0))" } ?? "PeriodPkPk"
        case .integral: "Integral"
        case let .power(resistance):
            resistance == powerReferenceResistance
                ? "Power"
                : "Power \(analysisFormatter.string(resistance))"
        case let .energy(resistance):
            resistance == 1
                ? "Energy"
                : "Energy \(analysisFormatter.string(resistance))"
        case let .dbm(resistance):
            if resistance == powerReferenceResistance {
                "dBm"
            }
            else {
                "dBm \(analysisFormatter.string(resistance))"
            }
        case .thd: "THD"
        case .fundamental: "Fundamental"
        case let .harmonic(number): "Harmonic \(number)"
        case .sineWaveType: "SineWaveType"
        case .squareWaveType: "SquareWaveType"
        case .sawtoothWaveType: "SawtoothWaveType"
        case .triangleWaveType: "TriangleWaveType"
        }
    }
}

// MARK: - AnalysisOutcome

enum AnalysisOutcome: Equatable {
    case scalar(Double)
    case periodAndFrequency(period: Double, frequency: Double)
    case frequencyAndAmplitude(frequency: Double, amplitude: Double)
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

    var label: String {
        analysis.label
    }

    /// Spectrum payload when this report is a successful FFT analysis.
    var fftSpectrum: FFTSpectrum? {
        if case let .fft(spectrum) = outcome {
            return spectrum
        }
        return nil
    }

    /// Console / plot line using the analysis engineering formatter (1 decimal).
    /// FFT reports dominant frequency and peak magnitude in dB; N is samples actually used.
    var displayLine: String {
        switch outcome {
        case let .scalar(value):
            let displayValue = value * analysis.scalarDisplayScale
            let formattedValue = if analysis.isPercentage {
                analysisPercentageFormatter.string(from: NSNumber(value: displayValue)) ?? "\(displayValue)"
            }
            else {
                analysisFormatter.string(displayValue)
            }
            return "\(label): \(formattedValue)\(analysis.scalarUnitSuffix)"
        case let .periodAndFrequency(period, frequency):
            return "\(label): T=\(analysisFormatter.string(period))s  f=\(analysisFormatter.string(frequency))Hz"
        case let .frequencyAndAmplitude(frequency, amplitude):
            return "\(label): f=\(analysisFormatter.string(frequency))Hz  A=\(analysisFormatter.string(amplitude))V"
        case .insufficientCrossings:
            return "\(label): no complete wave (need ≥ 3 level crossings)"
        case let .fft(spectrum):
            let freq = analysisFormatter.string(spectrum.centerFrequency)
            let mag = analysisFormatter.string(spectrum.centerMagnitudeDB)
            let heading = "FFT \(spectrum.usedPointCount) \(spectrum.windowPosition.rawValue)"
            return if spectrum.usedPointCount < spectrum.requestedPointCount {
                "\(heading): \(freq)Hz \(mag)dB (requested \(spectrum.requestedPointCount))"
            }
            else {
                "\(heading): \(freq)Hz \(mag)dB"
            }
        case .fftUnavailable:
            return "\(label): unavailable"
        case .unavailable:
            return "\(label): unavailable"
        }
    }

    /// Evaluate in list order, retaining the most recent FFT for dependent analyses.
    static func reports(for analyses: [Analysis], on points: [Point]) -> [AnalysisReport] {
        var currentSpectrum: FFTSpectrum?
        return analyses.map { analysis in
            let outcome = analysis.evaluate(on: points, using: currentSpectrum)
            if case let .fft(spectrum) = outcome {
                currentSpectrum = spectrum
            }
            else if case .fft = analysis {
                currentSpectrum = nil
            }
            return AnalysisReport(
                analysis: analysis,
                outcome: outcome,
            )
        }
    }
}

private extension Analysis {
    var isPercentage: Bool {
        switch self {
        case .duty,
             .overshoot,
             .undershoot,
             .thd,
             .sineWaveType,
             .squareWaveType,
             .sawtoothWaveType,
             .triangleWaveType:
            true
        default:
            false
        }
    }

    var scalarDisplayScale: Double {
        switch self {
        case .duty,
             .overshoot,
             .undershoot,
             .thd:
            100
        default:
            1
        }
    }

    /// Unit appended after the engineering prefix for scalar analysis outcomes.
    var scalarUnitSuffix: String {
        switch self {
        case .max,
             .min,
             .avg,
             .dc,
             .rms,
             .pkPk,
             .peak,
             .amplitude,
             .mid,
             .acRms,
             .stdDev,
             .median,
             .meanAbs,
             .top,
             .base,
             .harmonic:
            "V"
        case .duration,
             .interval,
             .start,
             .end,
             .peakTime,
             .minTime,
             .riseTime,
             .fallTime,
             .pulseWidth,
             .lowPulseWidth,
             .jitter,
             .periodMin,
             .periodMax,
             .periodPkPk:
            "s"
        case .sampleRate:
            "Sa/s"
        case .slewRise,
             .slewFall:
            "V/s"
        case .integral:
            "V·s"
        case .power:
            "W"
        case .energy:
            "J"
        case .dbm:
            "dBm"
        case .points:
            " samples"
        case .edgeCount,
             .riseCount,
             .fallCount:
            " edges"
        case .crossing,
             .frequency:
            "Hz"
        case .fft,
             .fundamental:
            ""
        case .crest:
            "×"
        case .duty,
             .overshoot,
             .undershoot,
             .thd,
             .sineWaveType,
             .squareWaveType,
             .sawtoothWaveType,
             .triangleWaveType:
            "%"
        }
    }
}

extension Analysis {
    /// Evaluate without an existing FFT. FFT-dependent analyses return unavailable.
    func evaluate(on points: [Point]) -> AnalysisOutcome {
        evaluate(on: points, using: nil)
    }

    /// Evaluate using the retained result of the most recent preceding FFT.
    func evaluate(
        on points: [Point],
        using spectrum: FFTSpectrum?,
    ) -> AnalysisOutcome {
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
        case let .fft(pointCount, position):
            let requested = pointCount ?? points.count
            guard let spectrum = computeFFTSpectrum(
                points: points,
                requestedPointCount: requested,
                position: position,
            ) else {
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
        case .peakTime:
            guard let time = extremeTime(points, maximum: true) else {
                return .unavailable
            }
            return .scalar(time)
        case .minTime:
            guard let time = extremeTime(points, maximum: false) else {
                return .unavailable
            }
            return .scalar(time)
        case .meanAbs:
            return .scalar(meanAbsoluteValue(points))
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
        case let .slewRise(low, high):
            guard let rate = transitionSlewRate(
                points,
                lowPercent: low,
                highPercent: high,
                rising: true,
            ) else {
                return .unavailable
            }
            return .scalar(rate)
        case let .slewFall(low, high):
            guard let rate = transitionSlewRate(
                points,
                lowPercent: low,
                highPercent: high,
                rising: false,
            ) else {
                return .unavailable
            }
            return .scalar(rate)
        case let .pulseWidth(threshold):
            let level = threshold ?? averageValue(points)
            guard let width = averagePulseWidth(points, threshold: level, high: true) else {
                return .unavailable
            }
            return .scalar(width)
        case let .lowPulseWidth(threshold):
            let level = threshold ?? averageValue(points)
            guard let width = averagePulseWidth(points, threshold: level, high: false) else {
                return .unavailable
            }
            return .scalar(width)
        case let .duty(threshold):
            let level = threshold ?? averageValue(points)
            guard let duty = dutyCycleFraction(points, threshold: level) else {
                return .unavailable
            }
            return .scalar(duty)
        case let .edgeCount(threshold):
            let level = threshold ?? averageValue(points)
            return .scalar(Double(directedLevelCrossings(points, threshold: level).count))
        case let .riseCount(threshold):
            let level = threshold ?? averageValue(points)
            let count = directedLevelCrossings(points, threshold: level).count(where: \.rising)
            return .scalar(Double(count))
        case let .fallCount(threshold):
            let level = threshold ?? averageValue(points)
            let count = directedLevelCrossings(points, threshold: level).count { !$0.rising }
            return .scalar(Double(count))
        case let .jitter(threshold):
            let level = threshold ?? averageValue(points)
            let crossings = levelCrossingTimes(points, threshold: level)
            guard let jitter = periodStandardDeviation(from: crossings) else {
                return .unavailable
            }
            return .scalar(jitter)
        case let .periodMin(threshold):
            return periodStatisticOutcome(points, threshold: threshold, statistic: .minimum)
        case let .periodMax(threshold):
            return periodStatisticOutcome(points, threshold: threshold, statistic: .maximum)
        case let .periodPkPk(threshold):
            return periodStatisticOutcome(points, threshold: threshold, statistic: .peakToPeak)
        case .integral:
            return .scalar(integralValue(points))
        case let .power(resistance):
            guard let power = averagePowerValue(points, resistance: resistance) else {
                return .unavailable
            }
            return .scalar(power)
        case let .energy(resistance):
            guard let energy = energyValue(points, resistance: resistance) else {
                return .unavailable
            }
            return .scalar(energy)
        case let .dbm(resistance):
            guard let dbm = dbmFromRMS(points, resistance: resistance) else {
                return .unavailable
            }
            return .scalar(dbm)
        case .thd:
            guard let spectrum,
                  let thd = thdFraction(spectrum: spectrum) else {
                return .unavailable
            }
            return .scalar(thd)
        case .fundamental:
            guard let spectrum,
                  let amplitude = fundamentalAmplitude(spectrum: spectrum) else {
                return .unavailable
            }
            return .frequencyAndAmplitude(
                frequency: spectrum.centerFrequency,
                amplitude: amplitude,
            )
        case let .harmonic(number):
            guard let spectrum,
                  let amplitude = harmonicAmplitude(spectrum: spectrum, number: number) else {
                return .unavailable
            }
            return .scalar(amplitude)
        case .sineWaveType:
            guard let spectrum, let percentages = waveTypePercentages(spectrum: spectrum) else {
                return .unavailable
            }
            return .scalar(percentages.sine)
        case .squareWaveType:
            guard let spectrum, let percentages = waveTypePercentages(spectrum: spectrum) else {
                return .unavailable
            }
            return .scalar(percentages.square)
        case .sawtoothWaveType:
            guard let spectrum, let percentages = waveTypePercentages(spectrum: spectrum) else {
                return .unavailable
            }
            return .scalar(percentages.sawtooth)
        case .triangleWaveType:
            guard let spectrum, let percentages = waveTypePercentages(spectrum: spectrum) else {
                return .unavailable
            }
            return .scalar(percentages.triangle)
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

    private enum PeriodStatistic {
        case minimum
        case maximum
        case peakToPeak
    }

    private func periodStatisticOutcome(
        _ points: [Point],
        threshold: Double?,
        statistic: PeriodStatistic,
    ) -> AnalysisOutcome {
        let level = threshold ?? averageValue(points)
        let periods = completeWavePeriods(from: levelCrossingTimes(points, threshold: level))
        guard let minimum = periods.min(), let maximum = periods.max() else {
            return .unavailable
        }
        switch statistic {
        case .minimum:
            return .scalar(minimum)
        case .maximum:
            return .scalar(maximum)
        case .peakToPeak:
            return .scalar(maximum - minimum)
        }
    }
}
