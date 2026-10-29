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

    func tab(_ name: String) { app.buttons[name].firstMatch.tap() }

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
        snap("09-after-onboarding")
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 10))
        snap("10-today")
        app.swipeUp(); snap("10b-today-scrolled"); app.swipeDown()

        // --- Log sheet → water ---
        tap("Log")
        XCTAssertTrue(app.navigationBars["Log"].waitForExistence(timeout: 5))
        snap("11-log-sheet")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Water'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Added 250 ml of water"].waitForExistence(timeout: 4), "water toast missing")

        // --- Symptom → persistent journal → contextual Today ---
        tap("Log")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Symptom'")).firstMatch.tap()
        XCTAssertTrue(app.textFields["symptomName"].waitForExistence(timeout: 5))
        snap("20-symptom-form")
        tap("saveSymptom")
        tab("Journal")
        XCTAssertTrue(app.staticTexts["Ongoing symptoms"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Headache"].firstMatch.exists)
        snap("21-journal")
        tab("Today")
        XCTAssertTrue(app.staticTexts["Keep today’s plan flexible."].waitForExistence(timeout: 5))
        snap("22-contextual-today")

        // --- Subjective energy adds context without replacing symptom priority ---
        tap("Check in")
        XCTAssertTrue(app.navigationBars["Daily check-in"].waitForExistence(timeout: 5))
        tap("Save")
        tab("Journal")
        snap("23-check-in-timeline")

        // --- Assistant → automatically saved editable plan ---
        tab("Assistant")
        let input = app.textFields["coachInput"].firstMatch
        let multiInput = app.textViews["coachInput"].firstMatch
        let field = input.exists ? input : multiInput
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Make a flexible plan for today")
        tap("coachSend")
        XCTAssertTrue(app.staticTexts["coachMessage"].firstMatch.waitForExistence(timeout: 30))
        snap("30-assistant-plan")
        tab("Library")
        let plan = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-'")).firstMatch
        snap("31-library-before-assertion")
        XCTAssertTrue(plan.waitForExistence(timeout: 5), "generated plan was not saved")
        snap("31-library")
        plan.tap()
        XCTAssertTrue(app.navigationBars["Document"].waitForExistence(timeout: 5))
        scrollAndTap("Incomplete:")
        snap("32-plan-detail")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()

        // --- Records remain opt-in; new notes are editable ---
        tap("Add document")
        tap("Write a note")
        XCTAssertTrue(app.navigationBars["Edit document"].waitForExistence(timeout: 5))
        let title = app.textFields["Document title"]
        title.tap(); title.typeText("Questions for my appointment")
        let editor = app.textViews.firstMatch
        editor.tap(); editor.typeText("Discuss recurring headaches and their timing.")
        tap("Save")
        XCTAssertTrue(app.buttons["Questions for my appointment"].waitForExistence(timeout: 5))
        snap("33-library-note")

        // --- Resolve symptom and verify source destinations remain reachable ---
        tab("Journal")
        tap("Mark resolved")
        XCTAssertTrue(app.staticTexts["Ongoing symptoms"].waitForNonExistence(timeout: 5))
        tab("Today")
        scrollAndTap("Sleep")
        XCTAssertTrue(app.navigationBars["Sleep"].waitForExistence(timeout: 5))
        snap("40-sleep-light")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollAndTap("Activity")
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        snap("41-activity-light")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollAndTap("Food")
        snap("42-food-light")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        // --- Relaunch keeps local logs and documents ---
        app.terminate()
        app.launchArguments = []
        app.launch()
        snap("09-after-onboarding")
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 10))
        tab("Library")
        XCTAssertTrue(app.buttons["Questions for my appointment"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-'")).firstMatch.exists)
        snap("50-persisted-library")
        tab("Today")
    }
}
