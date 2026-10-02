import Foundation
import Testing

/// Loads packaged fixtures without depending on the process's working directory.
enum TestResources {
    private final class BundleToken {}

    static func url(forResource name: String, withExtension ext: String? = "json") throws -> URL {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle(for: BundleToken.self)
        #endif
        return try #require(bundle.url(forResource: name, withExtension: ext),
                            "Missing test resource: \(name).\(ext ?? "") in \(bundle.bundlePath)")
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(forResource: name))
    }
}
