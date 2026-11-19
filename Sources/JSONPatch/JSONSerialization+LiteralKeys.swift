// Copyright © 2026 Raymond McCrae. Licensed under the Apache License, Version 2.0.

import CoreFoundation
import Foundation

// Corelibs JSONSerialization bridges object names through Swift dictionaries on
// both read and write. Keep literal JSON key identity at the library's Data boundary.
enum JSONSerializationSupport {
    static func object(with data: Data, options: JSONSerialization.ReadingOptions) throws -> Any {
        #if os(Linux)
        return try objectPreservingKeys(with: data, options: options)
        #else
        // Some Darwin Foundation versions mistake this BOM for UTF-16LE.
        let input = data.starts(with: [255, 254, 0, 0]) ? try utf8Data(data) : data
        return try JSONSerialization.jsonObject(with: input, options: options)
        #endif
    }

    static func data(with value: Any, options: JSONSerialization.WritingOptions) throws -> Data {
        #if os(Linux)
        return try dataPreservingKeys(with: value, options: options)
        #else
        return try JSONSerialization.data(withJSONObject: value, options: options)
        #endif
    }

    // Kept callable on Darwin so regressions exercise the workaround there too.
    static func objectPreservingKeys(with data: Data, options: JSONSerialization.ReadingOptions) throws -> Any {
        let utf8 = try utf8Data(data)
        // Foundation still validates the complete original syntax and options.
        let original = try JSONSerialization.jsonObject(with: utf8, options: options)
        guard utf8.contains(where: { $0 >= 128 || $0 == 92 }) else { return original }
        let names = try propertyNames(in: utf8)
        guard names.contains(where: { $0.name.unicodeScalars.contains(where: { $0.value > 127 }) }) else {
            return original
        }
        let protected = replacingNames(in: utf8, names: names) {
            Data(("\"" + Data($0.utf8).base64EncodedString() + "\"").utf8)
        }
        let parsed = try JSONSerialization.jsonObject(with: protected, options: options)
        return try restore(parsed, mutable: options.contains(.mutableContainers))
    }

    static func dataPreservingKeys(with value: Any, options: JSONSerialization.WritingOptions) throws -> Data {
        guard try containsUnicodeNames(value, depth: 512) else {
            return try JSONSerialization.data(withJSONObject: value, options: options)
        }
        var names: [String: String] = [:]
        func protect(_ value: Any, depth: Int) throws -> Any {
            guard depth > 0 else { throw JSONError.invalidObjectType }
            if let object = value as? NSDictionary {
                var entries = try fields(object)
                if options.contains(.sortedKeys) {
                    entries.sort {
                        $0.0.compare($1.0, options: [.numeric, .caseInsensitive, .forcedOrdering],
                                     locale: NSLocale.system) == .orderedAscending
                    }
                }
                let result = NSMutableDictionary(capacity: entries.count)
                for (key, item) in entries {
                    // Monotone numeric names retain original sorted-key order.
                    let code = String(names.count)
                    names[code] = key
                    result.setObject(try protect(item, depth: depth - 1), forKey: code as NSString)
                }
                return result
            }
            if let array = value as? NSArray {
                let result = NSMutableArray(capacity: array.count)
                for item in items(array) { result.add(try protect(item, depth: depth - 1)) }
                return result
            }
            return value
        }
        let protected = try protect(value, depth: 512)
        let encoded = try JSONSerialization.data(withJSONObject: protected, options: options)
        var stringOptions: JSONSerialization.WritingOptions = [.fragmentsAllowed]
        if options.contains(.withoutEscapingSlashes) { stringOptions.insert(.withoutEscapingSlashes) }
        var quoted: [String: Data] = [:]
        for (code, name) in names {
            quoted[code] = try JSONSerialization.data(withJSONObject: name, options: stringOptions)
        }
        return replacingNames(in: encoded, names: try propertyNames(in: encoded)) { quoted[$0]! }
    }

    private struct PropertyName {
        let range: Range<Int>
        let name: String
    }

    // Scan string tokens only; Foundation remains responsible for JSON grammar,
    // escapes, surrogate pairs, numeric types and all non-key values.
    private static func propertyNames(in data: Data) throws -> [PropertyName] {
        let bytes = Array(data)
        var names: [PropertyName] = []
        var index = 0
        while index < bytes.count {
            guard bytes[index] == 34 else { index += 1; continue }
            let start = index
            index += 1
            while index < bytes.count {
                if bytes[index] == 92 { index = min(index + 2, bytes.count) }
                else if bytes[index] == 34 { index += 1; break }
                else { index += 1 }
            }
            var next = index
            while next < bytes.count && [9, 10, 13, 32].contains(bytes[next]) { next += 1 }
            if next < bytes.count && bytes[next] == 58 {
                guard let name = try JSONSerialization.jsonObject(
                    with: Data(bytes[start..<index]), options: [.fragmentsAllowed]) as? String else {
                    throw JSONError.invalidObjectType
                }
                names.append(PropertyName(range: start..<index, name: name))
            }
        }
        return names
    }

