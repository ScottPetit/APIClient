import Foundation

public struct APIClient<Error: Swift.Error> {

    public enum Error: Swift.Error {
        case foundation(NSError)
        case decoding(DecodingError)
    }

    public let baseUrl: String
    fileprivate let errorMap: (APIClient.Error, Data?) -> Error
    public var headers: [String: String]

    public init(baseUrl: String, headers: [String: String] = ["Content-Type": "application/json"], errorMap: @escaping (APIClient.Error, Data?) -> Error) {
        self.baseUrl = baseUrl
        self.errorMap = errorMap
        self.headers = headers
    }

    @discardableResult
    public func load<T>(_ resource: Endpoint<T>, completion: @escaping (Result<T, Error>) -> Void) -> CancelableOperation {
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

            let result = resource.parse(responseData)
            switch result {
            case let .success(value):
                completion(.success(value))
            case let .failure(error):
                completion(.failure(self.errorMap(.decoding(error), data)))
            }
        }

        task.resume()
        return task
    }

    public func request<T>(from resource: Endpoint<T>) -> NSMutableURLRequest {
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
