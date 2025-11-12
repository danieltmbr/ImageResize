import Foundation
#if os(Linux)
import Glibc
#endif

public struct ImageRGBA {
    public let width: Int
    public let height: Int
    public var data: Data
}

@_silgen_name("decode_to_rgba")
private func c_decode_to_rgba(_ bytes: UnsafePointer<UInt8>, _ length: Int32, _ outW: UnsafeMutablePointer<Int32>, _ outH: UnsafeMutablePointer<Int32>) -> UnsafeMutablePointer<UInt8>?

@_silgen_name("resize_rgba")
private func c_resize_rgba(_ src: UnsafePointer<UInt8>, _ srcW: Int32, _ srcH: Int32, _ newW: Int32, _ newH: Int32) -> UnsafeMutablePointer<UInt8>?

@_silgen_name("encode_png")
private func c_encode_png(_ rgba: UnsafePointer<UInt8>, _ w: Int32, _ h: Int32, _ outLen: UnsafeMutablePointer<Int32>) -> UnsafeMutablePointer<UInt8>?

public enum ImageC {
    
    // MARK: - Format detection
    private enum ImageFormat { case png, jpeg, gif, webp, unknown }
    
    public func dimensions(of data: Data) -> CGSize {
        switch sniffFormat(data) {
        case .png:
            if let (w, h) = pngHeaderSize(data) {
                return CGSize(width: CGFloat(w), height: CGFloat(h))
            }
        case .jpeg:
            if let (w, h) = jpegHeaderSize(data) {
                return CGSize(width: CGFloat(w), height: CGFloat(h))
            }
        case .gif, .webp, .unknown:
            break
        }
        if let src = ImageC.decodeToRGBA(data) {
            return CGSize(width: CGFloat(src.width), height: CGFloat(src.height))
        }
        return CGSize()
    }
    
    public static func decodeToRGBA(_ data: Data) -> ImageRGBA? {
        return data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            var w: Int32 = 0
            var h: Int32 = 0
            guard let ptr = c_decode_to_rgba(base, Int32(data.count), &w, &h) else { return nil }
            defer { free(ptr) }
            let count = Int(w) * Int(h) * 4
            let buffer = Data(bytes: ptr, count: count)
            return ImageRGBA(width: Int(w), height: Int(h), data: buffer)
        }
    }
    
    public static func resizeRGBA(_ image: ImageRGBA, to newW: Int, _ newH: Int) -> ImageRGBA? {
        return image.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            guard let ptr = c_resize_rgba(base, Int32(image.width), Int32(image.height), Int32(newW), Int32(newH)) else { return nil }
            defer { free(ptr) }
            let count = newW * newH * 4
            let buffer = Data(bytes: ptr, count: count)
            return ImageRGBA(width: newW, height: newH, data: buffer)
        }
    }
    
    public static func encodePNG(_ image: ImageRGBA) -> Data? {
        return image.data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return nil }
            var len: Int32 = 0
            guard let ptr = c_encode_png(base, Int32(image.width), Int32(image.height), &len) else { return nil }
            defer { free(ptr) }
            return Data(bytes: ptr, count: Int(len))
        }
    }
    
    // MARK: - Header-only size reads (fast path)
    private func pngHeaderSize(_ data: Data) -> (Int, Int)? {
        // PNG IHDR is at fixed offset after 8-byte signature: 8(sig) + 4(len) + 4(\"IHDR\")
        // Then IHDR payload: width(4), height(4)
        guard data.count >= 24 else { return nil }
        // Validate signature
        let sig: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        guard data.starts(with: sig) else { return nil }
        // IHDR chunk follows
        // width: bytes 16..19, height: 20..23 (big-endian)
        let w = data[16...19].reduce(0) { ($0 << 8) | Int($1) }
        let h = data[20...23].reduce(0) { ($0 << 8) | Int($1) }
        guard w > 0 && h > 0 else { return nil }
        return (w, h)
    }
    
    private func jpegHeaderSize(_ data: Data) -> (Int, Int)? {
        // Parse JPEG markers until SOF0/SOF2 to get size
        // Minimal parser for size only
        guard data.count > 4, data[0] == 0xFF, data[1] == 0xD8 else { return nil }
        var i = 2
        while i + 9 < data.count {
            if data[i] != 0xFF { i += 1; continue }
            var marker = data[i + 1]
            i += 2
            while marker == 0xFF, i < data.count {
                marker = data[i]
                i += 1
            }
            if marker == 0xD9 || marker == 0xDA { break } // EOI or SOS
            if i + 1 >= data.count { break }
            let length = Int(data[i]) << 8 | Int(data[i + 1])
            if length < 2 || i + length > data.count { break }
            // SOF0(0xC0) or SOF2(0xC2) carry size
            if marker == 0xC0 || marker == 0xC2 {
                if i + 7 <= data.count {
                    let height = Int(data[i + 3]) << 8 | Int(data[i + 4])
                    let width  = Int(data[i + 5]) << 8 | Int(data[i + 6])
                    return (width, height)
                }
                break
            }
            i += length
        }
        return nil
    }
    
    private func sniffFormat(_ data: Data) -> ImageFormat {
        if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return .png } // "\x89PNG"
        if data.starts(with: [0xFF, 0xD8, 0xFF]) { return .jpeg }      // JPEG SOI
        if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return .gif } // "GIF8"
        if data.starts(with: [0x52, 0x49, 0x46, 0x46]) && data.count >= 12 {
            // RIFF....WEBP
            let fourcc = data[8..<12]
            if String(bytes: fourcc, encoding: .ascii) == "WEBP" { return .webp }
        }
        return .unknown
    }
}
