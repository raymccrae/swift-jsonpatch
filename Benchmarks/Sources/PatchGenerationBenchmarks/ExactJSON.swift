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
    var options: JSONSerialization.ReadingOptions = [.fragmentsAllowed]
    if mutable { options.insert(.mutableContainers) }
    return try JSONSerialization.jsonObject(with: data, options: options)
}
