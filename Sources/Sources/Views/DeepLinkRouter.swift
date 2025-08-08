import Foundation

enum DeepLink: Equatable {
    case wishlist(id: String)
    case gifter(username: String)
}

enum DeepLinkRouter {
    static func parse(url: URL) -> DeepLink? {
        guard url.scheme == "gifterclub" else { return nil }
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let parts = path.split(separator: "/").map(String.init)
        guard let first = parts.first else { return nil }
        switch first {
        case "wishlist":
            if parts.count > 1 { return .wishlist(id: parts[1]) }
        case "u", "g":
            if parts.count > 1 { return .gifter(username: parts[1]) }
        default:
            break
        }
        return nil
    }
}

