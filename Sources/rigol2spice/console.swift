import Foundation

enum Console {
    static func section(_ text: String) {
        print("")
        print("> \(text)")
    }

    static func detail(_ text: String, level: Int = 1) {
        let indentation = String(repeating: "    ", count: level)
        print("\(indentation)\(text)")
    }
}
