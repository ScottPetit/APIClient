public protocol CancelableOperation {
    func cancel()
}

struct StubbedOperation: CancelableOperation {
    func cancel() { }
}
