//
//  File.swift
//  
//
//  Created by Rui Magalhães Carneiro on 04/04/2022.
//

import Foundation

let sixteenBitNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .scientific
    nf.maximumIntegerDigits = 1
    nf.maximumFractionDigits = 4
    nf.minimumFractionDigits = 4
    nf.localizesFormat = false
    return nf
}()

let tenGigasamplesNF: NumberFormatter = {
    let nf = NumberFormatter()
    nf.numberStyle = .scientific
    nf.maximumFractionDigits = 10
    nf.minimumFractionDigits = 10
    nf.localizesFormat = false
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

