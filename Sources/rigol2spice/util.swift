import Foundation

func parseEngineeringNotation(_ input: String) -> Double? {
    var numberStr = input
    let lowercasedNumberStr = numberStr.lowercased()

    let suffixesToIgnore = ["s", "v", "x"] // seconds, volts, times
    let negativePrefixes = ["l", "m", "n", "d"] // left, minus, negative, down
    let positivePrefixes = ["r", "p", "u"] // right, plus/positive, up

    // Remove suffixes to ignore
    if let lastCharLowercased = lowercasedNumberStr.last,
        suffixesToIgnore.contains(String(lastCharLowercased)) {
        numberStr.removeLast()
    }

    // Determine the signal of the number
    let signal: Double = {
        guard let firstCharLowercased = lowercasedNumberStr.first else {
            return 1
        }
        
        let firstCharLowercasedStr = String(firstCharLowercased)
        
        if negativePrefixes.contains(firstCharLowercasedStr) {
            numberStr.removeFirst()
            return -1
        }
        else if positivePrefixes.contains(firstCharLowercasedStr) {
            numberStr.removeFirst()
            return 1
        }
        
        return 1 // Default to positive
    }()

    // Parse the number
    guard let value = engineeringFormatter.double(numberStr) else {
        return nil
    }

    return signal * value
}

extension String {
    static func + (lhs: String, rhs: [String]) -> String {
        lhs + rhs.joined(separator: " ")
    }
}
