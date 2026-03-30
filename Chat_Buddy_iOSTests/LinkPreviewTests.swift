import XCTest
@testable import Chat_Buddy_iOS

final class LinkPreviewTests: XCTestCase {

    // MARK: - URL Extraction

    func testExtractHttpUrl() {
        let url = LinkPreviewView.extractURL(from: "Check out https://example.com for more info")
        XCTAssertEqual(url?.absoluteString, "https://example.com")
    }

    func testExtractHttpsUrl() {
        let url = LinkPreviewView.extractURL(from: "Visit https://www.apple.com/iphone")
        XCTAssertEqual(url?.host, "www.apple.com")
    }

    func testExtractNoUrl() {
        let url = LinkPreviewView.extractURL(from: "This text has no URL in it.")
        XCTAssertNil(url)
    }

    func testExtractUrlWithPath() {
        let url = LinkPreviewView.extractURL(from: "See http://docs.swift.org/swift-book/reference")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.host?.contains("docs.swift.org") ?? false)
    }

    func testExtractFirstUrlOnly() {
        let url = LinkPreviewView.extractURL(from: "Two links: https://first.com and https://second.com")
        XCTAssertEqual(url?.host, "first.com")
    }

    func testExtractUrlWithQueryParams() {
        let url = LinkPreviewView.extractURL(from: "Search: https://google.com/search?q=swift")
        XCTAssertNotNil(url)
        XCTAssertTrue(url?.host?.contains("google.com") ?? false)
    }
}
