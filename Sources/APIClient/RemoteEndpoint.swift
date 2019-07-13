import Foundation

public func expected200to300(_ code: Int) -> Bool {
    return code >= 200 && code < 300
}

public struct RemoteEndpoint<A: Decodable> {
    public let path: PathConvertible
    public let method: HTTPMethod
    public let headers: [String: String]
    public let parameters: [String: String]?
    public let acceptableStatusCode: (Int) -> Bool
    public let parse: (Data) -> Result<A, DecodingError>

    public init(path: PathConvertible, method: HTTPMethod, headers: [String: String] = [:], parameters: [String: String]? = nil, acceptableStatusCode: @escaping (Int) -> Bool = expected200to300(_:), parse: @escaping (Data) -> Result<A, DecodingError> = decode) {
        self.path = path
        self.method = method
        self.headers = headers
        self.parameters = parameters
        self.acceptableStatusCode = acceptableStatusCode
        self.parse = parse
    }

    public func append(_ headers: [String: String], uniquingKeysWith combine: ((String, String) -> String)? = nil) -> RemoteEndpoint<A> {
        let newHeaders = self.headers.merging(headers) { (old, new) -> String in
            return combine?(old, new) ?? new
        }
        return RemoteEndpoint(path: self.path, method: self.method, headers: newHeaders, parameters: self.parameters, parse: parse)
    }

    public func map<B: Decodable>(_ transform: @escaping (A) -> B) -> RemoteEndpoint<B> {
        return RemoteEndpoint<B>(path: self.path, method: self.method, headers: self.headers, parameters: self.parameters) { self.parse($0).map(transform) }
    }
}
