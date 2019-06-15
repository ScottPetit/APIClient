import Foundation

public enum HTTPMethod {
    case options
    case get
    case head
    case post(Data?)
    case put(Data?)
    case patch(Data?)
    case delete
    case trace
    case connect

    public var body: Data? {
        switch self {
        case let .post(body): return body
        case let .put(body): return body
        case let .patch(body): return body
        default: return nil
        }
    }

    public var rawValue: String {
        switch self {
        case .options: return "OPTIONS"
        case .get: return "GET"
        case .head: return "HEAD"
        case .post: return "POST"
        case .put: return "PUT"
        case .patch: return "PATCH"
        case .delete: return "DELETE"
        case .trace: return "TRACE"
        case .connect: return "CONNECT"
        }
    }
}
