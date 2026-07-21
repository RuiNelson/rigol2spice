import Foundation

// MARK: - TransformationParseError

enum TransformationParseError: LocalizedError, Equatable {
    case emptyCommand(index: Int)
    case unknownOperation(name: String)
    case invalidArgumentCount(operation: String, expected: Int, actual: Int)
    case invalidScalar(operation: String, value: String)
    case invalidPositiveScalar(operation: String, value: String)
    case invalidFrequencyBand(operation: String, low: String, high: String)
    case invalidNotch(operation: String, center: String, width: String)
    case invalidTimeRange(operation: String, start: String, end: String)
    case invalidRange(operation: String, low: String, high: String)
    case invalidDCMethod(operation: String, value: String)
    case invalidResamplingFactor(operation: String, value: String)
    case invalidInterpolation(operation: String, value: String, allowed: String)

    var errorDescription: String? {
        switch self {
        case let .emptyCommand(index):
            "Transformation command \(index) is empty"
        case let .unknownOperation(name):
            "Unknown transformation operation: \(name)"
        case let .invalidArgumentCount(operation, expected, actual):
            "\(operation) expects \(expected) argument(s), but received \(actual)"
        case let .invalidScalar(operation, value):
            "Invalid scalar for \(operation): \(value)"
        case let .invalidPositiveScalar(operation, value):
            "\(operation) expects a positive scalar, but received: \(value)"
        case let .invalidFrequencyBand(operation, low, high):
            "\(operation) requires 0 < f1 < f2, but received \(low) and \(high)"
        case let .invalidNotch(operation, center, width):
            "\(operation) requires a positive center frequency and width smaller than twice the center, but received \(center) and \(width)"
        case let .invalidTimeRange(operation, start, end):
            "\(operation) requires start < end, but received \(start) and \(end)"
        case let .invalidRange(operation, low, high):
            "\(operation) requires low < high, but received \(low) and \(high)"
        case let .invalidDCMethod(operation, value):
            "\(operation) method must be DC, Avg, Median, or Mid, but received: \(value)"
        case let .invalidResamplingFactor(operation, value):
            "\(operation) factor must be greater than 1, but received: \(value)"
        case let .invalidInterpolation(operation, value, allowed):
            "\(operation) interpolation must be \(allowed), but received: \(value)"
        }
    }
}

// MARK: - Transformation

enum Transformation: Equatable {
    /// Subtract a DC estimate. Default method is k-means (`DC`); see `DCEstimationMethod`.
    case removeDC(DCEstimationMethod)
    /// Remove the least-squares constant and linear trend from sample values.
    case detrend
    case clampMin(Double)
    case clampMax(Double)
    case gate(Double)
    case offset(Double)
    /// Shift so the minimum sample value becomes 0 (add −min).
    case min0
    case addNoise(Double)
    case tvDenoise(Double)
    case multiply(Double)
    case invert
    case abs
    case rectify
    case normalize
    case peakTo(Double)
    case peakToPeak(Double)
    case scaleRMS(Double)
    case movingAverage(Int)
    case median(Int)
    case diff
    case integrate
    case deadZone(Double)
    case digitize(lowThreshold: Double, highThreshold: Double, lowOut: Double, highOut: Double)
    case slewLimit(Double)
    case softClip(lower: Double, upper: Double)
    case fade(inDuration: Double, outDuration: Double)
    case quantize(bits: Int, lower: Double, upper: Double)
    case limit(lower: Double, upper: Double)
    case db(Double)
    case dbmW(level: Double, resistance: Double)
    case dbW(level: Double, resistance: Double)
    case timeShift(Double)
    case timeScale(Double)
    case trigger(edge: TriggerEdge, threshold: Double, after: Double?)
    case triggerLevel(edge: TriggerEdge, level: TriggerLevel, after: Double?)
    case triggerSchmitt(edge: TriggerEdge, low: Double, high: Double, after: Double?)
    case triggerNth(edge: TriggerEdge, level: TriggerLevel, occurrence: Int, after: Double?)
    case triggerCapture(edge: TriggerEdge, level: TriggerLevel, pre: Double, post: Double, after: Double?)
    case triggerPulse(polarity: TriggerPulsePolarity, level: TriggerLevel, minimumWidth: Double, maximumWidth: Double?)
    case triggerBand(mode: TriggerBandMode, low: Double, high: Double, after: Double?)
    case triggerSlew(
        edge: TriggerEdge,
        lowPercent: Double,
        highPercent: Double,
        minimumRate: Double,
        maximumRate: Double?,
    )
    case triggerDropout(edge: TriggerEdge, level: TriggerLevel, duration: Double, after: Double?)
    case triggerRunt(edge: TriggerEdge, low: Double, high: Double, maximumDuration: Double)
    case seamless(rampDuration: Double?)
    case pad(duration: Double, value: Double?)
    case extendTo(endTime: Double, value: Double?)
    case downsample(factor: Double, interpolation: ResamplingInterpolation)
    case upsample(factor: Double, interpolation: ResamplingInterpolation)
    case extractPeriod(threshold: Double?)
    case cutAfter(Double)
    case cutBefore(Double)
    case trim(start: Double, end: Double)
    case `repeat`(Double)
    case am(carrier: Double, depth: Double, amplitude: Double)
    case fm(carrier: Double, sensitivity: Double, amplitude: Double)
    case pm(carrier: Double, sensitivity: Double, amplitude: Double)
    case demodAM(carrier: Double, depth: Double, cutoff: Double)
    case demodFM(carrier: Double, sensitivity: Double, cutoff: Double)
    case demodPM(carrier: Double, sensitivity: Double, cutoff: Double)
    case lowPass(Double)
    case highPass(Double)
    case bandPass(low: Double, high: Double)
    case bandStop(low: Double, high: Double)
    /// Convenience band-stop specified by center frequency and stop-band width.
    case notch(center: Double, width: Double)

