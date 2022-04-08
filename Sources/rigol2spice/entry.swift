//
//  main.swift
//  rigol2spice
//
//  Created by Rui Nelson Carneiro on 05/10/2021.
//

import Foundation
import ArgumentParser

@main
struct rigol2spice: ParsableCommand {
    enum Rigol2SpiceErrors: LocalizedError {
        case outputFileNotSpeccified
        case inputFileContainsNoPoints
        case invalidDownsampleValue(value: Int)
        
        var errorDescription: String? {
            switch self {
            case .outputFileNotSpeccified: return "Please speccify the output file name after the input file name"
            case .inputFileContainsNoPoints: return "Input file contains zero points"
            case .invalidDownsampleValue(value: let v): return "Invalid downsample value: \(v)"
            }
        }
    }
    
    @Flag(name: .shortAndLong, help: "Only list channels present in the file and quit")
    var listChannels: Bool = false
    
    @Option(name: .shortAndLong, help: "The label of the channel to be processed")
    var channel: String = "CH1"
    
    @Option(name: [.customLong("ds", withSingleDash: true), .customLong("downsample", withSingleDash: false)], help: "Downsample ratio")
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
    var outputFileExapnded: String {
        guard let outputFile = outputFile else {
            return ""
        }
        return NSString(string: outputFile).expandingTildeInPath
    }
        
    mutating func run() throws {
        // argument validation
        if listChannels == false {
            guard outputFile != nil else {
                throw Rigol2SpiceErrors.outputFileNotSpeccified
            }
        }
        
        // Loading
        print("→ Loading input file...")
        let inputFileUrl = URL(fileURLWithPath: inputFileExpanded, relativeTo: cdUrl)

        let data = try Data(contentsOf: inputFileUrl)
        
        let numBytesString = decimalNF.string(for: data.count)!
        
        print("  " + "Read \(numBytesString) bytes")
        
        // Parsing
        print("")
        print("→ Parsing input file...")
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
            
            print("  " + "Sample 𝛥t: \(timeIntervalString) s")
            print("  " + "Sample Rate: \(sampleRateString) sa/s")
        }
        
        if let ds = downsample {
            guard ds > 1 else {
                throw Rigol2SpiceErrors.invalidDownsampleValue(value: ds)
            }
            
            print("")
            print("→ Downsampling...")
            
            let beforePoints = points.count
            points = downsamplePoints(points, interval: ds)
            let afterPoints = points.count
            
            let beforePointsString = decimalNF.string(for: beforePoints)!
            let afterPointString = decimalNF.string(for: afterPoints)!
            
            print("  " + "From \(beforePointsString) to \(afterPointString) points")
        }
        
        // Compacting...
        if(!keepAll) {
            print("")
            print("→ Removing redundant points...")
            
            let beforePoints = points.count
            
            points = removeUnecessary(points)
            
            let afterPoints = points.count
            
            print("  " + "From \(decimalNF.string(for: beforePoints)!) points to \(decimalNF.string(for: afterPoints)!) points")
        }
        
        // Output
        print("")
        print("→ Writing output file...")
        let outputFileUrl = URL(fileURLWithPath: outputFileExapnded, relativeTo: cdUrl)
        
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
        print("→ Job complete ✓")
    }
}
