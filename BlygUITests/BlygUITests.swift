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
        let page = app.webViews.firstMatch
        XCTAssertTrue(page.waitForExistence(timeout: 10), "the post page should open")
        // Web content reaches the accessibility tree a moment after the view appears, slowly on a busy simulator.
        let text = page.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "about pace")).firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 20), "the thread's own words should show:\n\(app.debugDescription)")

        // Connect the blyg with a token, then write and publish a post.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.buttons["composeButton"].exists, "no composer before connecting")
        app.buttons["blygsButton"].tap()
        app.buttons["blygRow"].firstMatch.tap()
        let tokenField = app.secureTextFields["tokenField"]
        XCTAssertTrue(tokenField.waitForExistence(timeout: 5))
        tokenField.tap()
        tokenField.typeText("fixture-token")
        app.buttons["connectButton"].tap()
        XCTAssertTrue(app.buttons["disconnectButton"].waitForExistence(timeout: 10), "a good token should connect")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let compose = app.buttons["composeButton"]
        XCTAssertTrue(compose.waitForExistence(timeout: 5), "connected: the composer is offered")
        compose.tap()
        let editor = app.textViews["composerText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.typeText("Hello from the UI test")
        app.buttons["postButton"].tap()
        XCTAssertTrue(compose.waitForExistence(timeout: 10), "the composer closes after posting")
        XCTAssertFalse(app.buttons["postButton"].exists)
    }
}
