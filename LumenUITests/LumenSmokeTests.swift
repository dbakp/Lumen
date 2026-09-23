import XCTest

// MARK: - Lumen smoke test: onboarding → all 5 tabs → Snap sheet → Coach chat.
// Screenshots are attached to the result bundle for visual review.

final class LumenSmokeTests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func snap(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let att = XCTAttachment(screenshot: shot)
        att.name = name
        att.lifetime = .keepAlways
        add(att)
    }

    func testSmoke() throws {
        // --- Onboarding (skipped automatically if already completed) ---
        if app.buttons["Continue"].waitForExistence(timeout: 5) {
            for _ in 0..<4 {
                let cont = app.buttons["Continue"]
                XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue missing")
                cont.tap()
            }
            snap("03-onboarding-wake")
            let build = app.buttons["Build my plan"]
            XCTAssertTrue(build.waitForExistence(timeout: 10), "Build my plan missing")
            build.tap()
        }

        // --- Today tab ---
        let today = app.tabBars.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 10), "Today tab missing")
        snap("10-today")

        // --- Activity tab + manual workout sheet ---
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        snap("11-activity")

        // --- Snap (center capture) ---
        app.tabBars.buttons["Snap"].tap()
        let capture = app.navigationBars["Log meal"]
        XCTAssertTrue(capture.waitForExistence(timeout: 5), "Snap sheet did not open")
        snap("12-snap")
        app.buttons["Close"].tap()

        // --- Sleep hub ---
        app.tabBars.buttons["Sleep"].tap()
        XCTAssertTrue(app.navigationBars["Sleep & More"].waitForExistence(timeout: 5))
        snap("13-sleep-hub")

        // --- Nutrition via hub ---
        app.staticTexts["Nutrition"].tap()
        XCTAssertTrue(app.navigationBars["Nutrition"].waitForExistence(timeout: 5))
        snap("14-nutrition")
        app.navigationBars["Nutrition"].buttons.element(boundBy: 0).tap() // back

        // --- Profile & integrations (renders Health/Strava/Coach-AI controls) ---
        app.staticTexts["Profile & integrations"].tap()
        XCTAssertTrue(app.navigationBars["Profile"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Coach AI"].waitForExistence(timeout: 5))
        snap("14b-profile")
        app.navigationBars["Profile"].buttons.element(boundBy: 0).tap() // back

        // --- Coach: send a message, expect a reply bubble ---
        app.tabBars.buttons["Coach"].tap()
        XCTAssertTrue(app.navigationBars["Coach"].waitForExistence(timeout: 5))
        let field = app.textFields["Ask your coach…"]
        XCTAssertTrue(field.waitForExistence(timeout: 5), "coach input missing")
        let before = app.staticTexts.count
        field.tap()
        field.typeText("Should I train hard?")
        app.buttons["Send"].tap()
        // Wait for the coach answer bubble (local brain ~1s, LLM longer).
        var appeared = false
        for _ in 0..<50 {
            if app.staticTexts.count > before { appeared = true; break }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertTrue(appeared, "no coach reply appeared")
        snap("15-coach")
    }
}
