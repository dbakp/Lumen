import Foundation

/// Foundation accepts repeated object keys. Recovery refuses that ambiguity before
/// decoding, including equivalent escaped keys. No source value is interpreted.
enum JSONFieldAudit {
    static func check(_ data: Data, control: BackupOperationControl) throws {
        try data.withUnsafeBytes { bytes in
            var parser = Parser(bytes: bytes, control: control)
            try parser.value(depth: 0); try parser.space()
            guard parser.offset == bytes.count else { throw ReadableExport.Failure.format }
        }
    }
    private struct Parser {
        let bytes: UnsafeRawBufferPointer
        let control: BackupOperationControl
        var offset = 0
        mutating func space() throws {
            while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) {
                if offset % 4096 == 0 { try control.checkCancellation() }; offset += 1
            }
        }
        mutating func take(_ byte: UInt8) throws {
            try space(); guard offset < bytes.count, bytes[offset] == byte else { throw ReadableExport.Failure.format }; offset += 1
        }
        mutating func string(key: Bool = false) throws -> String? {
            try take(34); let start = offset - 1
            while offset < bytes.count {
                if offset % 4096 == 0 { try control.checkCancellation() }
                let byte = bytes[offset]; offset += 1
                if byte == 34 {
                    guard !key || offset - start <= 4096 else { throw ReadableExport.Failure.format }
                    if key { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) }
                    return nil
                }
                guard byte >= 32 else { throw ReadableExport.Failure.format }
                if byte == 92 {
                    guard offset < bytes.count else { throw ReadableExport.Failure.format }
                    offset += 1 // Foundation validates the escape and UTF-8 later.
                }
            }
            throw ReadableExport.Failure.format
        }
        mutating func value(depth: Int) throws {
            try control.checkCancellation(); try space()
            guard depth <= 64, offset < bytes.count else { throw ReadableExport.Failure.format }
            switch bytes[offset] {
            case 123:
                offset += 1; try space(); var keys = Set<String>()
                if offset < bytes.count, bytes[offset] == 125 { offset += 1; return }
                while true {
                    guard let key = try string(key: true), keys.insert(key).inserted else { throw ReadableExport.Failure.ambiguous }
                    guard keys.count <= 1000 else { throw ReadableExport.Failure.format }
                    try take(58); try value(depth: depth + 1); try space()
                    guard offset < bytes.count else { throw ReadableExport.Failure.format }
                    if bytes[offset] == 125 { offset += 1; return }
                    try take(44)
                }
            case 91:
                offset += 1; try space()
                if offset < bytes.count, bytes[offset] == 93 { offset += 1; return }
                while true {
                    try value(depth: depth + 1); try space()
                    guard offset < bytes.count else { throw ReadableExport.Failure.format }
                    if bytes[offset] == 93 { offset += 1; return }
                    try take(44)
                }
            case 34: _ = try string()
            default:
                let start = offset
                while offset < bytes.count && ![9, 10, 13, 32, 44, 93, 125].contains(bytes[offset]) {
                    if offset % 4096 == 0 { try control.checkCancellation() }; offset += 1
                }
                guard offset > start else { throw ReadableExport.Failure.format }
            }
        }
    }
}
