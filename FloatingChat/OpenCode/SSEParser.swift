import Foundation

/// Incremental Server-Sent Events parser. Only `data` fields matter to opencode; comments
/// (heartbeats) and other fields are ignored.
struct SSEParser {
    private var line: [UInt8] = []
    private var dataLines: [String] = []

    /// Returns the event payload when `byte` completes an event.
    mutating func push(_ byte: UInt8) -> String? {
        guard byte == UInt8(ascii: "\n") else {
            line.append(byte)
            return nil
        }
        if line.last == UInt8(ascii: "\r") { line.removeLast() }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)

        if text.isEmpty {
            guard !dataLines.isEmpty else { return nil }
            defer { dataLines.removeAll() }
            return dataLines.joined(separator: "\n")
        }
        if text.hasPrefix("data:") {
            var value = text.dropFirst(5)
            if value.first == " " { value = value.dropFirst() }
            dataLines.append(String(value))
        }
        return nil
    }

    mutating func push(_ bytes: some Sequence<UInt8>) -> [String] {
        bytes.compactMap { push($0) }
    }
}
