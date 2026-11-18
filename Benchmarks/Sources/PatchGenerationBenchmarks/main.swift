import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif

do {
    var arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] {
        print("--source PATH --target PATH --mode MODE [--samples N --sample-ms MS --warmup N --max-iterations N --same-reference --source-mutable --target-mutable --memory-only --validate-only]")
        exit(0)
    }
    var values: [String: String] = [:]
    var flags: Set<String> = []
    let flagNames: Set<String> = ["--same-reference", "--source-mutable", "--target-mutable", "--memory-only", "--validate-only"]
    let valueNames: Set<String> = ["--source", "--target", "--mode", "--samples", "--sample-ms", "--warmup", "--max-iterations"]
    while !arguments.isEmpty {
        let key = arguments.removeFirst()
        if flagNames.contains(key) { flags.insert(key) }
        else if valueNames.contains(key), !arguments.isEmpty { values[key] = arguments.removeFirst() }
        else { throw BenchmarkFailure.invalid("Unknown or incomplete argument: \(key)") }
    }
    guard let source = values["--source"], let target = values["--target"],
          let mode = Measurement(rawValue: values["--mode"] ?? "generate") else {
        throw BenchmarkFailure.invalid("Supply --source, --target, and a valid --mode")
    }
    var options = WorkerOptions(source: source, target: target, mode: mode)
    func integer(_ key: String, _ fallback: Int, minimum: Int) throws -> Int {
        guard let value = Int(values[key] ?? String(fallback)), value >= minimum, value <= 1_000_000 else {
            throw BenchmarkFailure.invalid("Invalid \(key)")
        }
        return value
    }
    options.samples = try integer("--samples", 10, minimum: 1)
    options.warmup = try integer("--warmup", 3, minimum: 0)
    options.maxIterations = try integer("--max-iterations", 10_000, minimum: 1)
    guard let milliseconds = Double(values["--sample-ms"] ?? "20"), milliseconds.isFinite,
          milliseconds > 0, milliseconds <= 10_000 else { throw BenchmarkFailure.invalid("Invalid --sample-ms") }
    options.sampleMS = milliseconds
    options.sameReference = flags.contains("--same-reference")
    options.sourceMutable = flags.contains("--source-mutable")
    options.targetMutable = flags.contains("--target-mutable")
    options.memoryOnly = flags.contains("--memory-only")
    options.validateOnly = flags.contains("--validate-only")
    let result = try Worker(options).run()
    let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
} catch {
    let message = "Benchmark failed: \(error)\n"
    FileHandle.standardError.write(Data(message.utf8))
    exit(1)
}
