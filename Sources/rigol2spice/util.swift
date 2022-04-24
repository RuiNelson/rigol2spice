// (C) Rui Carneiro

import Foundation

func parseEngineeringNotation(_ input: String) -> Double? {
    var numberStr = input

    if numberStr.hasSuffix("s") || numberStr.hasSuffix("S") {
        numberStr.removeLast()
    }

    let signal: Double = {
        let lowercased = input.lowercased()

        if lowercased.hasPrefix("l") || lowercased.hasPrefix("m") || lowercased.hasPrefix("n") || lowercased.hasPrefix("d") {
            numberStr.removeFirst()
            return -1
        } else if lowercased.hasPrefix("r") || lowercased.hasPrefix("p") || lowercased.hasPrefix("u") {
            numberStr.removeFirst()
            return +1
        } else {
            return +1
        }
    }()

    guard let value = engineeringNF.double(numberStr) else {
        return nil
    }

    return signal * value
}
