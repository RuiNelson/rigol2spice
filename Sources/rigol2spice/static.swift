import Foundation
import SwiftEngineeringNumberFormatter

let usLocale = Locale(identifier: "en_US")

// MARK: - LockedByteCountFormatter

final class LockedByteCountFormatter: @unchecked Sendable {
    private let formatter: ByteCountFormatter
    private let lock = NSLock()

    init() {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        self.formatter = formatter
    }

    func string(fromByteCount byteCount: Int64) -> String {
        lock.lock()
        defer { lock.unlock() }
        return formatter.string(fromByteCount: byteCount)
    }
}

let spiceFormatter: NumberFormatter = {
    let nf = NumberFormatter()
    nf.locale = usLocale
    nf.numberStyle = .decimal
    nf.minimumSignificantDigits = 1
    nf.maximumSignificantDigits = 14
    return nf
}()

let numberOfPointsFormatter: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.usesGroupingSeparator = true
    return nf
}()

let engineeringFormatter = EngineeringNumberFormatter(
    maximumFractionDigits: 12,
    locale: usLocale,
    useGreekMu: false,
)

let fileSizeFormatter = LockedByteCountFormatter()

// static
let newlineBytes = "\r\n".data(using: .ascii)!
let cd = FileManager.default.currentDirectoryPath
let cdURL = URL(fileURLWithPath: cd)
