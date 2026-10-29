import Foundation

/// Bounds-check ZIP directory metadata before passing offsets to the decompression library.
/// Format reference: https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT
/// This reads metadata only; ZIPFoundation still handles entry decoding and inflation.
enum ZIPPreflight {
    static let maxDirectoryBytes: UInt64 = 32 * 1024 * 1024
    struct Summary { var entries: Int; var fileBytes: UInt64; var zeroOffsetFields: [UInt64] }

    static func validate(_ url: URL, control: HealthImportControl) throws -> Summary {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let size = try file.seekToEnd()
        guard size >= 22, size <= UInt64(HealthZIPArchive.maxExpandedBytes) else { throw HealthZIPError.invalid }
        func read(_ offset: UInt64, _ count: Int) throws -> Data {
            try control.checkCancellation()
            guard offset <= size, count >= 0, UInt64(count) <= size - offset else { throw HealthZIPError.invalid }
            try file.seek(toOffset: offset)
            let data = try file.read(upToCount: count) ?? Data()
            guard data.count == count else { throw HealthZIPError.invalid }
            return data
        }
        let tailSize = Int(min(size, 65_557))
        let tail = try read(size - UInt64(tailSize), tailSize)
        var endIndex: Int?
        // Match the library's backwards search, then validate comment length and every offset.
        for index in stride(from: tailSize - 22, through: 0, by: -1) {
            if try tail.zipNumber(index, 4) == 0x06054b50 { endIndex = index; break }
        }
        guard let endIndex, try endIndex + 22 + Int(tail.zipNumber(endIndex + 20, 2)) == tailSize else { throw HealthZIPError.invalid }
        let endOffset = size - UInt64(tailSize) + UInt64(endIndex)
        let end = tail.subdata(in: endIndex..<(endIndex + 22))
        guard try end.zipNumber(4, 2) == 0, try end.zipNumber(6, 2) == 0 else { throw HealthZIPError.invalid }
        var count = try end.zipNumber(10, 2)
        var directorySize = try end.zipNumber(12, 4)
        var directoryOffset = try end.zipNumber(16, 4)
        var directoryEnd = endOffset
        let locator = endOffset >= 20 ? try read(endOffset - 20, 20) : Data()
        let hasZIP64 = try locator.count == 20 && locator.zipNumber(0, 4) == 0x07064b50
        if hasZIP64 {
            guard try locator.zipNumber(4, 4) == 0, try locator.zipNumber(16, 4) == 1, endOffset >= 76 else { throw HealthZIPError.invalid }
            let recordOffset = try locator.zipNumber(8, 8)
            // The library supports the standard fixed ZIP64 record, without extensible data.
            guard recordOffset == endOffset - 76 else { throw HealthZIPError.invalid }
            let record = try read(recordOffset, 56)
            guard try record.zipNumber(0, 4) == 0x06064b50, try record.zipNumber(4, 8) == 44,
                  try record.zipNumber(16, 4) == 0, try record.zipNumber(20, 4) == 0,
                  try record.zipNumber(24, 8) == record.zipNumber(32, 8) else { throw HealthZIPError.invalid }
            count = try record.zipNumber(32, 8)
            directorySize = try record.zipNumber(40, 8)
            directoryOffset = try record.zipNumber(48, 8)
            directoryEnd = recordOffset
        } else {
            guard count != 0xffff, directorySize != 0xffffffff, directoryOffset != 0xffffffff,
                  try end.zipNumber(8, 2) == count else { throw HealthZIPError.invalid }
        }
        guard count <= UInt64(HealthZIPArchive.maxEntries) else { throw HealthZIPError.tooManyEntries }
        guard directorySize <= maxDirectoryBytes, directoryOffset <= directoryEnd,
              directorySize <= directoryEnd - directoryOffset else { throw HealthZIPError.invalid }
        let directory = try read(directoryOffset, Int(directorySize))
        var cursor = 0
        var zeroOffsetFields: [UInt64] = []
        for _ in 0..<Int(count) {
            try control.checkCancellation()
            guard cursor <= directory.count, directory.count - cursor >= 46,
                  try directory.zipNumber(cursor, 4) == 0x02014b50 else { throw HealthZIPError.invalid }
            let flags = try directory.zipNumber(cursor + 8, 2)
            let method = try directory.zipNumber(cursor + 10, 2)
            guard flags & 0x41 == 0, method == 0 || method == 8 else { throw HealthZIPError.invalid }
            let nameSize = Int(try directory.zipNumber(cursor + 28, 2))
            let extraSize = Int(try directory.zipNumber(cursor + 30, 2))
            let commentSize = Int(try directory.zipNumber(cursor + 32, 2))
            let length = 46 + nameSize + extraSize + commentSize
            guard length <= directory.count - cursor else { throw HealthZIPError.invalid }
            var unpacked = try directory.zipNumber(cursor + 24, 4)
            var packed = try directory.zipNumber(cursor + 20, 4)
            var localOffset = try directory.zipNumber(cursor + 42, 4)
            let zip64LocalOffset = localOffset == 0xffffffff
            var disk = try directory.zipNumber(cursor + 34, 2)
            let needsZIP64 = unpacked == 0xffffffff || packed == 0xffffffff || localOffset == 0xffffffff || disk == 0xffff
            var resolvedZIP64 = false
            var extraCursor = cursor + 46 + nameSize
            let extraEnd = extraCursor + extraSize
            while extraCursor < extraEnd {
                guard extraEnd - extraCursor >= 4 else { throw HealthZIPError.invalid }
                let tag = try directory.zipNumber(extraCursor, 2)
                let bytes = Int(try directory.zipNumber(extraCursor + 2, 2))
                extraCursor += 4
                guard bytes <= extraEnd - extraCursor else { throw HealthZIPError.invalid }
                if tag == 1 {
                    guard !resolvedZIP64 else { throw HealthZIPError.invalid }
                    resolvedZIP64 = true
                    var valueCursor = extraCursor
                    func next(_ width: Int) throws -> UInt64 {
                        guard width <= extraCursor + bytes - valueCursor else { throw HealthZIPError.invalid }
                        let value = try directory.zipNumber(valueCursor, width); valueCursor += width; return value
                    }
                    if unpacked == 0xffffffff { unpacked = try next(8) }
                    if packed == 0xffffffff { packed = try next(8) }
                    if localOffset == 0xffffffff { localOffset = try next(8) }
                    if disk == 0xffff { disk = try next(4) }
                }
                extraCursor += bytes
            }
            guard !needsZIP64 || resolvedZIP64, disk == 0,
                  unpacked <= UInt64(Int64.max), localOffset <= directoryOffset,
                  directoryOffset - localOffset >= 30 else { throw HealthZIPError.invalid }
            if zip64LocalOffset && localOffset == 0 { zeroOffsetFields.append(directoryOffset + UInt64(cursor + 42)) }
            let local = try read(localOffset, 30)
            guard try local.zipNumber(0, 4) == 0x04034b50, try local.zipNumber(6, 2) == flags,
                  try local.zipNumber(8, 2) == method else { throw HealthZIPError.invalid }
            let localNameSize = Int(try local.zipNumber(26, 2))
            let localExtraSize = Int(try local.zipNumber(28, 2))
            let headerSize = UInt64(30 + localNameSize + localExtraSize)
            guard headerSize <= directoryOffset - localOffset else { throw HealthZIPError.invalid }
            let payloadOffset = localOffset + headerSize
            guard packed <= directoryOffset - payloadOffset,
                  method != 0 || packed == unpacked else { throw HealthZIPError.invalid }
            let localName = try read(localOffset + 30, localNameSize)
            let centralName = directory.subdata(in: (cursor + 46)..<(cursor + 46 + nameSize))
            guard localName == centralName else { throw HealthZIPError.invalid }
            cursor += length
        }
        guard cursor == directory.count else { throw HealthZIPError.invalid }
        return Summary(entries: Int(count), fileBytes: size, zeroOffsetFields: zeroOffsetFields)
    }
}

private extension Data {
    func zipNumber(_ offset: Int, _ width: Int) throws -> UInt64 {
        guard offset >= 0, width >= 0, width <= 8, offset <= count, width <= count - offset else { throw HealthZIPError.invalid }
        var value: UInt64 = 0
        for index in 0..<width { value |= UInt64(self[startIndex + offset + index]) << (8 * index) }
        return value
    }
}
