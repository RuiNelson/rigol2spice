import ArgumentParser
import Foundation
import Progress

func printI(_ indent: Int, _ text: String) {
    if indent == 0 {
        print("")
        print("> " + text)
    } else {
        let spaces = Array(repeating: "    ", count: indent).joined()
        print(spaces + text)
    }
}

// MARK: - Rigol2SpiceErrors

enum Rigol2SpiceErrors: LocalizedError {
    case outputFileNotSpecified
    case inputFileContainsNoPoints
    case invalidOffsetValue(value: String)
    case invalidAmplificationValue(value: String)
    case invalidDownsampleValue(value: Int)
    case invalidTimeShiftValue(value: String)
    case invalidCutAfterValue(value: String)
    case invalidRepeatCountValue(value: Int)
    case invalidClampValue(value: String)
    case mustHaveAtLeastTwoPointsToRepeat
    case operationRemovedEveryPoint
    case clampMinIsGreaterOrEqualToClampMax

    var errorDescription: String? {
        switch self {
        case .outputFileNotSpecified:
            return
                "Please specify the output file name after the input file name"
        case .inputFileContainsNoPoints:
            return "Input file contains zero samples"
        case let .invalidOffsetValue(value: v):
            return "Invalid offset value: \(v)"
        case let .invalidAmplificationValue(value: v):
            return "Invalid amplification factor: \(v)"
        case let .invalidDownsampleValue(value: v):
            return "Invalid downsample value: \(v)"
        case let .invalidTimeShiftValue(value: v):
            return "Invalid time-shift value: \(v)"
        case let .invalidCutAfterValue(value: v):
            return "Invalid cut timestamp: \(v)"
        case let .invalidRepeatCountValue(value: v):
            return "Invalid repeat count value: \(v)"
        case let .invalidClampValue(value: v):
            return "Invalid clamping value: \(v)"
        case .mustHaveAtLeastTwoPointsToRepeat:
            return "Must have at least two original samples to repeat capture"
        case .operationRemovedEveryPoint:
            return "Operation removed every sample"
        case .clampMinIsGreaterOrEqualToClampMax:
            return "`clamp-max` must be greater than `clamp-min`"
        }
    }
}

// MARK: - rigol2spice

@main
struct rigol2spice: ParsableCommand {
    @Flag(
        name: .shortAndLong,
        help: "Adopts the format used by the newer Rigol Centaurus platform oscilloscopes."
    )
    var newModels = false

    @Flag(
        name: .shortAndLong,
        help: "Only list channels present in the file and quit"
    )
    var listChannels = false

    @Option(
        name: .shortAndLong, help: "The label of the channel to be processed"
    )
    var channel: String?

    @Option(
        name: .long,
        help: "Clamp the signal to above this value (use N prefix for negative)"
    )
    var clampMin: String?

    @Option(
        name: .long,
        help: "Clamp the signal to below this value (use N prefix for negative)"
    )
    var clampMax: String?

    @Flag(
        name: [
            .customLong("removedc"),
        ],
        help: "Remove DC component"
    )
    var removeDc = false

    @Option(
        name: .shortAndLong,
        help: "Offset value for signal (use M and P prefixes)"
    )
    var offset: String?

    @Option(
        name: [
            .customShort("m"),
            .customLong("multiply", withSingleDash: false),
        ],
        help: "Multiplication factor for signal (use N prefix for negative)"
    )
    var multiplication: String?

    @Option(
        name: [
            .customShort("s"),
            .customLong("shift"),
        ],
        help: "Time-shift seconds (use L and R prefixes)"
    )
    var timeShift: String?

    @Option(
        name: [.customShort("x"), .customLong("cut")],
        help: "Cut signal after timestamp"
    )
    var cut: String?

    @Option(
        name: [
            .customShort("r"),
            .customLong("repeat"),
        ],
        help: "Repeat signal number of times"
    )
    var repeatTimes: Int?

    @Option(
        name: .shortAndLong,
        help: "Downsample ratio"
    )
    var downsample: Int?

    @Flag(
        name: .shortAndLong,
        help:
            "Don't remove redundant sample points. Sample points where the signal value maintains (useful for output file post-processing)"
    )
    var keepAll = false

    @Argument(
        help: "The filename of the .csv from the oscilloscope to be read",
        completion: CompletionKind.file(extensions: ["csv"])
    )
    var inputFile: String

    @Argument(help: "The PWL filename to write to", completion: nil)
    var outputFile: String?

    func filenameToURL(_ filename: String) -> URL {
        let ns = NSString(string: filename)
        let expandedNs = ns.expandingTildeInPath
        let expandedStr = String(expandedNs)

        let cd = FileManager.default.currentDirectoryPath
        let cdURL = URL(fileURLWithPath: cd)

        let fileURL = URL(fileURLWithPath: expandedStr, relativeTo: cdURL)
        return fileURL
    }

