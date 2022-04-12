//
//  File.swift
//
//
//  Created by Rui Magalhães Carneiro on 08/04/2022.
//

import Foundation
import SwiftEngineeringNumberFormatter

let usLocale = Locale(identifier: "en_US")

let valueNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.locale = usLocale
    nf.numberStyle = .decimal
    nf.maximumFractionDigits = 14
    return nf
}()

let timeNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.locale = usLocale
    nf.numberStyle = .decimal
    nf.minimumFractionDigits = 9
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

// static
let newlineBytes = "\r\n".data(using: .ascii)!
let cd = FileManager.default.currentDirectoryPath
let cdUrl = URL(fileURLWithPath: cd)
