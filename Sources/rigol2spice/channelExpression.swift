import Foundation

// MARK: - ChannelExpressionError

enum ChannelExpressionError: LocalizedError, Equatable {
    case empty
    case unexpectedCharacter(Character)
    case unexpectedToken(String)
    case unexpectedEnd
    case divisionByZero

    var errorDescription: String? {
        switch self {
        case .empty:
            "Channel expression is empty"
        case let .unexpectedCharacter(character):
            "Unexpected character in channel expression: \(character)"
        case let .unexpectedToken(token):
            "Unexpected token in channel expression: \(token)"
        case .unexpectedEnd:
            "Unexpected end of channel expression"
        case .divisionByZero:
            "Division by zero in channel expression"
        }
    }
}

// MARK: - ChannelBinaryOperator

enum ChannelBinaryOperator: Equatable {
    case add
    case subtract
    case multiply
    case divide

    var symbol: String {
        switch self {
        case .add: "+"
        case .subtract: "-"
        case .multiply: "*"
        case .divide: "/"
        }
    }
}

// MARK: - ChannelExpression

indirect enum ChannelExpression: Equatable {
    case channel(String)
    case unaryMinus(ChannelExpression)
    case binary(ChannelBinaryOperator, ChannelExpression, ChannelExpression)

    /// Channel names as they appear in the expression, in first-seen order.
    var channelNames: [String] {
        var names: [String] = []
        var seen = Set<String>()
        collectChannelNames(into: &names, seen: &seen)
        return names
    }

    var description: String {
        switch self {
        case let .channel(name):
            name
        case let .unaryMinus(expression):
            "-\(expression.parenthesizedDescription)"
        case let .binary(op, lhs, rhs):
            "\(lhs.parenthesizedDescription)\(op.symbol)\(rhs.parenthesizedDescription)"
        }
    }

    private var parenthesizedDescription: String {
        switch self {
        case .channel:
            description
        case .unaryMinus,
             .binary:
            "(\(description))"
        }
    }

    private func collectChannelNames(into names: inout [String], seen: inout Set<String>) {
        switch self {
        case let .channel(name):
            let key = name.lowercased()
            if seen.insert(key).inserted {
                names.append(name)
            }
        case let .unaryMinus(expression):
            expression.collectChannelNames(into: &names, seen: &seen)
        case let .binary(_, lhs, rhs):
            lhs.collectChannelNames(into: &names, seen: &seen)
            rhs.collectChannelNames(into: &names, seen: &seen)
        }
    }

    func evaluate(channels: [String: Double]) throws -> Double {
        switch self {
        case let .channel(name):
            if let value = channels[name] {
                return value
            }
            let match = channels.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }
            return match?.value ?? 0
        case let .unaryMinus(expression):
            return try -expression.evaluate(channels: channels)
        case let .binary(op, lhs, rhs):
            let left = try lhs.evaluate(channels: channels)
            let right = try rhs.evaluate(channels: channels)
            switch op {
            case .add:
                return left + right
            case .subtract:
                return left - right
            case .multiply:
                return left * right
            case .divide:
                guard right != 0 else {
                    throw ChannelExpressionError.divisionByZero
                }
                return left / right
            }
        }
    }
}

// MARK: - Parsing

func parseChannelExpression(_ source: String) throws -> ChannelExpression {
    var parser = ChannelExpressionParser(source)
    return try parser.parse()
}

// MARK: - ChannelExpressionParser

private struct ChannelExpressionParser {
    private enum Token: Equatable {
        case identifier(String)
        case plus
        case minus
        case star
        case slash
        case leftParen
        case rightParen
        case end
    }

    private let source: String
    private var index: String.Index
    private var current: Token = .end

    init(_ source: String) {
        self.source = source
        self.index = source.startIndex
    }

    mutating func parse() throws -> ChannelExpression {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ChannelExpressionError.empty
        }

        try advance()
        let expression = try parseExpression()
        guard current == .end else {
            throw ChannelExpressionError.unexpectedToken(tokenDescription(current))
        }
        return expression
    }

    private mutating func parseExpression() throws -> ChannelExpression {
        var expression = try parseTerm()
        while true {
            switch current {
            case .plus:
                try advance()
                expression = try .binary(.add, expression, parseTerm())
            case .minus:
                try advance()
                expression = try .binary(.subtract, expression, parseTerm())
            default:
                return expression
            }
        }
    }

    private mutating func parseTerm() throws -> ChannelExpression {
        var expression = try parseUnary()
        while true {
            switch current {
            case .star:
                try advance()
                expression = try .binary(.multiply, expression, parseUnary())
            case .slash:
                try advance()
                expression = try .binary(.divide, expression, parseUnary())
            default:
                return expression
            }
        }
    }

    private mutating func parseUnary() throws -> ChannelExpression {
        switch current {
        case .plus:
            try advance()
            return try parseUnary()
        case .minus:
            try advance()
            return try .unaryMinus(parseUnary())
        default:
            return try parsePrimary()
        }
    }

    private mutating func parsePrimary() throws -> ChannelExpression {
        switch current {
        case let .identifier(name):
            try advance()
            return .channel(name)
        case .leftParen:
            try advance()
            let expression = try parseExpression()
            guard current == .rightParen else {
                throw ChannelExpressionError.unexpectedToken(tokenDescription(current))
            }
            try advance()
            return expression
        case .end:
            throw ChannelExpressionError.unexpectedEnd
        default:
            throw ChannelExpressionError.unexpectedToken(tokenDescription(current))
        }
    }

    private mutating func advance() throws {
        skipWhitespace()
        guard index < source.endIndex else {
            current = .end
            return
        }

        let character = source[index]
        switch character {
        case "+":
            source.formIndex(after: &index)
            current = .plus
        case "-":
            source.formIndex(after: &index)
            current = .minus
        case "*":
            source.formIndex(after: &index)
            current = .star
        case "/":
            source.formIndex(after: &index)
            current = .slash
        case "(":
            source.formIndex(after: &index)
            current = .leftParen
        case ")":
            source.formIndex(after: &index)
            current = .rightParen
        default:
            if character.isLetter || character == "_" {
                current = .identifier(readIdentifier())
            }
            else {
                throw ChannelExpressionError.unexpectedCharacter(character)
            }
        }
    }

    private mutating func skipWhitespace() {
        while index < source.endIndex, source[index].isWhitespace {
            source.formIndex(after: &index)
        }
    }

    private mutating func readIdentifier() -> String {
        let start = index
        while index < source.endIndex {
            let character = source[index]
            if character.isLetter || character.isNumber || character == "_" {
                source.formIndex(after: &index)
            }
            else {
                break
            }
        }
        return String(source[start ..< index])
    }

    private func tokenDescription(_ token: Token) -> String {
        switch token {
        case let .identifier(name): name
        case .plus: "+"
        case .minus: "-"
        case .star: "*"
        case .slash: "/"
        case .leftParen: "("
        case .rightParen: ")"
        case .end: "end"
        }
    }
}
