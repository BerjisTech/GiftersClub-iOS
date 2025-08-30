import Foundation

enum DeepLink: Equatable {
    case wishlist(id: String)
    case gifter(username: String)
    case live(id: String, manage: Bool, setupMatch: Bool)
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
        case "live":
            if parts.count > 1 {
                var manage = false
                var setup = false
                if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
                    manage = items.first(where: { $0.name == "manage" })?.value == "1"
                    setup = items.first(where: { $0.name == "setupMatch" })?.value == "1"
                }
                return .live(id: parts[1], manage: manage, setupMatch: setup)
            }
        default:
            break
        }
        return nil
    }
}
