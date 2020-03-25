import Foundation
import Combine

public struct APIClient<APIError: Swift.Error> {

    public enum Error: Swift.Error {
        case foundation(NSError)
        case url(URLError)
        case decoding(DecodingError)
    }

    /// An enum representing different options for stubbing the response of the APIClient
    /// `.immediately` attempts to return a successful result by parsing `RemoteEndpoint.sampleData` if provided.  If this option is set and no `sampleData` is provided then the `APIClient` will return a `failure` case with an error.
    /// `.immediatelyError` allows clients to provide an `APIError` they wish to have return given an `AnyEndpoint`
    /// `.immediatelyWithOverride` allows clients to override the `sampleData` of a `RemoteEndpoint` and instead use the provided `Data`
    public enum StubBehavior {
        case immediately
        case immediatelyError((AnyEndpoint) -> APIError)
        case immediatelyWithOverride((AnyEndpoint) -> Data)
    }

    public let baseUrl: String
    fileprivate let errorMap: (APIClient.Error, Data?) -> APIError
    public var headers: [String: String]
    public var stubBehavior: StubBehavior?

    public init(baseUrl: String, headers: [String: String] = ["Content-Type": "application/json"], errorMap: @escaping (APIClient.Error, Data?) -> APIError) {
        self.baseUrl = baseUrl
        self.errorMap = errorMap
        self.headers = headers
    }

    @discardableResult
    public func load<T>(_ endpoint: RemoteEndpoint<T>, completion: @escaping (Result<T, APIError>) -> Void) -> CancelableOperation {
        let finalResource = endpoint.append(self.headers, uniquingKeysWith: { original, new in
            return original
        })
        let didStubEndpoint = stub(endpoint, with: completion)
        if didStubEndpoint {
            return StubbedOperation()
        }

        let request = self.request(from: finalResource)

        let session = URLSession.shared
        let task = session.dataTask(with: request as URLRequest) { data, response, error in
            if let error = error {
                //invalid error
                completion(.failure(self.errorMap(.foundation(error as NSError), data)))
                return
            }

            let responseData = data ?? Data()

            if let response = response as? HTTPURLResponse {
                guard endpoint.acceptableStatusCode(response.statusCode) else {
                    let error = NSError(domain: "com.webservice.load", code: response.statusCode, userInfo: ["Reason": "Failing Status Code"])
                    completion(.failure(self.errorMap(.foundation(error), data)))
                    return
                }                

                if response.requiresData() {
                    guard !responseData.isEmpty else {
                        let error = NSError(domain: "com.webservice.load", code: -1989, userInfo: ["Reason": "No Data"])
                        completion(.failure(self.errorMap(.foundation(error), data)))
                        return
                    }
                }
            }

            let parsedResult = endpoint.parse(responseData)
            let result = parsedResult.mapError { (decodingError) in
                self.errorMap(.decoding(decodingError), data)
            }
            completion(result)
        }

        task.resume()
        return task
    }

    @available(iOS 13, macOS 15, *)
    public func dataTaskPublisher<T>(_ endpoint: RemoteEndpoint<T>, decoder: JSONDecoder? = nil) -> AnyPublisher<T, APIError> {
        let finalEndpoint = endpoint.append(self.headers, uniquingKeysWith: { original, new in
            return original
        })

        if let stubbedPublisher = self.stub(finalEndpoint) {
            return stubbedPublisher
        }

        let request = self.request(from: finalEndpoint)
        let session = URLSession.shared
        let publisher = session.dataTaskPublisher(for: request as URLRequest).tryMap { (output) -> Data in
            let data = output.data
            if let httpResponse = output.response as? HTTPURLResponse {
                if !endpoint.acceptableStatusCode(httpResponse.statusCode) {
                    let foundationError = NSError(domain: "com.apiclient", code: httpResponse.statusCode, userInfo: nil)
                    let error = APIClient.Error.foundation(foundationError)
                    let mappedError = self.errorMap(error, data)
                    throw mappedError
                }
            }
            return data
        }
        .decode(type: T.self, decoder: decoder ?? JSONDecoder())
        .mapError { (error) -> APIError in
            if let apiError = error as? APIError {
                return apiError
            } else if let apiError = error as? APIClient.Error {
                return self.errorMap(apiError, nil)
            } else if let decodingError = error as? DecodingError {
                return self.errorMap(APIClient.Error.decoding(decodingError), nil)
            } else if let urlError = error as? URLError {
                return self.errorMap(APIClient.Error.url(urlError), nil)
            } else {
                let _error = APIClient.Error.foundation(error as NSError)
                return self.errorMap(_error, nil)
            }
        }.eraseToAnyPublisher()
        return publisher
    }

