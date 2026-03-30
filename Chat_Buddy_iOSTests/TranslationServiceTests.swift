import XCTest
@testable import Chat_Buddy_iOS

final class TranslationServiceTests: XCTestCase {

    // MARK: - Domain Detection

    func testDetectTechnicalDomain() {
        let text = "This function uses async await to fetch data from the API endpoint."
        let domain = TranslationService.detectDomain(text)
        XCTAssertEqual(domain, .technical)
    }

    func testDetectLiteraryDomain() {
        let text = "The poem uses metaphor and simile throughout each verse and stanza."
        let domain = TranslationService.detectDomain(text)
        XCTAssertEqual(domain, .literary)
    }

    func testDetectGeneralDomain() {
        let text = "I went to the store and bought some groceries today."
        let domain = TranslationService.detectDomain(text)
        XCTAssertEqual(domain, .general)
    }

    func testDetectTechnicalThreshold() {
        // Exactly 3 tech patterns needed
        let text = "import the class and export it"
        let domain = TranslationService.detectDomain(text)
        XCTAssertEqual(domain, .technical)
    }

    func testDetectBelowThreshold() {
        // Only 2 tech patterns — should be general
        let text = "import the library"
        let domain = TranslationService.detectDomain(text)
        XCTAssertEqual(domain, .general)
    }

    // MARK: - Glossary Data

    func testTechGlossaryNotEmpty() {
        XCTAssertGreaterThan(TranslationService.techGlossary.count, 30)
    }

    func testLiteraryGlossaryNotEmpty() {
        XCTAssertGreaterThan(TranslationService.literaryGlossary.count, 5)
    }

    func testTechGlossaryContainsKnownEntry() {
        let hasComponent = TranslationService.techGlossary.contains { $0.source == "component" }
        XCTAssertTrue(hasComponent)
    }

    // MARK: - Response Parsing

    func testParseResponseWithSteps() {
        let response = """
        step1: This is the direct translation.
        step2: This is the refined version.
        """
        let parsed = TranslationService.parseResponse(response, domain: .general)
        XCTAssertTrue(parsed.step1.contains("direct translation"))
        XCTAssertTrue(parsed.step2.contains("refined version"))
    }

    func testParseResponseNoSteps() {
        let response = "Just a plain translation without markers."
        let parsed = TranslationService.parseResponse(response, domain: .general)
        // When no markers, entire text becomes both step1 and step2
        XCTAssertFalse(parsed.step1.isEmpty)
        XCTAssertFalse(parsed.step2.isEmpty)
        XCTAssertEqual(parsed.step1, parsed.step2)
    }

    func testParseResponseOnlyStep1() {
        let response = "step1: Only direct, no refined."
        let parsed = TranslationService.parseResponse(response, domain: .technical)
        XCTAssertFalse(parsed.step1.isEmpty)
        XCTAssertEqual(parsed.step2, parsed.step1) // step2 falls back to step1
        XCTAssertEqual(parsed.domain, .technical)
    }

    // MARK: - Translation Prompt Building

    func testBuildTranslationPromptEnToZh() {
        let prompt = TranslationService.buildTranslationPrompt(
            text: "This function uses async await to call the API class import",
            from: "en",
            to: "zh"
        )
        XCTAssertTrue(prompt.contains("step1"))
        XCTAssertTrue(prompt.contains("step2"))
    }

    func testBuildTranslationPromptZhToEn() {
        let prompt = TranslationService.buildTranslationPrompt(
            text: "这是一个关于诗歌和隐喻的散文作品",
            from: "zh",
            to: "en"
        )
        XCTAssertFalse(prompt.isEmpty)
    }
}
