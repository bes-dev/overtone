import XCTest

final class ControlServerTests: XCTestCase {
    private func raw(_ text: String) -> Data { Data(text.utf8) }

    func testParsesPostWithBody() {
        let request = ControlServer.parse(raw(
            "POST /speak?x=1 HTTP/1.1\r\nContent-Length: 7\r\n\r\n{\"a\":1}"
        ))
        XCTAssertEqual(request?.method, "POST")
        XCTAssertEqual(request?.path, "/speak")
        XCTAssertEqual(request?.body, raw("{\"a\":1}"))
    }

    func testParsesGetWithoutBody() {
        let request = ControlServer.parse(raw("GET /status HTTP/1.1\r\nHost: x\r\n\r\n"))
        XCTAssertEqual(request?.method, "GET")
        XCTAssertEqual(request?.path, "/status")
        XCTAssertEqual(request?.body, Data())
    }

    func testWaitsForHeaders() {
        XCTAssertNil(ControlServer.parse(raw("POST /speak HTTP/1.1\r\nContent-Len")))
    }

    func testWaitsForTheRestOfTheBody() {
        XCTAssertNil(ControlServer.parse(raw("POST /speak HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"a\"")))
    }

    func testContentLengthIsCaseInsensitive() {
        let request = ControlServer.parse(raw("POST /stop HTTP/1.1\r\ncontent-length: 2\r\n\r\nhi"))
        XCTAssertEqual(request?.body, raw("hi"))
    }

    func testNegativeContentLengthIsRejected() {
        XCTAssertNil(ControlServer.parse(raw("POST /speak HTTP/1.1\r\nContent-Length: -5\r\n\r\n")))
    }

    func testGarbageRequestLine() {
        XCTAssertNil(ControlServer.parse(raw("nonsense\r\n\r\n")))
    }
}
