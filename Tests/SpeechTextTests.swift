import XCTest

final class SpeechTextTests: XCTestCase {
    func testCollapsesWhitespace() {
        XCTAssertEqual(SpeechText.normalized("  Привет,   мир!  "), "Привет, мир!")
    }

    func testKeepsHardWrappedSentenceInOneSentence() {
        let wrapped = """
        Сегодня утром я вышел на улицу
        и увидел, что весь город укрыт снегом.
        """
        XCTAssertEqual(
            SpeechText.normalized(wrapped),
            "Сегодня утром я вышел на улицу и увидел, что весь город укрыт снегом."
        )
    }

    func testEndsHeadingsAndListItemsAsSentences() {
        let markdown = """
        # Release notes

        - fixes a crash
        - adds a hotkey
        """
        XCTAssertEqual(
            SpeechText.normalized(markdown),
            "Release notes. fixes a crash. adds a hotkey."
        )
    }

    func testNumberedListMarkersAreDropped() {
        XCTAssertEqual(SpeechText.normalized("1. first\n2) second"), "first. second.")
    }

    func testStripsEmphasisButKeepsArithmetic() {
        XCTAssertEqual(SpeechText.normalized("It is **very** fast."), "It is very fast.")
        XCTAssertEqual(SpeechText.normalized("Use `speak` now."), "Use speak now.")
        XCTAssertEqual(SpeechText.normalized("2 * 3 = 6."), "2 * 3 = 6.")
        XCTAssertEqual(SpeechText.normalized("snake_case_name stays."), "snake_case_name stays.")
    }

    func testLinksReadAsTheirText() {
        XCTAssertEqual(SpeechText.normalized("See [the docs](https://x.dev/a/b)."), "See the docs.")
    }

    func testBareUrlReadsAsHost() {
        XCTAssertEqual(
            SpeechText.normalized("Open https://www.example.com/very/long?q=1 now."),
            "Open example.com now."
        )
    }

    func testQuestionAndQuotedSentenceEndsAreRespected() {
        XCTAssertEqual(SpeechText.normalized("Готово?\nДа."), "Готово? Да.")
        XCTAssertEqual(SpeechText.normalized("«Готово.»\nДальше"), "«Готово.» Дальше.")
    }

    func testEmptyInputStaysEmpty() {
        XCTAssertEqual(SpeechText.normalized("   \n\n\t"), "")
    }

    func testDropsZeroWidthCharacters() {
        XCTAssertEqual(SpeechText.normalized("да\u{200B}\u{FEFF} нет"), "да нет.")
    }
}
