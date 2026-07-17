import Foundation

struct Console {
    func section(_ text: String) {
        print("")
        print("> \(text)")
    }

    func detail(_ text: String, level: Int = 1) {
        let indentation = String(repeating: "    ", count: level)
        print("\(indentation)\(text)")
    }
}
