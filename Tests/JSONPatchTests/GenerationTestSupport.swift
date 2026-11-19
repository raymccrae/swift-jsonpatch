// Copyright © 2026 Raymond McCrae. Licensed under the Apache License, Version 2.0.

import CoreFoundation
import Foundation
import Testing
@testable import JSONPatch

// Test-only value model. Do not use JSONElement equality, JSONPointer, or the
// generator's helpers to decide whether a result matches its intended document.
// This follows the benchmark comparator without depending on that separate package.
indirect enum GenerationJSON: Equatable {
    case object([Key: GenerationJSON])
    case array([GenerationJSON])
    case string(Key)
    case number(Decimal)
    case boolean(Bool)
    case null

    struct Key: Hashable {
        let scalars: [UInt32]
        init(_ string: String) { scalars = string.unicodeScalars.map(\.value) }
        var string: String {
            String(String.UnicodeScalarView(scalars.map { Unicode.Scalar($0)! }))
        }
    }

    enum InvalidJSON: Error { case unsupportedValue, invalidKey, invalidNumber }

    init(_ value: Any) throws {
        switch value {
        case let object as NSDictionary:
            var entries: [Key: GenerationJSON] = [:]
            #if os(Linux)
            // Swift dictionary bridging can normalize keys or erase NSNumber
            // Boolean identity. Read Foundation storage directly on Linux.
            let dictionary = unsafeBitCast(object, to: CFDictionary.self)
            var keys = [UnsafeRawPointer?](repeating: nil, count: object.count)
            var values = keys
            CFDictionaryGetKeysAndValues(dictionary, &keys, &values)
            for index in keys.indices {
                let key = Unmanaged<AnyObject>.fromOpaque(keys[index]!).takeUnretainedValue()
                let item = Unmanaged<AnyObject>.fromOpaque(values[index]!).takeUnretainedValue()
                guard let string = key as? String else { throw InvalidJSON.invalidKey }
                entries[Key(string)] = try GenerationJSON(item)
            }
            #else
            for key in object.allKeys {
                guard let string = key as? String, let item = object.object(forKey: key) else {
                    throw InvalidJSON.invalidKey
                }
                entries[Key(string)] = try GenerationJSON(item)
            }
            #endif
            guard entries.count == object.count else { throw InvalidJSON.invalidKey }
            self = .object(entries)
        case let array as NSArray:
            var items: [GenerationJSON] = []
            for index in 0..<array.count {
                #if os(Linux)
                let raw = unsafeBitCast(array, to: CFArray.self)
                let item = Unmanaged<AnyObject>.fromOpaque(CFArrayGetValueAtIndex(raw, index)).takeUnretainedValue()
                #else
                let item = array.object(at: index)
                #endif
                items.append(try GenerationJSON(item))
            }
            self = .array(items)
        case let string as NSString:
            self = .string(Key(string as String))
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .boolean(number.boolValue)
            } else {
                guard let decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")),
                      !decimal.isNaN else { throw InvalidJSON.invalidNumber }
                self = .number(decimal)
            }
        case is NSNull: self = .null
        default: throw InvalidJSON.unsupportedValue
        }
    }

    static func read(_ json: String, mutable: Bool = false) throws -> Any {
        try FixtureJSON.read(Data(json.utf8), mutable: mutable)
    }

    static func parse(_ json: String) throws -> Self { try Self(read(json)) }
    static func text(_ string: String) -> Self { .string(Key(string)) }
    static func dictionary(_ entries: [(String, Self)]) -> Self {
        .object(Dictionary(uniqueKeysWithValues: entries.map { (Key($0.0), $0.1) }))
    }

    // Stable fixture encoding: sort scalar keys, preserve numeric precision, and
    // delegate only string escaping to Foundation. Never use Swift's Hasher as a seed.
    func json() throws -> String {
        func quoted(_ string: String) throws -> String {
            String(decoding: try JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed]), as: UTF8.self)
        }
        switch self {
        case .object(let entries):
            let fields = try entries.keys.sorted { $0.scalars.lexicographicallyPrecedes($1.scalars) }.map {
                try quoted($0.string) + ":" + entries[$0]!.json()
            }
            return "{" + fields.joined(separator: ",") + "}"
        case .array(let items): return "[" + (try items.map { try $0.json() }).joined(separator: ",") + "]"
        case .string(let key): return try quoted(key.string)
        case .number(var value): return NSDecimalString(&value, Locale(identifier: "en_US_POSIX"))
        case .boolean(let value): return value ? "true" : "false"
        case .null: return "null"
        }
    }
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

