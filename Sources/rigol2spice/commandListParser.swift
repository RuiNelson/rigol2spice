import Foundation

/// Split CLI command lists on semicolons or any conventional line ending.
/// `Character.isNewline` treats CRLF as one separator and also covers standalone CR and LF.
func splitCommandList(_ source: String) -> [Substring] {
    source.split(omittingEmptySubsequences: false) { character in
        character == ";" || character.isNewline
    }.filter { command in
        !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
