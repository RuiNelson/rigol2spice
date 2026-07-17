import ArgumentParser

@main
struct Rigol2SpiceCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rigol2spice",
        abstract: "Convert Rigol oscilloscope CSV captures to SPICE PWL files.",
    )

    @Flag(
        name: .shortAndLong,
        help: "Adopts the format used by newer Rigol Centaurus platform oscilloscopes.",
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

    @Option(name: .shortAndLong, help: "Downsample ratio.")
    var downsample: Int?

    @Flag(name: .shortAndLong, help: "Keep redundant sample points in the output.")
    var keepAll = false

    @Argument(
        help: "The Rigol CSV file to read.",
        completion: .file(extensions: ["csv"]),
    )
    var inputFile: String

    @Argument(help: "The PWL file to write.", completion: nil)
    var outputFile: String?

    mutating func run() throws {
        try Rigol2SpiceApplication(
            options: ApplicationOptions(
                format: newModels ? .centaurus : .legacy,
                listChannels: listChannels,
                channel: channel,
                transformations: transformations,
                downsample: downsample,
                keepAll: keepAll,
                inputFile: inputFile,
                outputFile: outputFile,
            ),
        ).run()
    }
}