    static func parseList(_ source: String) throws -> [Transformation] {
        let commands = source.split(separator: ";", omittingEmptySubsequences: false)

        return try commands.enumerated().map { index, rawCommand in
            let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !command.isEmpty else {
                throw TransformationParseError.emptyCommand(index: index + 1)
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
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: expected,
                        actual: arguments.count,
                    )
                }
            }

            func parseScalarArgument(_ argument: String) throws -> Double {
                guard !argument.contains(where: \Character.isWhitespace),
                      let value = parseEngineeringNotation(argument), value.isFinite else {
                    throw TransformationParseError.invalidScalar(operation: operation, value: argument)
                }
                return value
            }

            func positiveScalar(at index: Int) throws -> Double {
                let value = try parseScalarArgument(arguments[index])
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[index],
                    )
                }
                return value
            }

            func triggerEdge(at index: Int, allowEither: Bool = true) throws -> TriggerEdge {
                switch arguments[index].lowercased() {
                case "rising",
                     "rise",
                     "up": return .rising
                case "falling",
                     "fall",
                     "down": return .falling
                case "either",
                     "any",
                     "both":
                    guard allowEither else {
                        throw TransformationParseError.invalidScalar(
                            operation: operation,
                            value: arguments[index],
                        )
                    }
                    return .either
                default:
                    throw TransformationParseError.invalidScalar(
                        operation: operation,
                        value: arguments[index],
                    )
                }
            }

            func triggerLevel(at index: Int) throws -> TriggerLevel {
                let raw = arguments[index]
                if raw.lowercased() == "auto" {
                    return .automatic
                }
                if raw.hasSuffix("%") {
                    let percentRaw = String(raw.dropLast())
                    let percent = try parseScalarArgument(percentRaw)
                    guard percent >= 0, percent <= 100 else {
                        throw TransformationParseError.invalidScalar(operation: operation, value: raw)
                    }
                    return .percent(percent)
                }
                return try .value(parseScalarArgument(raw))
            }

            func positiveInteger(at index: Int) throws -> Int {
                let value = try positiveScalar(at: index)
                guard value <= Double(Int.max), value == value.rounded(.towardZero) else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[index],
                    )
                }
                return Int(value)
            }

            func resamplingInterpolation(
                at index: Int,
                allowed: [ResamplingInterpolation],
            ) throws -> ResamplingInterpolation {
                guard let interpolation = ResamplingInterpolation(rawValue: arguments[index].lowercased()),
                      allowed.contains(interpolation) else {
                    throw TransformationParseError.invalidInterpolation(
                        operation: operation,
                        value: arguments[index],
                        allowed: allowed.map(\.rawValue).joined(separator: ", "),
                    )
                }
                return interpolation
            }

            func validateRange(low: Double, high: Double, lowIndex: Int, highIndex: Int) throws {
                guard low < high else {
                    throw TransformationParseError.invalidRange(
                        operation: operation,
                        low: arguments[lowIndex],
                        high: arguments[highIndex],
                    )
                }
            }

            func scalar() throws -> Double {
                try requireArgumentCount(1)
                return try parseScalarArgument(arguments[0])
            }

            func positiveFrequency() throws -> Double {
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return value
            }

            func frequencyBand() throws -> (low: Double, high: Double) {
                try requireArgumentCount(2)
                let low = try parseScalarArgument(arguments[0])
                let high = try parseScalarArgument(arguments[1])
                guard low > 0, high > 0, low < high else {
                    throw TransformationParseError.invalidFrequencyBand(
                        operation: operation,
                        low: arguments[0],
                        high: arguments[1],
                    )
                }
                return (low, high)
            }

            /// Absolute power level with optional impedance (defaults to 50 Ω).
            func powerLevelWithResistance() throws -> (level: Double, resistance: Double) {
                guard arguments.count == 1 || arguments.count == 2 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 1,
                        actual: arguments.count,
                    )
                }
                let level = try parseScalarArgument(arguments[0])
                guard arguments.count == 2 else {
                    return (level, powerReferenceResistance)
                }
                let resistance = try parseScalarArgument(arguments[1])
                guard resistance > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[1],
                    )
                }
                return (level, resistance)
            }

            switch operation.lowercased() {
            case "removedc":
                // Forms: RemoveDC | RemoveDC DC|Avg|Median|Mid
                guard arguments.count <= 1 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 0,
                        actual: arguments.count,
                    )
                }
                if arguments.isEmpty {
                    return .removeDC(.dc)
                }
                guard let method = DCEstimationMethod.parse(arguments[0]) else {
                    throw TransformationParseError.invalidDCMethod(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .removeDC(method)
            case "detrend":
                try requireArgumentCount(0)
                return .detrend
            case "clampmin":
                return try .clampMin(scalar())
            case "clampmax":
                return try .clampMax(scalar())
            case "gate":
                return try .gate(scalar())
            case "offset":
                return try .offset(scalar())
            case "min0":
                try requireArgumentCount(0)
                return .min0
            case "addnoise":
                let value = try scalar()
                guard value >= 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .addNoise(value)
            case "tvdenoise":
                let value = try scalar()
                guard value >= 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .tvDenoise(value)
            case "multiply":
                return try .multiply(scalar())
            case "invert":
                try requireArgumentCount(0)
                return .invert
            case "abs":
                try requireArgumentCount(0)
                return .abs
            case "rectify":
                try requireArgumentCount(0)
                return .rectify
            case "normalize":
                try requireArgumentCount(0)
                return .normalize
            case "peakto":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .peakTo(value)
            case "peaktopeak":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .peakToPeak(value)
            case "scalerms":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .scaleRMS(value)
            case "movingaverage":
                let value = try scalar()
                guard value >= 1,
                      value < Double(Int.max),
                      value == value.rounded(.towardZero) else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .movingAverage(Int(value))
            case "median":
                let value = try scalar()
                guard value >= 1,
                      value < Double(Int.max),
                      value == value.rounded(.towardZero) else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .median(Int(value))
            case "diff":
                try requireArgumentCount(0)
                return .diff
            case "integrate":
                try requireArgumentCount(0)
                return .integrate
            case "deadzone":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .deadZone(value)
            case "slewlimit":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .slewLimit(value)
            case "softclip":
                try requireArgumentCount(2)
                let lower = try parseScalarArgument(arguments[0])
                let upper = try parseScalarArgument(arguments[1])
                guard lower < upper else {
                    throw TransformationParseError.invalidRange(
                        operation: operation,
                        low: arguments[0],
                        high: arguments[1],
                    )
                }
                return .softClip(lower: lower, upper: upper)
            case "fade":
                let duration = try scalar()
                guard duration > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .fade(inDuration: duration, outDuration: duration)
            case "fadein":
                let duration = try scalar()
                guard duration > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .fade(inDuration: duration, outDuration: 0)
            case "fadeout":
                let duration = try scalar()
                guard duration > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .fade(inDuration: 0, outDuration: duration)
            case "quantize":
                // Quantize bits, fullScale  → [0, fullScale]
                // Quantize bits, lower, upper
                guard arguments.count == 2 || arguments.count == 3 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 2,
                        actual: arguments.count,
                    )
                }
                let bitsValue = try parseScalarArgument(arguments[0])
                guard bitsValue >= 1,
                      bitsValue <= 32,
                      bitsValue == bitsValue.rounded(.towardZero) else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                let bits = Int(bitsValue)
                if arguments.count == 2 {
                    let fullScale = try parseScalarArgument(arguments[1])
                    guard fullScale > 0 else {
                        throw TransformationParseError.invalidPositiveScalar(
                            operation: operation,
                            value: arguments[1],
                        )
                    }
                    return .quantize(bits: bits, lower: 0, upper: fullScale)
                }
                let lower = try parseScalarArgument(arguments[1])
                let upper = try parseScalarArgument(arguments[2])
                guard lower < upper else {
                    throw TransformationParseError.invalidRange(
                        operation: operation,
                        low: arguments[1],
                        high: arguments[2],
                    )
                }
                return .quantize(bits: bits, lower: lower, upper: upper)
            case "digitize",
                 "threshold":
                // Digitize T                         → 0/1 hard threshold
                // Digitize T, lowOut, highOut        → hard threshold with custom levels
                // Digitize fall, rise, lowOut, highOut → Schmitt hysteresis
                switch arguments.count {
                case 1:
                    let threshold = try parseScalarArgument(arguments[0])
                    return .digitize(
                        lowThreshold: threshold,
                        highThreshold: threshold,
                        lowOut: 0,
                        highOut: 1,
                    )
                case 3:
                    let threshold = try parseScalarArgument(arguments[0])
                    let lowOut = try parseScalarArgument(arguments[1])
                    let highOut = try parseScalarArgument(arguments[2])
                    return .digitize(
                        lowThreshold: threshold,
                        highThreshold: threshold,
                        lowOut: lowOut,
                        highOut: highOut,
                    )
                case 4:
                    let lowThreshold = try parseScalarArgument(arguments[0])
                    let highThreshold = try parseScalarArgument(arguments[1])
                    let lowOut = try parseScalarArgument(arguments[2])
                    let highOut = try parseScalarArgument(arguments[3])
                    return .digitize(
                        lowThreshold: lowThreshold,
                        highThreshold: highThreshold,
                        lowOut: lowOut,
                        highOut: highOut,
                    )
                default:
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 3,
                        actual: arguments.count,
                    )
                }
            case "limit":
                try requireArgumentCount(2)
                let lower = try parseScalarArgument(arguments[0])
                let upper = try parseScalarArgument(arguments[1])
                guard lower < upper else {
                    throw TransformationParseError.invalidRange(
                        operation: operation,
                        low: arguments[0],
                        high: arguments[1],
                    )
                }
                return .limit(lower: lower, upper: upper)
            case "db":
                return try .db(scalar())
            case "dbmw",
                 "dbm":
                let power = try powerLevelWithResistance()
                return .dbmW(level: power.level, resistance: power.resistance)
            case "dbw":
                let power = try powerLevelWithResistance()
                return .dbW(level: power.level, resistance: power.resistance)
            case "timeshift":
                return try .timeShift(scalar())
            case "timescale":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .timeScale(value)
            case "trigger":
                // Forms:
                //   Trigger <level>                      → either edge
                //   Trigger <level>, <after>
                //   Trigger rising|falling|either, <level>[, <after>]
                guard (1 ... 3).contains(arguments.count) else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 2,
                        actual: arguments.count,
                    )
                }

                let first = arguments[0].lowercased()
                let edge: TriggerEdge
                let thresholdIndex: Int
                switch first {
                case "rising",
                     "rise",
                     "up":
                    edge = .rising
                    thresholdIndex = 1
                case "falling",
                     "fall",
                     "down":
                    edge = .falling
                    thresholdIndex = 1
                case "either",
                     "any",
                     "both":
                    edge = .either
                    thresholdIndex = 1
                default:
                    // Single scalar (or scalar + after): default edge is either.
                    edge = .either
                    thresholdIndex = 0
                }

                guard arguments.count > thresholdIndex else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: thresholdIndex + 1,
                        actual: arguments.count,
                    )
                }
                // Direction form takes 2–3 args; bare-level form takes 1–2.
                let maxArgs = thresholdIndex + 2
                guard arguments.count <= maxArgs else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: maxArgs,
                        actual: arguments.count,
                    )
                }

                let level = try triggerLevel(at: thresholdIndex)
                let after: Double? = if arguments.count > thresholdIndex + 1 {
                    try parseScalarArgument(arguments[thresholdIndex + 1])
                }
                else {
                    nil
                }
                if case let .value(threshold) = level {
                    return .trigger(edge: edge, threshold: threshold, after: after)
                }
                return .triggerLevel(edge: edge, level: level, after: after)
            case "triggerschmitt":
                guard arguments.count == 3 || arguments.count == 4 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 3,
                        actual: arguments.count,
                    )
                }
                let edge = try triggerEdge(at: 0)
                let low = try parseScalarArgument(arguments[1])
                let high = try parseScalarArgument(arguments[2])
                try validateRange(low: low, high: high, lowIndex: 1, highIndex: 2)
                let after = arguments.count == 4 ? try parseScalarArgument(arguments[3]) : nil
                return .triggerSchmitt(edge: edge, low: low, high: high, after: after)
            case "triggernth":
                guard arguments.count == 3 || arguments.count == 4 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 3,
                        actual: arguments.count,
                    )
                }
                return try .triggerNth(
                    edge: triggerEdge(at: 0),
                    level: triggerLevel(at: 1),
                    occurrence: positiveInteger(at: 2),
                    after: arguments.count == 4 ? parseScalarArgument(arguments[3]) : nil,
                )
            case "triggercapture",
                 "triggerwindow":
                guard arguments.count == 4 || arguments.count == 5 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 4,
                        actual: arguments.count,
                    )
                }
                let pre = try parseScalarArgument(arguments[2])
                guard pre >= 0 else {
                    throw TransformationParseError.invalidPositiveScalar(operation: operation, value: arguments[2])
                }
                return try .triggerCapture(
                    edge: triggerEdge(at: 0),
                    level: triggerLevel(at: 1),
                    pre: pre,
                    post: positiveScalar(at: 3),
                    after: arguments.count == 5 ? parseScalarArgument(arguments[4]) : nil,
                )
            case "triggerpulse":
                guard arguments.count == 3 || arguments.count == 4 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 3,
                        actual: arguments.count,
                    )
                }
                guard let polarity = TriggerPulsePolarity(rawValue: arguments[0].lowercased()) else {
                    throw TransformationParseError.invalidScalar(operation: operation, value: arguments[0])
                }
                let minimumWidth = try positiveScalar(at: 2)
                let maximumWidth = arguments.count == 4 ? try positiveScalar(at: 3) : nil
                if let maximumWidth, maximumWidth < minimumWidth {
                    throw TransformationParseError.invalidRange(
                        operation: operation,
                        low: arguments[2],
                        high: arguments[3],
                    )
                }
                return try .triggerPulse(
                    polarity: polarity,
                    level: triggerLevel(at: 1),
                    minimumWidth: minimumWidth,
                    maximumWidth: maximumWidth,
                )
            case "triggerband":
                guard arguments.count == 3 || arguments.count == 4 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 3,
                        actual: arguments.count,
                    )
                }
                guard let mode = TriggerBandMode(rawValue: arguments[0].lowercased()) else {
                    throw TransformationParseError.invalidScalar(operation: operation, value: arguments[0])
                }
                let low = try parseScalarArgument(arguments[1])
                let high = try parseScalarArgument(arguments[2])
                try validateRange(low: low, high: high, lowIndex: 1, highIndex: 2)
                return try .triggerBand(
                    mode: mode,
                    low: low,
                    high: high,
                    after: arguments.count == 4 ? parseScalarArgument(arguments[3]) : nil,
                )
            case "triggerslew":
                guard arguments.count == 4 || arguments.count == 5 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 4,
                        actual: arguments.count,
                    )
                }
                let edge = try triggerEdge(at: 0, allowEither: false)
                let lowPercent = try parseScalarArgument(arguments[1])
                let highPercent = try parseScalarArgument(arguments[2])
                guard lowPercent >= 0, highPercent <= 100, lowPercent < highPercent else {
                    throw TransformationParseError.invalidRange(
                        operation: operation,
                        low: arguments[1],
                        high: arguments[2],
                    )
                }
                let minimumRate = try positiveScalar(at: 3)
                let maximumRate = arguments.count == 5 ? try positiveScalar(at: 4) : nil
                if let maximumRate, maximumRate < minimumRate {
                    throw TransformationParseError.invalidRange(
                        operation: operation,
                        low: arguments[3],
                        high: arguments[4],
                    )
                }
                return .triggerSlew(
                    edge: edge,
                    lowPercent: lowPercent,
                    highPercent: highPercent,
                    minimumRate: minimumRate,
                    maximumRate: maximumRate,
                )
            case "triggerdropout":
                guard arguments.count == 3 || arguments.count == 4 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 3,
                        actual: arguments.count,
                    )
                }
                return try .triggerDropout(
                    edge: triggerEdge(at: 0),
                    level: triggerLevel(at: 1),
                    duration: positiveScalar(at: 2),
                    after: arguments.count == 4 ? parseScalarArgument(arguments[3]) : nil,
                )
            case "triggerrunt":
                try requireArgumentCount(4)
                let edge = try triggerEdge(at: 0, allowEither: false)
                let low = try parseScalarArgument(arguments[1])
                let high = try parseScalarArgument(arguments[2])
                try validateRange(low: low, high: high, lowIndex: 1, highIndex: 2)
                return try .triggerRunt(
                    edge: edge,
                    low: low,
                    high: high,
                    maximumDuration: positiveScalar(at: 3),
                )
            case "seamless",
                 "matchends":
                guard arguments.count <= 1 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 0,
                        actual: arguments.count,
                    )
                }
                if arguments.isEmpty {
                    return .seamless(rampDuration: nil)
                }
                let duration = try parseScalarArgument(arguments[0])
                guard duration > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .seamless(rampDuration: duration)
            case "pad",
                 "holdlast":
                guard arguments.count == 1 || arguments.count == 2 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 1,
                        actual: arguments.count,
                    )
                }
                let duration = try parseScalarArgument(arguments[0])
                guard duration > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                let holdValue: Double? = if arguments.count == 2 {
                    try parseScalarArgument(arguments[1])
                }
                else {
                    nil
                }
                return .pad(duration: duration, value: holdValue)
            case "extendto":
                guard arguments.count == 1 || arguments.count == 2 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 1,
                        actual: arguments.count,
                    )
                }
                let endTime = try parseScalarArgument(arguments[0])
                let holdValue: Double? = if arguments.count == 2 {
                    try parseScalarArgument(arguments[1])
                }
                else {
                    nil
                }
                return .extendTo(endTime: endTime, value: holdValue)
            case "downsample",
                 "upsample":
                guard arguments.count == 1 || arguments.count == 2 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 1,
                        actual: arguments.count,
                    )
                }
                let factor = try parseScalarArgument(arguments[0])
                guard factor > 1 else {
                    throw TransformationParseError.invalidResamplingFactor(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                let isDownsample = operation.lowercased() == "downsample"
                let allowed: [ResamplingInterpolation] = isDownsample
                    ? [.linear, .sinc]
                    : [.linear, .pchip, .sinc]
                let interpolation = try arguments.count == 2
                    ? resamplingInterpolation(at: 1, allowed: allowed)
                    : .linear
                return isDownsample
                    ? .downsample(factor: factor, interpolation: interpolation)
                    : .upsample(factor: factor, interpolation: interpolation)
            case "extractperiod":
                guard arguments.count <= 1 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 0,
                        actual: arguments.count,
                    )
                }
                if arguments.isEmpty {
                    return .extractPeriod(threshold: nil)
                }
                return try .extractPeriod(threshold: parseScalarArgument(arguments[0]))
            case "cutafter":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(operation: operation, value: arguments[0])
                }
                return .cutAfter(value)
            case "cutbefore":
                return try .cutBefore(scalar())
            case "trim":
                try requireArgumentCount(2)
                let start = try parseScalarArgument(arguments[0])
                let end = try parseScalarArgument(arguments[1])
                guard start < end else {
                    throw TransformationParseError.invalidTimeRange(
                        operation: operation,
                        start: arguments[0],
                        end: arguments[1],
                    )
                }
                return .trim(start: start, end: end)
            case "repeat":
                let value = try scalar()
                guard value > 0, value < Double(Int.max) else {
                    throw TransformationParseError.invalidPositiveScalar(operation: operation, value: arguments[0])
                }
                return .repeat(value)
            case "am",
                 "modulateam":
                guard arguments.count == 2 || arguments.count == 3 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 2,
                        actual: arguments.count,
                    )
                }
                return try .am(
                    carrier: positiveScalar(at: 0),
                    depth: positiveScalar(at: 1),
                    amplitude: arguments.count == 3 ? positiveScalar(at: 2) : 1,
                )
            case "fm",
                 "modulatefm":
                guard arguments.count == 2 || arguments.count == 3 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 2,
                        actual: arguments.count,
                    )
                }
                return try .fm(
                    carrier: positiveScalar(at: 0),
                    sensitivity: positiveScalar(at: 1),
                    amplitude: arguments.count == 3 ? positiveScalar(at: 2) : 1,
                )
            case "pm",
                 "modulatepm":
                guard arguments.count == 2 || arguments.count == 3 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 2,
                        actual: arguments.count,
                    )
                }
                return try .pm(
                    carrier: positiveScalar(at: 0),
                    sensitivity: positiveScalar(at: 1),
                    amplitude: arguments.count == 3 ? positiveScalar(at: 2) : 1,
                )
            case "demodam",
                 "amdemod":
                try requireArgumentCount(3)
                return try .demodAM(
                    carrier: positiveScalar(at: 0),
                    depth: positiveScalar(at: 1),
                    cutoff: positiveScalar(at: 2),
                )
            case "demodfm",
                 "fmdemod":
                try requireArgumentCount(3)
                return try .demodFM(
                    carrier: positiveScalar(at: 0),
                    sensitivity: positiveScalar(at: 1),
                    cutoff: positiveScalar(at: 2),
                )
            case "demodpm",
                 "pmdemod":
                try requireArgumentCount(3)
                return try .demodPM(
                    carrier: positiveScalar(at: 0),
                    sensitivity: positiveScalar(at: 1),
                    cutoff: positiveScalar(at: 2),
                )
            case "lowpass":
                return try .lowPass(positiveFrequency())
            case "highpass":
                return try .highPass(positiveFrequency())
            case "bandpass":
                let band = try frequencyBand()
                return .bandPass(low: band.low, high: band.high)
            case "bandstop":
                let band = try frequencyBand()
                return .bandStop(low: band.low, high: band.high)
            case "notch":
                try requireArgumentCount(2)
                let center = try parseScalarArgument(arguments[0])
                let width = try parseScalarArgument(arguments[1])
                guard center > 0, width > 0, center - width / 2 > 0 else {
                    throw TransformationParseError.invalidNotch(
                        operation: operation,
                        center: arguments[0],
                        width: arguments[1],
                    )
                }
                return .notch(center: center, width: width)
            default:
                throw TransformationParseError.unknownOperation(name: operation)
            }
        }
    }

    var reportsPointCount: Bool {
        switch self {
        case .timeShift,
             .trigger,
             .triggerLevel,
             .triggerSchmitt,
             .triggerNth,
             .triggerCapture,
             .triggerPulse,
             .triggerBand,
             .triggerSlew,
             .triggerDropout,
             .triggerRunt,
             .seamless,
             .pad,
             .extendTo,
             .downsample,
             .upsample,
             .extractPeriod,
             .cutAfter,
             .cutBefore,
             .trim,
             .repeat:
            true
        default:
            false
        }
    }

    var filterKind: FIRFilterKind? {
        switch self {
        case let .lowPass(cutoff):
            .lowPass(cutoff: cutoff)
        case let .highPass(cutoff):
            .highPass(cutoff: cutoff)
        case let .bandPass(low, high):
            .bandPass(low: low, high: high)
        case let .bandStop(low, high):
            .bandStop(low: low, high: high)
        case let .notch(center, width):
            .bandStop(low: center - width / 2, high: center + width / 2)
        default:
            nil
        }
    }

    func applying(to points: [Point], sampleInterval: Double? = nil) throws -> [Point] {
        switch self {
        case let .removeDC(method):
            return offsetPoints(points, offset: -calculateDC(points, method: method))
        case .detrend:
            return detrendPoints(points)
        case let .clampMin(value):
            return clamp(points, lowerLimit: value, upperLimit: nil)
        case let .clampMax(value):
            return clamp(points, lowerLimit: nil, upperLimit: value)
        case let .gate(value):
            return gatePoints(points, threshold: value)
        case let .offset(value):
            return offsetPoints(points, offset: value)
        case .min0:
            return shiftMinToZero(points)
        case let .addNoise(value):
            return addNoisePoints(points, amplitude: value)
        case let .tvDenoise(value):
            return tvDenoisePoints(points, lambda: value)
        case let .multiply(value):
            return multiplyValueOfPoints(points, factor: value)
        case .invert:
            return multiplyValueOfPoints(points, factor: -1)
        case .abs:
            return absPoints(points)
        case .rectify:
            return rectifyPoints(points)
        case .normalize:
            return scalePeakToPeak(points, target: 1)
        case let .peakTo(value):
            return scalePeakTo(points, target: value)
        case let .peakToPeak(value):
            return scalePeakToPeak(points, target: value)
        case let .scaleRMS(value):
            return scalePointsToRMS(points, target: value)
        case let .movingAverage(window):
            return movingAveragePoints(points, window: window)
        case let .median(window):
            return medianPoints(points, window: window)
        case .diff:
            return differentiatePoints(points)
        case .integrate:
            return integratePoints(points)
        case let .deadZone(value):
            return deadZonePoints(points, threshold: value)
        case let .digitize(lowThreshold, highThreshold, lowOut, highOut):
            return digitizePoints(
                points,
                lowThreshold: lowThreshold,
                highThreshold: highThreshold,
                lowOut: lowOut,
                highOut: highOut,
            )
        case let .slewLimit(value):
            return slewLimitPoints(points, maxSlew: value)
        case let .softClip(lower, upper):
            return softClipPoints(points, lower: lower, upper: upper)
        case let .fade(inDuration, outDuration):
            return fadePoints(points, fadeIn: inDuration, fadeOut: outDuration)
        case let .quantize(bits, lower, upper):
            return quantizePoints(points, bits: bits, lower: lower, upper: upper)
        case let .limit(lower, upper):
            return clamp(points, lowerLimit: lower, upperLimit: upper)
        case let .db(value):
            return multiplyValueOfPoints(points, factor: pow(10, value / 20))
        case let .dbmW(level, resistance):
            return multiplyValueOfPoints(points, factor: voltageFromDBmW(level, resistance: resistance))
        case let .dbW(level, resistance):
            return multiplyValueOfPoints(points, factor: voltageFromDBW(level, resistance: resistance))
        case let .timeShift(value):
            return timeShiftPoints(points, value: value)
        case let .timeScale(value):
            return timeScalePoints(points, factor: value)
        case let .trigger(edge, threshold, after):
            return try triggerPoints(points, edge: edge, threshold: threshold, after: after)
        case let .triggerLevel(edge, level, after):
            return try triggerLevelPoints(points, edge: edge, level: level, after: after)
        case let .triggerSchmitt(edge, low, high, after):
            return try triggerSchmittPoints(points, edge: edge, low: low, high: high, after: after)
        case let .triggerNth(edge, level, occurrence, after):
            return try triggerNthPoints(
                points,
                edge: edge,
                level: level,
                occurrence: occurrence,
                after: after,
            )
        case let .triggerCapture(edge, level, pre, post, after):
            return try triggerCapturePoints(
                points,
                edge: edge,
                level: level,
                pre: pre,
                post: post,
                after: after,
            )
        case let .triggerPulse(polarity, level, minimumWidth, maximumWidth):
            return try triggerPulsePoints(
                points,
                polarity: polarity,
                level: level,
                minimumWidth: minimumWidth,
                maximumWidth: maximumWidth,
            )
        case let .triggerBand(mode, low, high, after):
            return try triggerBandPoints(points, mode: mode, low: low, high: high, after: after)
        case let .triggerSlew(edge, lowPercent, highPercent, minimumRate, maximumRate):
            return try triggerSlewPoints(
                points,
                edge: edge,
                lowPercent: lowPercent,
                highPercent: highPercent,
                minimumRate: minimumRate,
                maximumRate: maximumRate,
            )
        case let .triggerDropout(edge, level, duration, after):
            return try triggerDropoutPoints(
                points,
                edge: edge,
                level: level,
                duration: duration,
                after: after,
            )
        case let .triggerRunt(edge, low, high, maximumDuration):
            return try triggerRuntPoints(
                points,
                edge: edge,
                low: low,
                high: high,
                maximumDuration: maximumDuration,
            )
        case let .seamless(rampDuration):
            return seamlessPoints(points, rampDuration: rampDuration)
        case let .pad(duration, value):
            return padPoints(points, duration: duration, value: value)
        case let .extendTo(endTime, value):
            return extendPoints(to: endTime, points: points, value: value)
        case let .downsample(factor, interpolation):
            return try resamplePoints(
                points,
                factor: factor,
                direction: .downsample,
                interpolation: interpolation,
            )
        case let .upsample(factor, interpolation):
            return try resamplePoints(
                points,
                factor: factor,
                direction: .upsample,
                interpolation: interpolation,
            )
        case let .extractPeriod(threshold):
            return try extractPeriodPoints(points, threshold: threshold)
        case let .cutAfter(value):
            return cutPointsAfter(points, after: value)
        case let .cutBefore(value):
            return cutPointsBefore(points, before: value)
        case let .trim(start, end):
            return trimPoints(points, start: start, end: end)
        case let .repeat(amount):
            return try repeatPoints(points, amount: amount)
        case let .am(carrier, depth, amplitude):
            return try modulateAMPoints(
                points,
                carrier: carrier,
                depth: depth,
                amplitude: amplitude,
                sampleInterval: sampleInterval,
            )
        case let .fm(carrier, sensitivity, amplitude):
            return try modulateFMPoints(
                points,
                carrier: carrier,
                sensitivity: sensitivity,
                amplitude: amplitude,
                sampleInterval: sampleInterval,
            )
        case let .pm(carrier, sensitivity, amplitude):
            return try modulatePMPoints(
                points,
                carrier: carrier,
                sensitivity: sensitivity,
                amplitude: amplitude,
                sampleInterval: sampleInterval,
            )
        case let .demodAM(carrier, depth, cutoff):
            return try demodulateAMPoints(
                points,
                carrier: carrier,
                depth: depth,
                cutoff: cutoff,
                sampleInterval: sampleInterval,
            )
        case let .demodFM(carrier, sensitivity, cutoff):
            return try demodulateFMPoints(
                points,
                carrier: carrier,
                sensitivity: sensitivity,
                cutoff: cutoff,
                sampleInterval: sampleInterval,
            )
        case let .demodPM(carrier, sensitivity, cutoff):
            return try demodulatePMPoints(
                points,
                carrier: carrier,
                sensitivity: sensitivity,
                cutoff: cutoff,
                sampleInterval: sampleInterval,
            )
        case let .lowPass(cutoff):
            let design = try designFilter(
                kind: .lowPass(cutoff: cutoff),
                points: points,
                sampleInterval: sampleInterval,
            )
            return applyFIRFilter(taps: design.taps, to: points)
        case let .highPass(cutoff):
            let design = try designFilter(
                kind: .highPass(cutoff: cutoff),
                points: points,
                sampleInterval: sampleInterval,
            )
            return applyFIRFilter(taps: design.taps, to: points)
        case let .bandPass(low, high):
            let design = try designFilter(
                kind: .bandPass(low: low, high: high),
                points: points,
                sampleInterval: sampleInterval,
            )
            return applyFIRFilter(taps: design.taps, to: points)
        case let .bandStop(low, high):
            let design = try designFilter(
                kind: .bandStop(low: low, high: high),
                points: points,
                sampleInterval: sampleInterval,
            )
            return applyFIRFilter(taps: design.taps, to: points)
        case let .notch(center, width):
            let design = try designFilter(
                kind: .bandStop(low: center - width / 2, high: center + width / 2),
                points: points,
                sampleInterval: sampleInterval,
            )
            return applyFIRFilter(taps: design.taps, to: points)
        }
    }

    func designFilter(
        kind: FIRFilterKind,
        points: [Point],
        sampleInterval: Double?,
    ) throws -> FIRFilterDesign {
        let interval = try resolveSampleInterval(sampleInterval, points: points, operation: kind.operationName)
        return try designFIRFilter(
            kind: kind,
            sampleRate: 1 / interval,
            sampleCount: points.count,
        )
    }
}
