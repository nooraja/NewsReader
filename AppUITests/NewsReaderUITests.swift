import XCTest

@MainActor
final class NewsReaderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testBrowsePagedSourcesAndArticlesThenSearchAndOpenDetail() {
        let app = launchDemo()
        app.staticTexts["General"].tap()

        let sourceList = app.tables["news-list"]
        XCTAssertTrue(sourceList.staticTexts["General Desk 01"].waitForExistence(timeout: 5))
        scrollTo("General Desk 25", in: sourceList)

        let sourceSearch = app.searchFields["Search sources"]
        scrollToTopIfNeeded(for: sourceSearch, in: sourceList)
        sourceSearch.tap()
        sourceSearch.typeText("General Desk 30")
        let source = sourceList.staticTexts["General Desk 30"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        XCTAssertFalse(sourceList.staticTexts["General Desk 01"].exists)
        source.tap()

        let articleList = app.tables["news-list"]
        XCTAssertTrue(articleList.staticTexts["Daily Briefing 01"].waitForExistence(timeout: 5))
        scrollTo("Daily Briefing 25", in: articleList)

        let articleSearch = app.searchFields["Search articles"]
        scrollToTopIfNeeded(for: articleSearch, in: articleList)
        articleSearch.tap()
        articleSearch.typeText("Field Notes")
        let article = articleList.staticTexts["Field Notes 33"]
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        XCTAssertFalse(articleList.staticTexts["Daily Briefing 01"].exists)
        article.tap()

        XCTAssertTrue(app.navigationBars["Field Notes 33"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.webViews.staticTexts["This article is provided by NewsReader's demo data."].waitForExistence(timeout: 10))
    }

    func testSourceSearchShowsEmptyStateAndCanRecover() {
        let app = launchDemo()
        app.staticTexts["General"].tap()

        let sourceList = app.tables["news-list"]
        XCTAssertTrue(sourceList.staticTexts["General Desk 01"].waitForExistence(timeout: 5))

        let search = app.searchFields["Search sources"]
        search.tap()
        search.typeText("zzzz")
        XCTAssertTrue(app.staticTexts["No results"].waitForExistence(timeout: 5))

        search.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 4))
        XCTAssertTrue(sourceList.staticTexts["General Desk 01"].waitForExistence(timeout: 5))
    }

    private func launchDemo() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-demo"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Categories"].waitForExistence(timeout: 5))
        return app
    }

    private func scrollTo(_ title: String, in list: XCUIElement) {
        let row = list.staticTexts[title]
        for _ in 0..<12 where !row.isHittable {
            list.swipeUp()
        }
        XCTAssertTrue(row.isHittable, "Could not scroll to \(title)")
    }

    private func scrollToTopIfNeeded(for search: XCUIElement, in list: XCUIElement) {
        for _ in 0..<12 where !search.isHittable {
            list.swipeDown()
        }
        XCTAssertTrue(search.isHittable)
    }

}
