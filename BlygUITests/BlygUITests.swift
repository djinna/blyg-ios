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
        let end = app.descendants(matching: .any)["feedEnd"]
        XCTAssertTrue(end.waitForExistence(timeout: 5), "the feed has an end")
        XCTAssertTrue(end.label.contains("You're up to date") && end.label.contains("14 days"), "it says how far back it goes: \(end.label)")

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

    /// The main feed is a 14-day window. When nothing is that recent it says so, posting is still at hand,
    /// and the blyg's own page still lists every saved post. (`-feedNow` moves the app's "now" for the window.)
    @MainActor
    func testAQuietFeedSaysSoAndTheBlygsOwnPageStillHasEveryPost() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useFixtures", "-inMemoryLibrary", "-seedBlyg", "sample.example", "-connectToken", "fixture-token",
                               "-feedNow", "2026-12-25T00:00:00Z"]
        app.launch()

        let end = app.descendants(matching: .any)["feedEnd"]
        XCTAssertTrue(end.waitForExistence(timeout: 10), "the feed shows, with its end line")
        XCTAssertTrue(end.label.contains("No posts in the last 14 days"), "an empty window says so: \(end.label)")
        XCTAssertEqual(app.buttons.matching(identifier: "timelineRow").count, 0)
        // The blyg is connected a moment after its posts arrive, so wait for it.
        XCTAssertTrue(app.buttons["composeButton"].waitForExistence(timeout: 10), "posting doesn't depend on recent posts")

        app.buttons["blygsButton"].tap()
        let row = app.buttons["blygRow"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("3 posts"), "the count is of every saved post: \(row.label)")
        row.tap()
        let all = app.buttons["allPostsRow"]
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        all.tap()
        let posts = app.buttons.matching(identifier: "blygPostRow")
        XCTAssertTrue(posts.firstMatch.waitForExistence(timeout: 5), "the blyg's own page lists its posts")
        XCTAssertEqual(posts.count, 3)
    }

    /// The refresh as the app opens is the one that tries again a blyg a Studio follows that couldn't be reached
    /// before. Here the seeded blyg's Studio follows the second fixture blyg, which is waiting as if it had failed once.
    @MainActor
    func testOpeningTheAppTriesAgainABlygItsStudioFollows() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-useFixtures", "-inMemoryLibrary", "-seedBlyg", "sample.example", "-connectToken", "fixture-token",
                               "-seedPendingFollow", "https://elsewhere.example/blyg/"]
        app.launch()
        let following = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Following 2 blygs")).firstMatch
        XCTAssertTrue(following.waitForExistence(timeout: 15), "the launch refresh should have followed the waiting blyg")
    }

    /// Jenna, build 3: one tap switched the look, then further taps did nothing.
    @MainActor
    func testAppearanceSwitchesBackAndForth() throws {
        let app = XCUIApplication()
        // No "-appearance" launch argument: it would override every change the app saves.
        app.launchArguments = ["-useFixtures", "-inMemoryLibrary", "-seedBlyg", "sample.example", "-openSettings"]
        app.launch()
        let studio = app.buttons["appearance-studio"]
        let system = app.buttons["appearance-system"]
        XCTAssertTrue(studio.waitForExistence(timeout: 10))
        if !studio.isSelected { studio.tap() }
        XCTAssertTrue(studio.waitForSelected(), "start from Studio")
        for round in 1...3 {
            system.tap()
            XCTAssertTrue(system.waitForSelected(), "round \(round): System should be selected")
            XCTAssertFalse(studio.isSelected)
            studio.tap()
            XCTAssertTrue(studio.waitForSelected(), "round \(round): Studio should be selected")
            XCTAssertFalse(system.isSelected)
        }
    }
}

extension XCUIElement {
    func waitForSelected(timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}