    private static func replacingNames(in data: Data, names: [PropertyName],
                                       transform: (String) -> Data) -> Data {
        var result = Data()
        result.reserveCapacity(data.count)
        var offset = 0
        for name in names {
            result.append(data[offset..<name.range.lowerBound])
            result.append(transform(name.name))
            offset = name.range.upperBound
        }
        result.append(data[offset..<data.count])
        return result
    }

    private static func fields(_ object: NSDictionary) throws -> [(String, Any)] {
        let raw = unsafeBitCast(object, to: CFDictionary.self)
        var keys = [UnsafeRawPointer?](repeating: nil, count: object.count)
        var values = keys
        CFDictionaryGetKeysAndValues(raw, &keys, &values)
        return try keys.indices.map { index in
            let key = Unmanaged<AnyObject>.fromOpaque(keys[index]!).takeUnretainedValue()
            let item = Unmanaged<AnyObject>.fromOpaque(values[index]!).takeUnretainedValue()
            guard let name = key as? String else { throw JSONError.invalidObjectType }
            return (name, item)
        }
    }

    private static func items(_ array: NSArray) -> [Any] {
        let raw = unsafeBitCast(array, to: CFArray.self)
        return (0..<array.count).map {
            Unmanaged<AnyObject>.fromOpaque(CFArrayGetValueAtIndex(raw, $0)).takeUnretainedValue()
        }
    }

    private static func restore(_ value: Any, mutable: Bool) throws -> Any {
        if let object = value as? NSDictionary {
            let result = NSMutableDictionary(capacity: object.count)
            for (key, item) in try fields(object) {
                guard let bytes = Data(base64Encoded: key),
                      let name = String(data: bytes, encoding: .utf8) else { throw JSONError.invalidObjectType }
                // CFString-backed keys avoid corelibs NSString normalization.
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
            let result = NSMutableArray(capacity: array.count)
            for item in items(array) { result.add(try restore(item, mutable: mutable)) }
            return mutable ? result : result.copy() as! NSArray
        }
        return value
    }

    private static func containsUnicodeNames(_ value: Any, depth: Int) throws -> Bool {
        guard depth > 0 else { throw JSONError.invalidObjectType }
        if let object = value as? NSDictionary {
            let entries = try fields(object)
            if entries.contains(where: { $0.0.unicodeScalars.contains(where: { $0.value > 127 }) }) { return true }
            for (_, item) in entries where try containsUnicodeNames(item, depth: depth - 1) { return true }
        } else if let array = value as? NSArray {
            for item in items(array) where try containsUnicodeNames(item, depth: depth - 1) { return true }
        }
        return false
    }

    private static func utf8Data(_ data: Data) throws -> Data {
        let prefix = Array(data.prefix(4))
        var encoding = String.Encoding.utf8
        var skip = 0
        if prefix.starts(with: [0, 0, 254, 255]) { encoding = .utf32BigEndian; skip = 4 }
        else if prefix.starts(with: [255, 254, 0, 0]) { encoding = .utf32LittleEndian; skip = 4 }
        else if prefix.starts(with: [254, 255]) { encoding = .utf16BigEndian; skip = 2 }
        else if prefix.starts(with: [255, 254]) { encoding = .utf16LittleEndian; skip = 2 }
        else if prefix.starts(with: [239, 187, 191]) { skip = 3 }
        else if prefix.count == 4 {
            if prefix[0...2].allSatisfy({ $0 == 0 }) { encoding = .utf32BigEndian }
            else if prefix[1...3].allSatisfy({ $0 == 0 }) { encoding = .utf32LittleEndian }
            else if prefix[0] == 0 && prefix[2] == 0 { encoding = .utf16BigEndian }
            else if prefix[1] == 0 && prefix[3] == 0 { encoding = .utf16LittleEndian }
        }
        if encoding == .utf8 { return Data(data.dropFirst(skip)) }
        guard let text = String(data: data.dropFirst(skip), encoding: encoding) else { throw JSONError.invalidObjectType }
        return Data(text.utf8)
    }
}
