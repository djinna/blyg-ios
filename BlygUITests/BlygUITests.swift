import XCTest

/// The main loop, offline: add a blyg, see its posts, open one.
/// The app serves the fictional blyg at sample.example from its DEBUG fixtures.
final class BlygUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testAddABlygAndOpenAPost() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useFixtures", "-inMemoryLibrary"]
        app.launch()

        let emptyAdd = app.buttons["emptyAddBlygButton"]
        XCTAssertTrue(emptyAdd.waitForExistence(timeout: 5), "empty state should offer to add a blyg")
        emptyAdd.tap()

        let field = app.textFields["blygAddressField"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.typeText("sample.example")
        app.buttons["confirmAddButton"].tap()

        let rows = app.buttons.matching(identifier: "timelineRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "posts should appear after adding")
        XCTAssertEqual(rows.count, 3, "two fragments and a thread; the withdrawn and unknown-kind items stay hidden")

        rows.firstMatch.tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5), "the post page should show the post")
        XCTAssertTrue(app.webViews.staticTexts["Both are about pace."].waitForExistence(timeout: 5))
    }
}
