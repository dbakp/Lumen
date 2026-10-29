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

    func reveal(_ element: XCUIElement) {
        for _ in 0..<8 where !(element.exists && element.isHittable) { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    func finishOnboarding() {
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

    }

    func testSmoke() throws {
        finishOnboarding()

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
        scrollAndTap("Personal context")
        let personalFocus = app.descendants(matching: .any).matching(identifier: "personalFocus").firstMatch
        XCTAssertTrue(personalFocus.waitForExistence(timeout: 5))
        reveal(personalFocus)
        personalFocus.tap(); personalFocus.typeText("Build a steady sleep routine")
        snap("28-personal-context-editor")
        tap("savePersonalContext")
        snap("29-personal-context-saved")
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
        tap("Document actions"); tap("Edit")
        let dateToggle = app.switches.matching(NSPredicate(format: "identifier BEGINSWITH 'plan-date-'")).element(boundBy: 1)
        reveal(dateToggle); dateToggle.tap()
        snap("32a-plan-editor")
        tap("Save")
        snap("32b-dated-plan")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()

        app.swipeDown(); app.swipeDown()
        scrollAndTap("Your next steps")
        XCTAssertTrue(app.navigationBars["Your next steps"].waitForExistence(timeout: 5))
        snap("32d-agenda")
        app.navigationBars["Your next steps"].buttons.element(boundBy: 0).tap()

        // --- Reopen the original chat after starting a new one ---
        tab("Assistant")
        tap("Conversation history")
        let originalConversation = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation-'")).firstMatch
        XCTAssertTrue(originalConversation.waitForExistence(timeout: 5))
        let originalID = originalConversation.identifier
        snap("32c-conversations")
        tap("New conversation")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 5))
        tap("Conversation history")
        tap(originalID)
        XCTAssertTrue(app.staticTexts["coachMessage"].firstMatch.waitForExistence(timeout: 5))
        tab("Library")

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

        // --- Evidence and appointment summaries ---
        app.swipeDown(); app.swipeDown(); app.swipeDown()
        scrollAndTap("Insights & appointment summaries")
        XCTAssertTrue(app.navigationBars["Insights"].waitForExistence(timeout: 5))
        snap("34-insights")
        scrollAndTap("Create appointment summary")
        XCTAssertTrue(app.navigationBars["Document"].waitForExistence(timeout: 5))
        snap("35-appointment-summary")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Insights"].buttons.element(boundBy: 0).tap()

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
        tap("Settings")
        let backupSettings = app.buttons["backupSettings"].firstMatch
        reveal(backupSettings); backupSettings.tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
        snap("60-backup-home")
        tap("createBackup")
        XCTAssertTrue(app.buttons["reviewBackup"].waitForExistence(timeout: 15))
        tap("reviewBackup")
        let restoreButton = app.buttons["restoreBackup"].firstMatch
        reveal(restoreButton)
        snap("61-backup-preview")
        restoreButton.tap(); tap("Restore records")
        let restored = app.staticTexts["backupRestored"].firstMatch
        for _ in 0..<8 where !(restored.exists && restored.isHittable) { app.swipeDown() }
        XCTAssertTrue(restored.waitForExistence(timeout: 10))
        snap("62-backup-restored")
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap()
        tap("Done")
        app.terminate(); app.launch()
        tab("Library")
        XCTAssertTrue(app.buttons["Questions for my appointment"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-'")).count, 1, "backup restore duplicated the plan")
        tab("Today")
    }
    func chooseImportFixture(_ name: String) throws {
        tap("Import health data")
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 25), "File picker did not open")
        if name == "Lumen-import-cancellation" { snap("69-import-picker") }
        if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
        if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        let fixture = app.staticTexts[name].firstMatch
        if !fixture.waitForExistence(timeout: 5) {
            print(app.debugDescription)
            throw XCTSkip("Run scripts/seed-import-ui-fixtures.py for this simulator before the file-backed scenario")
        }
        let fixtureCell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", name + ",")).firstMatch
        fixtureCell.images.firstMatch.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForNonExistence(timeout: 10), "File selection did not dismiss Files")
    }

    func testImportCancellation() throws {
        finishOnboarding()
        scrollAndTap("Your sources")
        XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 5))
        snap("68-import-home")
        try chooseImportFixture("Lumen-import-cancellation")
        let cancel = app.buttons["cancelHealthImport"].firstMatch
        reveal(cancel)
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        let reviewed = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@", "[1-9].*records reviewed")).firstMatch
        XCTAssertTrue(reviewed.waitForExistence(timeout: 10))
        snap("70-import-progress")
        cancel.tap()
        XCTAssertTrue(app.staticTexts["Import cancelled. No records were added."].waitForExistence(timeout: 5))
        let emptyHistory = app.staticTexts["Nothing imported yet"]
        reveal(emptyHistory)
        snap("71-import-cancelled")
        // Starting another file selection remains possible after cancellation.
        let importButton = app.buttons["Import health data"]
        for _ in 0..<6 where !(importButton.exists && importButton.isHittable) { app.swipeDown() }
        tap("Import health data")
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 25))
        tap("Cancel")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["Import health data"].exists)
        try chooseImportFixture("Lumen-import-small")
        let commit = app.buttons["Import 1 day"]
        reveal(commit); snap("72-import-preview")
        commit.tap()
        XCTAssertTrue(app.staticTexts["Health history imported"].waitForExistence(timeout: 5))
        let receipt = app.staticTexts["Lumen-import-small.csv"]
        reveal(receipt); snap("73-import-history")
        app.terminate(); app.launchArguments = []; app.launch()
        scrollAndTap("Your sources")
        reveal(app.staticTexts["Lumen-import-small.csv"])
        XCTAssertFalse(app.buttons["cancelHealthImport"].exists)
        snap("74-import-persisted")
    }

    func testAppleHealthZIP() throws {
        finishOnboarding()
        scrollAndTap("Your sources")
        try chooseImportFixture("Lumen-health-invalid.zip")
        XCTAssertTrue(app.alerts["Couldn't import health data"].waitForExistence(timeout: 10))
        snap("80-zip-invalid")
        tap("OK")
        try chooseImportFixture("Lumen-health-export.zip")
        let commit = app.buttons["Import 1 day"]
        reveal(commit)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Synthetic ZIP Watch")).firstMatch.exists)
        XCTAssertTrue(app.staticTexts["zipImportScope"].isHittable)
        snap("81-zip-preview")
        let discard = app.buttons["Discard preview"]
        reveal(discard); discard.tap()
        let empty = app.staticTexts["Nothing imported yet"]
        reveal(empty)
        XCTAssertFalse(app.staticTexts["Lumen-health-export.zip"].exists)
        // Discarding the preview never adds history; retry and explicitly confirm.
        let importButton = app.buttons["Import health data"]
        for _ in 0..<6 where !(importButton.exists && importButton.isHittable) { app.swipeDown() }
        try chooseImportFixture("Lumen-health-export.zip")
        reveal(commit); commit.tap()
        XCTAssertTrue(app.staticTexts["Health history imported"].waitForExistence(timeout: 5))
        reveal(app.staticTexts["Lumen-health-export.zip"])
        snap("82-zip-imported")
        app.terminate(); app.launchArguments = []; app.launch()
        scrollAndTap("Your sources")
        reveal(app.staticTexts["Lumen-health-export.zip"])
        snap("83-zip-persisted")
        app.navigationBars["Connections"].buttons.element(boundBy: 0).tap()
        tap("Settings")
        let licenses = app.buttons["Open-source licenses"].firstMatch
        reveal(licenses); licenses.tap()
        let license = app.staticTexts["zipLicenseText"]
        XCTAssertTrue(license.waitForExistence(timeout: 5))
        XCTAssertTrue(license.label.contains("Permission is hereby granted"))
        snap("84-open-source-license")
    }

    func testWorkoutAndVitalsImport() throws {
        finishOnboarding()
        scrollAndTap("Your sources")
        try chooseImportFixture("Lumen-workouts-vitals.zip")
        let heading = app.staticTexts["1 workout · 0 already recorded"]
        reveal(heading); snap("90-workout-preview")
        let commit = app.buttons["Import 1 day"]
        reveal(commit); commit.tap()
        XCTAssertTrue(app.staticTexts["Health history imported"].waitForExistence(timeout: 5))
        let importButton = app.buttons["Import health data"]
        for _ in 0..<8 where !(importButton.exists && importButton.isHittable) { app.swipeDown() }
        try chooseImportFixture("Lumen-workouts-vitals.zip")
        reveal(app.staticTexts["1 workout · 1 already recorded"])
        reveal(commit); commit.tap()
        app.navigationBars["Connections"].buttons.element(boundBy: 0).tap()
        for _ in 0..<4 { app.swipeDown() }
        scrollAndTap("Activity")
        scrollAndTap("Run")
        XCTAssertTrue(app.staticTexts["Energy not provided"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Health export · Synthetic workout Watch"].exists)
        snap("91-imported-workout-detail")
        app.terminate(); app.launchArguments = []; app.launch()
        for _ in 0..<4 { app.swipeDown() }
        scrollAndTap("Activity")
        scrollAndTap("Run")
        XCTAssertTrue(app.staticTexts["Lumen-workouts-vitals.zip"].waitForExistence(timeout: 5))
        snap("92-workout-persisted")
        app.navigationBars["Workout"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Activity"].buttons.element(boundBy: 0).tap()
        for _ in 0..<4 { app.swipeDown() }
        scrollAndTap("Explore your trends")
        scrollAndTap("Oxygen saturation")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Mean of recorded oxygen-saturation")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["latestEvidenceValue"].label.contains("98"))
        XCTAssertTrue(app.staticTexts["latestEvidenceDate"].exists)
        snap("93-oxygen-evidence")
        scrollAndTap("Recorded days")
        snap("94-recorded-evidence-days")
    }

    func testConversationalLogging() throws {
        finishOnboarding()
        tab("Assistant")
        let input = app.textFields["coachInput"].firstMatch
        let field = input.exists ? input : app.textViews["coachInput"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("I drank 250 ml of water. I walked for 20 minutes. I have a headache 5/10. Energy 2/5, mood 4/5, stress 3/5.")
        tap("coachSend")
        let review = app.buttons["Review health entries"].firstMatch
        for _ in 0..<5 where !(review.exists && review.isHittable) { app.swipeDown() }
        XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        XCTAssertTrue(app.navigationBars["Review health entries"].waitForExistence(timeout: 5))
        snap("100-chat-log-review")
        tap("Close")
        // Cancelling review must not save any proposed observations.
        tab("Journal")
        XCTAssertFalse(app.staticTexts["Ongoing symptoms"].exists)
        tab("Assistant")
        for _ in 0..<5 where !(review.exists && review.isHittable) { app.swipeDown() }
        review.tap()
        scrollAndTap("Water")
        XCTAssertTrue(app.navigationBars["Review water"].waitForExistence(timeout: 5))
        let amount = app.textFields["draftWaterML"]
        XCTAssertTrue(amount.waitForExistence(timeout: 5))
        reveal(amount)
        amount.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5)).tap(); amount.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 16) + "500")
        XCTAssertEqual(amount.value as? String, "500")
        snap("107-edited-water-value")
        tap("Done")
        app.navigationBars["Review water"].buttons.element(boundBy: 0).tap()
        let bar = app.navigationBars["Review health entries"]
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.buttons["Discard unsaved drafts"].waitForExistence(timeout: 5))
        snap("106-edited-draft-dismissal")
        tap("Keep reviewing")
        tap("Close")
        XCTAssertTrue(app.buttons["Discard unsaved drafts"].waitForExistence(timeout: 5))
        tap("Keep reviewing")
        scrollAndTap("Water")
        let confirm = app.buttons["confirmChatHealthLog"]
        reveal(confirm); snap("101-chat-water-edit"); confirm.tap()
        XCTAssertTrue(app.staticTexts["Water · 500 ml"].waitForExistence(timeout: 5))
        scrollAndTap("Workout")
        reveal(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["Walk"].waitForExistence(timeout: 5))
        scrollAndTap("Headache")
        let location = app.textFields["Body location"]
        XCTAssertTrue(location.waitForExistence(timeout: 5)); location.tap(); location.typeText("Head")
        tap("Done")
        reveal(confirm); confirm.tap()
        scrollAndTap("Check-in")
        reveal(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["Saved from this message"].waitForExistence(timeout: 5))
        snap("102-chat-entries-saved")
        tap("Close")
        app.terminate(); app.launchArguments = []; app.launch()
        tab("Assistant")
        for _ in 0..<5 where !(review.exists && review.isHittable) { app.swipeDown() }
        XCTAssertTrue(review.waitForExistence(timeout: 5)); review.tap()
        XCTAssertTrue(app.staticTexts["Water · 500 ml"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Walk"].exists)
        XCTAssertTrue(app.staticTexts["Headache"].exists)
        XCTAssertTrue(app.staticTexts["Check-in"].exists)
        XCTAssertFalse(app.buttons["confirmChatHealthLog"].exists)
        snap("103-chat-entries-persisted")
        tap("Close"); tab("Journal")
        XCTAssertTrue(app.staticTexts["Ongoing symptoms"].waitForExistence(timeout: 5))
        snap("104-chat-journal")
        tap("Edit")
        reveal(app.staticTexts["Confirmed from Assistant"])
        scrollAndTap("Original message")
        snap("105-chat-log-provenance")
        tap("Save")
        tab("Assistant")
        let nextInput = app.textFields["coachInput"].firstMatch
        let nextField = nextInput.exists ? nextInput : app.textViews["coachInput"].firstMatch
        nextField.tap(); nextField.typeText("Help me understand my symptom log")
        tap("coachSend")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "You logged headache")).firstMatch.waitForExistence(timeout: 15))
        snap("108-assistant-uses-confirmed-log")
    }

}
