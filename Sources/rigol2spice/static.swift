//
//  File.swift
//  
//
//  Created by Rui Magalhães Carneiro on 08/04/2022.
//

import Foundation

let usLocale = Locale(identifier: "en_US")

let valueNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.locale = usLocale
    nf.maximumFractionDigits = 14
    return nf
}()

let timeNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.locale = usLocale
    nf.minimumFractionDigits = 9
    nf.maximumFractionDigits = 14
    return nf
}()

let scientificNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .scientific
    nf.locale = usLocale
    nf.minimumFractionDigits = 2
    nf.maximumFractionDigits = 14
    return nf
}()

let decimalNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.locale = usLocale
    nf.hasThousandSeparators = true
    return nf
}()

// static
let newlineBytes = "\r\n".data(using: .ascii)!
let cd = FileManager.default.currentDirectoryPath
let cdUrl = URL(fileURLWithPath: cd)


