//
//  parser.swift
//  rigol2spice
//
//  Created by Rui Nelson Carneiro on 05/10/2021.
//

import Foundation

public enum ParseError: LocalizedError {
    case invalidFileFormat
    case insufficientLines
    case noChannelsDetected
    case channelNotFound(channelLabel: String)
    case incrementNotFound
    case invalidIncrementValue(value: String)
    case sequenceNumberNotFoundOrInvalid(line: String)
    case invalidValue(value: String, line: String)
    
    public var errorDescription: String? {
        switch self {
            case .invalidFileFormat: return "Invalid file format"
            case .insufficientLines: return "No header or values found"
            case .noChannelsDetected: return "No channels found"
            case .channelNotFound(channelLabel: let channel): return "Specified channel \"\(channel)\" not found in file"
            case .incrementNotFound: return "Time increment not found"
            case .invalidIncrementValue(value: let valueStr): return "Time increment value is not valid: \(valueStr)"
            case .sequenceNumberNotFoundOrInvalid(line: let lineStr): return "Couldn't find sequence number in line: \(lineStr)"
            case .invalidValue(value: let val, line: let line): return "Invalid decimal number: \"\(val)\" in line: \(line)"
        }
    }
}

public struct Point {
    var time: Decimal
    var value: Decimal
    
    var serialize: String {
        return "\(time)\t\(value)"
    }
}

class CSVParser {
    private struct HeaderInfo {
        var channels: [Channel]
        var increment: Decimal?
    }
    
    private struct Channel {
        var name: String
        var row: Int
        var unit: String?
    }
    
    private static func parseFirstAndSecondLines(_ line1: String, _ line2: String) throws -> HeaderInfo {
        var channels: [Channel] = []
        var increment: Decimal!
        var incrementIndex: Int?
        
        // First Line
        let line1Fields = line1.split(separator: ",")
        
        for line1Field in line1Fields.enumerated() {
            let index = line1Field.offset
            let text = String(line1Field.element)
            
            if text.lowercased() == "x" {
                // no matter
                ()
            }
            else if text.lowercased() == "start" {
                // discard this value
                ()
            }
            else if text.lowercased() == "increment" {
                incrementIndex = index
            }
            else {
                // it's a channel!
                let newChannel = Channel(name: text, row: index, unit: nil)
                channels.append(newChannel)
            }
        }
        
        guard channels.count > 0 else {
            throw ParseError.noChannelsDetected
        }
        
        guard let incrementIndex = incrementIndex else {
            throw ParseError.incrementNotFound
        }
        
        // Second Line
        let line2Fields = line2.split(separator: ",")
        
        let incrementString = line2Fields[incrementIndex]
        guard let incrementDouble = Double(incrementString) else {
            throw ParseError.invalidIncrementValue(value: String(incrementString))
        }
        increment = Decimal(incrementDouble)
        
        channels = channels.map({
            var copy = $0
            let unit = line2Fields[$0.row]
            copy.unit = String(unit)
            return copy
        })
        
        return HeaderInfo(channels: channels, increment: increment)
    }
    
    private static func parsePoint(text: String, incrementTime: Decimal, row: Int) throws -> Point {
        let fields = text.split(separator: ",").map({return String($0)})
        
        guard let firstField = fields.first, let sequence = Int(firstField) else {
            throw ParseError.sequenceNumberNotFoundOrInvalid(line: text)
        }
        
        let time = incrementTime * Decimal(sequence)
        
        let valueField = fields[row]
        
        guard let valueDouble = Double(valueField) else {
            throw ParseError.invalidValue(value: valueField, line: text)
        }
        let valueDecimal = Decimal(valueDouble)
        
        return Point(time: time, value: valueDecimal)
    }
    
    public static func parseCsv(_ data: Data, forChannel channelLabel: String) throws -> [Point]{
        // Convert to string
        guard let input = String(data: data, encoding: .ascii) else {
            throw ParseError.invalidFileFormat
        }
        
        // Split lines
        var lines = input.split(whereSeparator: \.isNewline)
        
        guard lines.count > 2 else {
            throw ParseError.insufficientLines
        }
                
        // Process Header
        let headerInfo = try parseFirstAndSecondLines(String(lines.removeFirst()),
                                                      String(lines.removeFirst()))
        let increment = headerInfo.increment
        let channels = headerInfo.channels
        
        guard let increment = increment else {
            throw ParseError.incrementNotFound
        }
        
        guard let selectedChannel = channels.first(where: {$0.name == channelLabel}) else {
            throw ParseError.channelNotFound(channelLabel: channelLabel)
        }
        
        let selectedRow = selectedChannel.row
        
        // Process points
        let points: [Point] = try lines.map { substring in
            let string = String(substring)
            return try parsePoint(text: string, incrementTime: increment, row: selectedRow)
        }
        
        return points
    }
}

