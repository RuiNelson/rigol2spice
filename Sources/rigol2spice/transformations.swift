import Foundation

// MARK: - TransformationParseError

enum TransformationParseError: LocalizedError, Equatable {
    case emptyCommand(index: Int)
    case unknownOperation(name: String)
    case invalidArgumentCount(operation: String, expected: Int, actual: Int)
    case invalidScalar(operation: String, value: String)
    case invalidPositiveScalar(operation: String, value: String)

    var errorDescription: String? {
        switch self {
        case let .emptyCommand(index):
            return "Transformation command \(index) is empty"
        case let .unknownOperation(name):
            return "Unknown transformation operation: \(name)"
        case let .invalidArgumentCount(operation, expected, actual):
            return "\(operation) expects \(expected) argument(s), but received \(actual)"
        case let .invalidScalar(operation, value):
            return "Invalid scalar for \(operation): \(value)"
        case let .invalidPositiveScalar(operation, value):
            return "\(operation) expects a positive scalar, but received: \(value)"
        }
    }
}

// MARK: - Transformation

enum Transformation: Equatable {
    case removeDC
    case clampMin(Double)
    case clampMax(Double)
    case offset(Double)
    case multiply(Double)
    case timeShift(Double)
    case cutAfter(Double)
    case `repeat`(Double)

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
                        actual: arguments.count
                    )
                }
            }

            func scalar() throws -> Double {
                try requireArgumentCount(1)
                let argument = arguments[0]
                guard !argument.contains(where: \Character.isWhitespace),
                      let value = parseEngineeringNotation(argument), value.isFinite else {
                    throw TransformationParseError.invalidScalar(operation: operation, value: argument)
                }
                return value
            }

            switch operation.lowercased() {
            case "removedc":
                try requireArgumentCount(0)
                return .removeDC
            case "clampmin":
                return try .clampMin(scalar())
            case "clampmax":
                return try .clampMax(scalar())
            case "offset":
                return try .offset(scalar())
            case "multiply":
                return try .multiply(scalar())
            case "timeshift":
                return try .timeShift(scalar())
            case "cutafter":
                let value = try scalar()
                guard value > 0 else {
                    throw TransformationParseError.invalidPositiveScalar(operation: operation, value: arguments[0])
                }
                return .cutAfter(value)
            case "repeat":
                let value = try scalar()
                guard value > 0, value < Double(Int.max) else {
                    throw TransformationParseError.invalidPositiveScalar(operation: operation, value: arguments[0])
                }
                return .repeat(value)
            default:
                throw TransformationParseError.unknownOperation(name: operation)
            }
        }
    }

    var reportsPointCount: Bool {
        switch self {
        case .timeShift,
             .cutAfter,
             .repeat:
            return true
        default:
            return false
        }
    }

    func applying(to points: [Point]) throws -> [Point] {
        switch self {
        case .removeDC:
            return offsetPoints(points, offset: -calculateDC(points))
        case let .clampMin(value):
            return clamp(points, lowerLimit: value, upperLimit: nil)
        case let .clampMax(value):
            return clamp(points, lowerLimit: nil, upperLimit: value)
        case let .offset(value):
            return offsetPoints(points, offset: value)
        case let .multiply(value):
            return multiplyValueOfPoints(points, factor: value)
        case let .timeShift(value):
            return timeShiftPoints(points, value: value)
        case let .cutAfter(value):
            return cutPointsAfter(points, after: value)
        case let .repeat(amount):
            return try repeatPoints(points, amount: amount)
        }
    }
}
