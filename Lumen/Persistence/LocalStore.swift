import Foundation

// MARK: - Local-first persistence
// Everything lives on this device, inside the App Group container so the
// widget reads the same truth. One JSON file per domain, written atomically.
// Swapping in a remote backend later means replacing this type only.

public enum AppGroup {
    public static let id = "group.com.dbakp.lumen"
    /// Shared defaults for small values the widget needs.
    public static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

public enum LocalStore {
    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    public static var directory: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.id)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("LumenData", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    private static func url(_ name: String) -> URL { directory.appendingPathComponent("\(name).json") }

    public static func save<T: Encodable>(_ value: T, as name: String) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url(name), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    public static func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        if let data = try? Data(contentsOf: url(name)), let v = try? decoder.decode(T.self, from: data) { return v }
        return nil
    }

    /// Load from file, falling back to a legacy UserDefaults key (pre-1.1 builds) once.
    public static func load<T: Decodable>(_ type: T.Type, from name: String, legacyKey: String) -> T? {
        if let v = load(type, from: name) { return v }
        if let data = UserDefaults.standard.data(forKey: legacyKey),
           let v = try? JSONDecoder().decode(T.self, from: data) {
            return v
        }
        return nil
    }

    /// All stored files — used by export.
    public static func allFiles() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    /// Wipe everything Lumen stores locally (account reset).
    public static func eraseAll() {
        for f in allFiles() { try? FileManager.default.removeItem(at: f) }
        if let bundle = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: bundle) }
        AppGroup.defaults.removePersistentDomain(forName: AppGroup.id)
    }

    /// One JSON document with every domain — the user's data, portable.
    public static func exportBundle() -> URL? {
        var root: [String: Any] = ["exportedAt": ISO8601DateFormatter().string(from: Date()), "app": "Lumen"]
        for f in allFiles() where f.pathExtension == "json" {
            if let d = try? Data(contentsOf: f), let obj = try? JSONSerialization.jsonObject(with: d) {
                root[f.deletingPathExtension().lastPathComponent] = obj
            }
        }
        guard let out = try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys]) else { return nil }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Lumen-export-\(f.string(from: Date())).json")
        try? out.write(to: file, options: .atomic)
        return file
    }
}
