import Foundation

/// jsonl 文件读写。整体重写，简单可靠；文件规模小（个人使用），不做流式。
public enum JsonlFile {
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    public static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        // 用 formatted 保留亚秒精度，避免同秒内多条记录顺序丢失。
        e.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(isoFormatter.string(from: date))
        }
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let s = try decoder.singleValueContainer().decode(String.self)
            if let d = isoFormatter.date(from: s) { return d }
            throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
                                                   debugDescription: "bad date: \(s)")
        }
        return d
    }

    public static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> [T] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let dec = decoder()
        var result: [T] = []
        for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let lineData = trimmed.data(using: .utf8) else { continue }
            do {
                result.append(try dec.decode(T.self, from: lineData))
            } catch {
                throw JsonlError.decodeLineFailed(line: i + 1, underlying: error)
            }
        }
        return result
    }

    public static func write<T: Encodable>(_ items: [T], to url: URL) throws {
        let enc = encoder()
        var lines: [String] = []
        lines.reserveCapacity(items.count)
        for item in items {
            let data = try enc.encode(item)
            guard let s = String(data: data, encoding: .utf8) else {
                throw JsonlError.encodeFailed
            }
            lines.append(s)
        }
        let joined = lines.joined(separator: "\n") + (lines.isEmpty ? "" : "\n")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // 原子写：先写到临时文件再 rename
        let tmp = url.appendingPathExtension("tmp-\(UUID().uuidString)")
        try joined.data(using: .utf8)!.write(to: tmp)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
    }
}

public enum JsonlError: Error, LocalizedError {
    case decodeLineFailed(line: Int, underlying: Error)
    case encodeFailed

    public var errorDescription: String? {
        switch self {
        case .decodeLineFailed(let line, let e): return "jsonl decode failed at line \(line): \(e)"
        case .encodeFailed: return "jsonl encode failed"
        }
    }
}
