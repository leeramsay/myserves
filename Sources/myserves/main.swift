import Foundation

let versionString = "1.0.0"

let usage = """
myserves \(versionString) — manage the macOS "Connect to Server" (⌘K) favourites

USAGE:
  myserves list [--json]            List favourite servers
  myserves add <url> [name]         Add a favourite (name optional)
        [--force]                   Add even if the URL already exists
  myserves remove <name-or-url>     Remove favourites matching a name or URL
  myserves version                  Print version
  myserves help                     Show this help

EXAMPLES:
  myserves add smb://nas.example.com
  myserves add smb://nas.example.com/media "Media"
  myserves add nfs://10.0.0.5/export "Backups"
  myserves remove "Media"
  myserves remove smb://nas.example.com/media

NOTES:
  URLs use a scheme Finder understands: smb://, afp://, nfs://, ftp://,
  http:// or https://. No Full Disk Access is required — changes go through
  the sharedfilelistd daemon and appear in ⌘K immediately.
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(1)
}

func jsonEscape(_ s: String) -> String {
    return s
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "\"", with: "\\\"")
        .replacingOccurrences(of: "\n", with: "\\n")
        .replacingOccurrences(of: "\r", with: "\\r")
        .replacingOccurrences(of: "\t", with: "\\t")
}

/// Parse a user-supplied server URL, rejecting local paths and detecting the
/// common `add <name> <url>` argument swap.
func parseServerURL(_ raw: String) throws -> URL {
    guard let url = URL(string: raw), let scheme = url.scheme, !scheme.isEmpty else {
        // No scheme at all — very likely the user put the name first.
        if !raw.contains("://") {
            throw MyservesError.looksSwapped(raw)
        }
        throw MyservesError.invalidURL(raw)
    }
    if scheme == "file" {
        throw MyservesError.invalidURL("\(raw) (file:// paths belong in the Finder sidebar, not Connect to Server)")
    }
    return url
}

let args = Array(CommandLine.arguments.dropFirst())
let command = args.first ?? "help"

do {
    switch command {

    case "help", "--help", "-h":
        print(usage)

    case "version", "--version", "-v":
        print(versionString)

    case "list", "ls":
        let json = args.contains("--json")
        let entries = try ServerFavorites().entries()
        if json {
            let parts = entries.map { "{\"name\":\"\(jsonEscape($0.name))\",\"url\":\"\(jsonEscape($0.url))\"}" }
            print("[\(parts.joined(separator: ","))]")
        } else if entries.isEmpty {
            print("(no favourite servers)")
        } else {
            for entry in entries {
                if entry.name == entry.url || entry.name.isEmpty {
                    print(entry.url)
                } else {
                    print("\(entry.name) -> \(entry.url)")
                }
            }
        }

    case "add":
        let positionals = args.dropFirst().filter { !$0.hasPrefix("--") }
        let force = args.contains("--force")
        guard let rawURL = positionals.first else {
            fail("add requires a URL\n\n\(usage)")
        }
        let url = try parseServerURL(rawURL)
        let name = positionals.count > 1 ? positionals[1] : nil
        try ServerFavorites().add(url: url, name: name, force: force)
        if let name = name {
            print("Added: \(name) -> \(url.absoluteString)")
        } else {
            print("Added: \(url.absoluteString)")
        }

    case "remove", "rm":
        let positionals = args.dropFirst().filter { !$0.hasPrefix("--") }
        guard let query = positionals.first else {
            fail("remove requires a name or URL\n\n\(usage)")
        }
        let count = try ServerFavorites().remove(matching: query)
        print("Removed \(count) favourite\(count == 1 ? "" : "s"): \(query)")

    default:
        fail("unknown command: \(command)\n\n\(usage)")
    }
} catch let error as MyservesError {
    fail(error.description)
} catch {
    fail(error.localizedDescription)
}