    func nPointsReport(before: Int, after: Int) throws {
        guard after > 0 else {
            throw Rigol2SpiceErrors.operationRemovedEveryPoint
        }

        if after != before {
            let before = numberOfPointsFormatter.string(for: before)!
            let after = numberOfPointsFormatter.string(for: after)!
            printI(1, "From \(before) samples to \(after) samples")
        } else {
            printI(1, "Maintained all the samples")
        }
    }

    mutating func run() throws {
        // argument validation
        if !listChannels, outputFile == nil {
            throw Rigol2SpiceErrors.outputFileNotSpecified
        }

        // Loading
        printI(0, "Loading input file...")
        let inputFileURL = filenameToURL(inputFile)
        let data = try Data(contentsOf: inputFileURL)
        let numBytesString = fileSizeFormatter.string(
            fromByteCount: Int64(data.count))

        printI(1, "Read \(numBytesString)")

        // Parsing
        printI(0, "Parsing input file...")
        if data.count > 1_000_000 {
            printI(1, "(This might take a while)")
        }

        func presentNumberOfPoints() {
            let num = points.count
            let str = numberOfPointsFormatter.string(for: num)!
            printI(1, "Samples: \(str)")

            if let last = points.last {
                let lastTime = engineeringFormatter.string(last.time)
                printI(1, "Last sample point: \(lastTime)s")
            }
        }

        func presentSampleIntervalAndSampleRate(
            interval: Double, duration: Double, pointsCount: Int
        ) {
            let rate = Double(pointsCount) / duration

            let intervalString = engineeringFormatter.string(interval)
            let rateString = engineeringFormatter.string(rate)
            let durationString = engineeringFormatter.string(duration)

            printI(1, "Sample Interval : \(intervalString)s")
            printI(1, "Sample Rate     : \(rateString)sa/s")
            printI(1, "Capture Duration: \(durationString)s")
        }

        var points: [Point] = .init()
        var sampleTimeInterval: Double = .init()
        var sampleDuration: Double = .init()

        if newModels {
            points = try CentaurusParser.parseCsv(
                data,
                forChannel: channel ?? "CH1",
                listChannelsOnly: listChannels)

            guard !listChannels else {
                return
            }

            guard !points.isEmpty else {
                throw Rigol2SpiceErrors.inputFileContainsNoPoints
            }

            presentNumberOfPoints()

            if points.count >= 2 {
                let lastPointIndex = points.count - 1
                let penultimatePointIndex = points.count - 2

                sampleTimeInterval =
                    points[lastPointIndex].time
                    - points[penultimatePointIndex].time

                sampleDuration =
                    points[lastPointIndex].time + sampleTimeInterval

                presentSampleIntervalAndSampleRate(
                    interval: sampleTimeInterval,
                    duration: sampleDuration,
                    pointsCount: points.count)
            }

        } else {
            let parsed = try CSVParser.parseCsv(
                data,
                forChannel: channel ?? "CH1",
                listChannelsOnly: listChannels)
            
            guard !listChannels else {
                return
            }
            
            points = parsed.points

            guard !points.isEmpty else {
                throw Rigol2SpiceErrors.inputFileContainsNoPoints
            }

            presentNumberOfPoints()

            sampleTimeInterval = parsed.header.increment ?? 0.0
            sampleDuration = points.last!.time + sampleTimeInterval

            // Sample Rate Calculation
            if points.count >= 2 {
                presentSampleIntervalAndSampleRate(
                    interval: sampleTimeInterval,
                    duration: sampleDuration,
                    pointsCount: points.count)
            }
        }

        guard !listChannels else {
            return
        }

        guard let outputFile = outputFile else {
            throw Rigol2SpiceErrors.outputFileNotSpecified
        }

        // Clamping
        if clampMin != nil || clampMax != nil {
            // values
            var clampMinDbl: Double?
            var clampMaxDbl: Double?

            if let clampMin {
                clampMinDbl = parseEngineeringNotation(clampMin)
                guard clampMinDbl != nil else {
                    throw Rigol2SpiceErrors.invalidClampValue(value: clampMin)
                }
            }

            if let clampMax {
                clampMaxDbl = parseEngineeringNotation(clampMax)
                guard clampMaxDbl != nil else {
                    throw Rigol2SpiceErrors.invalidClampValue(value: clampMax)
                }
            }

            // sanity check
            if let clampMinDbl, let clampMaxDbl {
                guard clampMaxDbl > clampMinDbl else {
                    throw Rigol2SpiceErrors.clampMinIsGreaterOrEqualToClampMax
                }
            }

            // present information to the user
            var print = "Clamping the signal "

            var clampMinStr: String?
            var clampMaxStr: String?

            if let clampMinDbl {
                clampMinStr = engineeringFormatter.string(clampMinDbl)
            }

            if let clampMaxDbl {
                clampMaxStr = engineeringFormatter.string(clampMaxDbl)
            }

            if let clampMinStr, let clampMaxStr {
                print = print + ["between", clampMinStr, "and", clampMaxStr]
            } else if let clampMinStr {
                print = print + ["above", clampMinStr]
            } else if let clampMaxStr {
                print = print + ["below", clampMaxStr]
            }

            print += "..."

            printI(0, print)

            // operation
            points = clamp(
                points, lowerLimit: clampMinDbl, upperLimit: clampMaxDbl)
        }

        // Removing DC component
        if removeDc {
            printI(0, "Removing DC component...")

            let dcComponent = calculateDC(points)
            let dcComponentStr = engineeringFormatter.string(dcComponent)

            printI(
                1, "Automatically calculated DC component: \(dcComponentStr)")

            points = offsetPoints(points, offset: 0 - dcComponent)
        }

        // Offset
        if let offset = offset {
            guard let offsetValue = parseEngineeringNotation(offset) else {
                throw Rigol2SpiceErrors.invalidOffsetValue(value: offset)
            }

            engineeringFormatter.positiveSign = "+"
            let offsetValueStr = engineeringFormatter.string(offsetValue)
            engineeringFormatter.positiveSign = ""

            printI(0, "Offsetting signal by \(offsetValueStr)...")

            points = offsetPoints(points, offset: offsetValue)
        }

        // Multiplication
        if let multiplication = multiplication {
            guard
                let multiplicationFactor = parseEngineeringNotation(
                    multiplication)
            else {
                throw Rigol2SpiceErrors.invalidAmplificationValue(
                    value: multiplication)
            }

            let multiplicationFactorStr = engineeringFormatter.string(
                multiplicationFactor)

            printI(
                0,
                "Multiplying the signal by a factor of \(multiplicationFactorStr)..."
            )

            points = multiplyValueOfPoints(points, factor: multiplicationFactor)
        }

        // Time-shift
        if let timeShift = timeShift {
            guard let timeShiftValue = parseEngineeringNotation(timeShift)
            else {
                throw Rigol2SpiceErrors.invalidTimeShiftValue(value: timeShift)
            }

            let timeShiftValueString = engineeringFormatter.string(
                timeShiftValue)

            printI(0, "Shifting signal for \(timeShiftValueString)s...")

            let nPointsBefore = points.count
            points = timeShiftPoints(points, value: timeShiftValue)
            let nPointsAfter = points.count

            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }

        // Cut
        if let cut = cut {
            guard let cutValue = parseEngineeringNotation(cut), cutValue > 0
            else {
                throw Rigol2SpiceErrors.invalidCutAfterValue(value: cut)
            }

            let cutValueString = engineeringFormatter.string(cutValue)

            printI(0, "Cutting signal after \(cutValueString)s...")

            let nPointsBefore = points.count
            points = cutAfter(points, after: cutValue)
            let nPointsAfter = points.count

            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }

        // Repeat
        if let repeatTimes = repeatTimes {
            guard repeatTimes > 0 else {
                throw Rigol2SpiceErrors.invalidRepeatCountValue(
                    value: repeatTimes)
            }

            printI(0, "Repeating capture for \(repeatTimes) times...")

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

            printI(0, "Downsampling at 1/\(ds)...")

            let nPointsBefore = points.count
            points = downsamplePoints(points, interval: ds)
            let nPointsAfter = points.count

            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }

        // Compacting...
        if !keepAll, points.count >= 3 {
            printI(0, "Removing redundant sample points (optimize)...")

            let nPointsBefore = points.count
            points = removeRedundant(points)
            let nPointsAfter = points.count

            try nPointsReport(before: nPointsBefore, after: nPointsAfter)
        }

        // Output
        printI(0, "Writing output file...")
        let nPoints = points.count
        let newFirstPointTime = points.first!.time
        let newLastPointTime = points.last!.time
        let captureDuration = newLastPointTime + sampleTimeInterval

        let nSamplesString = numberOfPointsFormatter.string(for: nPoints)!
        let firstSampleString = engineeringFormatter.string(newFirstPointTime)
        let lastSampleString = engineeringFormatter.string(newLastPointTime)
        let captureDurationString = engineeringFormatter.string(captureDuration)

        printI(1, "Number of sample points: \(nSamplesString)")

        var outputFileData = Data()
        var outputFileProgressBar = ProgressBar(count: points.count)

        for point in points {
            let pointBytes = point.serialize.data(using: .ascii)!
            outputFileData.append(pointBytes)
            outputFileData.append(newlineBytes)

            outputFileProgressBar.next()
        }

        let fileSizeStr = fileSizeFormatter.string(
            fromByteCount: Int64(outputFileData.count))

        printI(1, "First sample: \(firstSampleString)s")
        printI(1, "Last sample: \(lastSampleString)s")
        printI(1, "Capture duration: \(captureDurationString)s")
        printI(1, "Saving file: \(fileSizeStr)...")

        let outputFileURL = filenameToURL(outputFile)
        if FileManager.default.fileExists(atPath: outputFileURL.path) {
            try FileManager.default.removeItem(at: outputFileURL)
        }
        FileManager.default.createFile(
            atPath: outputFileURL.path, contents: outputFileData)

        printI(0, "Job complete")
        print("")
    }
}
