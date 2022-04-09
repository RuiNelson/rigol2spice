//
//  main.swift
//  rigol2spice
//
//  Created by Rui Nelson Carneiro on 05/10/2021.
//

import Foundation
import ArgumentParser

enum Rigol2SpiceErrors: LocalizedError {
    case outputFileNotSpecified
    case inputFileContainsNoPoints
    case invalidDownsampleValue(value: Int)
    case invalidTimeShiftValue(value: String)
    case invalidCutAfterValue(value: String)
    case invalidRepeatCountValue(value: Int)
    case mustHaveAtLeastTwoPointsToRepeat
    case operationRemovedEveryPoint
    
    var errorDescription: String? {
        switch self {
        case .outputFileNotSpecified: return "Please specify the output file name after the input file name"
        case .inputFileContainsNoPoints: return "Input file contains zero points"
        case .invalidDownsampleValue(value: let v): return "Invalid downsample value: \(v)"
        case .invalidTimeShiftValue(value: let v): return "Invalid time-shift value: \(v)"
        case .invalidCutAfterValue(value: let v): return "Invalid cut timestamp: \(v)"
        case .invalidRepeatCountValue(value: let v): return "Invalid repeat count value: \(v)"
        case .mustHaveAtLeastTwoPointsToRepeat: return "Must have at least two original points to repeat points"
        case .operationRemovedEveryPoint: return "Operation removed every point"
        }
    }
}


@main
struct rigol2spice: ParsableCommand {

    
    @Flag(name: .shortAndLong, help: "Only list channels present in the file and quit")
    var listChannels: Bool = false
    
    @Option(name: .shortAndLong, help: "The label of the channel to be processed")
    var channel: String = "CH1"
    
    @Option(name: [.customShort("s"), .customLong("shift")], help: "Time-shift seconds")
    var timeShift: String?
    
    @Option(name: [.customShort("x"), .customLong("cut")], help: "Cut signal after timestamp")
    var cut: String?
    
    @Option(name: [.customShort("r"), .customLong("repeat")], help: "Repeat signal number of times")
    var repeatTimes: Int?
    
    @Option(name: .shortAndLong, help: "Downsample ratio")
    var downsample: Int?
    
    @Flag(name: .shortAndLong, help: "Don't remove redundant points. Points where the signal value maintains (useful for output file post-processing)")
    var keepAll: Bool = false
    
    @Argument(help: "The filename of the .csv from the oscilloscope to be read", completion: CompletionKind.file(extensions: ["csv"]))
    var inputFile: String
    var inputFileExpanded: String {
        NSString(string: inputFile).expandingTildeInPath
    }
    
    @Argument(help: "The PWL filename to write to", completion: nil)
    var outputFile: String?
    var outputFileExpanded: String {
        guard let outputFile = outputFile else {
            return ""
        }
        return NSString(string: outputFile).expandingTildeInPath
    }
    
    func nPointsReport(before: Int, after: Int) throws {
        guard after > 0 else {
            throw Rigol2SpiceErrors.operationRemovedEveryPoint
        }
        
        if after != before {
            let beforeString = decimalNF.string(for: before)!
            let afterString = decimalNF.string(for: after)!
            
            print ("  " + "From \(beforeString) samples to \(afterString) samples")
        }
        else {
            print("  " + "Maintained all the samples")
        }
    }
    
