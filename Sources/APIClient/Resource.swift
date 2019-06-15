import Foundation

public struct Resource<A: Decodable> {
    public let path: String
    public let method: HTTPMethod
    public let headers: [String: String]
    public let parameters: [String: String]?
    public let parse: (Data) -> Result<A, DecodingError>

    public init(path: String, method: HTTPMethod, headers: [String: String] = [:], parameters: [String: String]? = nil, parse: @escaping (Data) -> Result<A, DecodingError> = decode) {
        self.path = path
        self.method = method
        self.headers = headers
        self.parameters = parameters
        self.parse = parse
    }

    public func append(_ headers: [String: String], uniquingKeysWith combine: ((String, String) -> String)? = nil) -> Resource<A> {
        let newHeaders = self.headers.merging(headers) { (old, new) -> String in
            return combine?(old, new) ?? new
        }
        return Resource(path: self.path, method: self.method, headers: newHeaders, parameters: self.parameters, parse: parse)
    }

    public func map<B: Decodable>(_ transform: @escaping (A) -> B) -> Resource<B> {
        return Resource<B>(path: self.path, method: self.method, headers: self.headers, parameters: self.parameters) { self.parse($0).map(transform) }        
    }
}
