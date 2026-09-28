import Foundation

/// Local JSON persistence under Application Support/Screentime.
final class JSONStore {
    let directory: URL
    private var usageDirectory: URL { directory.appendingPathComponent("usage", isDirectory: true) }
    private var configURL: URL { directory.appendingPathComponent("config.json") }

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Screentime", isDirectory: true)
        try? FileManager.default.createDirectory(at: usageDirectory, withIntermediateDirectories: true)
    }

    func loadDay(_ key: String) -> DayUsage {
        read(DayUsage.self, from: usageDirectory.appendingPathComponent("\(key).json")) ?? DayUsage(day: key)
    }

    func saveDay(_ usage: DayUsage) {
        write(usage, to: usageDirectory.appendingPathComponent("\(usage.day).json"))
    }

    func loadConfig() -> Config { read(Config.self, from: configURL) ?? Config() }

    func saveConfig(_ config: Config) { write(config, to: configURL) }

    /// The last `days` days ending with `end`, oldest first.
    func history(days: Int, endingAt end: Date = Date()) -> [DayUsage] {
        let calendar = Calendar.current
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: end).map { loadDay(DayKey.key(for: $0)) }
        }
    }

    func read<T: Decodable>(_ type: T.Type, named name: String) -> T? {
        read(type, from: directory.appendingPathComponent(name))
    }

    func write<T: Encodable>(_ value: T, named name: String) {
        write(value, to: directory.appendingPathComponent(name))
    }

    func remove(named name: String) {
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
