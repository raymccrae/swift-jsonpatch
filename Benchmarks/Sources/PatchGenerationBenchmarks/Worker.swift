import Foundation
import JSONPatch
#if os(Linux)
import Glibc
#else
import Darwin
#endif

enum Measurement: String, CaseIterable {
    case parse, generate, serialize
    case applyInPlace = "apply-inplace"
    case applyCopy = "apply-copy"
    case generateSerialize = "generate-serialize"
    case roundTrip = "roundtrip"
}

struct WorkerOptions {
    var source: String
    var target: String
    var mode: Measurement
    var sameReference = false
    var sourceMutable = false
    var targetMutable = false
    var samples = 10
    var sampleMS = 20.0
    var warmup = 3
    var maxIterations = 10_000
    var memoryOnly = false
    var validateOnly = false
}

func pooled<T>(_ work: () throws -> T) rethrows -> T {
    #if os(Linux)
    return try work()
    #else
    return try autoreleasepool(invoking: work)
    #endif
}

func peakRSSBytes() -> UInt64 {
    var usage = rusage()
    #if os(Linux)
    _ = getrusage(Int32(RUSAGE_SELF.rawValue), &usage)
    return UInt64(usage.ru_maxrss) * 1024
    #else
    _ = getrusage(RUSAGE_SELF, &usage)
    return UInt64(usage.ru_maxrss)
    #endif
}

final class Worker {
    let options: WorkerOptions
    let sourceData: Data
    let targetData: Data
    let source: Any
    let target: Any
    let sourceElement: JSONElement
    let targetElement: JSONElement
    var preparedPatch: JSONPatch?
    var checksum: UInt64 = 0

    init(_ options: WorkerOptions) throws {
        self.options = options
        sourceData = try Data(contentsOf: URL(fileURLWithPath: options.source))
        targetData = try Data(contentsOf: URL(fileURLWithPath: options.target))
        source = try readJSON(sourceData, mutable: options.sourceMutable)
        target = options.sameReference ? source : try readJSON(targetData, mutable: options.targetMutable)
        sourceElement = try JSONElement(any: source)
        targetElement = try JSONElement(any: target)
        if [.serialize, .applyInPlace, .applyCopy].contains(options.mode) {
            preparedPatch = try JSONPatch(source: sourceElement, target: targetElement)
        }
    }

    func validate() throws {
        let expectedSource = try ExactJSON(readJSON(sourceData))
        let expectedTarget = try ExactJSON(readJSON(targetData))
        guard try ExactJSON(source) == expectedSource, try ExactJSON(target) == expectedTarget else {
            throw BenchmarkFailure.invalid("Prepared inputs differ from fixture bytes")
        }
        let patch = try JSONPatch(source: sourceElement, target: targetElement)
        let decoded = try JSONPatch(data: patch.data())
        for _ in 0..<2 {
            let fresh = try readJSON(sourceData, mutable: true)
            let result = try decoded.apply(to: fresh)
            guard try ExactJSON(result) == expectedTarget else {
                throw BenchmarkFailure.invalid("Serialized patch round trip failed")
            }
        }
        guard try ExactJSON(source) == expectedSource, try ExactJSON(target) == expectedTarget else {
            throw BenchmarkFailure.invalid("Generation mutated its inputs")
        }
        if let preparedPatch {
            for _ in 0..<2 {
                let result: Any
                if options.mode == .applyCopy {
                    result = try preparedPatch.apply(to: source, options: [.applyOnCopy])
                } else {
                    result = try preparedPatch.apply(to: readJSON(sourceData, mutable: true))
                }
                guard try ExactJSON(result) == expectedTarget else {
                    throw BenchmarkFailure.invalid("Prepared patch changed or could not be reused")
                }
            }
            let encoded = try JSONPatch(data: preparedPatch.data())
            guard try ExactJSON(encoded.apply(to: readJSON(sourceData, mutable: true))) == expectedTarget else {
                throw BenchmarkFailure.invalid("Prepared patch serialization failed")
            }
        }
        if options.mode == .generateSerialize {
            let bytes = try JSONPatch(source: sourceData, target: targetData, options: [.fragmentsAllowed]).data()
            let encoded = try JSONPatch(data: bytes)
            guard try ExactJSON(encoded.apply(to: readJSON(sourceData, mutable: true))) == expectedTarget else {
                throw BenchmarkFailure.invalid("Data initializer round trip failed")
            }
        }
        if options.mode == .roundTrip {
            guard try ExactJSON(readJSON(roundTrip())) == expectedTarget else {
                throw BenchmarkFailure.invalid("Complete round trip failed")
            }
        }
        guard try ExactJSON(source) == expectedSource, try ExactJSON(target) == expectedTarget else {
            throw BenchmarkFailure.invalid("Validation or application mutated prepared inputs")
        }
    }

