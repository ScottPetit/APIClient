import Foundation

public struct AnyEndpoint {
    public let path: PathConvertible
    public let method: HTTPMethod
    public let headers: [String: String]
    public let parameters: [String: String]?
    public let acceptableStatusCode: (Int) -> Bool
    public let sampleData: Data?
    public let decoder: JSONDecoder?
    public let parse: (Data) -> Result<Any, DecodingError>
}
