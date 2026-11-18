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
        var options: JSONSerialization.ReadingOptions = [.fragmentsAllowed]
        if mutable { options.insert(.mutableContainers) }
        return try JSONSerialization.jsonObject(with: Data(json.utf8), options: options)
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
                let encodedBefore = try GenerationJSON(JSONSerialization.jsonObject(with: data))
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
                #expect(try GenerationJSON(JSONSerialization.jsonObject(with: patch.data())) == encodedBefore,
                        detail, sourceLocation: sourceLocation)
                #expect(try GenerationJSON(JSONSerialization.jsonObject(with: decoded.data())) == encodedBefore,
                        detail, sourceLocation: sourceLocation)
            } catch {
                throw GenerationCheckFailure(description: "\(detail.rawValue): \(error)")
            }
        }
    }
}

struct GenerationJSONTests {
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
