import Foundation

extension HTTPURLResponse {
    func hasValidStatusCode() -> Bool {
        if self.statusCode >= 200 && self.statusCode < 300 {
            return true
        }

        return false
    }

    func requiresData() -> Bool {
        return self.statusCode != 204
    }
}
