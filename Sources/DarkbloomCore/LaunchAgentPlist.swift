import Foundation

/// Reads the `io.darkbloom.provider` LaunchAgent plist that `darkbloom start`
/// writes. It survives `darkbloom stop`, so it records the models the user
/// last chose to serve.
public enum LaunchAgentPlist {
    /// `--model` values from the plist's ProgramArguments.
    public static func models(fromPlist data: Data) -> [String] {
        guard let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let args = dict["ProgramArguments"] as? [String] else { return [] }
        var models: [String] = []
        var i = 0
        while i < args.count - 1 {
            if args[i] == "--model" { models.append(args[i + 1]); i += 2 } else { i += 1 }
        }
        return models
    }

    public static func currentModels() -> [String] {
        guard let data = try? Data(contentsOf: DarkbloomPaths.launchAgentPlist) else { return [] }
        return models(fromPlist: data)
    }
}

public enum LocalModels {
    public static let hubDir = DarkbloomPaths.home
        .appendingPathComponent(".cache/huggingface/hub")

    /// Catalog ids with weights already on disk — the provider stores them
    /// as `models--<id>` in the Hugging Face hub cache.
    public static func downloadedIDs(hubDir: URL = hubDir) -> Set<String> {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: hubDir.path) else {
            return []
        }
        return Set(entries.filter { $0.hasPrefix("models--") }.map {
            String($0.dropFirst("models--".count))
        })
    }
}
