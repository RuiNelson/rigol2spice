import Foundation

func parseEngineeringNotation(_ input: String) -> Double? {
    engineeringFormatter.double(input)
}

extension String {
    static func + (lhs: String, rhs: [String]) -> String {
        lhs + rhs.joined(separator: " ")
    }
}
