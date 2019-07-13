import Foundation

extension HTTPURLResponse {
    func requiresData() -> Bool {
        return self.statusCode != 204
    }
}
