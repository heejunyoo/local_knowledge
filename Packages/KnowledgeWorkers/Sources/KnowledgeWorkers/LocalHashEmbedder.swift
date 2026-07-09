import Foundation
import KnowledgeIndex

/// Local hashing-trick embedder (no model download). Powers hybrid retrieval on Apple Silicon mini.
public enum LocalHashEmbedder {
    public static let dimension = 128

    public static func embed(_ text: String) -> [Float] {
        var vec = [Float](repeating: 0, count: dimension)
        let tokens = tokenize(text)
        guard !tokens.isEmpty else { return vec }
        for t in tokens {
            let h = stableHash(t)
            let idx = abs(h) % dimension
            let sign: Float = (h & 1) == 0 ? 1 : -1
            vec[idx] += sign
        }
        // L2 normalize
        var norm: Float = 0
        for v in vec { norm += v * v }
        norm = sqrt(max(norm, 1e-9))
        for i in 0..<vec.count { vec[i] /= norm }
        return vec
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var s: Float = 0
        for i in 0..<a.count { s += a[i] * b[i] }
        return s
    }

    /// Persist embeddings for all chunks of a unit.
    public static func indexUnit(store: KnowledgeStore, unitId: String) throws {
        let chunks = try store.chunks(forUnit: unitId)
        for c in chunks {
            let v = embed(c.text)
            try store.upsertChunkVector(chunkId: c.chunkId, dim: dimension, floats: v)
        }
    }

    private static func tokenize(_ text: String) -> [String] {
        var out: [String] = []
        let lowered = text.lowercased()
        // space tokens
        out.append(contentsOf: lowered.split { $0.isWhitespace || ".,;:!?()[]{}\"'".contains($0) }.map(String.init).filter { $0.count >= 2 })
        // hangul bigrams
        let compact = lowered.replacingOccurrences(of: " ", with: "")
        let chars = Array(compact)
        if chars.count >= 2 {
            for i in 0..<(chars.count - 1) {
                let bi = String(chars[i...i + 1])
                if bi.unicodeScalars.contains(where: { $0.value >= 0xAC00 && $0.value <= 0xD7A3 }) {
                    out.append(bi)
                }
            }
        }
        return out
    }

    private static func stableHash(_ s: String) -> Int {
        var h: UInt64 = 14695981039346656037
        for b in s.utf8 {
            h ^= UInt64(b)
            h &*= 1099511628211
        }
        return Int(truncatingIfNeeded: h)
    }
}
