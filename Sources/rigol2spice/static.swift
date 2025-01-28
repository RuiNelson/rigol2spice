import Foundation
import SwiftEngineeringNumberFormatter

let usLocale = Locale(identifier: "en_US")

let spiceFormatter: NumberFormatter = {
    let nf = NumberFormatter()
    nf.locale = usLocale
    nf.numberStyle = .decimal
    nf.minimumSignificantDigits = 1
    nf.maximumSignificantDigits = 16
    return nf
}()

let engineeringFormatter: EngineeringNumberFormatter = {
    let nf = EngineeringNumberFormatter()
    nf.locale = usLocale
    nf.maximumFractionDigits = 12
    nf.useGreekMu = false
    return nf
}()

let fileSizeFormatter: ByteCountFormatter = {
    let bcf = ByteCountFormatter()
    bcf.countStyle = .file
    return bcf
}()

// static
let newlineBytes = "\r\n".data(using: .ascii)!
let cd = FileManager.default.currentDirectoryPath
let cdURL = URL(fileURLWithPath: cd)
