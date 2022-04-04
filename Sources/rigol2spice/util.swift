//
//  File.swift
//  
//
//  Created by Rui Magalhães Carneiro on 04/04/2022.
//

import Foundation

let usLocale = Locale(identifier: "en_US")

let sixteenBitNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .scientific
    nf.locale = usLocale
    nf.maximumIntegerDigits = 1
    nf.maximumFractionDigits = 4
    nf.minimumFractionDigits = 4
    return nf
}()

let timeNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .scientific
    nf.locale = usLocale
    nf.minimumFractionDigits = 9
    nf.maximumFractionDigits = 14
    return nf
}()

func removeUnecessary(_ source: [Point]) -> [Point] {
    var previousValue: Double = Double.nan
    
    let output = source.filter { point in
        if point.value == previousValue {
            return false
        }
        else {
            previousValue = point.value
            return true
        }
    }
    
    return output
}

