import Foundation

/// Errors surfaced to the user with a clean, non-crashing message.
enum MyservesError: Error, CustomStringConvertible {
    case apiUnavailable(String)
    case invalidURL(String)
    case looksSwapped(String)
    case itemNotFound(String)
    case duplicate(String)

    var description: String {
        switch self {
        case .apiUnavailable(let detail):
            return "LSSharedFileList API unavailable: \(detail)"
        case .invalidURL(let value):
            return "not a valid server URL: \(value)"
        case .looksSwapped(let value):
            return """
            first argument \"\(value)\" has no URL scheme (e.g. smb://, afp://, nfs://).
            usage is: myserves add <url> [name]   (url first, name optional)
            """
        case .itemNotFound(let name):
            return "no favourite server matched: \(name)"
        case .duplicate(let url):
            return "a favourite server with URL \(url) already exists (use --force to add anyway)"
        }
    }
}
