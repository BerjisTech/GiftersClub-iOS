import Foundation

final class BackgroundUploadManager: NSObject, URLSessionTaskDelegate, URLSessionDataDelegate, URLSessionDelegate {
    static let shared = BackgroundUploadManager()
    private override init() { super.init() }

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: "club.gifters.giftersclub.uploads")
        // Ensure uploads proceed quickly and reliably across network types
        config.isDiscretionary = false
        config.allowsCellularAccess = true
        if #available(iOS 13.0, *) {
            config.allowsConstrainedNetworkAccess = true
            config.waitsForConnectivity = true
        }
        config.sharedContainerIdentifier = nil
        config.sessionSendsLaunchEvents = true
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    // Store completions by task identifier
    private var completions: [Int: (Result<(Data, URLResponse), Error>) -> Void] = [:]
    private var tempFiles: [Int: URL] = [:]
    private var bgCompletionHandler: (() -> Void)?
    private let lock = NSLock()

    func upload(request: URLRequest, data: Data) async throws -> (Data, URLResponse) {
        // Background sessions require file-based uploads, not in-memory Data.
        let tmpURL = try writeTempFile(data: data)
        return try await withCheckedThrowingContinuation { cont in
            let task = session.uploadTask(with: request, fromFile: tmpURL)
            storeTempFile(tmpURL, for: task.taskIdentifier)
            storeCompletion(for: task.taskIdentifier) { result in cont.resume(with: result) }
            task.resume()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let completion = takeCompletion(for: task.taskIdentifier) else { return }
        // Cleanup temp file if any
        if let url = takeTempFile(for: task.taskIdentifier) {
            try? FileManager.default.removeItem(at: url)
        }
        if let error { completion(.failure(error)); return }
        if let http = task.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            completion(.failure(URLError(.badServerResponse)))
            return
        }
        let resp = task.response ?? URLResponse()
        completion(.success((Data(), resp)))
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Optionally accumulate body data; for PUT presigned uploads body is often empty
    }

    private func storeCompletion(for id: Int, completion: @escaping (Result<(Data, URLResponse), Error>) -> Void) {
        lock.lock(); defer { lock.unlock() }
        completions[id] = completion
    }

    private func takeCompletion(for id: Int) -> ((Result<(Data, URLResponse), Error>) -> Void)? {
        lock.lock(); defer { lock.unlock() }
        return completions.removeValue(forKey: id)
    }

    private func storeTempFile(_ url: URL, for id: Int) {
        lock.lock(); defer { lock.unlock() }
        tempFiles[id] = url
    }

    private func takeTempFile(for id: Int) -> URL? {
        lock.lock(); defer { lock.unlock() }
        return tempFiles.removeValue(forKey: id)
    }

    private func writeTempFile(data: Data) throws -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString).appendingPathExtension("upload")
        try data.write(to: url, options: [.atomic])
        return url
    }

    // Called by AppDelegate when background events finish
    func setBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        lock.lock(); bgCompletionHandler = handler; lock.unlock()
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        lock.lock(); let handler = bgCompletionHandler; bgCompletionHandler = nil; lock.unlock()
        if let handler { DispatchQueue.main.async { handler() } }
    }
}
