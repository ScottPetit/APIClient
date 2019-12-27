import Foundation
import Combine

public struct APIClient<APIError: Swift.Error> {

    public enum Error: Swift.Error {
        case foundation(NSError)
        case url(URLError)
        case decoding(DecodingError)
    }

    public let baseUrl: String
    fileprivate let errorMap: (APIClient.Error, Data?) -> APIError
    public var headers: [String: String]

    public init(baseUrl: String, headers: [String: String] = ["Content-Type": "application/json"], errorMap: @escaping (APIClient.Error, Data?) -> APIError) {
        self.baseUrl = baseUrl
        self.errorMap = errorMap
        self.headers = headers
    }

    @discardableResult
    public func load<T>(_ resource: RemoteEndpoint<T>, completion: @escaping (Result<T, APIError>) -> Void) -> CancelableOperation {
        let finalResource = resource.append(self.headers, uniquingKeysWith: { original, new in
            return original
        })
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
                guard resource.acceptableStatusCode(response.statusCode) else {
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

            let parsedResult = resource.parse(responseData)
            let result = parsedResult.mapError { (decodingError) in
                self.errorMap(.decoding(decodingError), data)
            }
            completion(result)
        }

        task.resume()
        return task
    }

    @available(iOS 13, macOS 15, *)
    public func dataTaskPublisher<T>(_ resource: RemoteEndpoint<T>, decoder: JSONDecoder? = nil) -> AnyPublisher<T, APIError> {
        let finalResource = resource.append(self.headers, uniquingKeysWith: { original, new in
            return original
        })
        let request = self.request(from: finalResource)
        let session = URLSession.shared
        let publisher = session.dataTaskPublisher(for: request as URLRequest).tryMap { (output) -> Data in
            let data = output.data
            if let httpResponse = output.response as? HTTPURLResponse {
                if !resource.acceptableStatusCode(httpResponse.statusCode) {
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

    public func request<T>(from resource: RemoteEndpoint<T>) -> NSMutableURLRequest {
        var urlComponents = URLComponents(string: baseUrl + resource.path.path)
        if let parameters = resource.parameters, !parameters.isEmpty {
            let queryItems = parameters.map(URLQueryItem.init)
            urlComponents?.queryItems = queryItems
        }
        let request = NSMutableURLRequest(url: urlComponents!.url!)
        request.httpMethod = resource.method.rawValue

        if let data = resource.method.body {
            request.httpBody = data
        }

        for (key, value) in resource.headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }

}
