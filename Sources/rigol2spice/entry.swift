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
    @Argument(help: "The filename of the .csv file from your oscilloscope", completion: CompletionKind.file(extensions: ["csv"]))
    var inFile: String
    var inFileExpanded: String {
        NSString(string: inFile).expandingTildeInPath
    }
    
    @Option(name: .shortAndLong, help: "The label of the channel to be processed (case sensitive)")
    var channel: String = "CH1"
    
    mutating func run() throws {
        let cd = FileManager.default.currentDirectoryPath
        let cdUrl = URL(fileURLWithPath: cd)
        let url = URL(fileURLWithPath: inFileExpanded, relativeTo: cdUrl)
        
        let data = try Data(contentsOf: url)
        
        for point in try CSVParser.parseCsv(data, forChannel: channel) {
            print(point.serialize)
        }
    }
}
