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
    case movingAverage(Int)
    case diff
    case integrate
    case deadZone(Double)
    case limit(lower: Double, upper: Double)
    case db(Double)
    case dbmW(level: Double, resistance: Double)
    case dbW(level: Double, resistance: Double)
    case timeShift(Double)
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
        case let .movingAverage(window):
            return movingAveragePoints(points, window: window)
        case .diff:
            return differentiatePoints(points)
        case .integrate:
            return integratePoints(points)
        case let .deadZone(value):
            return deadZonePoints(points, threshold: value)
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
