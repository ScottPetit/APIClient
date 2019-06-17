import Foundation

public protocol PathConvertible {
    var path: String { get }
}

extension String: PathConvertible {
    public var path: String {
        return self
    }
}
