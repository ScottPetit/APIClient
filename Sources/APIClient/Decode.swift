import Foundation

public func decode<A: Decodable>(_ data: Data) -> Result<A, DecodingError> {
    return decode(data, with: JSONDecoder())
}

public func decode<A: Decodable>(_ data: Data, with decoder: JSONDecoder) -> Result<A, DecodingError> {
    do {
        let result = try decoder.decode(A.self, from: data)
        return .success(result)
    } catch let error as DecodingError {
        return .failure(error)
    } catch {
        fatalError("Evidently JSONDecoders can throw errors that aren't DecodingErrors")
    }
}