private struct GenerationCheckFailure: Error, CustomStringConvertible {
    let description: String
}

// Every fixture exercises all four source/target container-mutability pairs.
// Reuse both the original patch and its serialized form on fresh documents.
// The library applies the patch; the independent model checks the result.
func assertGeneratedPatch(
    source sourceJSON: String, target targetJSON: String,
    context: String = "focused fixture",
    generationOptions: [JSONPatch.GenerationOption] = [],
    sourceLocation: SourceLocation = #_sourceLocation,
    quality: (JSONPatch) throws -> Void = { _ in }
) throws {
    let expectedSource = try GenerationJSON.parse(sourceJSON)
    let expectedTarget = try GenerationJSON.parse(targetJSON)
    for sourceMutable in [false, true] {
        for targetMutable in [false, true] {
            let detail = Comment(rawValue: "\(context); generationOptions=\(generationOptions); sourceMutable=\(sourceMutable), targetMutable=\(targetMutable); source=\(sourceJSON); target=\(targetJSON)")
            do {
                let source = try JSONElement(any: GenerationJSON.read(sourceJSON, mutable: sourceMutable))
                let target = try JSONElement(any: GenerationJSON.read(targetJSON, mutable: targetMutable))
                #expect(try GenerationJSON(source.rawValue) == expectedSource, detail, sourceLocation: sourceLocation)
                #expect(try GenerationJSON(target.rawValue) == expectedTarget, detail, sourceLocation: sourceLocation)
                let patch = try JSONPatch(source: source, target: target, generationOptions: generationOptions)
                let data = try patch.data()
                let encodedBefore = try GenerationJSON(FixtureJSON.read(data))
                let decoded = try JSONPatch(data: data)
                #expect(try GenerationJSON(source.rawValue) == expectedSource, detail, sourceLocation: sourceLocation)
                #expect(try GenerationJSON(target.rawValue) == expectedTarget, detail, sourceLocation: sourceLocation)
                try quality(patch)

                for reusable in [patch, decoded] {
                    for mutable in [false, true] {
                        let result = try reusable.apply(to: GenerationJSON.read(sourceJSON, mutable: mutable))
                        #expect(try GenerationJSON(result) == expectedTarget, detail, sourceLocation: sourceLocation)
                    }
                    let result = try reusable.apply(to: source.rawValue, options: [.applyOnCopy])
                    #expect(try GenerationJSON(result) == expectedTarget, detail, sourceLocation: sourceLocation)
                    #expect(try GenerationJSON(source.rawValue) == expectedSource, detail, sourceLocation: sourceLocation)
                }
                #expect(try GenerationJSON(target.rawValue) == expectedTarget, detail, sourceLocation: sourceLocation)
                #expect(try GenerationJSON(FixtureJSON.read(patch.data())) == encodedBefore,
                        detail, sourceLocation: sourceLocation)
                #expect(try GenerationJSON(FixtureJSON.read(decoded.data())) == encodedBefore,
                        detail, sourceLocation: sourceLocation)
            } catch {
                throw GenerationCheckFailure(description: "\(detail.rawValue): \(error)")
            }
        }
    }
}

struct GenerationJSONTests {

