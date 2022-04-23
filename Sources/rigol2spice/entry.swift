// (C) Rui Carneiro

import ArgumentParser
import Foundation
import Progress

enum Rigol2SpiceErrors: LocalizedError {
    case outputFileNotSpecified
    case inputFileContainsNoPoints
    case invalidOffsetValue(value: String)
    case invalidAmplificationValue(value: String)
    case invalidDownsampleValue(value: Int)
    case invalidTimeShiftValue(value: String)
    case invalidCutAfterValue(value: String)
    case invalidRepeatCountValue(value: Int)
    case mustHaveAtLeastTwoPointsToRepeat
    case operationRemovedEveryPoint

    var errorDescription: String? {
        switch self {
        case .outputFileNotSpecified: return "Please specify the output file name after the input file name"
        case .inputFileContainsNoPoints: return "Input file contains zero samples"
        case let .invalidOffsetValue(value: v): return "Invalid offset value: \(v)"
        case let .invalidAmplificationValue(value: v): return "Invalid amplification factor: \(v)"
        case let .invalidDownsampleValue(value: v): return "Invalid downsample value: \(v)"
        case let .invalidTimeShiftValue(value: v): return "Invalid time-shift value: \(v)"
        case let .invalidCutAfterValue(value: v): return "Invalid cut timestamp: \(v)"
        case let .invalidRepeatCountValue(value: v): return "Invalid repeat count value: \(v)"
        case .mustHaveAtLeastTwoPointsToRepeat: return "Must have at least two original samples to repeat capture"
        case .operationRemovedEveryPoint: return "Operation removed every sample"
        }
    }
}

@main
struct rigol2spice: ParsableCommand {
    @Flag(name: .shortAndLong, help: "Only list channels present in the file and quit")
    var listChannels: Bool = false

    @Option(name: .shortAndLong, help: "The label of the channel to be processed")
    var channel: String = "CH1"
    
    @Flag(name: [.customLong("dc", withSingleDash: true), .customLong("remove-dc")], help: "Remove DC component")
    var removeDc: Bool = false
    
    @Option(name: .shortAndLong, help: "Offset factor for signal")
    var offset: String?
    
    @Option(name: .shortAndLong, help: "Multiplication factor for signal")
    var multiplication: String?
    
    @Option(name: [.customShort("s"), .customLong("shift")], help: "Time-shift seconds")
    var timeShift: String?

    @Option(name: [.customShort("x"), .customLong("cut")], help: "Cut signal after timestamp")
    var cut: String?

    @Option(name: [.customShort("r"), .customLong("repeat")], help: "Repeat signal number of times")
    var repeatTimes: Int?

    @Option(name: .shortAndLong, help: "Downsample ratio")
    var downsample: Int?

    @Flag(name: .shortAndLong, help: "Don't remove redundant sample points. Sample points where the signal value maintains (useful for output file post-processing)")
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

