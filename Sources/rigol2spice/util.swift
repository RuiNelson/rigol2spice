import Foundation

func parseEngineeringNotation(_ input: String) -> Double? {
    if let value = engineeringFormatter.double(input) {
        return value
    }

    let characters = Array(input)
    guard let numberEnd = numericPrefixEnd(in: characters), numberEnd < characters.endIndex else {
        return nil
    }

    let unitStart = engineeringPrefixEnd(in: characters, after: numberEnd)
    let unit = characters[unitStart...]
    guard unit.allSatisfy(isUnitCharacter) else {
        return nil
    }

    return engineeringFormatter.double(String(characters[..<unitStart]))
}

private func numericPrefixEnd(in characters: [Character]) -> Int? {
    var index = characters.startIndex

    if index < characters.endIndex, characters[index] == "+" || characters[index] == "-" {
        index += 1
    }

    var hasDigit = false
    while index < characters.endIndex, characters[index].isNumber {
        hasDigit = true
        index += 1
    }

    if index < characters.endIndex, characters[index] == "." {
        index += 1
        while index < characters.endIndex, characters[index].isNumber {
            hasDigit = true
            index += 1
        }
    }

    guard hasDigit else {
        return nil
    }

    if index < characters.endIndex, characters[index] == "e" || characters[index] == "E" {
        var exponentIndex = index + 1
        if exponentIndex < characters.endIndex,
           characters[exponentIndex] == "+" || characters[exponentIndex] == "-" {
            exponentIndex += 1
        }

        let exponentStart = exponentIndex
        while exponentIndex < characters.endIndex, characters[exponentIndex].isNumber {
            exponentIndex += 1
        }
        if exponentIndex > exponentStart {
            index = exponentIndex
        }
    }

    return index
}

private func engineeringPrefixEnd(in characters: [Character], after numberEnd: Int) -> Int {
    guard numberEnd + 1 < characters.endIndex else {
        return numberEnd
    }

    let candidate = String(characters[..<(numberEnd + 1)])
    return engineeringFormatter.double(candidate) == nil ? numberEnd : numberEnd + 1
}

private func isUnitCharacter(_ character: Character) -> Bool {
    character.isLetter || character == "µ" || character == "μ" || character == "Ω" || character == "Ω"
        || character == "/" || character == "·" || character == "²" || character == "³"
}
