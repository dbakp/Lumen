import Foundation

/// Core ML can keep CPU programs outside the installed model directory. Only
/// this app's observed E5 cache packages containing eight disjoint, pinned
/// weight fingerprints are disposable here. Metal/other model caches remain.
/// Call only after every MiniLM encoder/installation worker has stopped.
enum MiniLMRuntimeCache {
    struct Removal: Sendable { var packages = 0; var logicalBytes: Int64 = 0 }
    enum CacheError: Error { case unsafe, limits }
    static let sourceOffsets = [4096, 1048576, 8000000, 16000000, 24000000, 32000000, 40000000, 44000000]
    // 512 bytes from the Apache-2.0 pinned weight.bin, whose full SHA is checked
    // before preparation. See cache-investigation.json for independent hashes.
    static let fingerprints: [Data] = [
        "ZiU6pT+iTCeeItmmL6hcKs2fO6DfJqildKUAnXaih5w5JIOma6s1KjkneRtYHFEnpZo2mDUerSlbKPifz6NoqA==",
        "6iTCoJgg5iisInqoQ6jpJtSf3KKvKDKg7J51mSMhnp/0oYwiHKlcJ76UZiS2Ibgk4pXCoDwcFClBJuAYoalbqg==",
        "sSV8qa6t4iomp1Avaasnr9WvYy/7Kc8qrC7qLdulfitjLF0tnJLsrLGw2CDvnCAr0C1cr3QqmaJpqBGmLCzhKw==",
        "fq73o50iey4hISorqa00pIioDKeeKloeVyjhoCqjxKu5qyasHimLrJ+sQBibIFsrSShWmTquuKVAKYus96qrrg==",
        "CCkrMEoxU68Er/4r8LBBJUwyrTAXJpGsNa4drUut4aGlrVQljjBYLUiymy//L8mufi2+LoeofCTdLbE1ZzC4Mg==",
        "j6hoLncoBK5BqQyZTCixqBipQC8jLNoyACT2qMmtzq4nrpOouSp/p6CoBKoCrZcnSKkMr8ooCalKFVsZeDCxKw==",
        "wywdq38qQqr+LUgcICmPKYimtaJrLe8uUKmvJtKj3axlrQip2K0AqhmpSKk4KXorGJFvsq8R/6YAq6wv/avTKg==",
        "gqjJpNQkhikpKmOjEac5pjcn8qKunRQp+JvJKIKkPK/6KAokmynsIJakYqT5qAuoUifjGOorDSHKJAMcn6lEKg=="
    ].compactMap { Data(base64Encoded: $0) }

    static var currentAppRoot: URL? {
        guard let id = Bundle.main.bundleIdentifier,
              id.range(of: #"^[A-Za-z0-9][A-Za-z0-9.-]{0,199}$"#, options: .regularExpression) != nil,
              let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        return caches.appendingPathComponent(id, isDirectory: true).appendingPathComponent("com.apple.e5rt.e5bundlecache", isDirectory: true)
    }
    @discardableResult static func purgeCurrentApp() throws -> Removal {
        guard let root = currentAppRoot else { return Removal() }
        return try purge(at: root)
    }
    private static func directory(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        return values.isDirectory == true && values.isSymbolicLink != true
    }
    private static func hashName(_ name: String) -> Bool { name.count == 64 && name.allSatisfy { $0.isASCII && $0.isHexDigit } }
    @discardableResult static func purge(at root: URL) throws -> Removal {
        try Task.checkCancellation()
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return Removal() }
        // Do not traverse a redirected application namespace or cache root.
        guard try directory(root), try directory(root.deletingLastPathComponent()), fingerprints.count == 8,
              fingerprints.allSatisfy({ $0.count == 64 && Set($0).count > 16 }) else { throw CacheError.unsafe }
        var result = Removal(), scanned = 0, scannedBytes: Int64 = 0
        let builds = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard builds.count <= 32 else { throw CacheError.limits }
        for build in builds {
            try Task.checkCancellation()
            guard build.lastPathComponent.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$"#, options: .regularExpression) != nil,
                  try directory(build) else { continue }
            let models = try fm.contentsOfDirectory(at: build, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard models.count <= 2048 else { throw CacheError.limits }
            for model in models {
                guard hashName(model.lastPathComponent), try directory(model) else { continue }
                var removedInModel = false
                for package in try fm.contentsOfDirectory(at: model, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
                    try Task.checkCancellation()
                    guard package.pathExtension == "bundle", hashName(package.deletingPathExtension().lastPathComponent), try directory(package) else { continue }
                    scanned += 1; guard scanned <= 512 else { throw CacheError.limits }
                    guard let entry = try inventory(package) else { continue }
                    scannedBytes += entry.bytes; guard scannedBytes <= 4_294_967_296 else { throw CacheError.limits }
                    guard entry.programs.count == 1, let program = entry.programs.first else { continue }
                    let size = try program.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
                    guard size >= 44_940_672, size <= 128_000_000 else { continue }
                    // Mapped only for this bounded read, never retained by the owner.
                    let matches = try isPinnedProgram(program)
                    guard matches else { continue }
                    try Task.checkCancellation()
                    try fm.removeItem(at: package)
                    removedInModel = true
                    result.packages += 1; result.logicalBytes += entry.bytes
                }
                if removedInModel, try fm.contentsOfDirectory(atPath: model.path).isEmpty { try fm.removeItem(at: model) }
            }
        }
        return result
    }
    private static func isPinnedProgram(_ file: URL) throws -> Bool {
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        for fingerprint in fingerprints {
            try Task.checkCancellation()
            guard data.range(of: fingerprint) != nil else { return false }
        }
        return true
    }
    private static func inventory(_ package: URL) throws -> (bytes: Int64, programs: [URL])? {
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey]
        var enumerationError: Error?
        guard let enumerator = FileManager.default.enumerator(at: package, includingPropertiesForKeys: Array(keys), errorHandler: { _, error in enumerationError = error; return false }) else { throw CacheError.unsafe }
        var count = 0, total: Int64 = 0, programs: [URL] = []
        for case let file as URL in enumerator {
            try Task.checkCancellation(); count += 1
            guard count <= 128, file.pathComponents.count - package.pathComponents.count <= 8 else { return nil }
            let values = try file.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true else { return nil }
            if values.isDirectory == true { continue }
            guard values.isRegularFile == true, let size = values.fileSize, size >= 0 else { return nil }
            total += Int64(size); guard total <= 128_000_000 else { return nil }
            if file.lastPathComponent == "bnns_program.bnnsir" { programs.append(file) }
        }
        if let enumerationError { throw enumerationError }
        return (total, programs)
    }
}