            print("  " + "From \(beforeString) samples to \(afterString) samples")
        } else {
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
        let numBytes = data.count
        let numBytesString = decimalNF.string(for: numBytes)!

        print("  " + "Read \(numBytesString) bytes")

        // Parsing
        print("")
        print("> Parsing input file...")
        if numBytes > 1000000 {
            print("  " + "(This might take a while)")
        }
        var points = try CSVParser.parseCsv(data,
                                            forChannel: channel,
                                            listChannelsOnly: listChannels)

        guard !listChannels else {
            return
        }

        guard !points.isEmpty else {
            throw Rigol2SpiceErrors.inputFileContainsNoPoints
        }

        let firstPointTime = points.first!.time
        let lastPointTime = points.last!.time
        var sampleTimeInterval = 0.0

        let nPointsString = decimalNF.string(for: points.count)!
        let lastPointString = engineeringNF.string(lastPointTime)

        print("  " + "Samples: \(nPointsString)")
        print("  " + "Last Sample Point: \(lastPointString)s")

        // Sample Rate Calculation
        if points.count >= 2 {
            let nPoints = Double(points.count)

            sampleTimeInterval = (lastPointTime - firstPointTime) / (nPoints - 1)
            let sampleRate = 1 / sampleTimeInterval

            let timeIntervalString = engineeringNF.string(sampleTimeInterval)
            let sampleRateString = engineeringNF.string(sampleRate)

            print("  " + "Sample Interval: \(timeIntervalString)s")
            print("  " + "Sample Rate: \(sampleRateString)sa/s")
        }
        
        // Removing DC component
        if removeDc {
            print("")
            print("> Removing DC component...")
            
            let dcRemoved = removeDC(points)
            
            let dcComponentStr = engineeringNF.string(dcRemoved.dcComponent)
            print("  " + "DC Component: \(dcComponentStr) units")
            
            points = dcRemoved.points
        }
        
        // Offset
        if let offset = offset {
            guard let offsetValue = parseEngineeringNotation(offset) else {
                throw Rigol2SpiceErrors.invalidOffsetValue(value: offset)
            }
            
            engineeringNF.positiveSign = "+"
            let offsetValueStr = engineeringNF.string(offsetValue)
            engineeringNF.positiveSign = ""
            
            print("")
            print("> Offsetting signal by \(offsetValueStr) units...")
            
            points = offsetPoints(points, offset: offsetValue)
        }
        
        // Multiplication
        if let multiplication = multiplication {
            guard let multiplicationFactor = parseEngineeringNotation(multiplication) else {
                throw Rigol2SpiceErrors.invalidAmplificationValue(value: multiplication)
            }
            
            let isAttenuation = abs(multiplicationFactor) < 1.0
            
            let amplificationFactor = multiplicationFactor
            let attenuationFactor = 1 / multiplicationFactor
            
            let verb = isAttenuation ? "Attenuating" : "Amplifying"
            let value = isAttenuation ? attenuationFactor : amplificationFactor
            let valueStr = decimalNF.string(for: value)!
            
            print("")
            print("> \(verb) signal by a factor of \(valueStr)...")
            
            points = multiplyValueOfPoints(points, factor: multiplicationFactor)
        }

        // Time-shift
        if let timeShift = timeShift {
            guard let timeShiftValue = parseEngineeringNotation(timeShift) else {
                throw Rigol2SpiceErrors.invalidTimeShiftValue(value: timeShift)
            }

            let timeShiftValueString = engineeringNF.string(timeShiftValue)

            print("")
            print("> Shifting signal for \(timeShiftValueString)s...")

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

            let cutValueString = engineeringNF.string(cutValue)

            print("")
            print("> Cutting signal after \(cutValueString)s...")

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
            print("> Repeating capture for \(repeatTimes) times...")

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
            print("> Downsampling at 1/\(ds)...")

            let nPointsBefore = points.count
            points = downsamplePoints(points, interval: ds)
            let nPointsAfter = points.count

            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }

        // Compacting...
        if !keepAll {
            print("")
            print("> Removing redundant sample points (optimize)...")

            let nPointsBefore = points.count
            points = removeRedundant(points)
            let nPointsAfter = points.count

            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }

        // Output
        print("")
        print("> Writing output file...")
        let nPoints = points.count
        let newFirstPointTime = points.first!.time
        let newLastPointTime = points.last!.time
        let captureDuration = newLastPointTime + sampleTimeInterval

        let nSamplesString = decimalNF.string(for: nPoints)!
        let firstSampleString = engineeringNF.string(newFirstPointTime)
        let lastSampleString = engineeringNF.string(newLastPointTime)
        let captureDurationString = engineeringNF.string(captureDuration)

        print("  " + "Number of sample points: \(nSamplesString)")
        print("  " + "First sample: \(firstSampleString)s")
        print("  " + "Last sample: \(lastSampleString)s")
        print("  " + "Capture duration: \(captureDurationString)s")

        let outputFileUrl = URL(fileURLWithPath: outputFileExpanded, relativeTo: cdUrl)

        if FileManager.default.fileExists(atPath: outputFileUrl.path) {
            try FileManager.default.removeItem(at: outputFileUrl)
        }

        FileManager.default.createFile(atPath: outputFileUrl.path, contents: nil)

        let outputFileHandle = try FileHandle(forWritingTo: outputFileUrl)

        var outputFileProgressBar = ProgressBar(count: points.count)
        
        for point in points {
            let pointBytes = point.serialize.data(using: .ascii)!
            outputFileHandle.write(pointBytes)
            outputFileHandle.write(newlineBytes)
            
            outputFileProgressBar.next()
        }

        outputFileHandle.closeFile()

        print("")
        print("> Job complete")
        print("")
    }
}