    public func request<T>(from endpoint: RemoteEndpoint<T>) -> NSMutableURLRequest {
        var urlComponents = URLComponents(string: baseUrl + endpoint.path.path)
        if let parameters = endpoint.parameters, !parameters.isEmpty {
            let queryItems = parameters.map(URLQueryItem.init)
            urlComponents?.queryItems = queryItems
        }
        let request = NSMutableURLRequest(url: urlComponents!.url!)
        request.httpMethod = endpoint.method.rawValue

        if let data = endpoint.method.body {
            request.httpBody = data
        }

        for (key, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

    private func stub<T>(_ endpoint: RemoteEndpoint<T>, with completion: (Result<T, APIError>) -> ()) -> Bool {
        guard let stubBehavior = stubBehavior else { return false }
        switch stubBehavior {
        case .immediately:
            if let sampleData = endpoint.sampleData {
                let parsedResult = endpoint.parse(sampleData)
                let result = parsedResult.mapError { (decodingError) in
                    self.errorMap(.decoding(decodingError), sampleData)
                }
                completion(result)
            } else {
                let error = self.expectedSampleDataError(for: endpoint)
                completion(.failure(self.errorMap(error, Data())))
            }
        case let .immediatelyError(closure):
            let error = closure(endpoint.eraseToAnyEndpoint())
            completion(.failure(error))
        case let .immediatelyWithOverride(closure):
            let data = closure(endpoint.eraseToAnyEndpoint())
            let parsedResult = endpoint.parse(data)
            let result = parsedResult.mapError { (decodingError) in
                self.errorMap(.decoding(decodingError), data)
            }
            completion(result)
        }
        return true
    }

    @available(iOS 13, macOS 15, *)
    private func stub<T>(_ endpoint: RemoteEndpoint<T>) -> AnyPublisher<T, APIError>? {
        guard let stubBehavior = stubBehavior else { return nil }
        switch stubBehavior {
        case .immediately:
            let result = Future<T, APIError> { promise in
                if let sampleData = endpoint.sampleData {
                    let parsedResult = endpoint.parse(sampleData)
                    let result = parsedResult.mapError { (decodingError) in
                        self.errorMap(.decoding(decodingError), sampleData)
                    }
                    promise(result)
                } else {
                    let error = self.expectedSampleDataError(for: endpoint)
                    promise(.failure(self.errorMap(error, Data())))
                }
            }
            return result.eraseToAnyPublisher()
        case let .immediatelyError(closure):
            let error = closure(endpoint.eraseToAnyEndpoint())
            let result = Future<T, APIError> { (promise) in
                promise(.failure(error))
            }
            return result.eraseToAnyPublisher()
        case let .immediatelyWithOverride(closure):
            let result = Future<T, APIError> { promise in
                let data = closure(endpoint.eraseToAnyEndpoint())
                let parsedResult = endpoint.parse(data)
                let result = parsedResult.mapError { (decodingError) in
                    self.errorMap(.decoding(decodingError), data)
                }
                promise(result)
            }
            return result.eraseToAnyPublisher()
        }
    }

    private func expectedSampleDataError<T>(for endpoint: RemoteEndpoint<T>) -> APIClient.Error {
        let error = NSError(domain: "io.hecho.api-client",
                            code: 808,
                            userInfo: [NSLocalizedDescriptionKey: "Expected sample data for \(endpoint.path) but none was provided"])
        let apiError = APIClient.Error.foundation(error)
        return apiError
    }

}
