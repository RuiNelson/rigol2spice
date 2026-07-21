import ArgumentParser

enum OutputFormat: String, CaseIterable, ExpressibleByArgument {
    case pwl
    case matlab
}