    @Test(arguments: [false, true])
    func fixtureReaderPreservesNestedLiteralAndEscapedKeys(mutable: Bool) throws {
        let json = #"{"é":[{"\u00e9":true,"e\u0301":9007199254740993,"":null}],"e\u0301":{"w6k=":"quote \" : e\u0301","é":1,"é":2}}"#
        let expected = GenerationJSON.dictionary([
            ("é", .array([.dictionary([
                ("é", .boolean(true)), ("e\u{0301}", .number(Decimal(string: "9007199254740993")!)),
                ("", .null)
            ])])),
            ("e\u{0301}", .dictionary([
                ("w6k=", .text("quote \" : e\u{0301}")), ("é", .number(1)), ("e\u{0301}", .number(2))
            ]))
        ])
        let raw = try GenerationJSON.read(json, mutable: mutable)
        #expect((raw is NSMutableDictionary) == mutable)
        let element = try JSONElement(any: raw)
        for path in ["/é", "/é/0", "/e\u{0301}"] {
            #expect(try element.evaluate(pointer: JSONPointer(string: path)).isMutable == mutable)
        }
        #expect(try GenerationJSON(raw) == expected)
        #expect(try GenerationJSON.parse(expected.json()) == expected)
        let bytes = try JSONSerialization.data(with: JSONElement(any: raw))
        #expect(try GenerationJSON(FixtureJSON.read(bytes, mutable: mutable)) == expected)
    }

