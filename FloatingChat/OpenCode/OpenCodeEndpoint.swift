import Foundation

struct OpenCodeEndpoint: Equatable, Sendable {
    static let username = "opencode"

    let baseURL: URL
    let password: String

    init(baseURL: URL, password: String) {
        self.baseURL = baseURL
        self.password = password
    }

    init(_ service: ServiceInfo) {
        self.init(baseURL: service.url, password: service.password)
    }

    var authorization: String {
        "Basic " + Data("\(Self.username):\(password)".utf8).base64EncodedString()
    }

    /// `location` scopes location-aware routes (agents, models …). It must be sent as the
    /// deepObject `location[directory]`: other spellings are silently ignored by the server,
    /// which then falls back to its own default directory.
    func request(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        location: String? = nil,
        body: Data? = nil,
        accept: String = "application/json"
    ) -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: path), resolvingAgainstBaseURL: false)!
        var items = query
        if let location {
            items.append(URLQueryItem(name: "location[directory]", value: location))
        }
        if !items.isEmpty {
            components.queryItems = items
            // URLComponents leaves "+" alone, which servers decode as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(accept, forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
