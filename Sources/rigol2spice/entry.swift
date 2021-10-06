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
    @Argument(help: "The filename of the .csv from your oscilloscope", completion: CompletionKind.file(extensions: ["csv"]))
    var filename: String
    var filenameExpanded: String {
        NSString(string: filename).expandingTildeInPath
    }
    
    @Option(name: .shortAndLong, help: "The label of the channel to be processed (case sensitive)")
    var channel: String = "CH1"
    
    @Option(name: .shortAndLong, help: "Analyse the file and quit")
    var analyse: Bool = false
    
    mutating func run() throws {
        let cd = FileManager.default.currentDirectoryPath
        let cdUrl = URL(fileURLWithPath: cd)
        let url = URL(fileURLWithPath: filenameExpanded, relativeTo: cdUrl)
        
        let data = try Data(contentsOf: url)
        
        let (selChannel,points) = try CSVParser.parseCsv(data,
                                                         forChannel: channel,
                                                         analyse: analyse)
        
        if !analyse {
            for point in points  {
                print(point.serialize)
            }
        }
        else {
            var peakMin = Decimal.greatestFiniteMagnitude
            var peakMax = Decimal.greatestFiniteMagnitude * -1
            var timeSpan = Decimal(0)
            
            for point in points {
                let value = point.value
                if value < peakMin {
                    peakMin = value
                }
                if value > peakMax {
                    peakMax = value
                }
                
                let time = point.time
                if time > timeSpan {
                    timeSpan = time
                }
            }
            
            print("== Stats for \(selChannel.name) ==")
            print("Signal Peak Min:   \t \(peakMin) \(selChannel.unit ?? "")")
            print("Signal Peak Max:   \t \(peakMax) \(selChannel.unit ?? "")")
            print("Signal Points:     \t \(points.count)")
            print("Signal Last Point: \t \(timeSpan) s")
        }
    }
}
