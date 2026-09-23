import XCTest

// MARK: - Lumen smoke test: fresh onboarding → every tab → logging → coach.
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
        let b = app.buttons[label].firstMatch
        XCTAssertTrue(b.waitForExistence(timeout: timeout), "\(label) missing", file: file, line: line)
        b.tap()
    }

    func tab(_ name: String) { app.tabBars.buttons[name].tap() }

    /// Scroll until a button whose label starts with `prefix` is on screen, then tap it.
    func scrollAndTap(_ prefix: String, file: StaticString = #filePath, line: UInt = #line) {
        let q = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        for _ in 0..<6 where !(q.exists && q.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(q.exists && q.isHittable, "\(prefix) not reachable", file: file, line: line)
        q.tap()
    }

    func testSmoke() throws {
        // --- Onboarding ---
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        snap("01-welcome")
        tap("Get started")
        let name = app.textFields.firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap(); name.typeText("Alex")
        snap("02-name")
        tap("Continue")
        XCTAssertTrue(app.staticTexts["Connect Apple Health"].waitForExistence(timeout: 5))
        snap("03-health")
        tap("Not now")
        snap("04-body"); tap("Continue")
        snap("05-goal"); tap("Continue")
        snap("06-sleep"); tap("Continue")
        snap("07-reminders"); tap("Maybe later")
        XCTAssertTrue(app.buttons["Start using Lumen"].waitForExistence(timeout: 10))
        snap("08-plan")
        tap("Start using Lumen")

        // --- Today ---
        XCTAssertTrue(app.tabBars.buttons["Today"].waitForExistence(timeout: 10))
        snap("10-today")
        app.swipeUp(); snap("10b-today-scrolled"); app.swipeDown()

        // --- Log sheet → water ---
        tap("Log")
        XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 5))
        snap("11-log-sheet")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Water'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Added 250 ml of water"].waitForExistence(timeout: 4), "water toast missing")

        // --- Metric detail ---
        XCTAssertTrue(app.navigationBars["Log"].waitForNonExistence(timeout: 4))
        scrollAndTap("Steps")
        XCTAssertTrue(app.navigationBars["Steps"].waitForExistence(timeout: 5))
        snap("12-metric-detail")
        app.navigationBars["Steps"].buttons.element(boundBy: 0).tap()

        // --- Settings ---
        tap("Settings")
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        snap("13-settings")
        app.swipeUp(); snap("13b-settings-scrolled")
        tap("Done")

        // --- Sleep: empty → add a night → populated ---
        tab("Sleep")
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 5))
        snap("20-sleep-empty")
        tap("Add a night")
        tap("Save night")
        XCTAssertTrue(app.staticTexts["Sleep debt"].waitForExistence(timeout: 5), "sleep tab did not populate")
        snap("21-sleep")
        app.swipeUp(); snap("21b-sleep-scrolled")

        // --- Activity + log workout ---
        tab("Activity")
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        snap("30-activity")
        tap("Log a workout")
        XCTAssertTrue(app.navigationBars["Log a workout"].waitForExistence(timeout: 5))
        snap("31-log-workout")
        tap("Save walk")
        XCTAssertTrue(app.staticTexts["Walk"].waitForExistence(timeout: 5), "logged workout not listed")
        snap("32-activity-with-workout")

        // --- Food: camera opens; log a food via search ---
        tab("Food")
        XCTAssertTrue(app.navigationBars["Food"].waitForExistence(timeout: 5))
        snap("40-food")
        tap("Search foods")
        XCTAssertTrue(app.navigationBars["Add food"].waitForExistence(timeout: 5))
        snap("41-food-search")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Banana'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Banana"].waitForExistence(timeout: 5), "meal not listed")
        snap("42-food-with-meal")

        // --- Coach ---
        tab("Coach")
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        snap("50-coach")
        let field = app.textFields["coachInput"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "coach input missing")
        field.tap(); field.typeText("Should I train hard?")
        tap("coachSend")
        let reply = app.descendants(matching: .any).matching(identifier: "coachMessage").firstMatch
        XCTAssertTrue(reply.waitForExistence(timeout: 45), "coach did not reply")
        snap("51-coach-reply")

        // --- Today after: readiness live ---
        tab("Today")
        XCTAssertFalse(app.staticTexts["Getting to know you"].exists, "readiness still calibrating after logging sleep")
        snap("60-today-after")
    }
}
