//
//  File.swift
//  
//
//  Created by Rui Magalhães Carneiro on 04/04/2022.
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
    nf.minimumFractionDigits = 1
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

func downsamplePoints(_ source: [Point], interval: Int) -> [Point] {
    var i = 0
    
    let downsampled = source.filter {_ in
        i += 1
        return (i % interval) == 0
    }
    
    return downsampled
}