    func roundTrip() throws -> Data {
        let first = try JSONElement(any: readJSON(sourceData, mutable: options.sourceMutable))
        let second = try JSONElement(any: readJSON(targetData, mutable: options.targetMutable))
        let bytes = try JSONPatch(source: first, target: second).data()
        let decoded = try JSONPatch(data: bytes)
        let result = try decoded.apply(to: readJSON(sourceData, mutable: true))
        return try JSONSerialization.data(with: JSONElement(any: result), options: [.fragmentsAllowed])
    }

    // The result is consumed and temporary outputs are released in this call.
    // For in-place apply, preparation and release of the fresh input are outside timing.
    @inline(never) func perform(freshSource: Any?) throws -> Int {
        switch options.mode {
        case .parse:
            let first = try JSONElement(any: readJSON(sourceData, mutable: options.sourceMutable))
            let second = try JSONElement(any: readJSON(targetData, mutable: options.targetMutable))
            return first.isContainer ? (second.isContainer ? 2 : 1) : 0
        case .generate:
            return try JSONPatch(source: sourceElement, target: targetElement).operations.count
        case .serialize:
            return try preparedPatch!.data().count
        case .applyInPlace:
            let result = try preparedPatch!.apply(to: freshSource!)
            return try JSONElement(any: result).isContainer ? 1 : 0
        case .applyCopy:
            let result = try preparedPatch!.apply(to: source, options: [.applyOnCopy])
            return try JSONElement(any: result).isContainer ? 1 : 0
        case .generateSerialize:
            let patch = try JSONPatch(source: sourceData, target: targetData,
                                      options: [.fragmentsAllowed])
            return try patch.data().count
        case .roundTrip:
            return try roundTrip().count
        }
    }

    func invocation() throws -> UInt64 {
        // The outer pool drains setup temporaries outside the measured interval.
        // Without it, repeated fresh JSON parses accumulate autoreleased objects.
        try pooled {
            let fresh: Any? = options.mode == .applyInPlace ? try readJSON(sourceData, mutable: true) : nil
            let start = DispatchTime.now().uptimeNanoseconds
            let value = try pooled { try perform(freshSource: fresh) }
            let elapsed = DispatchTime.now().uptimeNanoseconds - start
            checksum &+= UInt64(value) &+ 1
            withExtendedLifetime(fresh) {}
            return elapsed
        }
    }

    func run() throws -> [String: Any] {
        var times: [Double] = []
        var iterations = 1
        var hitIterationLimit = false
        if options.memoryOnly {
            // The parent validates this case in another process first. Capture memory
            // before correctness checks and reporting build their own temporary values.
            _ = try invocation()
        } else {
            try pooled { try validate() }
            if !options.validateOnly {
                for _ in 0..<options.warmup { _ = try invocation() }
                let targetNS = UInt64(options.sampleMS * 1_000_000)
                var total: UInt64 = 0
                while true {
                    total = 0
                    for _ in 0..<iterations { total &+= try invocation() }
                    if total >= targetNS || iterations >= options.maxIterations { break }
                    iterations = min(iterations * 2, options.maxIterations)
                }
                hitIterationLimit = total < targetNS
                for _ in 0..<options.samples {
                    var elapsed: UInt64 = 0
                    for _ in 0..<iterations { elapsed &+= try invocation() }
                    times.append(Double(elapsed) / Double(iterations))
                }
            }
        }
        let memory = peakRSSBytes()
        try pooled { try validate() }
        let patch = try JSONPatch(source: sourceElement, target: targetElement)
        var counts: [String: Int] = [:]
        for operation in patch.operations {
            let name: String
            switch operation {
            case .add: name = "add"
            case .remove: name = "remove"
            case .replace: name = "replace"
            case .copy: name = "copy"
            case .move: name = "move"
            case .test: name = "test"
            }
            counts[name, default: 0] += 1
        }
        let sourceShape = try ExactJSON(readJSON(sourceData))
        let targetShape = try ExactJSON(readJSON(targetData))
        let bytes = try patch.data()
        return [
            "worker_schema_version": 1, "mode": options.mode.rawValue,
            "validation": "passed", "samples_ns": times,
            "iterations_per_sample": iterations, "iteration_limit_reached": hitIterationLimit,
            "checksum": String(checksum), "peak_rss_bytes": memory,
            "memory_only": options.memoryOnly, "source_bytes": sourceData.count,
            "target_bytes": targetData.count, "source_nodes": sourceShape.nodeCount,
            "target_nodes": targetShape.nodeCount, "source_depth": sourceShape.depth,
            "target_depth": targetShape.depth, "patch_bytes": bytes.count,
            "operation_counts": counts, "patch_data_base64": bytes.base64EncodedString()
        ]
    }
}
