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
        if !(q.exists && q.isHittable) { snap("unreachable-" + prefix) }
        XCTAssertTrue(q.exists && q.isHittable, "\(prefix) not reachable", file: file, line: line)
        q.tap()
    }

    func reveal(_ element: XCUIElement) {
        for _ in 0..<12 {
            // Return at the successful observation; rechecking after the loop races
            // the keyboard's own scroll of the next password field.
            if element.exists && element.isHittable { return }
            if element.exists && element.frame.midY < app.frame.midY { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        if element.exists && element.isHittable { return }
        snap("unreachable-element"); print(app.debugDescription)
        XCTFail("Element could not be brought into view")
    }

    func replaceAmount(_ field: XCUIElement, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        reveal(field); field.tap()
        field.typeKey("a", modifierFlags: .command)
        field.typeText(text)
        XCTAssertEqual(field.value as? String, text, "Replace the complete amount before saving", file: file, line: line)
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

    private let backupPassword = "Synthetic backup passphrase 42"

    func enterBackupPassword(_ identifier: String, value: String) {
        let field = app.secureTextFields[identifier].firstMatch
        reveal(field); field.tap(); field.typeKey("a", modifierFlags: .command); field.typeText(value)
    }

    func createEncryptedBackup(timeout: TimeInterval = 30) {
        tap("createBackup")
        XCTAssertTrue(app.navigationBars["Backup password"].waitForExistence(timeout: 5))
        enterBackupPassword("newBackupPassword", value: backupPassword)
        enterBackupPassword("confirmBackupPassword", value: backupPassword)
        app.secureTextFields["confirmBackupPassword"].typeText("\n")
        let create = app.buttons["confirmCreateBackup"].firstMatch; reveal(create); create.tap()
        XCTAssertTrue(app.buttons["cancelBackupOperation"].waitForNonExistence(timeout: timeout))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.buttons["reviewBackup"].waitForExistence(timeout: 10))
    }

    func unlockBackup(value: String? = nil) {
        XCTAssertTrue(app.buttons["cancelBackupOperation"].waitForNonExistence(timeout: 90), "Finish copying the selected file before entering its password")
        let field = app.secureTextFields["unlockBackupPassword"].firstMatch
        reveal(field); XCTAssertTrue(field.waitForExistence(timeout: 15))
        enterBackupPassword("unlockBackupPassword", value: value ?? backupPassword)
        field.typeText("\n")
        let button = app.buttons["unlockBackup"].firstMatch; reveal(button); button.tap()
    }

    func openBackupSettings() {
        tab("Today"); tap("Settings")
        let button = app.buttons["backupSettings"].firstMatch
        for _ in 0..<28 {
            if button.exists && button.isHittable { break }
            app.swipeUp(velocity: .fast)
        }
        XCTAssertTrue(button.exists && button.isHittable); button.tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
    }

    func testEncryptedBackup() throws {
        finishOnboarding(); openBackupSettings(); snap("110-backup-home")
        tap("createBackup"); XCTAssertTrue(app.secureTextFields["newBackupPassword"].waitForExistence(timeout: 5)); snap("111-backup-password-empty")
        XCTAssertFalse(app.buttons["confirmCreateBackup"].isEnabled)
        enterBackupPassword("newBackupPassword", value: "short")
        enterBackupPassword("confirmBackupPassword", value: "short")
        XCTAssertFalse(app.buttons["confirmCreateBackup"].isEnabled)
        enterBackupPassword("newBackupPassword", value: backupPassword)
        enterBackupPassword("confirmBackupPassword", value: "Different password")
        app.secureTextFields["confirmBackupPassword"].typeText("\n")
        XCTAssertTrue(app.staticTexts["The passwords don’t match."].exists)
        snap("112-backup-password-mismatch")
        XCTAssertFalse(app.buttons["confirmCreateBackup"].isEnabled)
        enterBackupPassword("confirmBackupPassword", value: backupPassword)
        app.secureTextFields["confirmBackupPassword"].typeText("\n")
        snap("113-backup-password-ready")
        let create = app.buttons["confirmCreateBackup"].firstMatch; reveal(create); create.tap()
        XCTAssertTrue(app.buttons["reviewBackup"].waitForExistence(timeout: 30))
        snap("114-backup-created")
        tap("reviewBackup")
        let field = app.secureTextFields["unlockBackupPassword"].firstMatch
        reveal(field); XCTAssertTrue(field.waitForExistence(timeout: 15)); snap("115-backup-locked")
        unlockBackup(value: "Wrong synthetic password")
        XCTAssertTrue(app.alerts["Couldn’t unlock backup"].waitForExistence(timeout: 20))
        snap("116-backup-wrong-password"); tap("OK")
        XCTAssertFalse(app.buttons["restoreBackup"].exists)
        unlockBackup()
        let restore = app.buttons["restoreBackup"].firstMatch
        reveal(restore); XCTAssertTrue(restore.waitForExistence(timeout: 30)); snap("117-backup-preview")
        app.swipeUp(velocity: .slow); snap("117a-backup-restore-options")
        restore.tap(); XCTAssertTrue(app.alerts["Restore missing records?"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Keep reviewing"].exists); snap("118-backup-restore-confirmation")
        tap("Keep reviewing"); restore.tap(); tap("Restore records")
        XCTAssertTrue(app.staticTexts["backupRestored"].waitForExistence(timeout: 30))
        for _ in 0..<5 { app.swipeDown() }
        snap("119-backup-restored")
        XCTAssertTrue(app.buttons["shareBackup"].exists)
    }

    func chooseBackupFixture(_ name: String) throws {
        let choose = app.buttons["chooseBackup"].firstMatch; reveal(choose); choose.tap()
        XCTAssertTrue(app.buttons["Cancel"].firstMatch.waitForExistence(timeout: 25))
        if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
        if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", name)).firstMatch
        // Files retains its scroll position between selections. Move toward the item,
        // including back up when a previously selected file left this one above the viewport.
        for _ in 0..<16 {
            if cell.exists && cell.isHittable { break }
            if cell.exists && cell.frame.midY < app.frame.midY { app.swipeDown(velocity: .fast) }
            else { app.swipeUp(velocity: .fast) }
        }
        XCTAssertTrue(cell.waitForExistence(timeout: 5) && cell.isHittable, "Seed synthetic backup fixtures before this scenario")
        let picker = app.buttons.matching(NSPredicate(format: "label == %@ AND identifier != %@", "Cancel", "cancelBackupOperation")).firstMatch
        cell.images.firstMatch.tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 15), "File selection must dismiss the picker; the app's processing Cancel is a separate control")
    }

    @discardableResult
    func backupPreview() -> XCUIElement {
        XCTAssertTrue(app.buttons["cancelBackupOperation"].waitForNonExistence(timeout: 90))
        XCTAssertFalse(app.alerts.firstMatch.exists, app.alerts.firstMatch.debugDescription)
        let kind = app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch
        reveal(kind)
        return kind
    }

    func confirmBackupRestore() {
        let restore = app.buttons["restoreBackup"].firstMatch; reveal(restore); restore.tap(); tap("Restore records")
        XCTAssertTrue(app.staticTexts["backupRestored"].waitForExistence(timeout: 30))
    }

    func testBackupFilesAndCancellation() throws {
        finishOnboarding(); openBackupSettings()
        try chooseBackupFixture("Lumen-backup-legacy")
        let legacy = backupPreview(); XCTAssertEqual(legacy.label, "Older, unencrypted backup"); snap("130-backup-legacy-preview")
        confirmBackupRestore()
        try chooseBackupFixture("Lumen-backup-encrypted"); unlockBackup()
        let encrypted = backupPreview(); XCTAssertEqual(encrypted.label, "Encrypted backup"); snap("131-backup-encrypted-preview")
        confirmBackupRestore()
        try chooseBackupFixture("Lumen-backup-damaged"); unlockBackup()
        XCTAssertTrue(app.alerts["Couldn’t unlock backup"].waitForExistence(timeout: 20))
        snap("132-backup-integrity-error"); tap("OK")
        XCTAssertFalse(app.buttons["restoreBackup"].exists)
        try chooseBackupFixture("Lumen-backup-large"); unlockBackup()
        let cancel = app.buttons["cancelBackupOperation"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); snap("133-backup-reading-progress"); cancel.tap()
        let cancelled = app.staticTexts["backupStatus"].firstMatch
        XCTAssertTrue(cancelled.waitForExistence(timeout: 30)); XCTAssertTrue(cancelled.label.contains("Cancelled"))
        snap("134-backup-cancelled")
        XCTAssertFalse(app.buttons["restoreBackup"].exists)
        // Retry the same private selected file, then install its valid photos and relaunch.
        unlockBackup()
        XCTAssertTrue(app.buttons["cancelBackupOperation"].waitForNonExistence(timeout: 90))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        _ = backupPreview()
        let waterCount = app.descendants(matching: .any).matching(identifier: "backupWaterCount").firstMatch
        XCTAssertEqual(waterCount.value as? String, Int(100_000).formatted(), "The large fixture's full water history must be decoded before preview")
        snap("135-backup-large-preview")
        confirmBackupRestore(); snap("136-backup-large-restored")
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap(); tap("Done")
        app.terminate(); app.launchArguments = []; app.launch(); tab("Library")
        XCTAssertTrue(app.buttons["Synthetic transfer plan"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-'")).count, 1)
        snap("137-backup-persisted-library")
        // Create and reopen a new archive from the restored large library on iPhone too.
        openBackupSettings(); createEncryptedBackup(timeout: 90); snap("138-backup-large-created")
        tap("reviewBackup"); unlockBackup()
        XCTAssertTrue(app.buttons["cancelBackupOperation"].waitForNonExistence(timeout: 90))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let roundTrip = backupPreview(); XCTAssertEqual(roundTrip.label, "Encrypted backup")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "backupWaterCount").firstMatch.value as? String, Int(100_001).formatted(), "The new archive must include both the retained local water entry and all restored entries")
        snap("139-backup-large-roundtrip")
    }

    func testBackupShareAndReopen() throws {
        finishOnboarding(); openBackupSettings(); createEncryptedBackup()
        tap("shareBackup")
        let saveToFiles = app.cells.matching(NSPredicate(format: "label == %@", "Save to Files")).firstMatch
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 10)); snap("150-backup-share-sheet"); saveToFiles.tap()
        let save = app.buttons["Save"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10))
        if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        let name = app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "Lumen-backup-")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), app.debugDescription)
        let savedName = "Lumen-shared-check-" + UUID().uuidString.prefix(8)
        name.tap(); name.typeKey("a", modifierFlags: .command); name.typeText(savedName + ".lumenbackup")
        snap("151-backup-save-to-files"); save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))
        // Leaving removes the private share copy; the external saved file must still reopen.
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap(); tap("Done")
        openBackupSettings(); try chooseBackupFixture(savedName); unlockBackup()
        let preview = backupPreview(); XCTAssertEqual(preview.label, "Encrypted backup"); snap("152-backup-saved-file-preview")
    }

    func testBackupPresentation() throws {
        finishOnboarding(); openBackupSettings()
        app.terminate(); app.launchArguments = ["-lumen.appearance", "dark"]; app.launch(); openBackupSettings()
        snap("140-backup-dark-home"); tap("createBackup"); XCTAssertTrue(app.secureTextFields["newBackupPassword"].waitForExistence(timeout: 5)); snap("141-backup-dark-password"); tap("Cancel")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openBackupSettings()
        XCTAssertGreaterThan(app.staticTexts["Keep your\nhistory close."].frame.height, 100, "The accessibility-size override must actually be active")
        snap("142-backup-large-type-home")
        let create = app.buttons["createBackup"].firstMatch; reveal(create); create.tap()
        XCTAssertTrue(app.navigationBars["Backup password"].waitForExistence(timeout: 5)); snap("143a-backup-large-type-password-heading")
        reveal(app.secureTextFields["newBackupPassword"].firstMatch); snap("143-backup-large-type-password")
        enterBackupPassword("newBackupPassword", value: backupPassword)
        enterBackupPassword("confirmBackupPassword", value: backupPassword)
        app.secureTextFields["confirmBackupPassword"].typeText("\n")
        let confirm = app.buttons["confirmCreateBackup"].firstMatch; reveal(confirm); snap("144-backup-large-type-create"); confirm.tap()
        let review = app.buttons["reviewBackup"].firstMatch; reveal(review)
        XCTAssertTrue(review.waitForExistence(timeout: 30)); review.tap(); unlockBackup()
        let restore = app.buttons["restoreBackup"].firstMatch; reveal(restore); snap("145-backup-large-type-restore")
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
        createEncryptedBackup()
        tap("reviewBackup"); unlockBackup()
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
        XCTAssertFalse(app.buttons["editWorkoutEntry"].exists)
        XCTAssertFalse(app.buttons["deleteWorkoutEntry"].exists)
        snap("91-imported-workout-detail")
        let managed = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Managed by its source.")).firstMatch
        reveal(managed); app.swipeUp(velocity: .slow); snap("95-managed-workout-source")
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
        replaceAmount(amount, with: "500")
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
        // Correct confirmed local entries without changing their original statements.
        tab("Journal")
        let waterEntry = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'water-'")).firstMatch
        reveal(waterEntry); waterEntry.tap()
        XCTAssertEqual(app.staticTexts["waterEntryValue"].label, "500 ml")
        tap("editWaterEntry")
        let correctedWater = app.textFields["correctWaterML"]
        reveal(correctedWater)
        replaceAmount(correctedWater, with: "750")
        if app.buttons["dismissCorrectionKeyboard"].isHittable { tap("dismissCorrectionKeyboard") }
        snap("130-water-correction")
        tap("cancelCorrectedEntry"); tap("Keep editing")
        tap("saveCorrectedEntry")
        XCTAssertTrue(app.staticTexts["waterEntryValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["waterEntryValue"].label, "750 ml")
        scrollAndTap("Original message")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "I drank 250 ml")).firstMatch.exists)
        snap("131-water-corrected-provenance")
        reveal(app.buttons["deleteWaterEntry"]); snap("138-water-delete-action"); tap("Done")
        let workoutEntry = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'workout-'")).firstMatch
        reveal(workoutEntry); workoutEntry.tap()
        tap("editWorkoutEntry")
        let minutes = app.textFields["correctWorkoutMinutes"]
        replaceAmount(minutes, with: "35")
        if app.buttons["dismissCorrectionKeyboard"].isHittable { tap("dismissCorrectionKeyboard") }
        snap("132-workout-correction"); tap("saveCorrectedEntry")
        XCTAssertTrue(app.staticTexts["35 min"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Energy not provided"].exists)
        snap("133-workout-corrected")
        // Relaunch must keep both corrected records, not append duplicates.
        app.terminate(); app.launchArguments = []; app.launch(); tab("Journal")
        reveal(waterEntry); waterEntry.tap(); tap("editWaterEntry")
        tap("cancelCorrectedEntry"); tap("Done")
        app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); tab("Journal")
        reveal(waterEntry); waterEntry.tap(); tap("editWaterEntry")
        XCTAssertEqual(app.textFields["correctWaterML"].value as? String, "750")
        reveal(app.textFields["correctWaterML"]); snap("136-large-water-editor"); tap("cancelCorrectedEntry"); tap("Done")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "dark"]; app.launch(); tab("Journal")
        reveal(workoutEntry); workoutEntry.tap()
        XCTAssertTrue(app.staticTexts["35 min"].waitForExistence(timeout: 5))
        tap("editWorkoutEntry"); reveal(app.textFields["correctWorkoutEnergy"]); snap("139-dark-workout-editor"); tap("cancelCorrectedEntry")
        scrollAndTap("Delete entry"); snap("137-workout-delete-confirmation"); tap("Keep entry")
        XCTAssertTrue(app.navigationBars["Workout"].exists)
        scrollAndTap("Delete entry"); app.alerts.buttons["Delete entry"].tap()
        XCTAssertTrue(workoutEntry.waitForNonExistence(timeout: 5))
        reveal(waterEntry); waterEntry.tap()
        XCTAssertEqual(app.staticTexts["waterEntryValue"].label, "750 ml")
        scrollAndTap("Delete entry"); snap("134-water-delete-confirmation")
        app.alerts.buttons["Delete entry"].tap()
        XCTAssertTrue(waterEntry.waitForNonExistence(timeout: 5))
        tab("Today"); scrollAndTap("Review today's readings")
        let waterReading = app.buttons["current-reading-water"]
        reveal(waterReading); waterReading.tap()
        XCTAssertEqual(app.staticTexts["currentReadingValue"].label, "Not recorded")
        snap("135-water-deleted-reading")
    }

    func testCurrentReadingConfidence() throws {
        finishOnboarding()
        scrollAndTap("Activity")
        for name in ["move", "exercise", "stand"] {
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "activity-stat-" + name).firstMatch.label.contains("No reading"))
        }
        snap("120-missing-activity")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<4 { app.swipeDown(velocity: .fast) }
        scrollAndTap("Review today's readings"); snap("121-current-readings")
        tap("current-reading-steps")
        XCTAssertEqual(app.staticTexts["currentReadingValue"].label, "Not recorded")
        snap("122-missing-steps")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.navigationBars.buttons.element(boundBy: 0).tap()
        scrollAndTap("Your sources")
        try chooseImportFixture("Lumen-confidence-zero")
        let commit = app.buttons["Import 1 day"]; reveal(commit); commit.tap()
        XCTAssertTrue(app.staticTexts["Health history imported"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<6 { app.swipeDown(velocity: .fast) }
        scrollAndTap("Review today's readings"); tap("current-reading-steps")
        XCTAssertEqual(app.staticTexts["currentReadingValue"].label, "0 steps")
        XCTAssertTrue(app.staticTexts["Synthetic zero fixture"].exists)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Sample times are unavailable")).firstMatch.exists)
        snap("123-recorded-zero-evidence")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "dark"]; app.launch()
        scrollAndTap("Review today's readings"); tap("current-reading-steps")
        XCTAssertEqual(app.staticTexts["currentReadingValue"].label, "0 steps")
        snap("124-dark-zero-evidence")
    }

    func testCurrentReadingsLargeText() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); finishOnboarding()
        XCTAssertTrue(app.buttons["currentReadingsShortcut"].waitForExistence(timeout: 10))
        snap("127-large-today")
        tap("currentReadingsShortcut")
        let steps = app.buttons["current-reading-steps"]; reveal(steps); steps.tap()
        let amount = app.staticTexts["currentReadingValue"]
        XCTAssertEqual(amount.label, "Not recorded")
        XCTAssertGreaterThan(amount.frame.height, 60, "The accessibility-size override must actually be active")
        snap("125-large-reading-details")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        snap("126-large-current-readings")
    }

    func testRetainedFoodAndSleepConfidence() throws {
        finishOnboarding()
        scrollAndTap("Food")
        XCTAssertEqual(app.staticTexts["foodEnergyValue"].label, "Not recorded")
        XCTAssertEqual(app.staticTexts["food-protein"].label, "Not recorded")
        XCTAssertFalse(app.staticTexts["Left today"].exists)
        snap("200-food-missing")
        let water = app.staticTexts["foodWaterValue"]; reveal(water)
        XCTAssertEqual(water.label, "Not recorded")
        XCTAssertFalse(app.buttons["undoQuickWater"].isEnabled)
        tap("+ 250 ml")
        XCTAssertEqual(water.label, "250 ml")
        tap("undoQuickWater")
        XCTAssertEqual(water.label, "Not recorded")
        XCTAssertTrue(app.staticTexts["waterUndoStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["waterUndoStatus"].label.contains("No Apple Health removal was attempted"))
        snap("201-water-after-quick-undo")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<5 { app.swipeDown(velocity: .fast) }
        scrollAndTap("Sleep")
        XCTAssertTrue(app.staticTexts["Sleep not recorded today"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sleepDebtEstimate").firstMatch.label.contains("Not available"))
        snap("202-sleep-missing")
        tap("Add a night")
        tap("Save night")
        XCTAssertTrue(app.staticTexts["currentSleepDuration"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Time in bed"].exists)
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sleepDebtEstimate").firstMatch.label.contains("Not available"))
        snap("203-one-manual-night")
        scrollAndTap("Sleep history")
        XCTAssertTrue(app.navigationBars["Sleep history"].waitForExistence(timeout: 5))
        let night = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sleep-entry-'")).firstMatch
        XCTAssertTrue(night.waitForExistence(timeout: 5)); XCTAssertTrue(night.isHittable)
        snap("203a-sleep-history"); night.tap()
        snap("203b-manual-sleep-editor")
        tap("Delete night")
        XCTAssertTrue(app.staticTexts["No detailed entries yet"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Sleep not recorded today"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<5 { app.swipeDown(velocity: .fast) }
        scrollAndTap("Your sources")
        try chooseImportFixture("Lumen-retained-zero")
        let commit = app.buttons["Import 1 day"]; reveal(commit); commit.tap()
        XCTAssertTrue(app.staticTexts["Health history imported"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<5 { app.swipeDown(velocity: .fast) }
        scrollAndTap("Food")
        XCTAssertEqual(app.staticTexts["foodEnergyValue"].label, "0 kcal")
        XCTAssertEqual(app.staticTexts["food-protein"].label, "0 g")
        XCTAssertEqual(app.staticTexts["food-fat"].label, "Not recorded")
        snap("204-partial-food-zero")
        reveal(water); XCTAssertEqual(water.label, "0 ml")
        XCTAssertFalse(app.buttons["undoQuickWater"].isEnabled)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<5 { app.swipeDown(velocity: .fast) }
        scrollAndTap("Sleep")
        XCTAssertEqual(app.staticTexts["currentSleepDuration"].label, "0h 0m")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sleepDebtEstimate").firstMatch.label.contains("Not available"))
        snap("205-imported-zero-sleep")
        // Optional capture for a widget installed in this dedicated simulator's Home Screen.
        // The functional Food/Sleep assertions do not depend on manual widget setup.
        XCUIDevice.shared.press(.home)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let widget = springboard.descendants(matching: .any).matching(NSPredicate(format: "label == 'Lumen' AND value == 'Widget'")).firstMatch
        if widget.waitForExistence(timeout: 4) { snap("210-widget-recorded-zero") }
        app.activate()
        app.terminate(); app.launchArguments = ["-lumen.appearance", "dark"]; app.launch()
        scrollAndTap("Food"); snap("206-dark-food-zero")
        app.terminate(); app.launchArguments = ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        let food = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Food")).firstMatch
        for _ in 0..<14 where !(food.exists && food.isHittable) { app.swipeUp(velocity: .fast) }
        XCTAssertTrue(food.isHittable); food.tap()
        XCTAssertEqual(app.staticTexts["foodEnergyValue"].label, "0 kcal")
        snap("207-large-food-zero")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<10 { app.swipeDown(velocity: .fast) }
        scrollAndTap("Sleep")
        XCTAssertEqual(app.staticTexts["currentSleepDuration"].label, "0h 0m")
        snap("208-large-sleep-zero")
    }

}
