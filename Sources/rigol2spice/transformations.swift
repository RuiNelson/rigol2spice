import Foundation

// MARK: - TransformationParseError

enum TransformationParseError: LocalizedError, Equatable {
    case emptyCommand(index: Int)
    case unknownOperation(name: String)
    case invalidArgumentCount(operation: String, expected: Int, actual: Int)
    case invalidScalar(operation: String, value: String)
    case invalidPositiveScalar(operation: String, value: String)
    case invalidFrequencyBand(operation: String, low: String, high: String)
    case invalidTimeRange(operation: String, start: String, end: String)
    case invalidRange(operation: String, low: String, high: String)

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
        case let .invalidTimeRange(operation, start, end):
            "\(operation) requires start < end, but received \(start) and \(end)"
        case let .invalidRange(operation, low, high):
            "\(operation) requires low < high, but received \(low) and \(high)"
        }
    }
}

// MARK: - Transformation

enum Transformation: Equatable {
    case removeDC
    case clampMin(Double)
    case clampMax(Double)
    case gate(Double)
    case offset(Double)
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
    case alignEdge(rising: Bool, threshold: Double, after: Double?)
    case seamless(rampDuration: Double?)
    case pad(duration: Double, value: Double?)
    case extendTo(endTime: Double, value: Double?)
    case resample(Double)
    case extractPeriod(threshold: Double?)
    case cutAfter(Double)
    case cutBefore(Double)
    case trim(start: Double, end: Double)
    case `repeat`(Double)
    case lowPass(Double)
    case highPass(Double)
    case bandPass(low: Double, high: Double)
    case bandStop(low: Double, high: Double)

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
                try requireArgumentCount(0)
                return .removeDC
            case "clampmin":
                return try .clampMin(scalar())
            case "clampmax":
                return try .clampMax(scalar())
            case "gate":
                return try .gate(scalar())
            case "offset":
                return try .offset(scalar())
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
            case "softclip",
                 "tanhlimit":
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
                // Digitize threshold
                // Digitize threshold, lowOut, highOut
                // Digitize lowThresh, highThresh, lowOut, highOut
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
            case "timescale",
                 "stretch":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .timeScale(value)
            case "alignedge",
                 "triggerat":
                guard arguments.count == 2 || arguments.count == 3 else {
                    throw TransformationParseError.invalidArgumentCount(
                        operation: operation,
                        expected: 2,
                        actual: arguments.count,
                    )
                }
                let direction = arguments[0].lowercased()
                let rising: Bool
                switch direction {
                case "rising", "rise", "up":
                    rising = true
                case "falling", "fall", "down":
                    rising = false
                default:
                    throw TransformationParseError.invalidScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                let threshold = try parseScalarArgument(arguments[1])
                let after: Double?
                if arguments.count == 3 {
                    after = try parseScalarArgument(arguments[2])
                }
                else {
                    after = nil
                }
                return .alignEdge(rising: rising, threshold: threshold, after: after)
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
                let holdValue: Double?
                if arguments.count == 2 {
                    holdValue = try parseScalarArgument(arguments[1])
                }
                else {
                    holdValue = nil
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
                let holdValue: Double?
                if arguments.count == 2 {
                    holdValue = try parseScalarArgument(arguments[1])
                }
                else {
                    holdValue = nil
                }
                return .extendTo(endTime: endTime, value: holdValue)
            case "resample":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(
                        operation: operation,
                        value: arguments[0],
                    )
                }
                return .resample(value)
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
                return .extractPeriod(threshold: try parseScalarArgument(arguments[0]))
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
            default:
                throw TransformationParseError.unknownOperation(name: operation)
            }
        }
    }

    var reportsPointCount: Bool {
        switch self {
        case .timeShift,
             .alignEdge,
             .seamless,
             .pad,
             .extendTo,
             .resample,
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
        default:
            nil
        }
    }

    func applying(to points: [Point], sampleInterval: Double? = nil) throws -> [Point] {
        switch self {
        case .removeDC:
            return offsetPoints(points, offset: -calculateDC(points))
        case let .clampMin(value):
            return clamp(points, lowerLimit: value, upperLimit: nil)
        case let .clampMax(value):
            return clamp(points, lowerLimit: nil, upperLimit: value)
        case let .gate(value):
            return gatePoints(points, threshold: value)
        case let .offset(value):
            return offsetPoints(points, offset: value)
        case let .multiply(value):
            return multiplyValueOfPoints(points, factor: value)
        case .invert:
            return multiplyValueOfPoints(points, factor: -1)
        case .abs:
            return absPoints(points)
        case .rectify:
            return rectifyPoints(points)
        case .normalize:
            return scalePeakTo(points, target: 1)
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
        case let .alignEdge(rising, threshold, after):
            return try alignEdgePoints(points, rising: rising, threshold: threshold, after: after)
        case let .seamless(rampDuration):
            return seamlessPoints(points, rampDuration: rampDuration)
        case let .pad(duration, value):
            return padPoints(points, duration: duration, value: value)
        case let .extendTo(endTime, value):
            return extendPoints(to: endTime, points: points, value: value)
        case let .resample(interval):
            return try resamplePoints(points, interval: interval)
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
