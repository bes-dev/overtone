import Foundation

struct SpeechRequestBody: Encodable {
    let input: String
    let voice: String
    let responseFormat: String
    let speed: Double
    let language: String
    let totalStep: Int
    let maxChunkLength: Int
    let silenceMs: Int

    enum CodingKeys: String, CodingKey {
        case input, voice, speed, language
        case responseFormat = "response_format"
        case totalStep = "total_step"
        case maxChunkLength = "max_chunk_len"
        case silenceMs = "silence_ms"
    }
}

final class StreamingSpeechRequest: NSObject, URLSessionDataDelegate {
    private let url: URL
    private let body: SpeechRequestBody
    private let onData: (Data) -> Void
    private let onCompletion: (Error?) -> Void
    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var responseError: Error?

    init(
        url: URL,
        body: SpeechRequestBody,
        onData: @escaping (Data) -> Void,
        onCompletion: @escaping (Error?) -> Void
    ) {
        self.url = url
        self.body = body
        self.onData = onData
        self.onCompletion = onCompletion
    }

    func start() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            onCompletion(error)
            return
        }
        self.session = session
        task = session.dataTask(with: request)
        task?.resume()
    }

    func cancel() {
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            responseError = NSError(domain: "Overtone", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "TTS server returned HTTP \(http.statusCode)"
            ])
            completionHandler(.cancel)
        } else {
            completionHandler(.allow)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onData(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        onCompletion(responseError ?? error)
        session.finishTasksAndInvalidate()
        self.session = nil
        self.task = nil
    }
}

