import Foundation
import CoreFoundation

/// Strict conversion boundary shared by Reader/Writer. No replacement-character fallback.
struct CSVCodec {
    static func foundationEncoding(_ encoding: CSVEncoding) -> String.Encoding {
        switch encoding {
        case .utf8: return .utf8
        case .macRoman: return .macOSRoman
        case .windows1252: return .windowsCP1252
        case .gbk: return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GBK_95.rawValue)))
        case .gb18030: return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        case .isoLatin2: return .isoLatin2
        case .windows1250: return .windowsCP1250
        case .windows1251: return .windowsCP1251
        case .windows1253: return .windowsCP1253
        case .windows1254: return .windowsCP1254
        case .japaneseEUC: return .japaneseEUC
        case .shiftJIS: return .shiftJIS
        case .iso2022JP: return .iso2022JP
        case .utf16, .utf16BigEndian: return .utf16BigEndian
        case .utf16LittleEndian: return .utf16LittleEndian
        case .utf32, .utf32BigEndian: return .utf32BigEndian
        case .utf32LittleEndian: return .utf32LittleEndian
        }
    }

    static let marks: [(CSVEncoding, [UInt8])] = [
        (.utf32LittleEndian, [0xff, 0xfe, 0, 0]), (.utf32BigEndian, [0, 0, 0xfe, 0xff]),
        (.utf8, [0xef, 0xbb, 0xbf]), (.utf16LittleEndian, [0xff, 0xfe]), (.utf16BigEndian, [0xfe, 0xff])
    ]

    static func decode(_ data: Data, encoding: CSVEncoding) throws -> (String, Bool) {
        var bytes = data
        var effective = encoding
        var hasMark = false
        // An explicit UTF-16 BOM followed by U+0000 overlaps the UTF-32LE prefix.
        // The selected encoding family resolves that ambiguity before stripping bytes.
        func accepts(_ marked: CSVEncoding) -> Bool {
            encoding == marked ||
                (encoding == .utf16 && [.utf16BigEndian, .utf16LittleEndian].contains(marked)) ||
                (encoding == .utf32 && [.utf32BigEndian, .utf32LittleEndian].contains(marked))
        }
        if let (markedEncoding, mark) = marks.first(where: { accepts($0.0) && data.starts(with: $0.1) }) {
            effective = markedEncoding
            bytes = data.dropFirst(mark.count)
            hasMark = true
        } else if marks.contains(where: { data.starts(with: $0.1) }) {
            throw CSVError.decodingFailed(encoding)
        }
        let nsEncoding = foundationEncoding(effective)
        guard let text = String(data: bytes, encoding: nsEncoding),
              let roundTrip = text.data(using: nsEncoding, allowLossyConversion: false), roundTrip == bytes else {
            throw CSVError.decodingFailed(encoding)
        }
        return (text, hasMark)
    }

    static func encode(_ text: String, encoding: CSVEncoding, bom: Bool) throws -> Data {
        let nsEncoding = foundationEncoding(encoding)
        guard let data = text.data(using: nsEncoding, allowLossyConversion: false),
              String(data: data, encoding: nsEncoding) == text else {
            throw CSVError.encodingFailed(encoding, row: nil, column: nil)
        }
        guard bom else { return data }
        let effective: CSVEncoding = encoding == .utf16 ? .utf16BigEndian : encoding == .utf32 ? .utf32BigEndian : encoding
        guard let mark = marks.first(where: { $0.0 == effective })?.1 else {
            throw CSVError.invalidConfiguration("BOM is only valid for Unicode encodings")
        }
        return Data(mark) + data
    }
}
