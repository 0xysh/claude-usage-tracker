import Foundation

/// Treats dynamic script values as data, never as shell syntax.
enum ShellLiteral {
    /// A POSIX shell literal. Single quotes may contain every character except
    /// another single quote, which is emitted as a separately escaped quote.
    static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// A comment must stay on one physical line even when a profile name does not.
    static func comment(_ value: String) -> String {
        value.replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
