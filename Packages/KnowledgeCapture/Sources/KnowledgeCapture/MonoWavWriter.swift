import Foundation

/// Simple mono int16 WAV writer with correct RIFF headers on close.
/// `AVAudioFile` often leaves `data` chunk size = 0 until/unless finalized correctly.
public final class MonoWavWriter: @unchecked Sendable {
    private let url: URL
    private var handle: FileHandle
    private let sampleRate: Int
    private(set) public var sampleCount: Int64 = 0
    private var closed = false

    public init(url: URL, sampleRate: Int = 16_000) throws {
        self.url = url
        self.sampleRate = sampleRate
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        self.handle = try FileHandle(forWritingTo: url)
        // Placeholder 44-byte header; rewritten on close.
        try handle.write(contentsOf: Self.header(dataBytes: 0, sampleRate: sampleRate))
    }

    public func write(int16Samples: UnsafeBufferPointer<Int16>) throws {
        guard !closed, !int16Samples.isEmpty else { return }
        let data = Data(bytes: int16Samples.baseAddress!, count: int16Samples.count * 2)
        try handle.write(contentsOf: data)
        sampleCount += Int64(int16Samples.count)
    }

    public func write(int16Array: [Int16]) throws {
        try int16Array.withUnsafeBufferPointer { try write(int16Samples: $0) }
    }

    public func close() throws {
        guard !closed else { return }
        closed = true
        let dataBytes = Int(sampleCount) * 2
        try handle.synchronize()
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Self.header(dataBytes: dataBytes, sampleRate: sampleRate))
        try handle.close()
    }

    public var byteCount: Int { 44 + Int(sampleCount) * 2 }

    private static func header(dataBytes: Int, sampleRate: Int) -> Data {
        var d = Data()
        let channels: UInt16 = 1
        let bitsPerSample: UInt16 = 16
        let byteRate = UInt32(sampleRate) * UInt32(channels) * UInt32(bitsPerSample / 8)
        let blockAlign = channels * (bitsPerSample / 8)
        let riffSize = UInt32(36 + dataBytes)

        func append(_ s: String) { d.append(contentsOf: s.utf8) }
        func appendU16(_ v: UInt16) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
        }
        func appendU32(_ v: UInt32) {
            var le = v.littleEndian
            withUnsafeBytes(of: &le) { d.append(contentsOf: $0) }
        }

        append("RIFF")
        appendU32(riffSize)
        append("WAVE")
        append("fmt ")
        appendU32(16) // PCM fmt chunk size
        appendU16(1) // PCM
        appendU16(channels)
        appendU32(UInt32(sampleRate))
        appendU32(byteRate)
        appendU16(blockAlign)
        appendU16(bitsPerSample)
        append("data")
        appendU32(UInt32(dataBytes))
        return d
    }
}