    mutating func run() throws {
        // argument validation
        if listChannels == false {
            guard outputFile != nil else {
                throw Rigol2SpiceErrors.outputFileNotSpecified
            }
        }
        
        // Loading
        print("> Loading input file...")
        let inputFileUrl = URL(fileURLWithPath: inputFileExpanded, relativeTo: cdUrl)
        
        let data = try Data(contentsOf: inputFileUrl)
        
        let numBytesString = decimalNF.string(for: data.count)!
        
        print("  " + "Read \(numBytesString) bytes")
        
        // Parsing
        print("")
        print("> Parsing input file...")
        var points = try CSVParser.parseCsv(data,
                                            forChannel: channel,
                                            listChannelsOnly: listChannels)
        
        guard listChannels == false else {
            return
        }
        
        guard points.isEmpty == false else {
            throw Rigol2SpiceErrors.inputFileContainsNoPoints
        }
        
        let lastTime = points.last!.time
        
        let nPointsString = decimalNF.string(for: points.count)!
        let lastPointString = scientificNF.string(for: lastTime)!
        
        print("  " + "Points: \(nPointsString)")
        print("  " + "Last Point: \(lastPointString) s")
        
        // Sample rate
        if points.count >= 2 {
            let firstPointTime = points.first!.time
            let lastPointTime = points.last!.time
            let nPoints = Double(points.count)
            
            let timeInterval = (lastPointTime - firstPointTime) / (nPoints - 1)
            let sampleRate = 1 / timeInterval
            
            let timeIntervalString = scientificNF.string(for: timeInterval)!
            let sampleRateString = decimalNF.string(for: sampleRate)!
            
            print("  " + "Sample Interval: \(timeIntervalString) s")
            print("  " + "Sample Rate: \(sampleRateString) sa/s")
        }
        
        // Time-shift
        if let timeShift = timeShift {
            guard let timeShiftValue = parseEngineeringNotation(timeShift) else {
                throw Rigol2SpiceErrors.invalidTimeShiftValue(value: timeShift)
            }
            
            let timeShiftValueString = scientificNF.string(for: timeShiftValue)!
            
            print("")
            print("> Shifting signal for \(timeShiftValueString) s")
            
            let nPointsBefore = points.count
            points = timeShiftPoints(points, value: timeShiftValue)
            let nPointsAfter = points.count
            
            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }
        // Cut
        if let cut = cut {
            guard let cutValue = parseEngineeringNotation(cut), cutValue > 0 else {
                throw Rigol2SpiceErrors.invalidCutAfterValue(value: cut)
            }
            
            let cutValueString = scientificNF.string(for: cutValue)!
            
            print("")
            print("> Cutting signal after \(cutValueString) s")
            
            let nPointsBefore = points.count
            points = cutAfter(points, after: cutValue)
            let nPointsAfter = points.count
            
            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }
        
        // Repeat
        if let repeatTimes = repeatTimes {
            guard repeatTimes > 0 else {
                throw Rigol2SpiceErrors.invalidRepeatCountValue(value: repeatTimes)
            }
            
            print("")
            print("> Repeating signal for \(repeatTimes) times")
            
            let nPointsBefore = points.count
            points = try repeatPoints(points, n: repeatTimes)
            let nPointsAfter = points.count
            
            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }
        
        // Downsample
        if let ds = downsample {
            guard ds > 1 else {
                throw Rigol2SpiceErrors.invalidDownsampleValue(value: ds)
            }
            
            print("")
            print("> Downsampling...")
            
            let nPointsBefore = points.count
            points = downsamplePoints(points, interval: ds)
            let nPointsAfter = points.count
            
            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }
        
        // Compacting...
        if(!keepAll) {
            print("")
            print("> Removing redundant points (optimize)...")
            
            let nPointsBefore = points.count
            points = removeRedundant(points)
            let nPointsAfter = points.count
            
            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }
        
        // Output
        print("")
        print("> Writing output file...")
        let nPoints = points.count
        let firstPointTime = points.first!.time
        let lastPointTime = points.last!.time
    
        let nSamplesString = decimalNF.string(for: nPoints)!
        let firstSampleString = scientificNF.string(for: firstPointTime)!
        let lastSampleString = scientificNF.string(for: lastPointTime)!
        
        print("  " + "Number of points: \(nSamplesString)")
        print("  " + "First sample: \(firstSampleString)")
        print("  " + "Last sample: \(lastSampleString)")
        
        let outputFileUrl = URL(fileURLWithPath: outputFileExpanded, relativeTo: cdUrl)
        
        if FileManager.default.fileExists(atPath: outputFileUrl.path) {
            try FileManager.default.removeItem(at: outputFileUrl)
        }
        
        FileManager.default.createFile(atPath: outputFileUrl.path, contents: nil)
        
        let outputFileHandle = try FileHandle(forWritingTo: outputFileUrl)
        
        for point in points {
            let pointBytes = point.serialize.data(using: .ascii)!
            outputFileHandle.write(pointBytes)
            outputFileHandle.write(newlineBytes)
        }
        
        outputFileHandle.closeFile()
        
        print("")
        print("> Job complete")
        print("")
    }
}
