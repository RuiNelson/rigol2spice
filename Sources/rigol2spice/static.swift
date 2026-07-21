import Foundation
import SwiftEngineeringNumberFormatter

let usLocale = Locale(identifier: "en_US")

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

/// Console analysis output (scopes-style one fractional digit).
let analysisFormatter = EngineeringNumberFormatter(
    maximumFractionDigits: 1,
    locale: usLocale,
    useGreekMu: false,
)

/// Percentages are dimensionless and must never receive engineering prefixes.
let analysisPercentageFormatter: NumberFormatter = {
    let nf = NumberFormatter()
    nf.locale = usLocale
    nf.numberStyle = .decimal
    nf.minimumFractionDigits = 1
    nf.maximumFractionDigits = 1
    nf.usesGroupingSeparator = false
    return nf
}()