    @Test func fixtureReaderKeepsUnicodeAndTransportNamesDistinct() throws {
        let raw = try GenerationJSON.read(#"{"\u00e9":2,"é":3,"w6k=":4}"#)
        #expect(try GenerationJSON(raw) == .dictionary([
            ("é", .number(2)), ("e\u{0301}", .number(3)), ("w6k=", .number(4))
        ]))
    }

    @Test(arguments: ["", #"{"é" 1}"#, #"{"é":"\q"}"#,
                      #"{"é":"unterminated}"#, #"{"é":01}"#, #"{"é":1} false"#])
    func fixtureReaderRetainsFoundationSyntaxValidation(json: String) {
        #expect(throws: (any Error).self) { try GenerationJSON.read(json) }
    }
    @Test func independentEqualityBoundaries() throws {
        #expect(try GenerationJSON.parse(#"{"a":1,"b":null}"#) == GenerationJSON.parse(#"{"b":null,"a":1.0}"#))
        for (a, b) in [("true", "1"), ("false", "0"), ("9007199254740992", "9007199254740993"),
                       ("18446744073709551614", "18446744073709551615"),
                       ("-9223372036854775808", "-9223372036854775807"),
                       (#"{"":null}"#, "{}"), ("[1,2]", "[2,1]"),
                       (#""\u00e9""#, #""e\u0301""#),
                       (#"{"\u00e9":1,"e\u0301":2}"#, #"{"\u00e9":2,"e\u0301":1}"#)] {
            #expect(try GenerationJSON.parse(a) != GenerationJSON.parse(b))
        }
        let literal = #"{"\u00e9":1,"e\u0301":2,"nested":[true,9007199254740993]}"#
        let value = try GenerationJSON.parse(literal)
        guard case .object(let entries) = value else { Issue.record("Expected object"); return }
        #expect(entries.count == 3)
        #expect(try value == GenerationJSON(GenerationJSON.read(literal, mutable: true)))
        #expect(try value == GenerationJSON.parse(value.json()))
    }
}


struct JSONSerializationLiteralKeyTests {


    @Test func shallowCopiesKeepNestedUnicodeKeysAndReferences() throws {
        let source = try GenerationJSON.read(#"{"edit":[{"é":1,"e\u0301":2}],"keep":[{"é":3,"e\u0301":4}]}"#)
        let element = try JSONElement(any: source)
        let keep = try element.evaluate(pointer: JSONPointer(string: "/keep")).rawValue as AnyObject
        let patch = JSONPatch(operations: [
            .replace(path: try JSONPointer(string: "/edit/0/é"), value: JSONElement(5)),
            .remove(path: try JSONPointer(string: "/edit/0/e\u{0301}"))
        ])
        let result = try patch.apply(to: source)
        #expect(try GenerationJSON(result) == .dictionary([
            ("edit", .array([.dictionary([("é", .number(5))])])),
            ("keep", .array([.dictionary([("é", .number(3)), ("e\u{0301}", .number(4))])]))
        ]))
        #expect(try GenerationJSON(source) == GenerationJSON.parse(#"{"edit":[{"é":1,"e\u0301":2}],"keep":[{"é":3,"e\u0301":4}]}"#))
        let unchanged = try JSONElement(any: result).evaluate(pointer: JSONPointer(string: "/keep")).rawValue as AnyObject
        #expect(unchanged === keep)
        let root = try GenerationJSON.read(#"[[{"é":1,"e\u0301":2}]]"#)
        let arrayPatch = JSONPatch(operations: [.replace(
            path: try JSONPointer(string: "/0/0/é"), value: JSONElement(6))])
        #expect(try GenerationJSON(arrayPatch.apply(to: root)) == .array([
            .array([.dictionary([("é", .number(6)), ("e\u{0301}", .number(2))])])
        ]))
    }

    @Test func asciiCanonicalEquivalentNamesCannotBypassProtection() throws {
        let json = #"{"K":1,"\u212a":2}"#
        let expected = GenerationJSON.dictionary([("K", .number(1)), ("\u{212a}", .number(2))])
        let raw = try JSONSerializationSupport.objectPreservingKeys(with: Data(json.utf8), options: [])
        #expect(try GenerationJSON(raw) == expected)
        let bytes = try JSONSerializationSupport.dataPreservingKeys(with: raw, options: [])
        #expect(try GenerationJSON(FixtureJSON.read(bytes)) == expected)
    }
    private let json = #"{"é":true,"e\u0301":9007199254740993,"nested":[{"é":1,"é":2}],"é/":"quote \" : é"}"#
    private var expected: GenerationJSON {
        .dictionary([
            ("é", .boolean(true)), ("e\u{0301}", .number(Decimal(string: "9007199254740993")!)),
            ("nested", .array([.dictionary([("é", .number(1)), ("e\u{0301}", .number(2))])])),
            ("é/", .text("quote \" : e\u{0301}"))
        ])
    }

    @Test(arguments: ["utf8", "utf8-bom", "utf16le", "utf16le-bom", "utf16be", "utf16be-bom",
                      "utf32le", "utf32le-bom", "utf32be", "utf32be-bom"], [false, true])
    func unicodeKeysSurviveEveryInputEncoding(encoding: String, mutable: Bool) throws {
        let name = encoding.replacingOccurrences(of: "-bom", with: "")
        var data = Data(json.utf8)
        if name != "utf8" {
            let units = name.hasPrefix("utf16") ? json.utf16.map(UInt32.init) : json.unicodeScalars.map(\.value)
            var shifts = name.hasPrefix("utf16") ? [0, 8] : [0, 8, 16, 24]
            if name.hasSuffix("be") { shifts.reverse() }
            data = Data(units.flatMap { unit in shifts.map { UInt8(truncatingIfNeeded: unit >> $0) } })
        }
        if encoding.hasSuffix("-bom") {
            let markers: [String: [UInt8]] = ["utf8": [239, 187, 191], "utf16le": [255, 254],
                "utf16be": [254, 255], "utf32le": [255, 254, 0, 0], "utf32be": [0, 0, 254, 255]]
            data = Data(markers[name]!) + data
        }
        let options: JSONSerialization.ReadingOptions = mutable ? [.mutableContainers] : []
        let raw = try JSONSerializationSupport.objectPreservingKeys(with: data, options: options)
        #expect(try GenerationJSON(raw) == expected)
        #expect((raw is NSMutableDictionary) == mutable)
        #expect(try GenerationJSON(JSONSerialization.jsonElement(with: data, options: options).rawValue) == expected)
    }

    @Test(arguments: [UInt(0), JSONSerialization.WritingOptions.prettyPrinted.rawValue,
                      JSONSerialization.WritingOptions.sortedKeys.rawValue,
                      JSONSerialization.WritingOptions.withoutEscapingSlashes.rawValue,
                      JSONSerialization.WritingOptions([.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]).rawValue])
    func unicodeKeysSurviveWritingOptions(flags: UInt) throws {
        let options = JSONSerialization.WritingOptions(rawValue: flags)
        let raw = try GenerationJSON.read(json)
        let data = try JSONSerializationSupport.dataPreservingKeys(with: raw, options: options)
        #expect(try GenerationJSON(FixtureJSON.read(data)) == expected)
        #expect(try GenerationJSON(FixtureJSON.read(JSONSerialization.data(with: JSONElement(any: raw), options: options))) == expected)
        if options.contains(.prettyPrinted) { #expect(data.contains(10)) }
        if options.contains(.withoutEscapingSlashes) { #expect(data.range(of: Data("\\/".utf8)) == nil) }
    }

    @Test func sortedKeysAndScalarValuesMatchFoundation() throws {
        let raw = try GenerationJSON.read(#"{"z":null,"a10":1,"a2":true,"é/":"x/y","A":"\\\""}"#)
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .prettyPrinted, .withoutEscapingSlashes]
        #expect(try JSONSerializationSupport.dataPreservingKeys(with: raw, options: options)
                == JSONSerialization.data(withJSONObject: raw, options: options))
        for json in ["true", "false", "null", "9007199254740993", "18446744073709551615", "1.25", #""é/e\u0301""#] {
            let raw = try GenerationJSON.read(json)
            #expect(try JSONSerializationSupport.dataPreservingKeys(with: raw, options: [.fragmentsAllowed])
                    == JSONSerialization.data(withJSONObject: raw, options: [.fragmentsAllowed]))
        }
    }

    @Test func publicDataPathsAndSnapshotsKeepLiteralKeys() throws {
        let source = Data(#"{"é":1,"e\u0301":2}"#.utf8)
        let target = Data(#"{"é":3,"e\u0301":4}"#.utf8)
        let expected = GenerationJSON.dictionary([("é", .number(3)), ("e\u{0301}", .number(4))])
        for policy: [JSONPatch.GenerationOption] in [[], [.preferSmallerPatch]] {
            let patch = try JSONPatch(source: source, target: target, generationOptions: policy)
            let decoded = try JSONPatch(data: patch.data())
            for reading: JSONSerialization.ReadingOptions in [[], [.mutableContainers]] {
                let result = try decoded.apply(to: source, readingOptions: reading)
                #expect(try GenerationJSON(FixtureJSON.read(result)) == expected)
            }
        }
        let snapshot = try JSONError.Value(jsonObject: GenerationJSON.read(String(decoding: target, as: UTF8.self)))
        #expect(try GenerationJSON(snapshot.jsonObject()) == expected)
        #expect(try GenerationJSON(FixtureJSON.read(snapshot.data)) == expected)
    }

    @Test func originalSyntaxAndFragmentOptionsStillApply() throws {
        for json in [#"{"é":"\q"}"#, #"{"é":01}"#, #"{"é":1}false"#, #""é""#] {
            #expect(throws: (any Error).self) {
                try JSONSerializationSupport.objectPreservingKeys(with: Data(json.utf8), options: [])
            }
        }
        #expect(try GenerationJSON(JSONSerializationSupport.objectPreservingKeys(
            with: Data(#""é""#.utf8), options: [.fragmentsAllowed])) == .text("é"))
    }
}
