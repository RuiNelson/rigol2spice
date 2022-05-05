// (C) Rui Carneiro

import Foundation
import SwiftEngineeringNumberFormatter

let usLocale = Locale(identifier: "en_US")

let valueNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.locale = usLocale
    nf.numberStyle = .decimal
    nf.minimumSignificantDigits = 3
    nf.maximumSignificantDigits = 14
    return nf
}()

let timeNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.locale = usLocale
    nf.numberStyle = .decimal
    nf.minimumFractionDigits = 12
    nf.maximumFractionDigits = 14
    return nf
}()

let engineeringNF: EngineeringNumberFormatter = {
    let nf = EngineeringNumberFormatter()
    nf.locale = usLocale
    nf.maximumFractionDigits = 12
    nf.useGreekMu = false
    return nf
}()

let decimalNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.hasThousandSeparators = true
    return nf
}()

let memBCF: ByteCountFormatter = {
    let bcf = ByteCountFormatter()
    bcf.countStyle = .file
    return bcf
}()

// static
let newlineBytes = "\r\n".data(using: .ascii)!
let cd = FileManager.default.currentDirectoryPath
let cdUrl = URL(fileURLWithPath: cd)
