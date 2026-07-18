import ArgumentParser
import Foundation

// MARK: - Rigol2SpiceEntrypoint

@main
enum Rigol2SpiceEntrypoint {
    static func main() {
        // Allow bare `-p` / `--plot` to mean `--plot plot.svg`.
        Rigol2SpiceCommand.main(normalizePlotArguments(Array(CommandLine.arguments.dropFirst())))
    }
}

/// Inserts the default plot path when `-p` / `--plot` is present without a value.
func normalizePlotArguments(_ arguments: [String]) -> [String] {
    var result: [String] = []
    var index = 0
    while index < arguments.count {
        let argument = arguments[index]
        if argument == "-p" || argument == "--plot" {
            result.append("--plot")
            let next = index + 1 < arguments.count ? arguments[index + 1] : nil
            if let next, !next.hasPrefix("-") {
                result.append(next)
                index += 2
            }
            else {
                result.append("plot.svg")
                index += 1
            }
        }
        else {
            result.append(argument)
            index += 1
        }
    }
    return result
}

// MARK: - Rigol2SpiceCommand

struct Rigol2SpiceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rigol2spice",
        abstract: "Convert Rigol oscilloscope CSV and WFM captures to SPICE PWL files.",
    )

    @Flag(
        name: .shortAndLong,
        help: "Adopts the CSV format used by newer Rigol Centaurus platform oscilloscopes. WFM is detected automatically.",
    )
    var newModels = false

    @Flag(name: .shortAndLong, help: "Only list channels present in the file and quit.")
    var listChannels = false

    @Option(
        name: .shortAndLong,
        help: "Channel or math expression to process (e.g. CH1, CH1+CH2, (CH1-CH2)/CH3).",
    )
    var channel = "CH1"

    @Option(name: .shortAndLong, help: "Ordered transformations separated by semicolons.")
    var transformations: String?

    @Option(
        name: .shortAndLong,
        help: "Analyses separated by semicolons (order independent; printed to the console after transforms).",
    )
    var analysis: String?

    @Option(name: .shortAndLong, help: "Downsample ratio.")
    var downsample: Int?

    @Flag(name: .shortAndLong, help: "Keep redundant sample points in the output.")
    var keepAll = false

    @Option(
        name: .shortAndLong,
        help: "Write an SVG plot of the processed signal (default: plot.svg).",
        completion: .file(extensions: ["svg"]),
    )
    var plot: String?

    @Argument(
        help: "The Rigol CSV or WFM file to read (WFM is detected by magic).",
        completion: .file(extensions: ["csv", "wfm"]),
    )
    var inputFile: String

    @Argument(
        help: "The PWL file to write (optional with --list-channels, --plot, or --analysis).",
        completion: nil,
    )
    var outputFile: String?

    mutating func run() throws {
        try Rigol2SpiceApplication(
            options: ApplicationOptions(
                format: newModels ? .centaurus : .legacy,
                listChannels: listChannels,
                channel: channel,
                transformations: transformations,
                analysis: analysis,
                downsample: downsample,
                keepAll: keepAll,
                plotFile: plot.map { $0.isEmpty ? "plot.svg" : $0 },
                inputFile: inputFile,
                outputFile: outputFile,
            ),
        ).run()
    }
}
