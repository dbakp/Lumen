import XCTest

// MARK: - Lumen smoke test: fresh onboarding → every tab → sheets → coach chat.
// Screenshots are attached to the result bundle for visual review.

final class LumenSmokeTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-resetForUITests"]
        app.launch()
    }

    func snap(_ name: String) {
        let att = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    func tap(_ label: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) {
        let b = app.buttons[label]
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "\(label) missing", file: file, line: line)
        b.tap()
    }

    func testSmoke() throws {
        // --- Onboarding ---
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        snap("01-welcome")
        tap("Get started")

        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Alex")
        snap("02-name")
        tap("Continue")

        XCTAssertTrue(app.staticTexts["Connect Apple Health"].waitForExistence(timeout: 5))
        snap("03-health")
        tap("Not now")

        snap("04-body")
        tap("Continue")
        snap("05-goal")
        tap("Continue")
        snap("06-sleep")
        tap("Continue")
        snap("07-reminders")
        tap("Maybe later")

        XCTAssertTrue(app.buttons["Start using Lumen"].waitForExistence(timeout: 10))
        snap("08-plan")
        tap("Start using Lumen")

        // --- Today ---
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        snap("10-today")
        app.swipeUp()
        snap("10b-today-scrolled")
        app.swipeDown()

        // --- Settings ---
        tap("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snap("11-settings")
        app.swipeUp()
        snap("11b-settings-scrolled")
        tap("Done")

        // --- Trends ---
        app.staticTexts["Trends"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Trends"].waitForExistence(timeout: 5))
        snap("12-trends")
        app.navigationBars["Trends"].buttons.element(boundBy: 0).tap()

        // --- Activity + log workout ---
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        snap("13-activity")
        tap("Log workout")
        XCTAssertTrue(app.navigationBars["Log workout"].waitForExistence(timeout: 5))
        snap("13b-log-workout")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Log '")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["TODAY"].waitForExistence(timeout: 5), "logged workout not listed")
        snap("13c-activity-with-workout")

        // --- Snap ---
        app.tabBars.buttons["Snap"].tap()
        XCTAssertTrue(app.navigationBars["Log meal"].waitForExistence(timeout: 5), "Snap sheet did not open")
        snap("14-snap")
        tap("Close")

        // --- Sleep (empty state → log a night → populated) ---
        app.tabBars.buttons["Sleep"].tap()
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 5))
        snap("15-sleep-empty")
        tap("Log a night")
        tap("Save night")
        XCTAssertTrue(app.staticTexts["SLEEP DEBT"].waitForExistence(timeout: 5), "sleep tab did not populate")
        snap("15b-sleep-populated")
        app.swipeUp()
        snap("15c-sleep-scrolled")

        // --- Coach ---
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        let field = app.textFields["Ask your coach…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "coach input missing")
        let before = app.staticTexts.count
        field.tap()
        field.typeText("Should I train hard?")
        tap("Send")
        var appeared = false
        for _ in 0..<50 {
            if app.staticTexts.count > before { appeared = true; break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(appeared, "no coach reply appeared")
        snap("16-coach")

        // --- Back to Today: readiness should now be live (a night was logged) ---
        app.tabBars.buttons["Today"].tap()
        XCTAssertFalse(app.staticTexts["CALIBRATING"].exists, "readiness still calibrating after logging sleep")
        snap("17-today-after")
    }
}
