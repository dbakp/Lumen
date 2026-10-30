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
        for _ in 0..<16 {
            let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
            let composerVisible = input.exists && input.isHittable && element.identifier != "coachInput"
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY + 16 : 130
            let bottom = composerVisible ? input.frame.minY - 20 : app.frame.maxY - 90
            if element.exists && element.isHittable && (!composerVisible || (element.frame.midY > top && element.frame.midY < bottom)) { return }
            let down = element.exists && element.frame.midY < (top + bottom) / 2
            if composerVisible {
                // A partly visible row can report hittable while its centre is
                // behind the fixed composer. Scroll in the real content gutter.
                let lower = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: bottom - 8))
                let upper = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: top + 8))
                if down { upper.press(forDuration: 0.05, thenDragTo: lower) }
                else { lower.press(forDuration: 0.05, thenDragTo: upper) }
            } else if down { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        snap("unreachable-element"); print(app.debugDescription)
        XCTFail("Element could not be brought into the visible content area")
    }

    func selectAmount(_ field: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        reveal(field); field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), file: file, line: line)
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let button = app.buttons["Select All"].firstMatch
        let menu = app.menuItems["Select All"].firstMatch
        if !(button.exists || menu.exists) { field.press(forDuration: 1.0) }
        let selectAll = button.exists ? button : menu
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5), "Select the complete prior amount", file: file, line: line)
        selectAll.tap()
    }
    func replaceAmount(_ field: XCUIElement, with text: String, file: StaticString = #filePath, line: UInt = #line) {
        selectAmount(field, file: file, line: line)
        if text.allSatisfy({ $0.isASCII && $0.isNumber }) {
            for digit in text { app.keyboards.keys[String(digit)].firstMatch.tap() }
        } else { field.typeText(text) }
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

    func prepareVoice(appearance: String = "light", failingRestart: Bool = false) {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-voice-fixture", "-lumen.appearance", appearance] + (failingRestart ? ["-voice-fixture-fail-restart"] : []); app.launch()
        finishOnboarding(); tab("Assistant")
    }
    func revealVoice(_ element: XCUIElement, towardsTop: Bool = false) {
        for _ in 0..<18 {
            let top = app.navigationBars.firstMatch.frame.maxY + 16
            let controls = app.descendants(matching: .any).matching(identifier: "voiceControls").firstMatch
            let bottom = controls.exists ? controls.frame.minY - 16 : app.frame.maxY - 110
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            let upper = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: top + 8))
            let lower = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 8, dy: bottom - 8))
            if (element.exists && element.frame.midY < top) || (!element.exists && towardsTop) { upper.press(forDuration: 0.05, thenDragTo: lower) }
            else { lower.press(forDuration: 0.05, thenDragTo: upper) }
        }
        XCTFail("Voice control not reachable: " + element.identifier)
    }
    func startAndReviewVoice() {
        tap("coachVoice")
        let start = app.buttons["startVoice"].firstMatch
        XCTAssertTrue(app.navigationBars["Voice draft"].waitForExistence(timeout: 5))
        revealVoice(start); start.tap()
        let live = app.staticTexts["voiceLiveText"].firstMatch
        let hypothesis = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in live.exists && live.label.contains("300") }, object: live)
        XCTAssertEqual(XCTWaiter.wait(for: [hypothesis], timeout: 5), .completed)
        snap("302-voice-live-fixture"); tap("stopVoice")
        XCTAssertTrue(app.buttons["useVoiceText"].waitForExistence(timeout: 8))
    }
    func replaceVoiceText(_ editor: XCUIElement, with text: String) {
        // These short fixture drafts fit in the editor. Tapping its empty lower
        // area puts the caret at the end without a simulator hardware shortcut.
        let previous = editor.value as? String ?? ""
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.9)).tap()
        editor.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: previous.count + 2))
        XCTAssertEqual(editor.value as? String ?? "", "", "Clear the entire prior fixture text before replacing it")
        editor.typeText(text); XCTAssertEqual(editor.value as? String, text)
    }
    func testVoiceDraftReview() throws {
        prepareVoice()
        let composer = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        composer.tap(); composer.typeText("Keep this typed question."); snap("300-voice-composer")
        startAndReviewVoice()
        let use = app.buttons["useVoiceText"].firstMatch
        XCTAssertFalse(use.isEnabled); snap("303-voice-review-unchecked")
        let edit = app.buttons["editVoiceText"].firstMatch; revealVoice(edit); edit.tap()
        let editor = app.textViews["voiceDraftText"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); snap("323-voice-editor-before-hardware-keys")
        replaceVoiceText(editor, with: "I drank 375 ml of water.\nMy shoulder pain is 2 out of 10."); snap("316-voice-text-editor"); tap("saveVoiceEdit")
        let checked = app.switches["voiceChecked"].firstMatch; revealVoice(checked); nativeSwitch("voiceChecked", enabled: true)
        XCTAssertTrue(use.isEnabled)
        revealVoice(edit); edit.tap(); replaceVoiceText(editor, with: "I drank 375 ml of water.\nMy shoulder pain is 2 out of 10. I checked this synthetic text."); tap("saveVoiceEdit")
        XCTAssertFalse(use.isEnabled, "Any later edit requires a fresh review acknowledgement")
        revealVoice(checked); nativeSwitch("voiceChecked", enabled: true); snap("304-voice-reviewed-ready"); use.tap()
        XCTAssertTrue(app.navigationBars["Voice draft"].waitForNonExistence(timeout: 5))
        XCTAssertTrue((composer.value as? String ?? "").contains("Keep this typed question.\nI drank 375"))
        XCTAssertTrue((composer.value as? String ?? "").contains("shoulder pain"))
        XCTAssertFalse(app.staticTexts["userMessage"].exists); XCTAssertFalse(app.staticTexts["coachMessage"].exists); snap("305-voice-unsent-draft")
        tap("coachSend")
        XCTAssertTrue(app.staticTexts["coachMessage"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 1)
        let review = app.buttons["Review health entries"].firstMatch; reveal(review); review.tap()
        XCTAssertTrue(app.navigationBars["Review health entries"].waitForExistence(timeout: 10)); snap("306-voice-health-review")
        let water = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Water'")).firstMatch
        reveal(water); water.tap()
        let amount = app.textFields["draftWaterML"].firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); XCTAssertEqual(amount.value as? String, "375")
        snap("319-voice-water-confirmation")
        let confirm = app.buttons["confirmChatHealthLog"].firstMatch; reveal(confirm); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(app.staticTexts["1 saved · 0 to review"].waitForExistence(timeout: 8)); snap("320-voice-one-entry-saved")
        tap("Close"); app.terminate(); app.launchArguments = ["-lumen.appearance", "light"]; app.launch(); tab("Assistant")
        let savedReview = app.buttons["Review health entries"].firstMatch; reveal(savedReview); savedReview.tap()
        XCTAssertTrue(app.staticTexts["1 saved · 0 to review"].waitForExistence(timeout: 8)); snap("321-voice-saved-after-relaunch")
        tap("Close")
    }
    func testVoiceDraftCancelAndBackground() throws {
        prepareVoice(); startAndReviewVoice()
        let again = app.buttons["recordVoiceAgain"].firstMatch; revealVoice(again); again.tap()
        XCTAssertTrue(app.alerts["Record again?"].waitForExistence(timeout: 5)); snap("307-voice-record-again")
        tap("Keep reviewing"); revealVoice(again); again.tap(); tap("Replace voice draft")
        XCTAssertTrue(app.buttons["stopVoice"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home); app.activate()
        XCTAssertTrue(app.buttons["useVoiceText"].waitForExistence(timeout: 10))
        let notice = app.staticTexts["voiceNotice"].firstMatch; revealVoice(notice); XCTAssertTrue(notice.label.contains("left Lumen")); snap("308-voice-foreground-stop")
        tap("cancelVoice"); XCTAssertTrue(app.alerts["Discard this voice draft?"].waitForExistence(timeout: 5)); snap("309-voice-discard-choice")
        tap("Keep reviewing"); tap("cancelVoice"); tap("Discard draft")
        XCTAssertTrue(app.navigationBars["Voice draft"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["userMessage"].exists)
        tap("coachVoice")
        let start = app.buttons["startVoice"].firstMatch; revealVoice(start); XCTAssertTrue(start.isHittable)
        XCTAssertFalse(app.textViews["voiceDraftText"].exists); snap("310-voice-clean-reopen"); tap("cancelVoice")
    }
    func testVoiceDraftFailedRestart() throws {
        prepareVoice(failingRestart: true); startAndReviewVoice()
        let edit = app.buttons["editVoiceText"].firstMatch; revealVoice(edit); edit.tap()
        let editor = app.textViews["voiceDraftText"].firstMatch; XCTAssertTrue(editor.waitForExistence(timeout: 5))
        replaceVoiceText(editor, with: "Corrected synthetic draft: I drank 375 ml of water."); tap("saveVoiceEdit")
        revealVoice(edit); edit.tap(); editor.tap(); editor.typeText(" Unsaved correction."); tap("cancelVoiceEdit")
        XCTAssertTrue(app.alerts["Discard your text changes?"].waitForExistence(timeout: 5)); snap("317-voice-editor-discard-choice")
        tap("Keep editing"); XCTAssertTrue(editor.exists); tap("cancelVoiceEdit"); tap("Discard changes")
        XCTAssertEqual(app.staticTexts["voiceReviewText"].label, "Corrected synthetic draft: I drank 375 ml of water.")
        let again = app.buttons["recordVoiceAgain"].firstMatch; revealVoice(again); again.tap(); tap("Replace voice draft")
        let notice = app.staticTexts["voiceNotice"].firstMatch; revealVoice(notice)
        XCTAssertTrue(notice.label.contains("couldn't start"))
        XCTAssertEqual(app.staticTexts["voiceReviewText"].label, "Corrected synthetic draft: I drank 375 ml of water."); snap("315-voice-failed-restart-keeps-edit")
        tap("cancelVoice"); tap("Discard draft")
    }
    func testVoiceDraftPresentation() throws {
        prepareVoice(appearance: "dark"); startAndReviewVoice(); snap("311-voice-dark-review")
        app.terminate(); app.launchArguments = ["-voice-fixture", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); tab("Assistant"); snap("312-voice-large-composer")
        startAndReviewVoice()
        let checked = app.switches["voiceChecked"].firstMatch; revealVoice(checked); snap("313-voice-large-acknowledgement")
        nativeSwitch("voiceChecked", enabled: true); XCTAssertTrue(app.buttons["useVoiceText"].isEnabled)
        let again = app.buttons["recordVoiceAgain"].firstMatch; revealVoice(again); snap("322-voice-large-actions")
        let edit = app.buttons["editVoiceText"].firstMatch; revealVoice(edit, towardsTop: true); edit.tap()
        let editor = app.textViews["voiceDraftText"].firstMatch; XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap()
        editor.typeText(String(repeating: "Additional synthetic review text.\n", count: 12) + "End of synthetic editor text.")
        XCTAssertTrue(app.buttons["saveVoiceEdit"].isHittable); snap("324-voice-large-editor-end")
        tap("cancelVoiceEdit"); tap("Discard changes")
        tap("cancelVoice"); tap("Discard draft")
    }
    func testComposerKeyboardReturn() throws {
        finishOnboarding(); tab("Assistant")
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("Synthetic keyboard submission.\n")
        XCTAssertTrue(app.staticTexts["coachMessage"].firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 1)
        XCTAssertEqual(app.staticTexts["userMessage"].firstMatch.label, "Synthetic keyboard submission.")
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (input.value as? String ?? "").isEmpty && !self.app.buttons["coachSend"].isEnabled
        }, object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
        snap("325-composer-keyboard-return")
        input.tap(); input.typeText("My next unsent synthetic question.")
        XCTAssertEqual(input.value as? String, "My next unsent synthetic question.")
        XCTAssertTrue(app.buttons["coachSend"].isEnabled)
        XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 1)
        snap("326-composer-new-unsent-text")
    }
    func testVoiceActualAvailability() throws {
        finishOnboarding(); tab("Assistant"); tap("coachVoice")
        let known = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            self.app.buttons["startVoice"].exists || self.app.buttons["downloadVoiceLanguage"].exists || self.app.staticTexts["voiceUnavailable"].exists
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [known], timeout: 30), .completed)
        XCTAssertFalse(app.staticTexts["voiceFixture"].exists); snap("314-voice-actual-availability")
        tap("cancelVoice"); XCTAssertTrue(app.navigationBars["Voice draft"].waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["userMessage"].exists)
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
        let share = app.buttons["shareBackup"].firstMatch; reveal(share)
        snap("119-backup-restored")
        XCTAssertTrue(share.isHittable)
    }

    func chooseBackupFixture(_ name: String) throws {
        let choose = app.buttons["chooseBackup"].firstMatch; reveal(choose); choose.tap()
        let picker = app.collectionViews["File View"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 25))
        if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
        if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", name)).firstMatch
        for _ in 0..<24 {
            if cell.exists && cell.isHittable && cell.frame.maxY > 220 && cell.frame.minY < 700 { break }
            if cell.exists && cell.frame.maxY < 220 { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(cell.exists && cell.isHittable, "Seed synthetic backup fixtures before this scenario")
        var previous = CGRect.null
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = cell.frame; defer { previous = current }; return current == previous
        }, object: cell)
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 5), .completed)
        let frame = cell.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: max(210, min(720, frame.minY + 50)))).tap()
        if !picker.waitForNonExistence(timeout: 15) { print(app.debugDescription); XCTFail("Selecting a backup must leave Files") }

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

    func openRecordImport() {
        tab("Library"); tap("Add document"); tap("Import a record")
        XCTAssertTrue(app.buttons["chooseRecordFile"].waitForExistence(timeout: 5))
    }
    func chooseRecordFixture(_ name: String) throws {
        let choose = app.buttons["chooseRecordFile"].firstMatch; reveal(choose); choose.tap()
        let picker = app.collectionViews["File View"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 25))
        if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
        if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        let folder = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH '00 Lumen record checks'")).firstMatch
        if folder.waitForExistence(timeout: 2) {
            for _ in 0..<12 where !(folder.isHittable && folder.frame.minY > 170 && folder.frame.minY < 680) { app.swipeDown(velocity: .slow) }
            folder.tap()
        }
        let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", name)).firstMatch
        for _ in 0..<24 {
            if cell.exists && cell.isHittable && cell.frame.maxY > 220 && cell.frame.minY < 700 { break }
            if cell.exists && cell.frame.maxY < 220 { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(cell.exists && cell.isHittable, "Seed synthetic record fixtures before this scenario")
        var previous = CGRect.null
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = cell.frame; defer { previous = current }
            return current == previous
        }, object: cell)
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 5), .completed)
        // Files grid cells can extend behind its floating tab bar. Tap a visible
        // part of the actual cell rather than letting XCTest choose its centre.
        let frame = cell.frame
        let y = max(210, min(720, frame.minY + 50))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: y)).tap()
        if !cell.waitForNonExistence(timeout: 15) { print(app.debugDescription); XCTFail("The selected record must leave Files") }
    }
    func waitForRecordPreview() {
        let ready = app.descendants(matching: .any).matching(identifier: "recordPreviewReady").firstMatch
        XCTAssertTrue(ready.waitForExistence(timeout: 90)); XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func nativeSwitch(_ identifier: String, enabled: Bool) {
        let toggle = app.switches[identifier].firstMatch; reveal(toggle)
        if (toggle.value as? String) != (enabled ? "1" : "0") {
            let control = toggle.switches.firstMatch
            if control.exists { reveal(control); control.tap() } else { toggle.tap() }
        }
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 5), .completed)
    }
    func openReadableRecovery() {
        openBackupSettings()
        let recover = app.buttons["readableRecovery"].firstMatch; reveal(recover); recover.tap()
        XCTAssertTrue(app.navigationBars["Recover export"].waitForExistence(timeout: 5))
    }

    func chooseReadableFixture(_ name: String) throws {
        let choose = app.buttons["chooseReadableExport"].firstMatch; reveal(choose); choose.tap()
        let picker = app.collectionViews["File View"].firstMatch; XCTAssertTrue(picker.waitForExistence(timeout: 25))
        if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
        if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        let folder = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH '00 Lumen readable checks'")).firstMatch
        if folder.waitForExistence(timeout: 2) {
            for _ in 0..<12 where !(folder.isHittable && folder.frame.minY > 170 && folder.frame.minY < 680) { app.swipeDown(velocity: .slow) }
            folder.tap()
        }
        let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", name)).firstMatch
        for _ in 0..<24 {
            if cell.exists && cell.isHittable && cell.frame.maxY > 220 && cell.frame.minY < 700 { break }
            if cell.exists && cell.frame.maxY < 220 { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(cell.exists && cell.isHittable, "Seed synthetic readable fixtures before this scenario")
        var previous = CGRect.null
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let current = cell.frame; defer { previous = current }; return current == previous
        }, object: cell)
        XCTAssertEqual(XCTWaiter.wait(for: [stable], timeout: 5), .completed)
        let frame = cell.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: max(210, min(720, frame.minY + 50)))).tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 15))
    }
    func waitForReadableReview() {
        XCTAssertTrue(app.buttons["cancelReadableOperation"].waitForNonExistence(timeout: 90))
        XCTAssertTrue(app.staticTexts["Lumen checks the file format but can’t confirm who created or edited it."].waitForExistence(timeout: 90), app.debugDescription)
        XCTAssertFalse(app.alerts.firstMatch.exists)
    }
    func confirmReadableRecovery() {
        let add = app.buttons["recoverReadableData"].firstMatch; reveal(add); add.tap()
        XCTAssertTrue(app.alerts["Add selected data?"].waitForExistence(timeout: 5)); snap("267-readable-confirmation")
        tap("Keep reviewing"); add.tap(); tap("Add data")
        let status = app.staticTexts["readableStatus"].firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 60)); reveal(status)
        XCTAssertTrue(status.label.contains("Selected data is saved")); snap("268-readable-complete")
    }
    func testReadableExportShareAndReopen() throws {
        finishOnboarding(); tab("Today"); tap("Settings")
        let export = app.buttons["readableExportSettings"].firstMatch; reveal(export); export.tap(); snap("276-readable-export-home")
        tap("createReadableExport")
        XCTAssertTrue(app.buttons["cancelReadableOperation"].waitForNonExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["readableExportReady"].waitForExistence(timeout: 20)); snap("277-readable-export-ready")
        tap("shareReadableExport")
        let saveToFiles = app.cells.matching(NSPredicate(format: "label == %@", "Save to Files")).firstMatch
        XCTAssertTrue(saveToFiles.waitForExistence(timeout: 10)); snap("278-readable-share"); saveToFiles.tap()
        let save = app.buttons["Save"].firstMatch; XCTAssertTrue(save.waitForExistence(timeout: 10))
        if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        let name = app.textFields.matching(NSPredicate(format: "value CONTAINS %@", "Lumen-export-")).firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        let savedName = "Lumen-readable-shared-" + UUID().uuidString.prefix(8)
        name.tap(); name.typeKey("a", modifierFlags: .command); name.typeText(savedName); snap("279-readable-save-to-files"); save.tap()
        XCTAssertTrue(save.waitForNonExistence(timeout: 15))
        app.navigationBars["Readable export"].buttons.element(boundBy: 0).tap(); tap("Done")
        openReadableRecovery()
        // The external saved file is at the Files root, rather than the fixture folder.
        let choose = app.buttons["chooseReadableExport"].firstMatch; reveal(choose); choose.tap()
        let picker = app.collectionViews["File View"].firstMatch; XCTAssertTrue(picker.waitForExistence(timeout: 25))
        if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
        if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", savedName)).firstMatch
        for _ in 0..<30 {
            if cell.exists && cell.isHittable && cell.frame.midY > 220 && cell.frame.midY < 700 { break }
            if cell.exists && cell.frame.midY < 220 { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(cell.exists && cell.isHittable); let frame = cell.frame
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: max(210, min(720, frame.minY + 50)))).tap()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 15)); waitForReadableReview(); snap("280-readable-shared-file-review")
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let emptyWater = app.switches["recoverReadable-water"].firstMatch; reveal(emptyWater)
        XCTAssertFalse(emptyWater.isEnabled)
        let add = app.buttons["recoverReadableData"].firstMatch; reveal(add); XCTAssertFalse(add.isEnabled)
    }

    func testReadableMessageMetadata() throws {
        finishOnboarding(); openReadableRecovery()
        try chooseReadableFixture("Lumen-readable-full"); waitForReadableReview()
        let review = app.buttons["reviewReadable-conversations"].firstMatch; reveal(review); review.tap(); tap("readableEntry-0")
        tap("readableMessage-1")
        let metadata = app.staticTexts["readableEntryMetadata"].firstMatch
        XCTAssertTrue(metadata.waitForExistence(timeout: 5)); XCTAssertEqual(metadata.label, "Synthetic fixture"); snap("289-readable-assistant-provider")
        app.navigationBars["Saved entry"].buttons.element(boundBy: 0).tap(); tap("Next messages"); tap("readableMessage-51")
        XCTAssertTrue(metadata.waitForExistence(timeout: 5)); XCTAssertTrue(metadata.label.contains(" · "))
        XCTAssertFalse(metadata.label.contains("Provider")); XCTAssertTrue(app.staticTexts["readableEntryText"].label.contains("Synthetic archived message 51")); snap("287-readable-saved-message")
    }
    func testReadableLargeReview() throws {
        finishOnboarding(); openReadableRecovery()
        try chooseReadableFixture("Lumen-readable-large"); waitForReadableReview()
        let water = app.switches["recoverReadable-water"].firstMatch; reveal(water)
        XCTAssertTrue(water.label.contains(Int(100_000).formatted())); snap("281-readable-large-count")
        let review = app.buttons["reviewReadable-water"].firstMatch; reveal(review); review.tap()
        XCTAssertTrue(app.buttons["readableEntry-0"].waitForExistence(timeout: 5))
        let next = app.buttons["Next entries"].firstMatch; reveal(next); next.tap()
        XCTAssertTrue(app.buttons["readableEntry-100"].waitForExistence(timeout: 5)); snap("282-readable-paged-records")
        tap("readableEntry-100")
        XCTAssertTrue(app.staticTexts["readableEntryText"].waitForExistence(timeout: 5)); snap("283-readable-large-record")
        app.navigationBars["Saved entry"].buttons.element(boundBy: 0).tap(); tap("Done")
        app.navigationBars["Recover export"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap(); tap("Done")
        app.terminate(); app.launchArguments = []; app.launch(); tab("Library")
        XCTAssertFalse(app.buttons["Synthetic recovered plan"].exists)
    }
    func testReadableRecovery() throws {
        finishOnboarding(); openReadableRecovery(); snap("260-readable-start")
        try chooseReadableFixture("Lumen-readable-full"); waitForReadableReview(); snap("261-readable-review")
        let review = app.buttons["reviewReadable-documents"].firstMatch; reveal(review); review.tap()
        XCTAssertTrue(app.navigationBars["Library documents"].waitForExistence(timeout: 5)); snap("262-readable-record-list")
        tap("readableEntry-0")
        let text = app.staticTexts["readableEntryText"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5)); XCTAssertTrue(text.label.contains("flexible synthetic plan")); snap("263-readable-entry")
        tap("Next"); XCTAssertTrue(text.label.hasPrefix("Synthetic saved paragraph")); snap("285-readable-text-pagination")
        app.navigationBars["Saved entry"].buttons.element(boundBy: 0).tap(); tap("Done")
        let conversation = app.buttons["reviewReadable-conversations"].firstMatch; reveal(conversation); conversation.tap(); tap("readableEntry-0")
        tap("Next messages"); XCTAssertTrue(app.buttons["readableMessage-50"].waitForExistence(timeout: 5)); snap("286-readable-message-pagination")
        tap("readableMessage-51"); XCTAssertTrue(app.staticTexts["readableEntryText"].label.contains("Synthetic archived message 51")); snap("287-readable-saved-message")
        app.navigationBars["Saved entry"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Saved conversation"].buttons.element(boundBy: 0).tap(); tap("Done")
        let daily = app.buttons["reviewReadable-imported-days"].firstMatch; reveal(daily); daily.tap(); tap("readableEntry-0")
        XCTAssertTrue(app.staticTexts["readableEntryText"].label.contains("original daily time zone was not saved")); snap("284-readable-daily-timestamp")
        app.navigationBars["Saved entry"].buttons.element(boundBy: 0).tap(); tap("Done")
        for key in ["profile", "goals", "habits", "personal-context"] {
            let toggle = app.switches["recoverReadable-" + key].firstMatch; reveal(toggle); XCTAssertEqual(toggle.value as? String, "0")
            if key == "profile" {
                let settings = app.buttons["reviewReadable-profile"].firstMatch; reveal(settings); settings.tap(); tap("readableEntry-0")
                XCTAssertTrue(app.staticTexts["readableEntryText"].label.contains("Synthetic recovered profile")); snap("288-readable-profile-settings")
                app.navigationBars["Saved entry"].buttons.element(boundBy: 0).tap(); tap("Done")
            }
        }
        snap("264-readable-optional-settings")
        let missing = app.descendants(matching: .any).matching(identifier: "readableMissingPhotos").firstMatch; reveal(missing); snap("265-readable-omissions")
        XCTAssertTrue(missing.label.contains("1") || (missing.value as? String ?? "").contains("1"))
        XCTAssertTrue(app.staticTexts["Temporary daily totals"].exists); XCTAssertTrue(app.staticTexts["Reminder settings"].exists)
        confirmReadableRecovery()
        tap("finishReadableRecovery")
        let recover = app.buttons["readableRecovery"].firstMatch; reveal(recover); recover.tap()
        try chooseReadableFixture("Lumen-readable-full"); waitForReadableReview(); confirmReadableRecovery()
        app.terminate(); app.launchArguments = []; app.launch(); tab("Library"); tap("Synthetic recovered plan")
        let sharing = app.switches["Use in assistant"].firstMatch; reveal(sharing); XCTAssertEqual(sharing.value as? String, "0"); snap("269-readable-persisted")
    }
    func testReadablePresentationAndCancellation() throws {
        finishOnboarding(); openReadableRecovery()
        try chooseReadableFixture("Lumen-readable-invalid")
        XCTAssertTrue(app.alerts["Couldn't read export"].waitForExistence(timeout: 30)); snap("270-readable-invalid"); tap("OK")
        XCTAssertFalse(app.buttons["recoverReadableData"].exists)
        try chooseReadableFixture("Lumen-readable-large")
        let cancel = app.buttons["cancelReadableOperation"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); snap("271-readable-progress"); cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 90)); XCTAssertFalse(app.buttons["recoverReadableData"].exists)
        let cancelled = app.staticTexts["readableStatus"].firstMatch; reveal(cancelled); snap("272-readable-cancelled")
        XCTAssertTrue(cancelled.label.contains("Cancelled"))
        try chooseReadableFixture("Lumen-readable-partial"); waitForReadableReview()
        XCTAssertFalse(app.switches["recoverReadable-profile"].exists)
        nativeSwitch("recoverReadable-water", enabled: false)
        let add = app.buttons["recoverReadableData"].firstMatch; reveal(add); XCTAssertFalse(add.isEnabled)
        nativeSwitch("recoverReadable-water", enabled: true)
        app.terminate(); app.launchArguments = ["-lumen.appearance", "dark"]; app.launch()
        openReadableRecovery(); try chooseReadableFixture("Lumen-readable-partial"); waitForReadableReview(); snap("273-readable-dark-partial")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        openReadableRecovery(); try chooseReadableFixture("Lumen-readable-full"); waitForReadableReview()
        let water = app.switches["recoverReadable-water"].firstMatch; reveal(water); snap("274-readable-large-controls")
        XCTAssertEqual(water.value as? String, "1")
        let review = app.buttons["reviewReadable-documents"].firstMatch; reveal(review); review.tap(); tap("readableEntry-0")
        let content = app.staticTexts["readableEntryText"].firstMatch; reveal(content); snap("275-readable-large-entry")
        XCTAssertGreaterThan(content.frame.height, 200)
    }

    func prepareRetrievalLibrary(allShared: Bool = false) throws {
        finishOnboarding(); openBackupSettings(); try chooseBackupFixture("Lumen-backup-retrieval")
        _ = backupPreview(); confirmBackupRestore()
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap(); tap("Done"); tab("Library")
        let titles = (allShared ? (1...7).map { "Recent walking note \($0)" } : []) + ["Autumn appointment record"]
        for title in titles {
            let document = app.buttons[title].firstMatch; reveal(document); document.tap()
            nativeSwitch("Use in assistant", enabled: true)
            app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        }
        tab("Assistant")
    }

    func askLibrary(_ question: String, replies: Int = 1) {
        let input = app.textFields["coachInput"].firstMatch
        let field = input.exists ? input : app.textViews["coachInput"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(question); tap("coachSend")
        let count = NSPredicate(format: "count == %d", replies)
        expectation(for: count, evaluatedWith: app.staticTexts.matching(identifier: "coachMessage"))
        waitForExpectations(timeout: 30)
    }

    func openLibraryReference() {
        let disclosure = app.buttons["Library matches"].firstMatch; reveal(disclosure)
        let source = app.buttons["library-reference-1"].firstMatch
        if disclosure.value as? String == "Collapsed" { disclosure.tap() }
        reveal(source); source.tap()
        XCTAssertTrue(app.navigationBars["Saved reference"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["reference-excerpt"].label.contains("12.5 mg/L"))
    }

    func testLibraryRetrievalAndWithdrawal() throws {
        try prepareRetrievalLibrary(allShared: true)
        snap("210-library-search-intro")
        askLibrary("What does my record say about ferritin?")
        let reply = app.staticTexts["coachMessage"].firstMatch
        XCTAssertTrue(reply.label.contains("12.5 mg/L")); XCTAssertFalse(reply.label.contains("PRIVATE-CANARY")); snap("211-library-search-reply")
        let disclosure = app.buttons["Library matches"].firstMatch; reveal(disclosure); disclosure.tap()
        XCTAssertEqual(disclosure.value as? String, "Expanded")
        reveal(app.buttons["library-reference-1"].firstMatch)
        XCTAssertTrue(app.staticTexts["8 shared documents searched"].exists); snap("212-library-search-expanded")
        openLibraryReference(); snap("213-library-source-current")
        let open = app.buttons["Open in Library"].firstMatch; reveal(open); open.tap()
        nativeSwitch("Use in assistant", enabled: false); snap("214-library-sharing-withdrawn")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        let off = app.staticTexts["Assistant sharing is off for this document. This saved excerpt stays with the earlier reply."].firstMatch
        reveal(off); XCTAssertTrue(off.exists); snap("215-library-source-sharing-off"); tap("Done")
        let save = app.buttons["Save to Library"].firstMatch; reveal(save); save.tap()
        let saved = app.buttons["View saved document"].firstMatch; reveal(saved); saved.tap()
        let savedRefs = app.buttons["Library matches"].firstMatch; reveal(savedRefs); savedRefs.tap(); reveal(app.buttons["library-reference-1"].firstMatch); snap("216-library-saved-references")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        app.terminate(); app.launchArguments = []; app.launch(); tab("Assistant")
        openLibraryReference(); snap("217-library-reference-persisted"); tap("Done")
        askLibrary("What does my record say about ferritin?", replies: 2)
        XCTAssertTrue(app.staticTexts.matching(identifier: "coachMessage").element(boundBy: 1).label.contains("No match in the shared documents searched"))
        snap("218-library-no-match-after-withdrawal")
        openLibraryReference()
        let current = app.buttons["Open in Library"].firstMatch; reveal(current); current.tap()
        tap("Document actions"); tap("Edit")
        let body = app.textViews.firstMatch; reveal(body); body.tap(); body.typeKey("a", modifierFlags: .command); body.typeText("Changed synthetic appointment note.")
        tap("Save"); app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        let changed = app.staticTexts["The Library text has changed"].firstMatch; reveal(changed); snap("219-library-source-changed")
        reveal(app.buttons["Open in Library"].firstMatch); tap("Open in Library")
        tap("Document actions"); tap("Delete")
        XCTAssertTrue(app.alerts["Delete this document?"].waitForExistence(timeout: 5)); snap("219a-library-delete-copy-explanation")
        tap("Keep document"); XCTAssertTrue(app.alerts["Delete this document?"].waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Document"].exists)
        tap("Document actions"); tap("Delete"); tap("Delete")
        let removed = app.staticTexts["Document removed from Library"].firstMatch; reveal(removed); XCTAssertTrue(removed.exists); snap("219b-library-source-removed")
        tap("Done")
    }

    func testLibraryProviderReferenceLayout() throws {
        finishOnboarding(); openBackupSettings(); try chooseBackupFixture("Lumen-backup-reference-layout")
        _ = backupPreview(); confirmBackupRestore()
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap(); tap("Done"); tab("Assistant")
        tap("Conversation history"); scrollAndTap("Reference layout fixture")
        let disclosure = app.buttons["Library for this reply"].firstMatch; reveal(disclosure); disclosure.tap()
        let fourth = app.buttons["library-reference-4"].firstMatch; reveal(fourth); snap("230-library-provider-context-fixture")
        XCTAssertTrue(app.staticTexts["Shared with provider · not cited"].firstMatch.exists)
        let invalid = app.staticTexts["The reply included an unrecognized reference. It couldn't be linked to saved text."].firstMatch; reveal(invalid); snap("231-library-unknown-reference-fixture")
        let first = app.buttons["library-reference-1"].firstMatch; reveal(first); first.tap()
        XCTAssertTrue(app.navigationBars["Saved reference"].waitForExistence(timeout: 5)); snap("232-library-provider-snapshot-fixture"); tap("Done")
        let legacy = app.staticTexts["This earlier reply has no saved references and isn't included with new questions."].firstMatch; reveal(legacy); snap("233-library-legacy-reply")
        let quote = app.buttons["Quote in new question"].firstMatch; reveal(quote); quote.tap()
        let field = app.textFields["coachInput"].firstMatch
        let input = field.exists ? field : app.textViews["coachInput"].firstMatch
        XCTAssertTrue((input.value as? String ?? "").contains("Synthetic earlier reply without source metadata.")); snap("234-library-legacy-quote-draft")
        XCTAssertEqual(app.staticTexts.matching(identifier: "coachMessage").count, 2, "Quoting must not send the draft")
    }

    func testLibraryReferencePresentation() throws {
        try prepareRetrievalLibrary()
        askLibrary("What does my record say about ferritin?")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "dark"]; app.launch(); tab("Assistant")
        let disclosure = app.buttons["Library matches"].firstMatch; reveal(disclosure); disclosure.tap(); reveal(app.buttons["library-reference-1"].firstMatch); snap("220-library-dark-reply")
        openLibraryReference(); snap("221-library-dark-source"); tap("Done")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); tab("Assistant")
        let largeDisclosure = app.buttons["Library matches"].firstMatch; reveal(largeDisclosure); largeDisclosure.tap(); reveal(app.buttons["library-reference-1"].firstMatch); snap("222-library-large-references")
        openLibraryReference(); snap("223-library-large-source")
        let excerpt = app.staticTexts["reference-excerpt"].firstMatch
        XCTAssertGreaterThan(excerpt.frame.height, 150)
        for _ in 0..<8 {
            let top = app.navigationBars["Saved reference"].frame.maxY + 16
            if excerpt.frame.minY >= top && excerpt.frame.maxY < app.frame.maxY - 60 { break }
            let lower = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: 600))
            let upper = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: 400))
            if excerpt.frame.minY < top { upper.press(forDuration: 0.05, thenDragTo: lower) }
            else { lower.press(forDuration: 0.05, thenDragTo: upper) }
        }
        XCTAssertGreaterThan(excerpt.frame.minY, app.navigationBars["Saved reference"].frame.maxY)
        XCTAssertLessThan(excerpt.frame.maxY, app.frame.maxY - 45)
        snap("223a-library-large-excerpt")
        let open = app.buttons["Open in Library"].firstMatch; reveal(open); snap("224-library-large-source-footer")
    }

    func testScannedRecordReview() throws {
        finishOnboarding(); openRecordImport(); snap("180-record-start")
        try chooseRecordFixture("Lumen-record-scan"); waitForRecordPreview(); snap("181-record-scan-preview")
        XCTAssertFalse(app.buttons["saveReviewedRecord"].isEnabled)
        let title = app.textFields["recordTitle"].firstMatch; replaceAmount(title, with: "Synthetic reviewed record"); title.typeText("\n")
        let content = app.textViews["recordPageText"].firstMatch; reveal(content)
        XCTAssertTrue((content.value as? String ?? "").contains("12.5")); snap("182-record-page-text")
        content.tap(); content.typeKey("a", modifierFlags: .command); content.typeText("Reviewed synthetic value: 12.5 mg/L"); tap("finishRecordEditing")
        app.swipeDown(velocity: .slow)
        let next = app.buttons["Next page"].firstMatch; reveal(next); next.tap()
        XCTAssertTrue((app.descendants(matching: .any).matching(identifier: "recordPageNumber").firstMatch.label).contains("2"))
        let secondPage = app.textViews["recordPageText"].firstMatch; reveal(secondPage)
        secondPage.tap()
        let softwareKeyboard = app.keyboards.firstMatch
        if softwareKeyboard.waitForExistence(timeout: 5) { snap("199b-record-software-keyboard") }
        else { snap("199b-record-keyboard-state"); print("Software keyboard wasn't visible after focus") }
        secondPage.typeKey("a", modifierFlags: .command); secondPage.typeText("Reviewed second synthetic value: 12.5 mg/L"); snap("199-record-editing"); tap("finishRecordEditing")
        snap("183-record-second-page")
        nativeSwitch("acknowledgeRecordText", enabled: true)
        XCTAssertEqual(app.switches["shareImportedRecord"].firstMatch.value as? String, "0")
        snap("184-record-reviewed-ready"); tap("saveReviewedRecord")
        XCTAssertTrue(app.buttons["saveReviewedRecord"].waitForNonExistence(timeout: 10))
        let saved = app.buttons["Synthetic reviewed record"].firstMatch; reveal(saved); saved.tap()
        XCTAssertTrue(app.staticTexts["Reviewed imported text"].waitForExistence(timeout: 5)); snap("185-record-saved")
        XCTAssertTrue(app.staticTexts["Reviewed synthetic value: 12.5 mg/L"].firstMatch.exists)
        app.terminate(); app.launchArguments = []; app.launch(); tab("Library"); tap("Synthetic reviewed record")
        XCTAssertTrue(app.staticTexts["Reviewed imported text"].waitForExistence(timeout: 5)); snap("186-record-persisted")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        openRecordImport(); try chooseRecordFixture("Lumen-record-scan"); waitForRecordPreview()
        nativeSwitch("acknowledgeRecordText", enabled: true); tap("saveReviewedRecord")
        XCTAssertTrue(app.alerts["Save another copy?"].waitForExistence(timeout: 5)); snap("198-record-duplicate")
        tap("Keep reviewing"); tap("cancelRecordImport")
    }
    func testRecordPresentationAndDraftGuard() throws {
        finishOnboarding()
        app.terminate(); app.launchArguments = ["-lumen.appearance", "dark"]; app.launch()
        openRecordImport(); try chooseRecordFixture("Lumen-record-blank"); waitForRecordPreview()
        XCTAssertFalse(app.buttons["saveReviewedRecord"].isEnabled)
        let text = app.textViews["recordPageText"].firstMatch; reveal(text)
        text.tap(); text.typeText("Synthetic transcribed page for review."); tap("finishRecordEditing")
        let reviewBar = app.navigationBars["Review record"]
        reviewBar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.alerts["Discard your changes?"].waitForExistence(timeout: 5)); snap("191b-record-swipe-guard"); tap("Keep reviewing")
        tap("cancelRecordImport"); tap("Keep reviewing")
        XCTAssertTrue(text.exists); snap("191-record-dark-draft")
        nativeSwitch("acknowledgeRecordText", enabled: true)
        XCTAssertTrue(app.buttons["saveReviewedRecord"].isEnabled)
        nativeSwitch("excludeRecordPage", enabled: true)
        nativeSwitch("acknowledgeRecordText", enabled: true)
        XCTAssertFalse(app.buttons["saveReviewedRecord"].isEnabled, "Excluding every page must not create an empty record")
        snap("192-record-dark-excluded"); tap("cancelRecordImport"); tap("Discard changes")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        openRecordImport(); snap("193-record-large-start")
        try chooseRecordFixture("Lumen-record-hybrid"); waitForRecordPreview(); snap("194-record-large-review")
        let title = app.textFields["recordTitle"].firstMatch; reveal(title)
        XCTAssertGreaterThan(title.frame.height, 45, "Actual accessibility type must enlarge the title field")
        let source = app.descendants(matching: .any).matching(identifier: "recordTextSource").firstMatch
        reveal(source); source.tap(); tap("Selectable text")
        let page = app.textViews["recordPageText"].firstMatch; reveal(page)
        XCTAssertTrue((page.value as? String ?? "").contains("header")); XCTAssertFalse((page.value as? String ?? "").contains("LAB-42"))
        snap("195-record-large-source")
        let pageImage = app.buttons["Page image"].firstMatch; reveal(pageImage); pageImage.tap()
        let renderedPage = app.images["Original page 1"].firstMatch; reveal(renderedPage); snap("195b-record-page-image")
        let original = app.buttons["Open original"].firstMatch; reveal(original); original.tap()
        let originalPage = app.staticTexts["Selectable header only"].firstMatch
        XCTAssertTrue(originalPage.waitForExistence(timeout: 15), app.debugDescription); snap("196-record-original")
        let closeOriginal = app.buttons["closeOriginalRecord"].firstMatch
        XCTAssertTrue(closeOriginal.waitForExistence(timeout: 10), app.debugDescription); closeOriginal.tap()
        XCTAssertTrue(closeOriginal.waitForNonExistence(timeout: 10))
        nativeSwitch("acknowledgeRecordText", enabled: true); snap("197-record-large-controls")
        let sharing = app.switches["shareImportedRecord"].firstMatch; reveal(sharing); snap("197b-record-large-sharing")
        XCTAssertEqual(app.switches["shareImportedRecord"].firstMatch.value as? String, "0")
        tap("cancelRecordImport")
    }

    func testRecordSourceReplacementAndKeyboard() throws {
        finishOnboarding(); openRecordImport()
        try chooseRecordFixture("Lumen-record-hybrid"); waitForRecordPreview()
        let text = app.textViews["recordPageText"].firstMatch; reveal(text); text.tap()
        if app.keyboards.firstMatch.waitForExistence(timeout: 5) { snap("200-record-software-keyboard") }
        else { snap("200-record-keyboard-state"); print("Software keyboard wasn't visible after record focus") }
        text.typeKey("a", modifierFlags: .command); text.typeText("Reviewed synthetic correction: 12.5 mg/L")
        let footer = app.staticTexts["Save keeps your reviewed text and page details. The original file isn't stored in Library; keep your own copy."].firstMatch
        reveal(footer)
        let done = app.buttons["finishRecordEditing"].firstMatch
        for _ in 0..<8 where footer.frame.maxY + 12 > done.frame.minY {
            let top = app.navigationBars["Review record"].frame.maxY + 24
            let bottom = done.frame.minY - 24
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: bottom)).press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: top)))
        }
        XCTAssertLessThanOrEqual(footer.frame.maxY + 12, done.frame.minY, "Focused text must scroll clear of the keyboard Done action")
        snap("201-record-focused-footer"); done.tap()
        let source = app.descendants(matching: .any).matching(identifier: "recordTextSource").firstMatch
        reveal(source); source.tap(); tap("Selectable text")
        XCTAssertTrue(app.alerts["Replace your edits with the other text version?"].waitForExistence(timeout: 5)); snap("202-record-source-guard"); tap("Keep edits")
        XCTAssertEqual(text.value as? String, "Reviewed synthetic correction: 12.5 mg/L")
        reveal(source); source.tap(); tap("Selectable text"); tap("Replace page text")
        XCTAssertTrue((text.value as? String ?? "").contains("header")); XCTAssertFalse((text.value as? String ?? "").contains("Reviewed synthetic correction"))
        XCTAssertEqual(app.switches["acknowledgeRecordText"].firstMatch.value as? String, "0")
        snap("203-record-replaced-source"); tap("cancelRecordImport"); XCTAssertTrue(app.buttons["cancelRecordImport"].waitForNonExistence(timeout: 10))
    }

    func testRecordCancellationAndErrors() throws {
        finishOnboarding(); openRecordImport()
        try chooseRecordFixture("Lumen-record-long")
        let progress = app.descendants(matching: .any).matching(identifier: "recordReadingProgress").firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 10)); snap("187-record-progress"); tap("cancelRecordImport")
        XCTAssertTrue(app.buttons["chooseRecordFile"].waitForExistence(timeout: 30)); snap("188-record-cancelled")
        try chooseRecordFixture("Lumen-record-locked")
        XCTAssertTrue(app.alerts["Couldn't read record"].waitForExistence(timeout: 20)); snap("189-record-locked"); tap("OK")
        try chooseRecordFixture("Lumen-record-damaged")
        XCTAssertTrue(app.alerts["Couldn't read record"].waitForExistence(timeout: 20)); tap("OK")
        try chooseRecordFixture("Lumen-record-hybrid"); waitForRecordPreview()
        let content = app.textViews["recordPageText"].firstMatch; reveal(content)
        XCTAssertTrue((content.value as? String ?? "").contains("LAB-42")); snap("190-record-hybrid")
        tap("cancelRecordImport")
    }

    func openHealthConnections() {
        tap("Settings")
        let link = app.buttons["Health imports & contextual reminders"].firstMatch
        reveal(link); link.tap()
        XCTAssertTrue(app.navigationBars["Connections"].waitForExistence(timeout: 5))
    }

    func setHealthDeliverySwitch(_ toggle: XCUIElement, enabled: Bool) {
        // SwiftUI exposes the label and UISwitch as one wide accessibility element.
        // Tap the actual trailing control, then wait for its published value.
        reveal(toggle)
        let nativeControl = toggle.switches.firstMatch
        if nativeControl.exists { reveal(nativeControl); nativeControl.tap() }
        else { toggle.tap() }
        let expected = enabled ? "1" : "0"
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", expected), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    func approveSyntheticHealthAccess(until completed: XCUIElement) {
        let all = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Select All'")).firstMatch
        if all.waitForExistence(timeout: 6) { all.tap() }
        for step in 0..<3 {
            if completed.exists { return }
            let range = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'All Recorded Data and Future Data'")).firstMatch
            if range.exists && range.isHittable { range.tap() }
            let approval = app.buttons.matching(NSPredicate(format: "identifier == 'UIA.Health.Allow.Button' OR label == 'Allow' OR label == 'Continue'")).firstMatch
            for _ in 0..<10 where !(approval.exists && approval.isHittable && approval.isEnabled) { app.swipeUp(velocity: .slow) }
            if !(approval.exists && approval.isHittable) { snap("health-approval-unreachable"); print(app.debugDescription) }
            XCTAssertTrue(approval.exists && approval.isHittable, "Health approval step must be reachable")
            snap("170b-health-approval-" + String(step)); approval.tap()
            let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: completed)
            _ = XCTWaiter.wait(for: [complete], timeout: 3)
        }
    }

    func testHealthForegroundSynchronization() throws {
        finishOnboarding(); openHealthConnections(); tap("Connect Apple Health")
        let reviewed = app.buttons["Review Health access & sync"].firstMatch
        approveSyntheticHealthAccess(until: reviewed)
        XCTAssertTrue(reviewed.waitForExistence(timeout: 20))
        let retry = app.buttons["checkHealthNow"].firstMatch
        reveal(retry)
        let history = app.descendants(matching: .any).matching(identifier: "healthHistoryCheck").firstMatch
        XCTAssertTrue(history.waitForExistence(timeout: 30)); snap("171-health-foreground-sync")
        app.terminate(); app.launchArguments = []; app.launch(); openHealthConnections()
        XCTAssertTrue(history.waitForExistence(timeout: 30)); snap("172-health-foreground-persisted")
    }

    func testHealthOnboardingSynchronization() throws {
        tap("Get started")
        let name = app.textFields.firstMatch; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Alex")
        tap("Continue"); tap("Connect Apple Health")
        let requested = app.staticTexts["Access requested"].firstMatch
        approveSyntheticHealthAccess(until: requested)
        XCTAssertTrue(requested.waitForExistence(timeout: 30)); snap("173-health-onboarding-readings")
        tap("Continue"); tap("Continue"); tap("Continue"); tap("Continue"); tap("Maybe later"); tap("Start using Lumen")
        openHealthConnections()
        let history = app.descendants(matching: .any).matching(identifier: "healthHistoryCheck").firstMatch
        reveal(history); XCTAssertFalse((history.value as? String ?? "").isEmpty)
        snap("174-health-onboarding-sync")
        app.navigationBars["Connections"].buttons.element(boundBy: 0).tap()
        let erase = app.buttons["Erase all data"].firstMatch; reveal(erase); erase.tap()
        tap("Erase everything")
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        snap("175-health-reset-cleared")
    }

    func testHealthDeliveryPreferences() throws {
        finishOnboarding(); openHealthConnections()
        let toggle = app.switches["backgroundHealthUpdates"].firstMatch
        reveal(toggle); XCTAssertEqual(toggle.value as? String, "0")
        snap("160-health-updates-off")
        setHealthDeliverySwitch(toggle, enabled: true)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "healthDeliveryStatus").firstMatch.value as? String, "Waiting for Apple Health connection")
        snap("161-health-updates-awaiting-access")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "dark"]; app.launch(); openHealthConnections()
        reveal(toggle); XCTAssertEqual(toggle.value as? String, "1")
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "healthDeliveryStatus").firstMatch.value as? String, "Waiting for Apple Health connection")
        snap("162-health-updates-dark")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); openHealthConnections(); reveal(toggle)
        let largeControl = app.descendants(matching: .any).matching(identifier: "healthUpdatesControl").firstMatch
        reveal(largeControl)
        XCTAssertGreaterThan(largeControl.frame.height, 128, "The accessibility-size override must enlarge the full-width control")
        snap("163-health-updates-large-type")
        setHealthDeliverySwitch(toggle, enabled: false)
        snap("164-health-updates-large-type-off")
        let status = app.descendants(matching: .any).matching(identifier: "healthDeliveryStatus").firstMatch
        reveal(status); snap("165-health-updates-large-type-status")
        let explanation = app.staticTexts["iOS decides when to deliver changes. Updates may wait until you unlock your iPhone. Open Lumen to refresh at any time."].firstMatch
        reveal(explanation); snap("166-health-updates-large-type-explanation")
        app.terminate(); app.launchArguments = []; app.launch(); openHealthConnections(); reveal(toggle)
        XCTAssertEqual(toggle.value as? String, "0"); XCTAssertTrue(app.staticTexts["Not connected"].firstMatch.exists)
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

    func focusHealthDraftInput(_ identifier: String, capture: String? = nil) {
        let field = identifier == "draftHealthNotes" ? app.textViews[identifier].firstMatch : app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if identifier == "draftHealthNotes" {
            let edit = app.buttons["editHealthDraftNotes"].firstMatch; reveal(edit); edit.tap()
            XCTAssertTrue(field.waitForExistence(timeout: 5))
        } else { reveal(field); field.tap() }
        let done = app.buttons[identifier == "draftHealthNotes" ? "finishHealthDraftNotes" : "dismissHealthDraftKeyboard"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable); XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        XCTAssertLessThanOrEqual(done.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        if let capture { snap(capture) }
        done.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
    }
    func reopenWaterDraft() {
        let review = app.buttons["Review health entries"].firstMatch; reveal(review); review.tap()
        let water = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Water'")).firstMatch; reveal(water); water.tap()
        XCTAssertTrue(app.navigationBars["Review water"].waitForExistence(timeout: 5))
    }
    func testHealthDraftKeyboardPresentation() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-lumen.appearance", "dark"]; app.launch()
        finishOnboarding(); tab("Assistant")
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("I drank 350 ml of water."); tap("coachSend")
        reopenWaterDraft(); focusHealthDraftInput("draftWaterML", capture: "333-water-dark-keyboard")
        app.navigationBars["Review water"].buttons.element(boundBy: 0).tap(); tap("Close")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); tab("Assistant")
        reopenWaterDraft(); snap("334-water-large-review")
        let notes = app.textViews["draftHealthNotes"].firstMatch
        let edit = app.buttons["editHealthDraftNotes"].firstMatch; reveal(edit); edit.tap()
        XCTAssertTrue(notes.waitForExistence(timeout: 5)); notes.tap(); notes.typeText("Large synthetic note.\nThe final line stays visible.")
        let done = app.buttons["finishHealthDraftNotes"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(done.isHittable); XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        XCTAssertLessThanOrEqual(done.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        snap("335-water-large-note-keyboard")
        XCTAssertEqual(notes.value as? String, "Large synthetic note.\nThe final line stays visible.")
        done.tap(); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["draftHealthNotesPreview"].label, "Large synthetic note.\nThe final line stays visible."); snap("336-water-large-note-dismissed")
        reveal(app.buttons["editHealthDraftNotes"].firstMatch); snap("346-water-large-full-note-route")
        app.navigationBars["Review water"].buttons.element(boundBy: 0).tap(); tap("Close")
        XCTAssertTrue(app.alerts["Discard your unsaved changes?"].waitForExistence(timeout: 5)); snap("337-water-large-discard")
        tap("Keep reviewing"); tap("Close"); tap("Discard unsaved drafts")
        XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 1)
    }

    func testHealthLogSourceDisclosure() throws {
        finishOnboarding(); tab("Assistant")
        let statement = "I drank 250 ml of water. I walked for 20 minutes. I have a headache 5/10. Energy 2/5, mood 4/5, stress 3/5."
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText(statement); tap("coachSend"); reopenWaterDraft()
        let confirm = app.buttons["confirmChatHealthLog"].firstMatch; reveal(confirm); confirm.tap(); tap("Close")
        tab("Journal")
        let water = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'water-' ")).firstMatch
        reveal(water); water.tap(); tap("editWaterEntry")
        replaceAmount(app.textFields["correctWaterML"].firstMatch, with: "750")
        tap("dismissCorrectionKeyboard"); tap("saveCorrectedEntry")
        XCTAssertEqual(app.staticTexts["waterEntryValue"].label, "750 ml")
        scrollAndTap("Original message")
        let full = app.staticTexts[statement].firstMatch; XCTAssertTrue(full.waitForExistence(timeout: 5))
        let top = app.navigationBars.firstMatch.frame.maxY + 8
        let bottom = app.frame.maxY - 70
        for _ in 0..<8 {
            if full.exists && full.frame.minY >= top && full.frame.maxY <= bottom { break }
            if full.exists && full.frame.minY < top { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        var prior = CGRect.null, unchanged = 0
        let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = full.frame
            unchanged = frame == prior ? unchanged + 1 : 0; prior = frame
            return unchanged >= 2 && frame.minY >= top && frame.maxY <= bottom && frame.height > 40
        }, object: full)
        XCTAssertEqual(XCTWaiter.wait(for: [settled], timeout: 8), .completed)
        XCTAssertEqual(full.label, statement); snap("348-complete-original-message")
        tap("Done")
    }

    func testHealthDraftLayout() throws {
        finishOnboarding(); tab("Assistant")
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("I drank 350 ml of water."); tap("coachSend")
        let review = app.buttons["Review health entries"].firstMatch; reveal(review); review.tap()
        let water = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Water'")).firstMatch; reveal(water); water.tap()
        let amount = app.textFields["draftWaterML"].firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); XCTAssertEqual(amount.value as? String, "350")
        snap("330-water-review-layout")
        amount.tap(); XCTAssertTrue(app.buttons["dismissHealthDraftKeyboard"].waitForExistence(timeout: 5)); snap("331-water-keyboard")
        tap("dismissHealthDraftKeyboard"); XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(amount.value as? String, "350"); snap("332-water-keyboard-dismissed")
        let confirm = app.buttons["confirmChatHealthLog"].firstMatch; reveal(confirm); XCTAssertTrue(confirm.isEnabled)
        app.navigationBars["Review water"].buttons.element(boundBy: 0).tap(); tap("Close")
        XCTAssertEqual(app.staticTexts.matching(identifier: "userMessage").count, 1)
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
        selectAmount(amount)
        app.keyboards.keys["5"].firstMatch.tap()
        XCTAssertEqual(amount.value as? String, "5")
        tap("Done"); app.navigationBars["Review water"].buttons.element(boundBy: 0).tap(); scrollAndTap("Water")
        XCTAssertEqual(amount.value as? String, "5", "The first single-key edit must survive marking the draft as changed")
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
        let savedNote = "Reviewed synthetic water note.\nKept separately from the original 250 ml message."
        let correctedNote = savedNote + "\nCorrection note kept with this entry."
        let editNote = app.buttons["editHealthDraftNotes"].firstMatch; reveal(editNote); editNote.tap()
        let noteEditor = app.textViews["draftHealthNotes"].firstMatch
        XCTAssertTrue(noteEditor.waitForExistence(timeout: 5)); noteEditor.tap(); noteEditor.typeText(savedNote)
        XCTAssertEqual(noteEditor.value as? String, savedNote); snap("341-water-note-before-confirmation")
        tap("finishHealthDraftNotes")
        XCTAssertEqual(app.staticTexts["draftHealthNotesPreview"].label, savedNote)
        let confirm = app.buttons["confirmChatHealthLog"]
        reveal(confirm); snap("101-chat-water-edit"); confirm.tap()
        XCTAssertTrue(app.staticTexts["Water · 500 ml"].waitForExistence(timeout: 5))
        scrollAndTap("Workout")
        for id in ["draftWorkoutName", "draftWorkoutDuration", "draftWorkoutEnergy", "draftHealthNotes"] { focusHealthDraftInput(id, capture: id == "draftHealthNotes" ? "338-workout-note-keyboard" : nil) }
        reveal(confirm); confirm.tap()
        XCTAssertTrue(app.staticTexts["Walk"].waitForExistence(timeout: 5))
        scrollAndTap("Headache")
        for id in ["draftSymptomName", "draftSymptomDuration", "draftHealthNotes"] { focusHealthDraftInput(id, capture: id == "draftHealthNotes" ? "339-symptom-note-keyboard" : nil) }
        let location = app.textFields["Body location"]
        XCTAssertTrue(location.waitForExistence(timeout: 5)); location.tap(); location.typeText("Head")
        XCTAssertEqual(location.value as? String, "Head")
        tap("Done")
        reveal(confirm); confirm.tap()
        scrollAndTap("Check-in")
        focusHealthDraftInput("draftHealthNotes", capture: "340-checkin-note-keyboard")
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
        XCTAssertTrue(app.staticTexts[savedNote].exists, "Confirmed notes persist through relaunch separately from their original message")
        snap("342-water-note-after-relaunch")
        tap("editWaterEntry")
        let editCorrectedNote = app.buttons["editCorrectedEntryNotes"].firstMatch; reveal(editCorrectedNote); editCorrectedNote.tap()
        let correctionNoteEditor = app.textViews["draftHealthNotes"].firstMatch
        XCTAssertTrue(correctionNoteEditor.waitForExistence(timeout: 5)); XCTAssertEqual(correctionNoteEditor.value as? String, savedNote)
        replaceVoiceText(correctionNoteEditor, with: correctedNote); snap("347-correction-note-editor")
        tap("finishHealthDraftNotes")
        let correctedWater = app.textFields["correctWaterML"]
        reveal(correctedWater)
        replaceAmount(correctedWater, with: "750")
        if app.buttons["dismissCorrectionKeyboard"].isHittable { tap("dismissCorrectionKeyboard") }
        snap("130-water-correction")
        tap("cancelCorrectedEntry"); tap("Keep editing")
        tap("saveCorrectedEntry")
        XCTAssertTrue(app.staticTexts["waterEntryValue"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["waterEntryValue"].label, "750 ml")
        XCTAssertTrue(app.staticTexts[correctedNote].exists)
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
        reveal(waterEntry); waterEntry.tap(); XCTAssertTrue(app.staticTexts[correctedNote].exists); tap("editWaterEntry")
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
