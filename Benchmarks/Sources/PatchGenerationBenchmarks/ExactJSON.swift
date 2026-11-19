import CoreFoundation
import Foundation

enum BenchmarkFailure: Error, CustomStringConvertible {
    case invalid(String)
    var description: String { switch self { case .invalid(let message): return message } }
}

// Deliberately independent of JSONElement, JSONPointer, and library equality helpers.
// Scalar arrays prevent Swift String's normalization from merging distinct JSON keys.
indirect enum ExactJSON: Equatable {
    case object([ScalarString: ExactJSON])
    case array([ExactJSON])
    case string(ScalarString)
    case number(Decimal)
    case boolean(Bool)
    case null

    struct ScalarString: Hashable {
        let scalars: [UInt32]
        init(_ string: String) { scalars = string.unicodeScalars.map(\.value) }
    }

    init(_ value: Any) throws {
        switch value {
        case let object as NSDictionary:
            var entries: [ScalarString: ExactJSON] = [:]
            #if os(Linux)
            let dictionary = unsafeBitCast(object, to: CFDictionary.self)
            var keys = [UnsafeRawPointer?](repeating: nil, count: object.count)
            var values = keys
            CFDictionaryGetKeysAndValues(dictionary, &keys, &values)
            for index in keys.indices {
                let key = Unmanaged<AnyObject>.fromOpaque(keys[index]!).takeUnretainedValue()
                let item = Unmanaged<AnyObject>.fromOpaque(values[index]!).takeUnretainedValue()
                guard let string = key as? String else { throw BenchmarkFailure.invalid("Non-string JSON key") }
                entries[ScalarString(string)] = try ExactJSON(item)
            }
            #else
            for key in object.allKeys {
                guard let string = key as? String, let item = object.object(forKey: key) else {
                    throw BenchmarkFailure.invalid("Invalid JSON object")
                }
                entries[ScalarString(string)] = try ExactJSON(item)
            }
            #endif
            guard entries.count == object.count else { throw BenchmarkFailure.invalid("Merged JSON keys") }
            self = .object(entries)
        case let array as NSArray:
            var items: [ExactJSON] = []
            for index in 0..<array.count {
                #if os(Linux)
                let raw = unsafeBitCast(array, to: CFArray.self)
                let item = Unmanaged<AnyObject>.fromOpaque(CFArrayGetValueAtIndex(raw, index)).takeUnretainedValue()
                #else
                let item = array.object(at: index)
                #endif
                items.append(try ExactJSON(item))
            }
            self = .array(items)
        case let string as NSString:
            self = .string(ScalarString(string as String))
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .boolean(number.boolValue)
            } else {
                // Do not convert through Double: adjacent large integers must stay distinct.
                guard let decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")),
                      !decimal.isNaN else { throw BenchmarkFailure.invalid("Unsupported JSON number") }
                self = .number(decimal)
            }
        case is NSNull: self = .null
        default: throw BenchmarkFailure.invalid("Unsupported JSON value")
        }
    }

    var nodeCount: Int {
        switch self {
        case .object(let entries): return 1 + entries.values.reduce(0) { $0 + $1.nodeCount }
        case .array(let items): return 1 + items.reduce(0) { $0 + $1.nodeCount }
        default: return 1
        }
    }

    var depth: Int {
        switch self {
        case .object(let entries): return 1 + (entries.values.map(\.depth).max() ?? 0)
        case .array(let items): return 1 + (items.map(\.depth).max() ?? 0)
        default: return 0
        }
    }
}

func readJSON(_ data: Data, mutable: Bool = false) throws -> Any {
    try FixtureJSON.read(data, mutable: mutable)
}

// Foundation's Linux JSON parser passes object names through Swift Dictionary.
// Encode names as ASCII before parsing, then restore CFString-backed keys. Scalar
// values still use Foundation's JSON grammar, Boolean identity and number types.
// This fixture reader deliberately does not call any JSONPatch helpers.
enum FixtureJSON {
    enum Invalid: Error { case propertyName }

    static func read(_ data: Data, mutable: Bool = false) throws -> Any {
        let bytes = Array(data)
        var encoded = [UInt8]()
        encoded.reserveCapacity(bytes.count)
        var position = 0
        while position < bytes.count {
            guard bytes[position] == 34 else {
                encoded.append(bytes[position]); position += 1; continue
            }
            let start = position
            position += 1
            while position < bytes.count {
                if bytes[position] == 92 {
                    position = min(position + 2, bytes.count)
                } else if bytes[position] == 34 {
                    position += 1; break
                } else { position += 1 }
            }
            var next = position
            while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
            if next < bytes.count && bytes[next] == 58 {
                let fragment = Data(bytes[start..<position])
                guard let name = try JSONSerialization.jsonObject(with: fragment, options: [.fragmentsAllowed]) as? String else {
                    throw Invalid.propertyName
                }
                encoded.append(34)
                encoded.append(contentsOf: Data(name.utf8).base64EncodedString().utf8)
                encoded.append(34)
            } else { encoded.append(contentsOf: bytes[start..<position]) }
        }
        let parsed = try JSONSerialization.jsonObject(with: Data(encoded), options: [.fragmentsAllowed])
        return try restore(parsed, mutable: mutable)
    }

    private static func restore(_ value: Any, mutable: Bool) throws -> Any {
        if let object = value as? NSDictionary {
            let raw = unsafeBitCast(object, to: CFDictionary.self)
            var keys = [UnsafeRawPointer?](repeating: nil, count: object.count)
            var values = keys
            CFDictionaryGetKeysAndValues(raw, &keys, &values)
            let result = NSMutableDictionary(capacity: object.count)
            for index in keys.indices {
                let key = Unmanaged<AnyObject>.fromOpaque(keys[index]!).takeUnretainedValue()
                let item = Unmanaged<AnyObject>.fromOpaque(values[index]!).takeUnretainedValue()
                guard let encoded = key as? String, let data = Data(base64Encoded: encoded),
                      let name = String(data: data, encoding: .utf8) else { throw Invalid.propertyName }
                let characters = Array(name.utf16)
                let literal = characters.withUnsafeBufferPointer {
                    CFStringCreateWithCharacters(nil, $0.baseAddress, $0.count)!
                }
                result.setObject(try restore(item, mutable: mutable),
                                 forKey: unsafeBitCast(literal, to: NSString.self))
            }
            return mutable ? result : result.copy() as! NSDictionary
        }
        if let array = value as? NSArray {
            let raw = unsafeBitCast(array, to: CFArray.self)
            let result = NSMutableArray(capacity: array.count)
            for index in 0..<array.count {
                let item = Unmanaged<AnyObject>.fromOpaque(CFArrayGetValueAtIndex(raw, index)).takeUnretainedValue()
                result.add(try restore(item, mutable: mutable))
            }
            return mutable ? result : result.copy() as! NSArray
        }
        return value
    }
}
