import ArgumentParser

enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case pwl
    case matlab
    case wav32
    case wav16
}
