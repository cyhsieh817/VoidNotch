import Foundation

func decodeCString(_ buffer: [CChar]) -> String {
    // String(validatingCString:) returns nil for invalid UTF-8, which has different semantics.
    return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
}
