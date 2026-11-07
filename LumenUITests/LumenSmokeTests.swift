import XCTest
import CryptoKit
import UIKit

// MARK: - Lumen smoke test: fresh onboarding → every tab → logging → coach.
// Screenshots are attached to the result bundle for visual review.

final class LumenSmokeTests: XCTestCase {
    var app: XCUIApplication!
    var coachMessages: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "coachMessage") }
    var userMessages: XCUIElementQuery { app.descendants(matching: .any).matching(identifier: "userMessage") }
    var referenceExcerpt: XCUIElement { app.descendants(matching: .any).matching(identifier: "reference-excerpt").firstMatch }
    var fhirFullText: XCUIElement { app.descendants(matching: .any).matching(identifier: "fhirFullText").firstMatch }
    private var healthFileRecoveryLeavesReview: Bool {
        ["LegacyBack", "EncryptedBack", "ReadableBack"].contains { name.contains($0) }
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        // Settings discovery reads only the dedicated simulator. Do not reset
        // Lumen's last audited synthetic state or launch the product here.
        if name.contains("testReduceMotionSettingsDiscovery") || name.contains("testReduceMotionSettingsCapability") { return }
        // The focused wrapping probe reuses this dedicated simulator's saved
        // synthetic record, with a public Files-import fallback if absent.
        app.launchArguments = name.contains("testFHIRLiteralWrappingSnapshots") || name.contains("testLiteralIdentifier") || name.contains("testProviderCitationRejection") || name.contains("testProviderTransportFallback") ? ["-librarySearchRemoteUITestMode"] : ["-resetForUITests"]
        if name.contains("testHealthLegacyRootAcquisition") {
            let mode = name.contains("NoPrior") ? "legacy-root-missing-no-prior" : name.contains("Ordinary") ? "ordinary-root-missing-pending-removal-control" : "legacy-root-missing-with-prior"
            app.launchArguments = ["-resetForUITests", "-health-write-native-probe", "-health-legacy-root-probe", mode, "-health-backup-ui-fixture", "-health-backup-case", "legacy", "-health-backup-healthy-merge-ui", "-health-backup-empty-ui", "-health-legacy-origin-ui", "data", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        if name.contains("testDailyCacheClearCorrupt") || name.contains("testDailyCacheClearDirectory") || name.contains("testDailyCacheClearMissing") || name.contains("testDailyCacheClearHealthy") {
            app.launchArguments = ["-resetForUITests", "-health-recovery-ui-fixture", "-health-daily-cache-ui-fixture", "-health-recovery-cancel-ui",
                                   "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
            if name.contains("testDailyCacheClearDirectory") { app.launchArguments.append("-health-daily-cache-directory-ui") }
            if name.contains("testDailyCacheClearMissing") { app.launchArguments.append("-health-daily-cache-missing-ui") }
            if name.contains("testDailyCacheClearHealthy") { app.launchArguments.append("-health-daily-cache-healthy-ui") }
        }
        if name.contains("testDailyCacheRejectsLink") {
            app.launchArguments = ["-resetForUITests", "-health-recovery-ui-fixture", "-health-daily-cache-ui-fixture", "-health-daily-cache-link-ui", "-health-recovery-cancel-ui",
                                   "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        if name.contains("testDailyCacheRebuildHealthKit") {
            app.launchArguments = ["-resetForUITests", "-health-recovery-ui-fixture", "-health-daily-cache-ui-fixture",
                                   "-health-daily-cache-rebuild-ui", "-health-recovery-cancel-ui", "-lumen.appearance", name.contains("LargestDetails") || name.contains("DarkDetails") ? "dark" : "light",
                                   "-UIPreferredContentSizeCategoryName", name.contains("LargestDetails") ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            if name.contains("Recorded") { app.launchArguments.append("-health-daily-cache-recorded-ui") }
        }
        if name.contains("testDailyCacheHealthQuery") {
            app.launchArguments = ["-resetForUITests", "-health-recovery-ui-fixture", "-health-daily-cache-ui-fixture",
                                   "-health-daily-cache-rebuild-ui", "-health-daily-cache-query-interrupt-ui",
                                   "-health-recovery-cancel-ui", "-lumen.appearance", "light",
                                   "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        }
        if name.contains("testDurableHealthRestart") {
            let phase = name.contains("Resume") ? "resume" : "prepare"
            let scenario = name.contains("Undo") ? "undo-before-receipt" : name.contains("BeforeReceipt") ? "before-receipt" : "before-worker"
            app.launchArguments = ["-resetForUITests", "-health-write-lifecycle", phase, "-health-write-case", scenario]
            if phase == "prepare", scenario != "before-worker" {
                app.launchArguments += ["-quick-save-fault", "health-receipt:1,2,3,4,5,6,7"]
            }
        }
        if name.contains("testHealthRecoveryScreen") {
            app.launchArguments = ["-resetForUITests", "-health-recovery-ui-fixture", "-lumen.appearance", name.contains("Dark") || name.contains("Largest") ? "dark" : "light"]
            if name.contains("Largest") { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            if name.contains("Cancel") { app.launchArguments += ["-health-recovery-cancel-ui"] }
        }
        if name.contains("testHealthRecoveryReadRetainedRecords") {
            app.launchArguments = ["-resetForUITests", "-health-recovery-ui-fixture", "-health-read-ui"]
        }
        if name.contains("testHealthRecoveryReadRetainedPhoto") {
            app.launchArguments = ["-resetForUITests", "-health-review-records-fixture", "-health-review-oriented-photo", "-health-read-ui", "-health-read-scope", "retained-photo"]
        }
        if name.contains("testHealthRecoveryReadRetainedPhotoPayload") {
            app.launchArguments += ["-health-read-photo-payload"]
        }
        if name.contains("testHealthRecordReview") {
            app.launchArguments = ["-resetForUITests", "-health-review-records-fixture", "-lumen.appearance", name.contains("Dark") || name.contains("Largest") ? "dark" : "light"]
            if name.contains("Largest") { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            if name.contains("Empty") { app.launchArguments += ["-health-review-empty-fixture"] }
            if name.contains("PhotoUnavailable") { app.launchArguments += ["-health-review-invalid-photo"] }
            if name.contains("PhotoOriented") { app.launchArguments += ["-health-review-oriented-photo"] }
        }
        if name.contains("testHealthOriginalImport") {
            let kind = name.contains("Encrypted") ? "encrypted" : name.contains("Readable") ? "readable" : "legacy"
            app.launchArguments = ["-resetForUITests", "-health-backup-ui-fixture", "-health-backup-case", kind, "-health-read-ui", "-health-read-scope", "selected-import"]
            if name.contains("OriginalImportCopy") { app.launchArguments.append("-health-read-original-copy") }
            if name.contains("OriginalImportPayload") { app.launchArguments.append("-health-read-original-payload") }
            if name.contains("OriginalImportDecrypt") { app.launchArguments.append("-health-read-encrypted-record") }
            if name.contains("OriginalImportUnlock") { app.launchArguments.append("-health-read-encrypted-unlock") }
            if name.contains("OriginalImportCopyDenied") {
                app.launchArguments += ["-lumen.appearance", name.contains("Dark") || name.contains("Largest") ? "dark" : "light",
                    "-UIPreferredContentSizeCategoryName", name.contains("Largest") ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            }
        }
        if name.contains("testHealthBackupFileRead") {
            let kind = name.contains("Encrypted") ? "encrypted" : name.contains("Readable") ? "readable" : "legacy"
            app.launchArguments = ["-resetForUITests", "-health-backup-ui-fixture", "-health-backup-case", kind, "-health-read-ui", "-health-read-scope", "selected-record"]
            if name.contains("OwnerUnwind") { app.launchArguments.append("-health-read-owner-unwind") }
        }
        if name.contains("testHealthBackupPhoto") {
            let kind = name.contains("Encrypted") ? "encrypted" : "legacy"
            app.launchArguments = ["-resetForUITests", "-health-backup-ui-fixture", "-health-backup-case", kind,
                "-health-read-ui", "-health-read-scope", "selected-photo", "-health-read-photo-payload"]
            if name.contains("OwnerUnwind") { app.launchArguments.append("-health-read-owner-unwind") }
        }
        if name.contains("testHealthBackupFileRecovery") {
            let kind = name.contains("Encrypted") ? "encrypted" : name.contains("Readable") ? "readable" : "legacy"
            app.launchArguments = ["-resetForUITests", "-health-backup-ui-fixture", "-health-backup-case", kind]
            if name.contains("Cancel") || healthFileRecoveryLeavesReview || name.contains("RecoveryCommit") || name.contains("AllCommit") { app.launchArguments += ["-health-recovery-cancel-ui"] }
            if name.contains("AllCommit") { app.launchArguments.append("-health-backup-multi-ui") }
            if name.contains("RecoveryEmpty") || name.contains("RecoveryPhotoMatrix") || name.contains("RecoveryPhotoFault") { app.launchArguments += ["-health-backup-healthy-merge-ui", "-health-backup-empty-ui", "-health-recovery-cancel-ui"] }
            if name.contains("RecoveryPhotoFault") {
                app.launchArguments += ["-health-success-observation-ui", "-lumen.appearance", name.contains("Dark") || name.contains("Largest") ? "dark" : "light",
                                        "-UIPreferredContentSizeCategoryName", name.contains("Largest") ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL"]
            }
            if name.contains("OriginData") || name.contains("OriginString") {
                app.launchArguments += ["-health-legacy-origin-ui", name.contains("OriginData") ? "data" : "string"]
            }
            if name.contains("RecoveryPhotoFaultErrorBack") {
                app.launchArguments += ["-health-read-ui", "-health-read-scope", "selected-record"]
            }
        }
        if name.contains("testHealthBackupHealthyMerge") {
            let kind = name.contains("Encrypted") ? "encrypted" : name.contains("Readable") ? "readable" : "legacy"
            app.launchArguments = ["-resetForUITests", "-health-backup-ui-fixture", "-health-backup-case", kind, "-health-backup-healthy-merge-ui"]
            if name.contains("Preferences") { app.launchArguments.append("-health-backup-preferences-ui") }
        }
        app.launch()
    }

    func historyIdentity(_ fields: [String]) -> String {
        SHA256.hash(data: Data(fields.map { "\($0.utf8.count):" + $0 }.joined().utf8)).map { String(format: "%02x", $0) }.joined()
    }
    func historyPoint(_ record: String) -> String { historyIdentity([record, record + "-result"]) }
    func openUnitPair(coded: Bool = false, second: String = "unit-later") {
        let firstID = coded ? "unit-coded-earlier" : "unit-earlier", secondID = coded ? "unit-coded-later" : second
        openHistoryRecords([firstID, secondID])
        if coded {
            let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-group-' AND label BEGINSWITH 'Hemoglobin' ")).firstMatch; reveal(first); first.tap()
        } else {
            let first = app.buttons["history-group-" + historyIdentity(["Hemoglobin", "g/dL", "Synthetic laboratory", "Serum", "Synthetic assay", "Final"])].firstMatch; reveal(first); first.tap()
        }
        selectHistoryResult(firstID); tap("historyAllTests")
        if coded {
            let next = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-group-' AND label BEGINSWITH 'Hb' ")).firstMatch; reveal(next); next.tap()
        } else {
            let nextUnit = second == "unit-arbitrary" ? "IU/L" : "g/L"
            let nextName = second == "unit-renamed" ? "Hb" : "Hemoglobin"
            let next = app.buttons["history-group-" + historyIdentity([nextName, nextUnit, "Synthetic laboratory", "Serum", "Synthetic assay", "Final"])].firstMatch; reveal(next); next.tap()
        }
        selectHistoryResult(secondID); tap("compareLabHistoryResults"); tap("historyDecimal-dot")
        XCTAssertTrue(app.staticTexts["labComparisonNoArithmetic"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["saveLabComparison"].isEnabled)
    }
    func editUnitTarget(_ value: String, capture: String) {
        let button = app.buttons["editFull-normalizationTarget"].firstMatch; reveal(button); button.tap()
        let field = app.textViews["normalizationCodeText"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); settleLabFrame(field)
        labField("normalizationCodeText", value: value, replacing: true, doneIdentifier: "finishNormalizationCode", finish: value.count <= 100, inOpenEditor: true, capturePrefix: capture)
        if value.count > 100 {
            // Exercise the actual end insertion point with the software keyboard.
            field.typeText(XCUIKeyboardKey.delete.rawValue); field.typeText(String(value.suffix(1)))
            XCTAssertEqual(field.value as? String, value); settleLabFrame(field)
            XCTAssertTrue(app.keyboards.firstMatch.exists && app.buttons["finishNormalizationCode"].isHittable)
            snap(capture + "-end-caret-keyboard"); tap("finishNormalizationCode")
        }
    }
    func checkUnitReview(coded: Bool = false, reviewedNames: Bool = false, capture: String? = nil) {
        nativeSwitch("normalizationFirstChecked", enabled: true, towardsTop: true)
        if let capture { revealLabExcerpt(app.switches["normalizationFirstChecked"].firstMatch); snap(capture + "-earlier-unit-checked") }
        nativeSwitch("normalizationSecondChecked", enabled: true)
        if let capture { revealLabExcerpt(app.switches["normalizationSecondChecked"].firstMatch); snap(capture + "-later-unit-checked") }
        let picker = app.buttons["normalizationTestMatch"].firstMatch; reveal(picker); picker.tap(); tap(coded ? "Supplied test code" : (reviewedNames ? "My reviewed name match" : "Same reported name"))
        if !coded { XCTAssertTrue(app.staticTexts["normalizationNameScope"].exists) }
        if reviewedNames, let capture {
            revealLabExcerpt(picker); snap(capture + "-reviewed-name-choice")
            revealLabExcerpt(app.staticTexts["normalizationNameScope"].firstMatch); snap(capture + "-name-match-scope")
        }
        nativeSwitch("normalizationTestChecked", enabled: true)
        if let capture { revealLabExcerpt(app.switches["normalizationTestChecked"].firstMatch); snap(capture + "-identity-checked") }
    }
    func saveUnitComparison(capture: String, expected: String = "15") {
        let difference = app.staticTexts["labComparisonDifference"].firstMatch; reveal(difference); revealLabExcerpt(difference); XCTAssertEqual(difference.label, expected); snap(capture + "-difference")
        nativeSwitch("acknowledgeLabComparison", enabled: true); XCTAssertTrue(app.buttons["saveLabComparison"].isEnabled)
        if capture == "726-units-xxxl" {
            revealLabExcerpt(app.switches["acknowledgeLabComparison"].firstMatch); snap(capture + "-final-acknowledgement")
            // Save belongs to navigation chrome, above the scrollable content.
            let save = app.buttons["saveLabComparison"].firstMatch; settleLabFrame(save)
            XCTAssertTrue(save.isHittable && app.frame.contains(save.frame))
            snap(capture + "-save-ready")
        }
        tap("saveLabComparison")
        XCTAssertTrue(app.staticTexts["labComparisonSaved"].waitForExistence(timeout: 20))
        let view = app.buttons["viewSavedLabComparison"].firstMatch; reveal(view); revealLabExcerpt(view); snap(capture + "-complete-action"); view.tap()
        let captured = app.staticTexts["capturedLabDifference"].firstMatch; reveal(captured); XCTAssertEqual(captured.label, expected); snap(capture + "-saved")
    }
    func testLabUnitComparisonLifecycle() throws {
        try prepareHistoryFixture(fixture: "Lumen-backup-unit-review")
        openUnitPair(); snap("700-units-literal-before-review")
        nativeSwitch("normalizeLabComparison", enabled: true); snap("701-units-review-unchecked")
        let firstTarget = app.frame.width < 390 ? "g/L" + String(repeating: ".1", count: 56) : "g/L"
        editUnitTarget(firstTarget, capture: "702-units-common-editor")
        checkUnitReview()
        let first = app.staticTexts["normalizedValue-0"].firstMatch; reveal(first); XCTAssertEqual(first.label, "120"); snap("703-units-converted-earlier")
        XCTAssertEqual(app.staticTexts["normalizedReported-0"].label, "Reported: 12.00 g/dL")
        let later = app.staticTexts["normalizedValue-1"].firstMatch; reveal(later); XCTAssertEqual(later.label, "135"); snap("704-units-converted-later")
        nativeSwitch("acknowledgeLabComparison", enabled: true); XCTAssertTrue(app.buttons["saveLabComparison"].isEnabled)
        let target = app.buttons["editFull-normalizationTarget"].firstMatch; reveal(target, towardsTop: true); target.tap()
        labField("normalizationCodeText", value: "g/dL", replacing: true, doneIdentifier: "finishNormalizationCode", inOpenEditor: true)
        XCTAssertFalse(app.buttons["saveLabComparison"].isEnabled)
        XCTAssertEqual(app.switches["normalizationFirstChecked"].firstMatch.value as? String, "0"); snap("705-units-edit-resets-review")
        editUnitTarget("g/L", capture: "706-units-common-correction")
        nativeSwitch("normalizationFirstChecked", enabled: true, towardsTop: true); nativeSwitch("normalizationSecondChecked", enabled: true)
        let support = app.buttons["normalizationSupported"].firstMatch; reveal(support); support.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); snap("707-units-supported-reader")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        saveUnitComparison(capture: "708-units")
        let sharing = app.switches["Use in assistant"].firstMatch; reveal(sharing); XCTAssertEqual(sharing.value as? String, "0")
        let source = app.staticTexts["capturedLabValue-" + historyPoint("unit-earlier")].firstMatch; reveal(source); XCTAssertEqual(source.label, "12.00"); snap("709-units-original-retained")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library")
        let saved = app.buttons["Lab comparison · 2026-01-20 to 2026-10-20"].firstMatch; reveal(saved); saved.tap()
        let difference = app.staticTexts["capturedLabDifference"].firstMatch; reveal(difference); XCTAssertEqual(difference.label, "15"); snap("710-units-relaunched")
        let receipt = app.buttons["capturedNormalizationReview"].firstMatch; reveal(receipt); receipt.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); snap("711-units-captured-review")
        XCTAssertFalse(fhirFullText.label.contains("## Reviewed unit conversion"))
        if app.frame.width >= 390 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
            openLabRecord("Synthetic report · unit-earlier"); tap("Document actions"); tap("Edit")
            let title = app.textFields["Document title"].firstMatch; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(" corrected"); tap("Save")
            app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); reveal(saved); saved.tap()
            let changed = app.staticTexts["Source record changed after this capture"].firstMatch; reveal(changed); snap("712-units-original-changed")
            XCTAssertEqual(app.staticTexts["capturedLabDifference"].firstMatch.label, "15")
            app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
            openLabRecord("Synthetic report · unit-later"); tap("Document actions"); tap("Delete"); tap("Delete")
            reveal(saved); saved.tap()
            let removed = app.staticTexts["Source record removed; this captured copy remains"].firstMatch; reveal(removed); snap("713-units-original-removed")
            XCTAssertEqual(app.staticTexts["capturedLabValue-" + historyPoint("unit-later")].firstMatch.label, "135.00")
            app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); reveal(saved); saved.tap()
            reveal(removed); XCTAssertTrue(removed.exists); XCTAssertEqual(app.staticTexts["capturedLabDifference"].firstMatch.label, "15"); snap("714-units-removed-source-relaunch")
        }
    }
    func testLabUnitCodingAndUnsupported() throws {
        try prepareHistoryFixture(fixture: "Lumen-backup-unit-review")
        openUnitPair(coded: true); nativeSwitch("normalizeLabComparison", enabled: true)
        editUnitTarget("g/L", capture: "740-units-coded-target"); checkUnitReview(coded: true)
        let read = app.buttons["normalizationCodeReader"].firstMatch; reveal(read); read.tap()
        let text = fhirFullText; XCTAssertTrue(text.waitForExistence(timeout: 5)); XCTAssertTrue(text.label.contains("718-7") && text.label.contains("2.80")); snap("741-units-supplied-code")
        app.navigationBars.buttons.element(boundBy: 0).tap(); saveUnitComparison(capture: "742-units-coded")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library")
        openUnitPair(second: "unit-arbitrary"); nativeSwitch("normalizeLabComparison", enabled: true)
        editUnitTarget("g/L", capture: "743-units-unsupported-target"); checkUnitReview()
        let unavailable = app.staticTexts["labComparisonNoArithmetic"].firstMatch; reveal(unavailable); revealLabExcerpt(unavailable); snap("744-units-unsupported-literal")
        XCTAssertFalse(app.staticTexts["labComparisonDifference"].exists)
        let reason = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Later result:' AND label CONTAINS 'not supported for linear conversion: IU' ")).firstMatch; reveal(reason); XCTAssertTrue(reason.exists)
    }
    func testLabUnitComparisonPresentation() throws {
        try prepareHistoryFixture(fixture: "Lumen-backup-unit-review", arguments: ["-lumen.appearance", "dark"])
        openUnitPair(); nativeSwitch("normalizeLabComparison", enabled: true); editUnitTarget("g/L", capture: "720-units-dark-editor")
        let help = app.buttons["normalizationSupported"].firstMatch; reveal(help); help.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); app.swipeUp(velocity: .slow); snap("720-units-supported-limits")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        checkUnitReview(); saveUnitComparison(capture: "721-units-dark")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); tab("Library")
        openUnitPair(); nativeSwitch("normalizeLabComparison", enabled: true)
        let match = app.buttons["normalizationTestMatch"].firstMatch; reveal(match); match.tap(); tap("Same reported name")
        revealLabExcerpt(match); snap("722-units-xxxl-same-reported-name-choice")
        revealLabExcerpt(app.staticTexts["normalizationNameScope"].firstMatch); snap("723-units-xxxl-same-name-scope")
        app.terminate(); app.launch(); tab("Library")
        openUnitPair(second: "unit-renamed"); nativeSwitch("normalizeLabComparison", enabled: true)
        let longCode = "g/L" + String(repeating: ".1", count: 56)
        editUnitTarget(longCode, capture: "724-units-xxxl-long-editor"); checkUnitReview(reviewedNames: true, capture: "724-units-xxxl")
        let converted = app.staticTexts["normalizedValue-0"].firstMatch; reveal(converted); XCTAssertEqual(converted.label, "120"); snap("725-units-xxxl-converted")
        saveUnitComparison(capture: "726-units-xxxl")
        app.terminate(); app.launch(); tab("Library")
        openUnitPair(coded: true); nativeSwitch("normalizeLabComparison", enabled: true)
        reveal(match); match.tap(); tap("Supplied test code"); revealLabExcerpt(match); snap("727-units-xxxl-supplied-code-choice")
    }
    func testLabUnitCompleteAcknowledgements() throws {
        try prepareHistoryFixture(fixture: "Lumen-backup-unit-review")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); tab("Library")
        openUnitPair(); nativeSwitch("normalizeLabComparison", enabled: true)
        for (identifier, field, code, capture) in [
            ("normalizationFirstChecked", "normalizationFirst", "g/dL", "750-units-xxxl-earlier-complete-acknowledgement"),
            ("normalizationSecondChecked", "normalizationSecond", "g/L", "751-units-xxxl-later-complete-acknowledgement")
        ] {
            nativeSwitch(identifier, enabled: true, towardsTop: identifier == "normalizationFirstChecked")
            let control = app.switches[identifier].firstMatch
            let codeButton = app.buttons["editFull-" + field].firstMatch
            XCTAssertEqual(codeButton.value as? String, code)
            // At accessibility sizes the visible sentence is a sibling of the
            // native switch. Keep the code, complete sentence and switch in one
            // settled content frame, rather than checking the thumb alone.
            let labels = app.staticTexts.matching(NSPredicate(format: "label == %@", "I checked this unit against the report")).allElementsBoundByIndex
            let label = try XCTUnwrap(labels.filter { $0.frame.maxY <= control.frame.maxY }.min { abs($0.frame.maxY - control.frame.minY) < abs($1.frame.maxY - control.frame.minY) })
            for _ in 0..<12 {
                settleLabFrame(control)
                let top = app.navigationBars.firstMatch.frame.maxY + 12, bottom = app.frame.maxY - 40
                let region = codeButton.frame.union(label.frame).union(control.frame)
                XCTAssertLessThanOrEqual(region.height, bottom - top)
                if region.minY >= top && region.maxY <= bottom { break }
                let above = region.minY < top, overflow = above ? top - region.minY : region.maxY - bottom
                let distance = min(bottom - top - 40, max(40, overflow + 12)), startY = above ? top + 20 : bottom - 20
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: startY))
                let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: startY + (above ? distance : -distance)))
                start.press(forDuration: 0.05, thenDragTo: end)
            }
            settleLabFrame(label); settleLabFrame(control)
            let region = codeButton.frame.union(label.frame).union(control.frame)
            XCTAssertGreaterThanOrEqual(region.minY, app.navigationBars.firstMatch.frame.maxY + 12)
            XCTAssertLessThanOrEqual(region.maxY, app.frame.maxY - 40)
            XCTAssertEqual(control.value as? String, "1"); snap(capture)
        }
        tap("cancelLabComparison")
    }
    var earlierHistorySource: String { "Ferritin: 12.00 µg/L; collection 2026-01-20; Synthetic laboratory; Serum; Synthetic assay." }
    func prepareHistoryFixture(fixture: String = "Lumen-backup-history", arguments: [String] = []) throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"] + arguments; app.launch()
        finishOnboarding(); openBackupSettings(); try chooseBackupFixture(fixture)
        _ = backupPreview(); confirmBackupRestore()
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap(); tap("Done"); tab("Library")
    }
    func openHistoryRecords(_ ids: [String]) {
        let history = app.buttons["openLabHistory"].firstMatch; reveal(history); history.tap()
        XCTAssertTrue(app.buttons["reviewLabHistoryRecords"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["reviewLabHistoryRecords"].isEnabled)
        snap("530-history-record-selection")
        for id in ids { let record = app.buttons["history-record-" + id].firstMatch; reveal(record); record.tap(); XCTAssertEqual(record.value as? String, "Selected") }
        tap("reviewLabHistoryRecords")
        XCTAssertFalse(app.buttons["prepareLabHistory"].isEnabled)
        nativeSwitch("labHistoryPersonChecked", enabled: true); snap("531-history-person-review")
        tap("prepareLabHistory")
        XCTAssertTrue(app.staticTexts["labHistoryPreparedCount"].waitForExistence(timeout: 20)); snap("532-history-test-groups")
    }
    func openFirstHistoryGroup() {
        let group = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-group-'")).firstMatch
        reveal(group); group.tap()
        XCTAssertTrue(app.buttons["historyDecimal-dot"].waitForExistence(timeout: 5))
    }
    func selectHistoryResult(_ record: String) {
        let button = app.buttons["history-select-" + historyPoint(record)].firstMatch; reveal(button); button.tap()
        XCTAssertTrue(button.label.contains("Selected for comparison"))
    }
    func historyPlot() -> XCUIElement {
        // Charts exposes both a virtual accessibility summary (whose frame can
        // extend outside the content) and its actual interactive plot area.
        // Scroll using the visible plot's geometry, not the virtual summary.
        let candidates = app.otherElements.matching(identifier: "labHistoryNumericPlot")
        let bounded = candidates.allElementsBoundByIndex.filter { !$0.frame.isEmpty && $0.frame.minX >= 0 && $0.frame.maxX <= app.frame.maxX }
        return bounded.min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height } ?? candidates.firstMatch
    }
    func testLabHistoryComparison() throws {
        try prepareHistoryFixture()
        openHistoryRecords(["history-earlier", "history-later", "history-qualified", "history-undated", "history-zero"])
        XCTAssertTrue(app.staticTexts["labHistoryPreparedCount"].label.contains("5 saved results"))
        openFirstHistoryGroup()
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "labHistoryNumericPlot").firstMatch.exists)
        tap("historyDecimal-dot")
        let plot = historyPlot()
        revealLabExcerpt(plot); snap("533-history-numeric-points")
        plot.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).tap()
        let selectedDay = app.buttons["Show selected day"].firstMatch; XCTAssertTrue(selectedDay.waitForExistence(timeout: 5)); reveal(selectedDay); selectedDay.tap()
        XCTAssertTrue(app.staticTexts["historyValue-" + historyPoint("history-later")].exists)
        XCTAssertFalse(app.staticTexts["historyValue-" + historyPoint("history-earlier")].exists); snap("561-history-selected-collection-day")
        let all = app.buttons["Show all results"].firstMatch; reveal(all); all.tap()
        let coverage = app.staticTexts["labHistoryPlotCoverage"].firstMatch; reveal(coverage)
        XCTAssertTrue(coverage.label.contains("3 of 3 numeric results") && coverage.label.contains("2 other results"))
        let qualified = app.staticTexts["historyValue-" + historyPoint("history-qualified")].firstMatch
        reveal(qualified); XCTAssertEqual(qualified.label, "<5,0"); snap("534-history-qualified-literal")
        let undated = app.staticTexts["historyValue-" + historyPoint("history-undated")].firstMatch
        reveal(undated); XCTAssertEqual(undated.label, "7.00"); snap("535-history-undated-literal")
        let read = app.buttons["history-read-" + historyPoint("history-earlier")].firstMatch; reveal(read); read.tap()
        let excerpt = app.staticTexts["historySourceExcerpt-" + historyPoint("history-earlier")].firstMatch
        revealLabExcerpt(excerpt); XCTAssertTrue(excerpt.label.contains("12.00 µg/L")); snap("536-history-full-source")
        tap("Done")
        selectHistoryResult("history-later")
        XCTAssertEqual(app.staticTexts["historyComparisonSelectionState"].label, "1 of 2 selected"); snap("562-history-one-of-two-selected")
        selectHistoryResult("history-earlier"); tap("compareLabHistoryResults")
        XCTAssertTrue(app.buttons["saveLabComparison"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["saveLabComparison"].isEnabled)
        let difference = app.staticTexts["labComparisonDifference"].firstMatch; reveal(difference); XCTAssertEqual(difference.label, "6.5"); snap("537-history-review-difference")
        nativeSwitch("acknowledgeLabComparison", enabled: true)
        let comma = app.buttons["historyDecimal-comma"].firstMatch; reveal(comma); comma.tap()
        XCTAssertFalse(app.buttons["saveLabComparison"].isEnabled)
        XCTAssertTrue(app.staticTexts["labComparisonNoArithmetic"].exists); snap("538-history-interpretation-resets-review")
        tap("historyDecimal-dot"); nativeSwitch("acknowledgeLabComparison", enabled: true); snap("539-history-ready-to-save")
        tap("saveLabComparison")
        XCTAssertTrue(app.staticTexts["labComparisonSaved"].waitForExistence(timeout: 15)); snap("540-history-comparison-saved")
        tap("viewSavedLabComparison")
        let captured = app.staticTexts["capturedLabDifference"].firstMatch; reveal(captured); XCTAssertEqual(captured.label, "6.5"); snap("541-history-saved-snapshot")
        let sharing = app.switches["Use in assistant"].firstMatch; reveal(sharing); XCTAssertEqual(sharing.value as? String, "0", "A newly saved comparison starts with sharing off")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library")
        let saved = app.buttons["Lab comparison · 2026-01-20 to 2026-10-20"].firstMatch; reveal(saved); saved.tap()
        reveal(captured); XCTAssertEqual(captured.label, "6.5"); snap("542-history-relaunched-snapshot")
        let value = app.staticTexts["capturedLabValue-" + historyPoint("history-earlier")].firstMatch; reveal(value); XCTAssertEqual(value.label, "12.00")
        let source = app.buttons["historySourceDisclosure-" + historyPoint("history-earlier")].firstMatch; reveal(source); source.tap()
        // SwiftUI can propagate a DisclosureGroup identifier to its contents.
        // Assert the exact visible source wording rather than a descendant ID.
        let savedExcerpt = app.staticTexts[earlierHistorySource].firstMatch
        revealLabExcerpt(savedExcerpt); XCTAssertEqual(savedExcerpt.label, earlierHistorySource); snap("543-history-saved-full-source")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        openLabRecord("Synthetic report · history-earlier"); tap("Document actions"); tap("Edit")
        let title = app.textFields["Document title"].firstMatch; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(" corrected")
        tap("Save"); app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        let comparisonTitle = "Lab comparison · 2026-01-20 to 2026-10-20"
        let comparisonRecord = app.buttons[comparisonTitle].firstMatch; reveal(comparisonRecord); comparisonRecord.tap()
        let changedSource = app.staticTexts["Source record changed after this capture"].firstMatch; reveal(changedSource); snap("544-history-original-renamed")
        XCTAssertEqual(value.label, "12.00")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        openLabRecord("Synthetic report · history-later"); tap("Document actions"); tap("Delete"); tap("Delete")
        reveal(comparisonRecord); comparisonRecord.tap()
        let removedSource = app.staticTexts["Source record removed; this captured copy remains"].firstMatch; reveal(removedSource); snap("545-history-original-removed")
        XCTAssertEqual(app.staticTexts["capturedLabValue-" + historyPoint("history-later")].firstMatch.label, "18.50")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); reveal(comparisonRecord); comparisonRecord.tap()
        reveal(removedSource); XCTAssertTrue(removedSource.exists); snap("546-history-removed-source-relaunch")
    }

    func testLabHistoryPresentation() throws {
        try prepareHistoryFixture(arguments: ["-lumen.appearance", "dark"])
        openHistoryRecords(["history-earlier", "history-later"]); openFirstHistoryGroup(); tap("historyDecimal-dot")
        let plot = historyPlot()
        revealLabExcerpt(plot); snap("547-history-dark-plot")
        selectHistoryResult("history-later"); selectHistoryResult("history-earlier"); tap("compareLabHistoryResults")
        let difference = app.staticTexts["labComparisonDifference"].firstMatch; reveal(difference); XCTAssertEqual(difference.label, "6.5"); snap("548-history-dark-comparison")
        let comma = app.buttons["historyDecimal-comma"].firstMatch; reveal(comma); comma.tap()
        let literal = app.staticTexts["labComparisonNoArithmetic"].firstMatch; reveal(literal); snap("577-history-dark-decimal-wording")
        tap("cancelLabComparison")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); tab("Library")
        openHistoryRecords(["history-earlier", "history-later"]); openFirstHistoryGroup(); tap("historyDecimal-dot")
        revealLabExcerpt(plot); snap("549-history-xxxl-plot")
        selectHistoryResult("history-later"); selectHistoryResult("history-earlier"); tap("compareLabHistoryResults")
        reveal(difference); XCTAssertEqual(difference.label, "6.5"); snap("550-history-xxxl-comparison")
        nativeSwitch("acknowledgeLabComparison", enabled: true); snap("551-history-xxxl-review-action")
        tap("saveLabComparison"); XCTAssertTrue(app.staticTexts["labComparisonSaved"].waitForExistence(timeout: 15)); snap("552-history-xxxl-completion")
        let view = app.buttons["viewSavedLabComparison"].firstMatch; reveal(view); XCTAssertTrue(view.isHittable); snap("576-history-xxxl-completion-action"); view.tap()
        let value = app.staticTexts["capturedLabValue-" + historyPoint("history-earlier")].firstMatch; reveal(value); XCTAssertEqual(value.label, "12.00"); snap("553-history-xxxl-saved-literal")
        let source = app.buttons["historySourceDisclosure-" + historyPoint("history-earlier")].firstMatch; reveal(source); source.tap()
        let excerpt = app.staticTexts[earlierHistorySource].firstMatch; revealLabExcerpt(excerpt); XCTAssertEqual(excerpt.label, earlierHistorySource); snap("554-history-xxxl-exact-source")
    }

    func testLabHistoryLiteralContextsAndPaging() throws {
        try prepareHistoryFixture()
        openHistoryRecords(["history-imported", "history-imported-copy", "history-paged", "history-earlier", "history-other-lab", "history-qualitative"])
        let base = historyIdentity(["Ferritin", "µg/L", "Synthetic laboratory", "Serum", "Synthetic assay", "Final"])
        let other = historyIdentity(["Ferritin", "µg/L", "Other synthetic laboratory", "Serum", "Synthetic assay", "Final"])
        let baseGroup = app.buttons["history-group-" + base].firstMatch; reveal(baseGroup); baseGroup.tap(); selectHistoryResult("history-earlier"); tap("historyAllTests")
        let otherGroup = app.buttons["history-group-" + other].firstMatch; reveal(otherGroup); otherGroup.tap(); selectHistoryResult("history-other-lab"); tap("compareLabHistoryResults")
        tap("historyDecimal-dot")
        let unavailable = app.staticTexts["labComparisonNoArithmetic"].firstMatch; reveal(unavailable); XCTAssertTrue(unavailable.exists); snap("555-history-different-laboratories")
        nativeSwitch("acknowledgeLabComparison", enabled: true); XCTAssertTrue(app.buttons["saveLabComparison"].isEnabled)
        tap("cancelLabComparison"); tap("historyClearComparedResults"); tap("historyAllTests")
        let pcr = historyIdentity(["PCR", "", "", "", "", ""])
        let pcrGroup = app.buttons["history-group-" + pcr].firstMatch; reveal(pcrGroup); pcrGroup.tap(); tap("historyDecimal-literal")
        let wording = app.staticTexts["historyValue-" + historyPoint("history-qualitative")].firstMatch; reveal(wording); XCTAssertEqual(wording.label, "Not detected"); snap("556-history-qualitative-wording-only")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "labHistoryNumericPlot").firstMatch.exists)
        tap("historyAllTests")
        let paged = historyIdentity(["Paged synthetic test", "mg/L", "Synthetic laboratory", "Serum", "Synthetic assay", "Final"])
        let pagedGroup = app.buttons["history-group-" + paged].firstMatch; reveal(pagedGroup); pagedGroup.tap(); tap("historyDecimal-literal")
        let next = app.buttons["historyNextPage"].firstMatch; reveal(next); XCTAssertTrue(next.isEnabled); snap("557-history-page-one-complete")
        var reported = Dictionary(uniqueKeysWithValues: app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'historyValue-'")).allElementsBoundByIndex.map { ($0.identifier, $0.label) })
        XCTAssertEqual(reported.count, 20); next.tap()
        // Equal-day history is explicitly unordered within its day. Paging
        // follows stable result IDs, so check the complete page count rather
        // than assuming source-row 21 is the last displayed result.
        let pageCount = app.staticTexts["labHistoryPageCount"].firstMatch; reveal(pageCount); XCTAssertEqual(pageCount.label, "21–21 of 21"); snap("558-history-last-page")
        XCTAssertFalse(next.isEnabled); XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'historyValue-'")).count, 1)
        for value in app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'historyValue-'")).allElementsBoundByIndex { XCTAssertNil(reported[value.identifier]); reported[value.identifier] = value.label }
        XCTAssertEqual(reported.count, 21)
        for row in 1...21 { XCTAssertEqual(reported["historyValue-" + historyIdentity(["history-paged", "history-paged-\(row)"])], "\(row).00") }
        let previous = app.buttons["historyPreviousPage"].firstMatch; previous.tap(); reveal(pageCount); XCTAssertEqual(pageCount.label, "1–20 of 21")
        tap("historyAllTests")
        let copied = historyIdentity(["Synthetic copied cells", "µg/L", "Synthetic laboratory", "", "", ""])
        let copiedGroup = app.buttons["history-group-" + copied].firstMatch; reveal(copiedGroup); copiedGroup.tap(); tap("historyDecimal-dot")
        let duplicate = app.staticTexts["Selected records repeat the same imported cells. Choose one copy in the record selection."].firstMatch; reveal(duplicate); snap("559-history-duplicate-cells-block-plot")
        let blockedCoverage = app.staticTexts["labHistoryPlotCoverage"].firstMatch; reveal(blockedCoverage); XCTAssertTrue(blockedCoverage.label.hasPrefix("0 of 2 numeric results"))
        let selections = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'history-select-'")).allElementsBoundByIndex
        XCTAssertEqual(selections.count, 2)
        for button in selections { reveal(button); button.tap() }
        tap("compareLabHistoryResults"); nativeSwitch("acknowledgeLabComparison", enabled: true)
        XCTAssertFalse(app.buttons["saveLabComparison"].isEnabled); snap("560-history-duplicate-comparison-blocked"); tap("cancelLabComparison")
    }

    func testLabHistorySmallScreen() throws {
        XCTAssertEqual(app.frame.width, 375); XCTAssertEqual(app.frame.height, 667)
        try prepareHistoryFixture(arguments: ["-lumen.appearance", "light"])
        openHistoryRecords(["history-earlier", "history-later"]); openFirstHistoryGroup()
        let allTests = app.buttons["historyAllTests"].firstMatch; reveal(allTests); snap("575-history-all-tests-return")
        tap("historyDecimal-dot")
        let plot = historyPlot(); revealLabExcerpt(plot); snap("563-history-compact-plot")
        selectHistoryResult("history-later")
        XCTAssertEqual(app.staticTexts["historyComparisonSelectionState"].label, "1 of 2 selected"); snap("564-history-compact-one-selection")
        selectHistoryResult("history-earlier"); tap("compareLabHistoryResults")
        let difference = app.staticTexts["labComparisonDifference"].firstMatch; reveal(difference); XCTAssertEqual(difference.label, "6.5"); snap("565-history-compact-review")
        nativeSwitch("acknowledgeLabComparison", enabled: true); snap("566-history-compact-acknowledgement")
        tap("saveLabComparison"); XCTAssertTrue(app.staticTexts["labComparisonSaved"].waitForExistence(timeout: 15)); snap("567-history-compact-completion")
        let view = app.buttons["viewSavedLabComparison"].firstMatch; reveal(view); view.tap()
        let source = app.buttons["historySourceDisclosure-" + historyPoint("history-earlier")].firstMatch; reveal(source); source.tap()
        let excerpt = app.staticTexts[earlierHistorySource].firstMatch; revealLabExcerpt(excerpt); XCTAssertEqual(excerpt.label, earlierHistorySource); snap("568-history-compact-exact-source")
        let sharing = app.switches["Use in assistant"].firstMatch; reveal(sharing); XCTAssertEqual(sharing.value as? String, "0")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", "light"]; app.launch(); tab("Library")
        let saved = app.buttons["Lab comparison · 2026-01-20 to 2026-10-20"].firstMatch; reveal(saved); saved.tap()
        let captured = app.staticTexts["capturedLabDifference"].firstMatch; reveal(captured); XCTAssertEqual(captured.label, "6.5"); snap("569-history-compact-relaunched")
    }

    func testLabHistoryEditedSnapshot() throws {
        try prepareHistoryFixture(fixture: "Lumen-backup-captured-comparison")
        let document = app.buttons["Restored synthetic comparison"].firstMatch; reveal(document); document.tap()
        let captured = app.staticTexts["capturedLabDifference"].firstMatch; reveal(captured); XCTAssertEqual(captured.label, "6.5")
        tap("Document actions"); tap("Edit")
        let notes = "My separately edited comparison notes. No current lab measurement is recorded here."
        let body = app.textViews.firstMatch; reveal(body); body.tap(); body.typeKey("a", modifierFlags: .command); body.typeText(notes)
        XCTAssertEqual(body.value as? String, notes); tap("Save")
        let edited = app.staticTexts["labComparisonEditedText"].firstMatch; reveal(edited)
        XCTAssertFalse(captured.exists, "Earlier arithmetic stays inside the separately labelled historical disclosure")
        let currentText = app.staticTexts[notes].firstMatch; reveal(currentText); XCTAssertEqual(currentText.label, notes); snap("570-history-edited-current-text")
        let earlier = app.buttons["Earlier captured comparison"].firstMatch; reveal(earlier); earlier.tap()
        reveal(captured); XCTAssertEqual(captured.label, "6.5"); snap("571-history-earlier-captured-facts")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); reveal(document); document.tap()
        reveal(edited); XCTAssertTrue(edited.exists); XCTAssertFalse(captured.exists)
        reveal(currentText); XCTAssertEqual(currentText.label, notes); snap("572-history-edited-snapshot-relaunch")
        let sharing = app.switches["Use in assistant"].firstMatch; reveal(sharing); XCTAssertEqual(sharing.value as? String, "0")
    }

    func testLabHistoryChangedSourceDraft() throws {
        try prepareHistoryFixture()
        openHistoryRecords(["history-earlier", "history-later"]); openFirstHistoryGroup(); tap("historyDecimal-dot")
        selectHistoryResult("history-later"); selectHistoryResult("history-earlier"); tap("compareLabHistoryResults")
        nativeSwitch("acknowledgeLabComparison", enabled: true); XCTAssertTrue(app.buttons["saveLabComparison"].isEnabled)
        let original = app.buttons["comparisonOpenSource-" + historyPoint("history-earlier")].firstMatch; reveal(original); original.tap()
        tap("Document actions"); tap("Edit")
        let title = app.textFields["Document title"].firstMatch; XCTAssertTrue(title.waitForExistence(timeout: 5)); title.tap(); title.typeText(" corrected while reviewing")
        tap("Save"); app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        let changed = app.staticTexts["labComparisonSourceChanged"].firstMatch; reveal(changed)
        XCTAssertFalse(app.buttons["saveLabComparison"].isEnabled); snap("573-history-source-change-blocks-draft")
        nativeSwitch("acknowledgeLabComparison", enabled: true); XCTAssertFalse(app.buttons["saveLabComparison"].isEnabled)
        tap("cancelLabComparison")
        let status = app.staticTexts["labHistorySourceStatus"].firstMatch; reveal(status); snap("574-history-refresh-requires-person-check")
        XCTAssertTrue(status.label.contains("Check the intended person"))
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library")
        XCTAssertFalse(app.buttons["Lab comparison · 2026-01-20 to 2026-10-20"].exists, "The source-changed draft has not created a saved comparison")
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

    func reveal(_ element: XCUIElement, towardsTop: Bool = false) {
        for _ in 0..<32 {
            let targetIdentifier = element.exists ? element.identifier : ""
            let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
            let composerVisible = input.exists && input.isHittable && targetIdentifier != "coachInput"
            let contextBar = app.navigationBars["Personal context"].firstMatch
            let personalContext = contextBar.exists && contextBar.isHittable
            let navigation = personalContext ? contextBar : app.navigationBars.firstMatch
            let top = navigation.exists ? navigation.frame.maxY + 16 : 130
            let bar = app.tabBars.firstMatch
            var bottom = composerVisible ? input.frame.minY - 20 : (bar.exists && bar.isHittable ? bar.frame.minY - 12 : app.frame.maxY - 40)
            // Lab history's comparison inset sits above the tab bar. Start
            // scrolling in content, clear of both fixed action rows.
            for identifier in ["compareLabHistoryResults", "historyClearComparedResults"] where targetIdentifier != identifier {
                let action = app.buttons[identifier].firstMatch
                // A sheet can keep the background history's AX nodes. Reserve
                // only the front screen's footer; Clear remains available even
                // when a comparison is blocked.
                if action.exists && action.isHittable && !action.frame.isEmpty && action.frame.minY > top && action.frame.minY < bottom { bottom = min(bottom, action.frame.minY - 12) }
            }
            let selectionStatus = app.staticTexts["historyComparisonSelectionState"].firstMatch
            if selectionStatus.exists && selectionStatus.isHittable && !selectionStatus.frame.isEmpty && selectionStatus.frame.minY > top && selectionStatus.frame.minY < bottom { bottom = min(bottom, selectionStatus.frame.minY - 12) }
            if app.keyboards.firstMatch.exists {
                bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 12)
                for identifier in ["SystemInputAssistantView", "inputView"] {
                    let accessory = app.otherElements[identifier].firstMatch
                    if accessory.exists && !accessory.frame.isEmpty { bottom = min(bottom, accessory.frame.minY - 12) }
                }
            }
            // Native controls may report hittable while their centre is behind
            // a modal navigation bar. Check the actual visible content region.
            if element.exists && element.isHittable && element.frame.midY > top && element.frame.midY < bottom { return }
            // Lazy stacks can remove the target from the accessibility tree.
            // A known earlier row then needs an explicit search direction.
            let down = element.exists ? element.frame.midY < (top + bottom) / 2 : towardsTop
            // Use the actual content gutter. A whole-app swipe can start on
            // navigation or selectable text instead of moving the scroll view.
            // The inset personal-context form can leave the outer gutter
            // outside its scrolling hit region. Pan inside this form; keep
            // the existing gutter path for selectable Library readers.
            let x = personalContext ? app.frame.maxX - 24 : 10
            let lower = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: bottom - 8))
            let upper = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: top + 8))
            if down { upper.press(forDuration: 0.05, thenDragTo: lower) }
            else { lower.press(forDuration: 0.05, thenDragTo: upper) }
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

    func finishOnboarding(reminderAction: (() -> Void)? = nil) {
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
        snap("07-reminders")
        if let reminderAction { reminderAction() } else { tap("Maybe later") }
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
        XCTAssertFalse(userMessages.firstMatch.exists); XCTAssertFalse(coachMessages.firstMatch.exists); snap("305-voice-unsent-draft")
        tap("coachSend")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(userMessages.count, 1)
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
        XCTAssertFalse(userMessages.firstMatch.exists)
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
    func conversationControl(_ path: String = "/counts") throws -> Data {
        final class Response: @unchecked Sendable {
            private let lock = NSLock()
            private var result: Result<Data, Error>?
            func store(_ value: Result<Data, Error>) { lock.lock(); defer { lock.unlock() }; result = value }
            func read() throws -> Data { lock.lock(); defer { lock.unlock() }; return try XCTUnwrap(result).get() }
        }
        let response = Response(), completed = XCTestExpectation(description: "Loopback request counts")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        session.dataTask(with: URL(string: "http://127.0.0.1:48731" + path)!) { data, reply, error in
            if let error { response.store(.failure(error)) }
            else if let data, [200, 204].contains((reply as? HTTPURLResponse)?.statusCode ?? 0) { response.store(.success(data)) }
            else { response.store(.failure(URLError(.badServerResponse))) }
            completed.fulfill()
        }.resume()
        guard XCTWaiter.wait(for: [completed], timeout: 15) == .completed else { throw URLError(.timedOut) }
        return try response.read()
    }

    func conversationRouteCounts(_ route: String) throws -> [String: Int] {
        let counts = try XCTUnwrap(JSONSerialization.jsonObject(with: conversationControl()) as? [String: [String: Int]])
        return counts[route] ?? [:]
    }

    func conversationRequestCount() throws -> Int {
        let counts = try conversationRouteCounts("native-stop")
        return counts["requests"] ?? 0
    }

    func armHeldConversation() throws -> Int {
        _ = try conversationControl("/arm-held")
        return try conversationRouteCounts("native-held")["requests"] ?? 0
    }

    func waitForHeldConversation(_ expected: Int, completed: Bool = false, route: String = "native-held") throws {
        for _ in 0..<40 {
            let counts = try conversationRouteCounts(route)
            XCTAssertEqual(counts["holdTimeouts"] ?? 0, 0, "The response must remain explicitly controlled")
            let value = completed ? (counts["responsesWritten"] ?? 0) + (counts["clientDisconnected"] ?? 0) : counts["requests"] ?? 0
            if value == expected { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("Controlled conversation request did not reach its expected state")
        throw URLError(.timedOut)
    }

    func relaunchConversations(large: Bool) {
        app.terminate()
        app.launchArguments = ["-lumen.appearance", large ? "dark" : "light"]
            + (large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launch()
    }

    func captureConversationChoice(_ prefix: String, title: String, large: Bool) {
        let removal = app.scrollViews["conversationRemovalBody"].firstMatch
        if !app.alerts.firstMatch.exists && removal.exists {
            let retained = app.descendants(matching: .any).matching(identifier: "conversationRemovalRetained").firstMatch
            let action = title.hasPrefix("Delete") ? "Delete" : "Clear"
            let bar = app.navigationBars[action == "Delete" ? "Delete chat?" : "Clear chat?"]
            XCTAssertTrue(bar.exists && retained.exists)
            var reachedEnd = false
            for step in 0..<20 {
                snap(prefix + "-body-\(step)")
                let frame = removal.frame
                let top = max(frame.minY + 8, bar.frame.maxY + 8)
                let bottom = frame.maxY - 8
                let viewport = CGRect(x: frame.minX, y: top, width: frame.width, height: bottom - top)
                if retained.isHittable && viewport.contains(retained.frame) { reachedEnd = true; break }
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.minX + 10, dy: bottom - 20))
                let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.minX + 10, dy: max(top + 20, bottom - 200)))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            }
            XCTAssertTrue(reachedEnd, "Capture the complete retained-data assurance before accepting the removal warning")
            for label in ["Cancel", action] {
                let button = bar.buttons[label]
                XCTAssertTrue(button.isHittable && app.frame.insetBy(dx: -0.5, dy: -0.5).contains(button.frame))
            }
            return
        }
        if !large { snap(prefix); return }
        let alert = app.alerts.firstMatch
        let sheet = app.sheets.firstMatch
        let container = alert.exists ? alert : sheet
        XCTAssertTrue(container.waitForExistence(timeout: 5), "Identify the native confirmation before claiming complete content/action capture")
        XCTAssertTrue(container.staticTexts[title].exists || container.label == title,
                      "Capture the intended native choice, not its background sheet")
        capturePreferenceAlert(container, prefix: prefix)
    }

    func capturePendingConversationReply(_ prefix: String) {
        captureConversationSection(heading: "unsavedConversationReply", action: "retryConversationReply", prefix: prefix)
    }

    func captureConversationSection(heading headingID: String, action actionID: String, prefix: String) {
        let heading = app.descendants(matching: .any).matching(identifier: headingID).firstMatch
        let retry = app.buttons[actionID].firstMatch
        XCTAssertTrue(heading.exists && retry.exists)
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.exists)
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        let top = max(app.navigationBars["Assistant"].frame.maxY + 8, scroll.frame.minY + 8)
        // At XXXL the mic is bottom-aligned in a much taller composer. Its
        // top is inside the composer, not the end of scrollable content.
        let bottom = min(scroll.frame.maxY - 8, input.frame.minY - 20)
        XCTAssertGreaterThan(bottom - top, 120)
        snap(prefix + "-before-position")
        func drag(up: Bool, distance: CGFloat) {
            let y = up ? bottom - 12 : top + 12
            let x = app.frame.minX + 10
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y + (up ? -distance : distance)))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        for _ in 0..<24 {
            let y = heading.frame.minY
            if y >= top && heading.frame.maxY <= bottom { break }
            drag(up: y > top, distance: max(32, min(180, abs(y - top))))
        }
        XCTAssertGreaterThanOrEqual(heading.frame.minY, top - 1, "Start the retained packet with its complete unsaved heading")
        for step in 0..<20 {
            print("PENDING REPLY SWEEP", prefix, "step", step, "viewport", top, bottom, "scroll", scroll.frame, "heading", heading.frame, "retry", retry.frame)
            snap(prefix + "-segment-\(step)")
            if retry.frame.minY >= top && retry.frame.maxY <= bottom && retry.isHittable { return }
            drag(up: true, distance: min(180, bottom - top - 40))
        }
        XCTFail("Complete conversation section/action sweep was not reached")
    }

    func enterConversationQuestion(_ text: String) {
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10)); input.tap(); input.typeText(text)
        XCTAssertTrue(app.buttons["coachSend"].isEnabled); tap("coachSend")
    }

    func openConversationClearControl() {
        tab("Today"); tap("Settings")
        let clear = app.buttons["Clear coach conversation"].firstMatch
        reveal(clear); clear.tap()
    }

    func replaceConversationTitle(_ field: XCUIElement, large: Bool) {
        let replacement = "Conversation reliability check updated"
        if !large { replaceAmount(field, with: replacement); return }
        reveal(field); field.tap()
        print("RENAME WAITING FOR SOFTWARE KEYBOARD BEFORE TITLE EDIT")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 60))
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let button = app.buttons["Select All"].firstMatch, menu = app.menuItems["Select All"].firstMatch
        if !(button.exists || menu.exists) { field.press(forDuration: 1) }
        // At XXXL the native edit menu has one item per page. Its real paging
        // controls must be followed instead of treating an off-page item as absent.
        for page in 0..<8 {
            snap("1032-rename-native-selection-menu-page-\(page)")
            if (button.exists && button.isHittable) || (menu.exists && menu.isHittable) { break }
            let next = app.buttons["Next Page"].firstMatch
            guard next.exists && next.isEnabled && next.isHittable else { break }
            next.tap()
        }
        let selectAll = button.exists && button.isHittable ? button : menu
        XCTAssertTrue(selectAll.exists && selectAll.isHittable, "Reach Select All through the native paged edit menu")
        selectAll.tap(); field.typeText(replacement)
        XCTAssertEqual(field.value as? String, replacement)
    }

    func testConversationQuestionSaveFailure() throws { try conversationQuestionSaveFailure(large: false) }
    func testConversationQuestionMirrorFailure() throws { try conversationQuestionSaveFailure(large: false, fault: "chat.json:2") }

    func testConversationCountGrammar() throws {
        for count in 0...2 {
            quickFault("none:0", extra: ["-conversation-startup-fixture", "counts", "-conversation-count", String(count)])
            tab("Assistant"); tap("Conversation history")
            let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation-' "))
            if count == 0 { XCTAssertEqual(rows.count, 0) }
            else {
                XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
                XCTAssertTrue(rows.firstMatch.label.contains("\(count) \(count == 1 ? "message" : "messages") ·"))
                XCTAssertFalse(rows.firstMatch.label.contains("1 messages"))
            }
            snap("1072-history-count-\(count)"); tap("Done")
            if count > 0 { tap("Conversation actions"); tap("New conversation") }
            let summary = app.staticTexts["conversationContextCounts"].firstMatch
            XCTAssertTrue(summary.waitForExistence(timeout: 10))
            XCTAssertEqual(summary.label, "0 ongoing symptom logs · \(count) shared \(count == 1 ? "record" : "records")")
            snap("1071-shared-count-\(count)")
        }
    }

    func testConversationStartupCorruptLarge() throws {
        quickFault("none:0", large: true, extra: ["-conversation-startup-fixture", "corrupt"]); tab("Assistant")
        XCTAssertTrue(app.staticTexts["conversationStorageIssue"].waitForExistence(timeout: 10))
        captureConversationSection(heading: "conversationStorageIssue", action: "retryOpeningConversations", prefix: "1068-startup-complete-explanation")
        tap("retryOpeningConversations")
        XCTAssertTrue(app.staticTexts["conversationStorageIssue"].waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.count, 0); XCTAssertFalse(app.buttons["coachSend"].isEnabled)
    }

    func testConversationStartupCorrupt() throws { try conversationStartupUnavailable(mode: "corrupt") }
    func testConversationStartupUnreadable() throws { try conversationStartupUnavailable(mode: "unreadable") }
    func conversationStartupUnavailable(mode: String) throws {
        quickFault("none:0", extra: ["-conversation-startup-fixture", mode]); tab("Assistant")
        let issue = app.staticTexts["conversationStorageIssue"]
        XCTAssertTrue(issue.waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.count, 0); XCTAssertEqual(coachMessages.count, 0)
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("Synthetic unsent draft")
        XCTAssertFalse(app.buttons["coachSend"].isEnabled)
        let retry = app.buttons["retryOpeningConversations"].firstMatch
        retry.tap(); XCTAssertTrue(issue.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "Synthetic unsent draft")
        XCTAssertFalse(app.buttons["coachSend"].isEnabled); snap("1036-startup-" + mode)
        relaunchConversations(large: false); tab("Assistant")
        XCTAssertTrue(issue.waitForExistence(timeout: 10)); XCTAssertEqual(userMessages.count, 0)
        snap("1037-startup-" + mode + "-relaunch")
    }

    func testConversationStartupLegacyRetry() throws {
        quickFault("conversations.json:1", extra: ["-conversation-startup-fixture", "legacy"]); tab("Assistant")
        XCTAssertTrue(app.staticTexts["conversationStorageIssue"].waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.count, 0); snap("1038-migration-save-failed")
        tap("retryOpeningConversations")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.firstMatch.label, "Synthetic saved question\nCafé · 12,5 µg/L")
        XCTAssertEqual(userMessages.count, 1); snap("1039-migration-retry")
        relaunchConversations(large: false); tab("Assistant")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(userMessages.firstMatch.label, "Synthetic saved question\nCafé · 12,5 µg/L"); snap("1040-migration-relaunch")
    }

    func testConversationStartupEmptyArchive() throws {
        quickFault("none:0", large: true, extra: ["-conversation-startup-fixture", "empty"]); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.count, 0); snap("1041-empty-archive-stale-mirror")
        relaunchConversations(large: true); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.count, 0); tap("Conversation history")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation-' ")).count, 0)
        snap("1042-empty-archive-relaunch-history")
    }

    func testConversationHistoryNewFailureLarge() throws {
        quickFault("conversations.json:1", large: true, extra: ["-conversation-startup-fixture", "saved"]); tab("Assistant")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10)); tap("Conversation history"); tap("New conversation")
        let alert = app.alerts["Couldn’t start conversation"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        captureConversationChoice("1043-history-new-failed", title: "Couldn’t start conversation", large: true)
        alert.buttons["Keep"].tap()
        XCTAssertTrue(app.buttons["conversation-synthetic-startup-conversation-39"].exists)
        tap("Done"); XCTAssertEqual(userMessages.count, 1)
        tap("Conversation history"); tap("New conversation")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10)); XCTAssertEqual(userMessages.count, 0)
        relaunchConversations(large: true); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10)); snap("1044-history-new-relaunch")
    }

    func testConversationToolbarNewFailure() throws {
        quickFault("conversations.json:1", extra: ["-conversation-startup-fixture", "saved"]); tab("Assistant")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10)); tap("Conversation actions"); tap("New conversation")
        let alert = app.alerts["Couldn’t change conversation"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10)); snap("1045-toolbar-new-failed"); alert.buttons["OK"].tap()
        XCTAssertEqual(userMessages.count, 1)
        tap("Conversation actions"); tap("New conversation")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10)); XCTAssertEqual(userMessages.count, 0)
        relaunchConversations(large: false); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10)); snap("1046-toolbar-new-relaunch")
    }

    func testConversationSelectionFailure() throws {
        quickFault("conversations.json:2", extra: ["-conversation-startup-fixture", "saved"]); tab("Assistant")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10)); tap("Conversation actions"); tap("New conversation")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("Synthetic independent draft")
        tap("Conversation history"); tap("conversation-synthetic-startup-conversation-39")
        let alert = app.alerts["Couldn’t open conversation"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10)); snap("1047-selection-failed"); alert.buttons["Keep"].tap()
        tap("Done"); XCTAssertEqual(userMessages.count, 0)
        XCTAssertEqual(input.value as? String, "Synthetic independent draft"); snap("1048-selection-draft-kept")
        tap("Conversation history"); tap("conversation-synthetic-startup-conversation-39")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "Synthetic independent draft")
        relaunchConversations(large: false); tab("Assistant")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.firstMatch.label, "Synthetic saved question\nCafé · 12,5 µg/L"); snap("1049-selection-relaunch")
    }

    func testConversationStaleRenameLarge() throws {
        quickFault("none:0", large: true, extra: ["-conversation-startup-fixture", "saved", "-conversation-rename-change"]); tab("Assistant")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10)); tap("Conversation history")
        let row = app.buttons["conversation-synthetic-startup-conversation-39"]
        row.press(forDuration: 1); tap("Rename")
        let title = app.descendants(matching: .any).matching(identifier: "conversationTitleDraft").firstMatch
        replaceConversationTitle(title, large: true); tap("Save")
        let failure = app.staticTexts["conversationRenameFailure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 10)); XCTAssertTrue(failure.label.contains("saved title changed"))
        XCTAssertEqual(title.value as? String, "Conversation reliability check updated")
        capturePreferenceDisclosure("conversationRenameFailure", prefix: "1060-stale-rename-explanation", navigationTitle: "Rename")
        tap("Cancel"); XCTAssertTrue(row.label.contains("Synthetic external title change")); snap("1061-newer-title-kept")
        tap("Done"); relaunchConversations(large: true); tab("Assistant"); tap("Conversation history")
        XCTAssertTrue(row.waitForExistence(timeout: 10)); XCTAssertTrue(row.label.contains("Synthetic external title change"))
        row.tap(); XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.firstMatch.label, "Synthetic saved question\nCafé · 12,5 µg/L"); snap("1062-stale-rename-relaunch")
    }

    func testConversationPreparedSaveKeepsNewTyping() throws {
        quickFault("none:0", extra: ["-conversation-startup-fixture", "saved", "-conversation-preparation-ui-hold", "-providerTransportUITestMode"]); tab("Assistant")
        _ = try conversationControl("/arm-prepared")
        let before = try conversationRouteCounts("prepared-stage")["requests"] ?? 0
        let beforeProvider = try conversationRequestCount()
        enterConversationQuestion("Complete HTTP control")
        try waitForHeldConversation(before + 1, route: "prepared-stage")
        XCTAssertEqual(userMessages.count, 1); XCTAssertEqual(try conversationRequestCount(), beforeProvider)
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        XCTAssertEqual(input.value as? String, "Complete HTTP control")
        replaceAmount(input, with: "Independent next draft")
        snap("1063-new-draft-before-prepared-commit")
        _ = try conversationControl("/release-prepared")
        try waitForHeldConversation(before + 1, completed: true, route: "prepared-stage")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(userMessages.count, 2); XCTAssertEqual(userMessages.element(boundBy: 1).label, "Complete HTTP control")
        XCTAssertEqual(input.value as? String, "Independent next draft")
        XCTAssertEqual(try conversationRequestCount(), beforeProvider + 1); XCTAssertTrue(app.buttons["coachSend"].isEnabled)
        snap("1064-new-draft-after-prepared-commit")
    }

    func testConversationHeldDelete() throws { try conversationHeldRemoval(clear: false) }
    func testConversationHeldClear() throws { try conversationHeldRemoval(clear: true) }
    func conversationHeldRemoval(clear: Bool) throws {
        quickFault("none:0", extra: ["-conversation-startup-fixture", "saved", "-providerTransportUITestMode"]); tab("Assistant")
        let before = try armHeldConversation()
        enterConversationQuestion("Held HTTP control")
        try waitForHeldConversation(before + 1)
        XCTAssertTrue(app.buttons["Stop response"].exists)
        if clear {
            openConversationClearControl(); tap("Clear")
            XCTAssertTrue(app.buttons["Clear coach conversation"].waitForNonExistence(timeout: 10))
            tap("Done"); tab("Assistant")
        } else {
            tap("Conversation history")
            let row = app.buttons["conversation-synthetic-startup-conversation-39"]
            row.press(forDuration: 1); tap("Delete"); tap("Delete")
            XCTAssertTrue(row.waitForNonExistence(timeout: 10)); tap("Done")
        }
        XCTAssertTrue(app.buttons["Stop response"].waitForNonExistence(timeout: 10), "Removing the origin must cancel its running request")
        XCTAssertEqual(userMessages.count, 0)
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("Independent next draft")
        XCTAssertTrue(app.buttons["coachSend"].isEnabled, "Send must recover before the held response is released")
        snap(clear ? "1050-clear-cancelled-held-request" : "1051-delete-cancelled-held-request")
        _ = try conversationControl("/release-held"); try waitForHeldConversation(before + 1, completed: true)
        XCTAssertFalse(coachMessages.firstMatch.waitForExistence(timeout: 3)); XCTAssertEqual(userMessages.count, 0)
        XCTAssertEqual(input.value as? String, "Independent next draft")
        relaunchConversations(large: false); tab("Assistant")
        XCTAssertEqual(userMessages.count, 0); XCTAssertEqual(coachMessages.count, 0)
        snap(clear ? "1052-clear-late-response-relaunch" : "1053-delete-late-response-relaunch")
    }

    func testConversationHeldStopAndNewTyping() throws {
        quickFault("none:0", extra: ["-conversation-startup-fixture", "saved", "-providerTransportUITestMode"]); tab("Assistant")
        let before = try armHeldConversation(), beforeComplete = try conversationRequestCount()
        enterConversationQuestion("Held HTTP control"); try waitForHeldConversation(before + 1)
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("Complete HTTP control")
        XCTAssertFalse(app.buttons["coachSend"].isEnabled); tap("Stop response")
        XCTAssertTrue(app.buttons["Stop response"].waitForNonExistence(timeout: 10))
        XCTAssertEqual(input.value as? String, "Complete HTTP control"); XCTAssertTrue(app.buttons["coachSend"].isEnabled)
        snap("1054-stopped-request-keeps-next-question"); tap("coachSend")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 30)); XCTAssertEqual(coachMessages.count, 1)
        _ = try conversationControl("/release-held"); try waitForHeldConversation(before + 1, completed: true)
        XCTAssertEqual(try conversationRequestCount(), beforeComplete + 1)
        relaunchConversations(large: false); tab("Assistant")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(coachMessages.count, 1); XCTAssertEqual(userMessages.count, 3); snap("1055-new-question-outlives-stopped-response")
    }

    func testConversationHeldResetFresh() throws {
        // Run only on the newly created, Lumen-only synthetic compact device.
        quickFault("none:0", extra: ["-conversation-startup-fixture", "saved", "-providerTransportUITestMode"]); tab("Assistant")
        let before = try armHeldConversation()
        enterConversationQuestion("Held HTTP control"); try waitForHeldConversation(before + 1)
        tab("Today"); tap("Settings")
        let erase = app.buttons["Erase all data"].firstMatch; reveal(erase); erase.tap(); tap("Erase everything")
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 10))
        _ = try conversationControl("/release-held"); try waitForHeldConversation(before + 1, completed: true)
        snap("1065-reset-before-late-response")
        finishOnboarding(); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.count, 0); XCTAssertEqual(coachMessages.count, 0)
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("Fresh after reset"); XCTAssertTrue(app.buttons["coachSend"].isEnabled)
        relaunchConversations(large: false); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["conversationStorageIssue"].exists)
        input.tap(); input.typeText("Fresh after relaunch"); XCTAssertTrue(app.buttons["coachSend"].isEnabled)
        XCTAssertEqual(userMessages.count, 0); XCTAssertEqual(coachMessages.count, 0); snap("1066-reset-late-response-relaunch")
    }

    func testConversationHeldRestore() throws {
        quickFault("none:0", extra: ["-conversation-startup-fixture", "restore", "-providerTransportUITestMode"]); tab("Assistant")
        let before = try armHeldConversation()
        enterConversationQuestion("Held HTTP control"); try waitForHeldConversation(before + 1)
        let heldAt = Date()
        openBackupSettings(); unlockBackup(); _ = backupPreview()
        XCTAssertLessThan(Date().timeIntervalSince(heldAt), 50, "Restore must occur before the real request deadline")
        confirmBackupRestore()
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap(); tap("Done"); tab("Assistant")
        XCTAssertTrue(app.buttons["Stop response"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10))
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("Fresh after restore"); XCTAssertTrue(app.buttons["coachSend"].isEnabled)
        XCTAssertLessThan(Date().timeIntervalSince(heldAt), 55, "Cancellation must be proved before the 60-second timeout")
        _ = try conversationControl("/release-held"); try waitForHeldConversation(before + 1, completed: true)
        XCTAssertFalse(coachMessages.firstMatch.waitForExistence(timeout: 3)); XCTAssertEqual(input.value as? String, "Fresh after restore")
        tap("Conversation history")
        XCTAssertTrue(app.buttons["conversation-synthetic-restore-missing-39"].exists)
        tap("conversation-synthetic-startup-conversation-39")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(userMessages.count, 2); XCTAssertEqual(coachMessages.count, 0)
        relaunchConversations(large: false); tab("Assistant")
        XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(userMessages.count, 2); XCTAssertEqual(coachMessages.count, 0)
        snap("1067-restored-origin-rejects-late-response")
    }

    func testConversationRestoreDisclosureLarge() throws {
        quickFault("none:0", large: true, extra: ["-conversation-startup-fixture", "restore"])
        openBackupSettings(); unlockBackup(); _ = backupPreview()
        let restore = app.buttons["restoreBackup"].firstMatch; reveal(restore); restore.tap()
        let alert = app.alerts["Restore missing records?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        capturePreferenceAlert(alert, prefix: "1069-restore-reply-disclosure")
        alert.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["restoreBackup"].exists)
    }

    func testConversationHeldReferenceReplyRecovery() throws {
        quickFault("conversations.json:3", extra: ["-conversation-startup-fixture", "references", "-providerTransportUITestMode"]); tab("Assistant")
        let before = try armHeldConversation()
        enterConversationQuestion("Held HTTP control ferritin"); try waitForHeldConversation(before + 1)
        tap("Conversation actions"); tap("New conversation")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Stop response"].exists, "Navigation must preserve a request to its intact origin")
        _ = try conversationControl("/release-held"); try waitForHeldConversation(before + 1, completed: true)
        let failed = app.alerts["Couldn’t save reply"]
        XCTAssertTrue(failed.waitForExistence(timeout: 10)); failed.buttons["OK"].tap()
        let reopen = app.buttons["Open conversation"].firstMatch
        XCTAssertTrue(reopen.waitForExistence(timeout: 5)); snap("1056-pending-recovery-before-visibility-assertion"); XCTAssertTrue(reopen.isHittable)
        snap("1056-inactive-pending-recovery-visible"); reopen.tap()
        let pending = app.descendants(matching: .any).matching(identifier: "unsavedConversationReply").firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 10))
        let exactReply = coachMessages.firstMatch.label
        XCTAssertTrue(exactReply.contains("Synthetic complete HTTP control."))
        let provider = app.staticTexts["pendingReplyProvider"].firstMatch
        XCTAssertTrue(provider.exists); let exactProvider = provider.label
        capturePendingConversationReply("1057-pending-complete-packet")
        reveal(provider); snap("1057-pending-provider")
        openLibraryReference(); let exactReference = referenceExcerpt.label; snap("1057-pending-exact-reference"); tap("Done")
        let retry = app.buttons["retryConversationReply"].firstMatch; reveal(retry); retry.tap()
        XCTAssertTrue(pending.waitForNonExistence(timeout: 10)); XCTAssertEqual(coachMessages.firstMatch.label, exactReply)
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'savedReplyProvider-' ")).firstMatch.label, exactProvider)
        openLibraryReference(); XCTAssertEqual(referenceExcerpt.label, exactReference); snap("1057-retried-exact-reference"); tap("Done")
        XCTAssertEqual(try conversationRouteCounts("native-held")["requests"], before + 1)
        let save = app.buttons["Save to Library"].firstMatch; reveal(save); save.tap(); snap("1058-reference-rich-reply-saved")
        tap("Conversation history"); let row = app.buttons["conversation-synthetic-startup-conversation-39"]
        row.press(forDuration: 1); tap("Delete"); tap("Delete"); XCTAssertTrue(row.waitForNonExistence(timeout: 10)); tap("Done")
        tab("Library")
        let saved = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Synthetic complete HTTP control' ")).firstMatch; reveal(saved); saved.tap()
        XCTAssertTrue(app.navigationBars["Document"].waitForExistence(timeout: 10)); snap("1059-independent-library-copy-after-delete")
    }
    func testConversationQuestionSaveFailureLarge() throws { try conversationQuestionSaveFailure(large: true) }
    func conversationQuestionSaveFailure(large: Bool, fault: String = "conversations.json:2") throws {
        quickFault(fault, large: large, extra: ["-providerTransportUITestMode"]); tab("Assistant")
        let before = try conversationRequestCount()
        enterConversationQuestion("Complete HTTP control")
        let alert = app.alerts["Couldn’t save question"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10)); captureConversationChoice("1010-question-save-failed", title: "Couldn’t save question", large: large)
        XCTAssertEqual(userMessages.count, 0); XCTAssertEqual(coachMessages.count, 0)
        XCTAssertEqual(try conversationRequestCount(), before, "A failed user save must start no provider request")
        alert.buttons["OK"].tap()
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        XCTAssertEqual(input.value as? String, "Complete HTTP control"); snap("1011-question-draft-retained")
        tap("coachSend"); XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(userMessages.count, 1); XCTAssertEqual(try conversationRequestCount(), before + 1)
        snap("1012-question-retry-saved")
        relaunchConversations(large: large); tab("Assistant")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(userMessages.firstMatch.label, "Complete HTTP control"); snap("1013-question-relaunch")
    }

    func testConversationReplySaveFailure() throws { try conversationReplySaveFailure(large: false) }
    func testConversationReplySaveFailureLarge() throws { try conversationReplySaveFailure(large: true) }
    func conversationReplySaveFailure(large: Bool) throws {
        quickFault("conversations.json:3", large: large, extra: ["-providerTransportUITestMode"]); tab("Assistant")
        let before = try conversationRequestCount()
        enterConversationQuestion("Complete HTTP control")
        let alert = app.alerts["Couldn’t save reply"]
        XCTAssertTrue(alert.waitForExistence(timeout: 30)); captureConversationChoice("1014-reply-save-failed", title: "Couldn’t save reply", large: large)
        XCTAssertEqual(try conversationRequestCount(), before + 1)
        alert.buttons["OK"].tap()
        let unsaved = app.descendants(matching: .any).matching(identifier: "unsavedConversationReply").firstMatch
        XCTAssertTrue(unsaved.waitForExistence(timeout: 5))
        XCTAssertEqual(userMessages.count, 1)
        let exactReply = coachMessages.firstMatch.label
        if large { capturePendingConversationReply("1015-complete-pending-packet") }
        let retry = app.buttons["retryConversationReply"].firstMatch; reveal(retry)
        XCTAssertTrue(retry.isEnabled); snap("1015-reply-retained-before-retry"); retry.tap()
        XCTAssertTrue(unsaved.waitForNonExistence(timeout: 10))
        XCTAssertEqual(try conversationRequestCount(), before + 1, "Retry save must never call the provider again")
        XCTAssertEqual(coachMessages.count, 1); XCTAssertEqual(coachMessages.firstMatch.label, exactReply)
        snap("1016-reply-storage-retry")
        relaunchConversations(large: large); tab("Assistant")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(coachMessages.count, 1); XCTAssertEqual(coachMessages.firstMatch.label, exactReply)
        XCTAssertEqual(try conversationRequestCount(), before + 1); snap("1017-reply-relaunch")
    }

    func testConversationRenameFailureAndUnsentRelaunch() throws { try conversationRenameFailureAndUnsentRelaunch(large: false) }
    func testConversationRenameFailureAndUnsentRelaunchLarge() throws { try conversationRenameFailureAndUnsentRelaunch(large: true) }
    func conversationRenameFailureAndUnsentRelaunch(large: Bool) throws {
        quickFault("conversations.json:4", large: large); tab("Assistant")
        enterConversationQuestion("Conversation reliability check")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 30))
        tap("Conversation history")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation-' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); let savedID = row.identifier
        row.press(forDuration: 1); tap("Rename")
        let title = app.descendants(matching: .any).matching(identifier: "conversationTitleDraft").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["Rename"].exists)
        replaceConversationTitle(title, large: large)
        let key = app.keyboards.keys["x"].firstMatch
        print("RENAME WAITING FOR VISIBLE SOFTWARE X KEY", large ? "XXXL" : "normal")
        XCTAssertTrue(key.waitForExistence(timeout: 60) && key.isHittable); key.tap()
        XCTAssertEqual(title.value as? String, "Conversation reliability check updatedx")
        let delete = app.keyboards.keys["delete"].firstMatch
        XCTAssertTrue(delete.exists && delete.isHittable); delete.tap()
        XCTAssertEqual(title.value as? String, "Conversation reliability check updated")
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.frame.height > 100 && app.frame.insetBy(dx: -0.5, dy: -0.5).contains(keyboard.frame))
        print("RENAME VISIBLE KEYBOARD FRAME", keyboard.frame, "application", app.frame)
        snap("1034-rename-typed-keyboard"); tap("Save")
        let failure = app.staticTexts["conversationRenameFailure"]
        XCTAssertTrue(failure.waitForExistence(timeout: 10))
        if large { reveal(failure) }
        XCTAssertEqual(title.value as? String, "Conversation reliability check updated"); snap("1018-rename-draft-retained")
        tap("Save"); XCTAssertTrue(app.navigationBars["Rename"].waitForNonExistence(timeout: 10))
        XCTAssertTrue(app.buttons[savedID].label.contains("Conversation reliability check updated")); snap("1019-rename-saved")
        tap("New conversation")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10))
        relaunchConversations(large: large); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10)); XCTAssertEqual(userMessages.count, 0)
        snap("1020-unsent-selection-relaunch"); tap("Conversation history")
        XCTAssertTrue(app.buttons[savedID].waitForExistence(timeout: 10)); XCTAssertTrue(app.buttons[savedID].label.contains("Conversation reliability check updated"))
        app.buttons[savedID].tap(); XCTAssertTrue(userMessages.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.firstMatch.label, "Conversation reliability check"); snap("1021-renamed-history-reopened")
    }

    func testConversationDeleteFailureAndFinalRelaunch() throws { try conversationDeleteFailureAndFinalRelaunch(large: false) }
    func testConversationDeleteFailureAndFinalRelaunchLarge() throws { try conversationDeleteFailureAndFinalRelaunch(large: true) }
    func conversationDeleteFailureAndFinalRelaunch(large: Bool) throws {
        quickFault("conversations.json:4", large: large); tab("Assistant")
        enterConversationQuestion("Synthetic final conversation")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 30)); tap("Conversation history")
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation-' ")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10)); let savedID = row.identifier
        row.press(forDuration: 1); tap("Delete"); captureConversationChoice("1022-delete-confirmation", title: "Delete this conversation?", large: large)
        tap("Cancel")
        XCTAssertTrue(app.buttons["Delete"].firstMatch.waitForNonExistence(timeout: 5)); XCTAssertTrue(app.buttons[savedID].exists)
        snap("1022-delete-dismissed-keeps-history")
        app.buttons[savedID].press(forDuration: 1); tap("Delete"); tap("Delete")
        let alert = app.alerts["Couldn’t delete chat"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10)); captureConversationChoice("1023-delete-save-failed", title: "Couldn’t delete chat", large: large); alert.buttons["Keep"].tap()
        XCTAssertTrue(app.buttons[savedID].exists); snap("1024-failed-delete-keeps-history")
        app.buttons[savedID].press(forDuration: 1); tap("Delete"); tap("Delete")
        XCTAssertTrue(app.buttons[savedID].waitForNonExistence(timeout: 10)); snap("1025-final-conversation-deleted"); tap("Done")
        relaunchConversations(large: large); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10)); XCTAssertEqual(userMessages.count, 0)
        tap("Conversation history"); XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'conversation-' ")).count, 0)
        snap("1026-final-deletion-relaunch-empty")
    }

    func testConversationClearFailureAndRelaunch() throws { conversationClearFailureAndRelaunch(large: false) }
    func testConversationClearFailureAndRelaunchLarge() throws { conversationClearFailureAndRelaunch(large: true) }
    func conversationClearFailureAndRelaunch(large: Bool) {
        quickFault("conversations.json:4", large: large); tab("Assistant")
        enterConversationQuestion("Synthetic conversation to clear")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 30))
        openConversationClearControl()
        captureConversationChoice("1027-clear-confirmation", title: "Clear this conversation?", large: large); tap("Clear")
        let alert = app.alerts["Couldn’t clear chat"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10)); captureConversationChoice("1028-clear-save-failed", title: "Couldn’t clear chat", large: large)
        alert.buttons["Keep"].tap(); tap("Done"); tab("Assistant")
        XCTAssertEqual(userMessages.count, 1); XCTAssertEqual(coachMessages.count, 1); snap("1029-failed-clear-keeps-messages")
        openConversationClearControl(); tap("Clear")
        XCTAssertTrue(app.buttons["Clear coach conversation"].waitForNonExistence(timeout: 10)); tap("Done"); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10)); snap("1030-cleared-conversation")
        relaunchConversations(large: large); tab("Assistant")
        XCTAssertTrue(app.staticTexts["Let’s put it\nin context."].waitForExistence(timeout: 10))
        XCTAssertEqual(userMessages.count, 0); XCTAssertEqual(coachMessages.count, 0); snap("1031-clear-relaunch-empty")
    }

    func testComposerKeyboardReturn() throws {
        finishOnboarding(); tab("Assistant")
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        input.tap(); input.typeText("Synthetic keyboard submission.\n")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 30))
        XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(userMessages.firstMatch.label, "Synthetic keyboard submission.")
        let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (input.value as? String ?? "").isEmpty && !self.app.buttons["coachSend"].isEnabled
        }, object: input)
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
        snap("325-composer-keyboard-return")
        input.tap(); input.typeText("My next unsent synthetic question.")
        XCTAssertEqual(input.value as? String, "My next unsent synthetic question.")
        XCTAssertTrue(app.buttons["coachSend"].isEnabled)
        XCTAssertEqual(userMessages.count, 1)
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
        XCTAssertFalse(userMessages.firstMatch.exists)
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
        if name.contains("OriginalImportCopyDenied") {
            reveal(button)
            settleLabFrame(button, pixelTolerance: 1, timeout: 20)
            snap("original-denied-settings-entry")
        } else if name.contains("RecoveryPhotoFault") && name.contains("Largest") {
            reveal(button)
            settleLabFrame(button, pixelTolerance: 1, timeout: 20)
            snap("photo-fault-largest-settings-entry")
        } else {
            for _ in 0..<28 {
                if button.exists && button.isHittable { break }
                app.swipeUp(velocity: .fast)
            }
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
        XCTAssertTrue(app.buttons["Cancel"].exists); snap("118-backup-restore-confirmation")
        tap("Cancel"); restore.tap(); tap("Restore records")
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
        let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", name)).firstMatch
        if name == "Lumen-backup-lab-context" {
            // Browse may already open this directory. Its navigation title is
            // not a location row to scroll or tap, especially on compact phones.
            if !cell.waitForExistence(timeout: 5) && !app.navigationBars["On My iPhone"].exists {
                let button = app.buttons["On My iPhone"].firstMatch
                let label = app.staticTexts["On My iPhone"].firstMatch
                let location = button.waitForExistence(timeout: 5) ? button : label
                XCTAssertTrue(location.waitForExistence(timeout: 5))
                for _ in 0..<8 where !location.isHittable { app.swipeDown(velocity: .slow) }
                XCTAssertTrue(location.isHittable); location.tap()
            }
        } else if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        for _ in 0..<24 {
            if cell.exists && cell.isHittable && cell.frame.maxY > 220 && cell.frame.minY < 700 { break }
            if cell.exists && cell.frame.maxY < 220 { app.swipeDown(velocity: .slow) }
            else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(cell.exists && cell.isHittable, "Seed synthetic backup fixtures before this scenario")
        settleLabFrame(cell, pixelTolerance: 1, timeout: self.name.contains("OriginalImportCopyDenied") ? 20 : 8)
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
    func nativeSwitch(_ identifier: String, enabled: Bool, towardsTop: Bool = false) {
        let toggle = app.switches[identifier].firstMatch; reveal(toggle, towardsTop: towardsTop)
        if identifier.hasPrefix("recoverFile-") {
            // The nested native AX switch can resolve a different tap origin
            // while its surrounding sheet is settling. Use its measured app
            // coordinate, and repeat only if the actual requested state did
            // not change. Every change still comes from a real native touch.
            let target = enabled ? "1" : "0"
            for attempt in 1...2 {
                if toggle.value as? String == target { return }
                reveal(toggle); settleLabFrame(toggle)
                let control = toggle.switches.firstMatch
                XCTAssertTrue(control.exists && control.isEnabled)
                let frame = control.frame
                XCTAssertFalse(frame.isEmpty); XCTAssertTrue(app.frame.contains(frame))
                let point = CGVector(dx: frame.minX + frame.width * (enabled ? 0.25 : 0.75), dy: frame.midY)
                print("FILE RECOVERY SWITCH NATIVE TOUCH", attempt, frame, point)
                app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
                let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", target), object: toggle)
                if XCTWaiter.wait(for: [changed], timeout: 3) == .completed { return }
            }
            snap("switch-state-" + identifier); XCTFail("Native file recovery switch did not reach the requested state")
            return
        }
        let preference = ["personalContextSharing", "contextualCheckIns", "reminderDetails"].contains(identifier)
        let touchThumb = identifier.contains("FHIR") || identifier.hasPrefix("normalization") || identifier == "normalizeLabComparison" || identifier.hasPrefix("recoverFile-") || preference
        if touchThumb { settleLabFrame(toggle) }
        if (toggle.value as? String) != (enabled ? "1" : "0") {
            let control = toggle.switches.firstMatch
            if preference {
                print("PREFERENCE SWITCH BEFORE", toggle.debugDescription)
                if control.exists { print("PREFERENCE SWITCH CONTROL", control.debugDescription) }
                snap("1006-preference-switch-before")
            }
            if control.exists {
                reveal(control)
                // Touch the visible native thumb. A labelled SwiftUI switch
                // also exposes a larger outer AX rectangle; its centre can
                // land on the label or a non-interactive part of the track.
                if preference {
                    let frame = control.frame
                    let point = CGVector(dx: frame.minX + frame.width * (enabled ? 0.25 : 0.75), dy: frame.midY)
                    print("PREFERENCE SWITCH ABSOLUTE POINT", point)
                    app.coordinate(withNormalizedOffset: .zero).withOffset(point).tap()
                } else if touchThumb {
                    control.coordinate(withNormalizedOffset: CGVector(dx: enabled ? 0.25 : 0.75, dy: 0.5)).tap()
                } else { control.tap() }
            } else { toggle.tap() }
        }
        let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        let result = XCTWaiter.wait(for: [expected], timeout: 5)
        if result != .completed { snap("switch-state-" + identifier); print(app.debugDescription) }
        XCTAssertEqual(result, .completed)
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
        settleLabFrame(cell, pixelTolerance: 1, timeout: self.name.contains("OriginalImportCopyDenied") ? 20 : 8)
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

    func openFHIRImport() {
        tab("Library"); tap("Add document"); tap("Import FHIR lab results")
        XCTAssertTrue(app.buttons["chooseFHIRFile"].waitForExistence(timeout: 5))
    }
    @discardableResult
    func reviewFHIRNDJSON(capturePrefix: String, detailed: Bool = false) throws -> String {
        try chooseLabFile("Lumen-fhir-ndjson-review", chooseIdentifier: "chooseFHIRFile")
        XCTAssertTrue(app.staticTexts["fhirCoverageCounts"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts["fhirCoverageCounts"].label.contains("3 entries"))
        if detailed { revealLabExcerpt(app.staticTexts["fhirCoverageCounts"]); snap(capturePrefix + "-complete-counts") }
        let coverage = app.staticTexts["fhirNDJSONCoverage"].firstMatch; reveal(coverage); snap(capturePrefix + "-coverage")
        let original = app.buttons["fhirOriginalJSON"].firstMatch; reveal(original); original.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5))
        XCTAssertTrue(fhirFullText.label.contains("synthetic-hb-1"))
        let copiedInput = fhirFullText.label
        tap("copyFHIRText")
        XCTAssertTrue(copiedInput.contains("\"display\":\"Hemoglobin\""))
        snap(capturePrefix + "-original")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let details = app.buttons["fhirCoverageDetails"].firstMatch; reveal(details, towardsTop: true); details.tap()
        let format = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Format: FHIR R4 NDJSON'")).firstMatch; reveal(format); format.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5))
        XCTAssertTrue(fhirFullText.label.contains("physical line N")); snap(capturePrefix + "-line-locations")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        nativeSwitch("acknowledgeFHIRCoverage", enabled: true)
        if detailed {
            revealLabExcerpt(app.switches["acknowledgeFHIRCoverage"].firstMatch); snap(capturePrefix + "-complete-coverage-ack")
            let next = app.buttons["continueFHIRCoverage"].firstMatch; revealLabExcerpt(next); XCTAssertTrue(next.isEnabled); snap(capturePrefix + "-complete-coverage-action")
        }
        tap("continueFHIRCoverage")
        let person = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fhirPerson-' AND label CONTAINS 'Patient/synthetic-a'")).firstMatch
        reveal(person); person.tap(); snap(capturePrefix + "-person")
        if detailed {
            revealLabExcerpt(person); snap(capturePrefix + "-complete-selected-person")
            let other = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fhirPerson-' AND label CONTAINS 'Patient/synthetic-b'")).firstMatch
            revealLabExcerpt(other); snap(capturePrefix + "-complete-other-person")
        }
        nativeSwitch("acknowledgeFHIRPerson", enabled: true)
        if detailed {
            revealLabExcerpt(app.switches["acknowledgeFHIRPerson"].firstMatch); snap(capturePrefix + "-complete-person-ack")
            let next = app.buttons["reviewFHIRResults"].firstMatch; revealLabExcerpt(next); XCTAssertTrue(next.isEnabled); snap(capturePrefix + "-complete-person-action")
        }
        tap("reviewFHIRResults")
        XCTAssertTrue(app.staticTexts["fhirIncludedCount"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["fhirIncludedCount"].label.contains("2 included"))
        return copiedInput
    }
    func verifyFHIRCopiedText(in identifier: String, expected: String, capture: String) {
        let field = openLabField(identifier)
        tap("selectAllLabText")
        // Use the actual foreground app's native Paste command. The UI-test
        // runner is intentionally not authorized to read another app's clipboard.
        field.typeKey("v", modifierFlags: .command)
        let pasted = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in (field.value as? String) == expected }, object: field)
        XCTAssertEqual(XCTWaiter.wait(for: [pasted], timeout: 5), .completed, "Native Paste must retain all copied source characters")
        snap(capture)
        tap("cancelLabText"); tap("Discard changes")
    }
    func testFHIRNDJSONLifecycle() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding(); openFHIRImport(); snap("800-ndjson-intro")
        try chooseLabFile("Lumen-fhir-ndjson-invalid", chooseIdentifier: "chooseFHIRFile")
        XCTAssertTrue(app.alerts["Check the FHIR import"].waitForExistence(timeout: 20))
        settleLabFrame(app.alerts["Check the FHIR import"]); snap("801-ndjson-malformed")
        tap("OK"); XCTAssertFalse(app.staticTexts["fhirCoverageCounts"].exists)
        let originalInput = try reviewFHIRNDJSON(capturePrefix: "802-ndjson")
        nativeSwitch("acknowledgeFHIRResults", enabled: true)
        let edit = app.buttons["editFHIRResult-0"].firstMatch; reveal(edit, towardsTop: true); edit.tap()
        verifyFHIRCopiedText(in: "labReportedResult", expected: originalInput, capture: "803-ndjson-full-input-native-paste")
        labField("labReportedResult", value: "13.25", replacing: true, capturePrefix: "803-ndjson-correction"); tap("finishLabResult")
        XCTAssertFalse(app.buttons["saveFHIRImport"].isEnabled)
        let fields = app.buttons["fhirResultFields-0"].firstMatch; reveal(fields); fields.tap()
        let quantity = app.buttons.matching(NSPredicate(format: "label CONTAINS '/line/1/valueQuantity'")).firstMatch
        reveal(quantity); quantity.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); XCTAssertTrue(fhirFullText.label.contains("12.00")); snap("804-ndjson-original-value")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let code = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '/line/1/code,'")).firstMatch; reveal(code); code.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); XCTAssertTrue(fhirFullText.label.contains("Hemoglobin")); snap("804-ndjson-original-code")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        nativeSwitch("acknowledgeFHIRResults", enabled: true); tap("saveFHIRImport")
        XCTAssertTrue(app.staticTexts["fhirImportSaved"].waitForExistence(timeout: 20)); snap("805-ndjson-saved")
        tap("viewFHIRRecord"); XCTAssertTrue(app.staticTexts["13.25 g/dL"].waitForExistence(timeout: 5)); snap("806-ndjson-record")
        let receipt = app.buttons["fhirImportReceipt"].firstMatch; reveal(receipt); receipt.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); XCTAssertTrue(fhirFullText.label.contains("NDJSON")); snap("807-ndjson-receipt")
        let viewport = max(200, app.frame.height - app.navigationBars.firstMatch.frame.maxY - 80)
        let parts = min(24, max(1, Int(ceil(fhirFullText.frame.height / (viewport * 0.6)))))
        for part in 1...parts { app.swipeUp(velocity: .slow); snap("807-ndjson-receipt-scroll-\(part)") }
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); openLabRecord("Lumen-fhir-ndjson-review")
        XCTAssertTrue(app.staticTexts["13.25 g/dL"].waitForExistence(timeout: 5)); snap("808-ndjson-relaunch")
        app.navigationBars.buttons.element(boundBy: 0).tap(); openFHIRImport(); try reviewFHIRNDJSON(capturePrefix: "809-ndjson-duplicate")
        nativeSwitch("acknowledgeFHIRResults", enabled: true); tap("saveFHIRImport")
        XCTAssertTrue(app.alerts["Save another copy?"].waitForExistence(timeout: 5)); snap("810-ndjson-duplicate-confirmation")
        tap("Keep reviewing"); tap("cancelFHIRImport"); tap("Discard draft")
    }
    func testFHIRNDJSONPresentation() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode", "-lumen.appearance", "dark"]; app.launch()
        finishOnboarding(); openFHIRImport(); snap("820-ndjson-dark-intro")
        try reviewFHIRNDJSON(capturePrefix: "821-ndjson-dark")
        nativeSwitch("acknowledgeFHIRResults", enabled: true); snap("822-ndjson-dark-review"); tap("saveFHIRImport")
        XCTAssertTrue(app.staticTexts["fhirImportSaved"].waitForExistence(timeout: 20)); snap("823-ndjson-dark-saved")
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        finishOnboarding(); tab("Library"); settleLabFrame(app.buttons["Add document"].firstMatch); snap("824-ndjson-xxxl-library-before-sheet")
        let backgroundFrame = app.buttons["openLabHistory"].frame
        let background = XCTAttachment(string: "Application bounds: \(app.frame)\nUnderlying Lab history row: \(backgroundFrame)")
        background.name = "NDJSON XXXL underlying Library geometry"; background.lifetime = .keepAlways; add(background)
        tap("Add document"); tap("Import FHIR lab results")
        XCTAssertTrue(app.buttons["chooseFHIRFile"].waitForExistence(timeout: 5)); settleLabFrame(app.buttons["chooseFHIRFile"]); snap("824-ndjson-xxxl-intro")
        tap("cancelFHIRImport"); XCTAssertTrue(app.buttons["Add document"].waitForExistence(timeout: 5)); settleLabFrame(app.buttons["Add document"]); snap("824-ndjson-xxxl-library-after-sheet")
        tap("Add document"); tap("Import FHIR lab results"); XCTAssertTrue(app.buttons["chooseFHIRFile"].waitForExistence(timeout: 5))
        let limits = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'FHIR R4 JSON or NDJSON'")).firstMatch
        revealLabExcerpt(limits); snap("824-ndjson-xxxl-limits")
        let originalInput = try reviewFHIRNDJSON(capturePrefix: "825-ndjson-xxxl", detailed: true)
        let first = app.staticTexts["Synthetic hemoglobin"].firstMatch; reveal(first, towardsTop: true); snap("826-ndjson-xxxl-first-result")
        let edit = app.buttons["editFHIRResult-0"].firstMatch; reveal(edit, towardsTop: true); edit.tap()
        verifyFHIRCopiedText(in: "labReportedResult", expected: originalInput, capture: "826-ndjson-xxxl-full-input-native-paste")
        labField("labReportedResult", value: "13.25", replacing: true, capturePrefix: "826-ndjson-xxxl-correction"); tap("finishLabResult")
        nativeSwitch("acknowledgeFHIRResults", enabled: true)
        let ack = app.switches["acknowledgeFHIRResults"].firstMatch; revealLabExcerpt(ack); snap("827-ndjson-xxxl-acknowledgement")
        XCTAssertTrue(app.buttons["saveFHIRImport"].isEnabled); tap("saveFHIRImport")
        XCTAssertTrue(app.staticTexts["fhirImportSaved"].waitForExistence(timeout: 20)); snap("828-ndjson-xxxl-saved")
        let view = app.buttons["viewFHIRRecord"].firstMatch; revealLabExcerpt(view); snap("829-ndjson-xxxl-open-action"); view.tap()
        let reviewed = app.staticTexts["13.25 g/dL"].firstMatch; revealLabExcerpt(reviewed); snap("829-ndjson-xxxl-reviewed-value")
        let original = app.staticTexts["Original number text: 12.00"].firstMatch; revealLabExcerpt(original); snap("829-ndjson-xxxl-original-number")
        let source = app.buttons["Original FHIR fields"].firstMatch; revealLabExcerpt(source); snap("829-ndjson-xxxl-source-action")
        source.tap()
        let code = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '/line/1/code,'")).firstMatch; reveal(code); code.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); XCTAssertTrue(fhirFullText.label.contains("Hemoglobin"))
        snap("829-ndjson-xxxl-code-top"); app.swipeUp(velocity: .slow); snap("829-ndjson-xxxl-code-lower")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        let receipt = app.buttons["fhirImportReceipt"].firstMatch; revealLabExcerpt(receipt); receipt.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); snap("830-ndjson-xxxl-receipt")
        XCTAssertTrue(fhirFullText.label.contains("e825a983f0746edd9dd2a85709eaa5a5ba000e13724df46134a17593669ed9fe"))
        let viewport = max(200, app.frame.height - app.navigationBars.firstMatch.frame.maxY - 80)
        let parts = min(24, max(1, Int(ceil(fhirFullText.frame.height / (viewport * 0.6)))))
        for part in 1...parts { app.swipeUp(velocity: .slow); snap("830-ndjson-xxxl-receipt-scroll-\(part)") }
    }
    func testFHIRLiteralWrappingSnapshots() throws {
        for appearance in ["light", "dark", "xxxl"] {
            app.terminate()
            app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", appearance == "dark" ? "dark" : "light"]
            if appearance == "xxxl" { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            app.launch()
            if app.buttons["Get started"].waitForExistence(timeout: 2) { finishOnboarding() }
            tab("Library")
            let record = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-record-' AND label == 'Lumen-fhir-ndjson-review'")).firstMatch
            if record.exists { reveal(record); record.tap() }
            else {
                openFHIRImport(); try reviewFHIRNDJSON(capturePrefix: "850-wrap-fallback-" + appearance)
                nativeSwitch("acknowledgeFHIRResults", enabled: true); tap("saveFHIRImport")
                XCTAssertTrue(app.staticTexts["fhirImportSaved"].waitForExistence(timeout: 20)); tap("viewFHIRRecord")
            }
            let receipt = app.buttons["fhirImportReceipt"].firstMatch; reveal(receipt); receipt.tap()
            XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5))
            XCTAssertTrue(fhirFullText.label.contains("e825a983f0746edd9dd2a85709eaa5a5ba000e13724df46134a17593669ed9fe"))
            settleLabFrame(app.buttons["copyFHIRText"]); snap("850-wrap-" + appearance + "-receipt-top")
            let viewport = max(200, app.frame.height - app.navigationBars.firstMatch.frame.maxY - 80)
            let count = appearance == "xxxl" ? min(24, max(1, Int(ceil(fhirFullText.frame.height / (viewport * 0.6))))) : 2
            for part in 1...count { app.swipeUp(velocity: .slow); snap("850-wrap-" + appearance + "-receipt-\(part)") }
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let fields = app.buttons["Original FHIR fields"].firstMatch; reveal(fields, towardsTop: true); fields.tap()
            let code = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '/line/1/code,'")).firstMatch; reveal(code); code.tap()
            XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); XCTAssertTrue(fhirFullText.label.contains("Hemoglobin"))
            snap("851-wrap-" + appearance + "-code-top")
            if appearance == "xxxl" { app.swipeUp(velocity: .slow); snap("851-wrap-xxxl-code-lower") }
        }
    }
    func reviewFHIRFixture(capturePrefix: String? = nil) throws {
        try chooseLabFile("Lumen-fhir-review", chooseIdentifier: "chooseFHIRFile")
        XCTAssertTrue(app.staticTexts["fhirCoverageCounts"].waitForExistence(timeout: 25))
        XCTAssertTrue(app.staticTexts["fhirCoverageCounts"].label.contains("7 entries"))
        if let capturePrefix { snap(capturePrefix + "-coverage") }
        nativeSwitch("acknowledgeFHIRCoverage", enabled: true)
        let next = app.buttons["continueFHIRCoverage"].firstMatch; reveal(next); next.tap()
        let person = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fhirPerson-' AND label CONTAINS 'Synthetic Person A'")).firstMatch
        XCTAssertTrue(person.waitForExistence(timeout: 5)); reveal(person); person.tap()
        if let capturePrefix {
            let reference = app.buttons["Read person reference"].firstMatch; reveal(reference); reference.tap()
            XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); XCTAssertTrue(fhirFullText.label.contains("Patient/a")); snap(capturePrefix + "-person-reference")
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        nativeSwitch("acknowledgeFHIRPerson", enabled: true)
        if let capturePrefix { snap(capturePrefix + "-person") }
        let review = app.buttons["reviewFHIRResults"].firstMatch; reveal(review)
        if let capturePrefix { revealLabExcerpt(review); snap(capturePrefix + "-review-action") }
        review.tap()
        XCTAssertTrue(app.staticTexts["fhirIncludedCount"].waitForExistence(timeout: 15))
    }
    func testFHIRLabImportLifecycle() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding(); openFHIRImport(); snap("600-fhir-intro")
        try reviewFHIRFixture(capturePrefix: "609-fhir"); snap("601-fhir-results")
        nativeSwitch("acknowledgeFHIRResults", enabled: true)
        XCTAssertFalse(app.buttons["saveFHIRImport"].isEnabled)
        nativeSwitch("includeFHIRResult-2", enabled: false)
        nativeSwitch("acknowledgeFHIRResults", enabled: true)
        XCTAssertTrue(app.buttons["saveFHIRImport"].isEnabled)
        let edit = app.buttons["editFHIRResult-0"].firstMatch; reveal(edit); edit.tap()
        XCTAssertTrue(app.buttons["finishLabResult"].waitForExistence(timeout: 5)); snap("602-fhir-edit")
        let editorPrefix = app.frame.width < 390 ? "634-fhir-compact" : "634-fhir-normal"
        let longEditorValue = String(repeating: "Long reported wording ", count: 20) + "END REPORTED VALUE"
        labField("labReportedResult", value: longEditorValue, replacing: true, finish: false, capturePrefix: editorPrefix + "-long-end")
        labField("labReportedResult", value: "13.25", replacing: true, inOpenEditor: true, capturePrefix: editorPrefix + "-correction"); tap("finishLabResult")
        XCTAssertFalse(app.buttons["saveFHIRImport"].isEnabled)
        let fields = app.buttons["fhirResultFields-0"].firstMatch; reveal(fields); fields.tap()
        let quantity = app.buttons.matching(NSPredicate(format: "label CONTAINS '/entry/1/resource/valueQuantity'")).firstMatch
        for _ in 0..<7 {
            if quantity.exists { break }
            let next = app.buttons["historyNextPage"].firstMatch; reveal(next)
            guard next.exists && next.isEnabled else { break }
            next.tap()
        }
        reveal(quantity); quantity.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); XCTAssertTrue(fhirFullText.label.contains("12.00")); snap("603-fhir-original-value")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        for _ in 0..<8 {
            let count = app.staticTexts["fhirIncludedCount"].firstMatch
            if count.exists && count.isHittable { break }
            app.swipeDown(velocity: .slow)
        }
        XCTAssertTrue(app.staticTexts["fhirIncludedCount"].waitForExistence(timeout: 5)); XCTAssertTrue(app.staticTexts["fhirIncludedCount"].label.contains("2 included"))
        snap("622-fhir-draft-after-source-reader")
        tap("cancelFHIRImport"); XCTAssertTrue(app.alerts["Discard this FHIR import?"].waitForExistence(timeout: 5)); tap("Keep reviewing")
        nativeSwitch("acknowledgeFHIRResults", enabled: true); tap("saveFHIRImport")
        XCTAssertTrue(app.staticTexts["fhirImportSaved"].waitForExistence(timeout: 20)); XCTAssertTrue(app.staticTexts["fhirImportSaved"].label.contains("2 reviewed results")); snap("604-fhir-saved")
        tap("viewFHIRRecord"); XCTAssertTrue(app.staticTexts["13.25 g/dL"].waitForExistence(timeout: 5)); snap("605-fhir-record")
        let receipt = app.buttons["fhirImportReceipt"].firstMatch; reveal(receipt); receipt.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); XCTAssertTrue(fhirFullText.label.contains("Next page reported: Yes")); snap("606-fhir-receipt")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap(); tap("cancelFHIRImport")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); openLabRecord("Lumen-fhir-review")
        XCTAssertTrue(app.staticTexts["13.25 g/dL"].waitForExistence(timeout: 5)); snap("607-fhir-relaunch")
        app.navigationBars.buttons.element(boundBy: 0).tap(); openFHIRImport(); try reviewFHIRFixture()
        nativeSwitch("includeFHIRResult-2", enabled: false); nativeSwitch("acknowledgeFHIRResults", enabled: true); tap("saveFHIRImport")
        XCTAssertTrue(app.alerts["Save another copy?"].waitForExistence(timeout: 5)); snap("608-fhir-duplicate"); tap("Keep reviewing"); tap("cancelFHIRImport"); tap("Discard draft")
    }
    func testFHIRLabImportPresentation() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode", "-lumen.appearance", "dark"]; app.launch()
        finishOnboarding(); openFHIRImport(); snap("610-fhir-dark-intro")
        try reviewFHIRFixture(capturePrefix: "611-fhir-dark")
        nativeSwitch("includeFHIRResult-2", enabled: false)
        let first = app.staticTexts["Synthetic hemoglobin"].firstMatch; reveal(first, towardsTop: true); snap("612-fhir-dark-review")
        nativeSwitch("acknowledgeFHIRResults", enabled: true); tap("saveFHIRImport")
        XCTAssertTrue(app.staticTexts["fhirImportSaved"].waitForExistence(timeout: 20)); snap("613-fhir-dark-complete")
        tap("viewFHIRRecord"); XCTAssertTrue(app.staticTexts["Collection day: Not recorded"].firstMatch.waitForExistence(timeout: 5)); snap("614-fhir-dark-record")
        let darkWording = app.staticTexts["Kept as wording"].firstMatch; reveal(darkWording); snap("630-fhir-dark-coded")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        tab("Library"); openLabRecord("Lumen-fhir-review"); snap("615-fhir-xxxl-record")
        let receipt = app.buttons["fhirImportReceipt"].firstMatch; reveal(receipt); receipt.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); snap("616-fhir-xxxl-receipt")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        openFHIRImport(); snap("617-fhir-xxxl-intro")
        try reviewFHIRFixture(capturePrefix: "618-fhir-xxxl")
        nativeSwitch("includeFHIRResult-2", enabled: false)
        let inclusion = app.switches["includeFHIRResult-2"].firstMatch; revealLabExcerpt(inclusion); snap("640-fhir-xxxl-final-inclusion")
        let reviewed = app.staticTexts["Synthetic hemoglobin"].firstMatch; reveal(reviewed, towardsTop: true); snap("619-fhir-xxxl-review")
        let edit = app.buttons["editFHIRResult-0"].firstMatch; reveal(edit); edit.tap()
        XCTAssertTrue(app.buttons["finishLabResult"].waitForExistence(timeout: 5)); snap("632-fhir-xxxl-edit")
        let longEditorValue = String(repeating: "Long reported wording ", count: 20) + "END REPORTED VALUE"
        labField("labReportedResult", value: longEditorValue, replacing: true, finish: false, capturePrefix: "636-fhir-xxxl-long-end")
        labField("labReportedResult", value: "12.00", replacing: true, inOpenEditor: true, capturePrefix: "637-fhir-xxxl-correction"); tap("finishLabResult")
        nativeSwitch("acknowledgeFHIRResults", enabled: true)
        let privacy = app.staticTexts["Assistant sharing starts off. Saving creates a separate reviewed record; keep the original file."].firstMatch
        reveal(privacy); revealLabExcerpt(privacy)
        let acknowledgement = app.staticTexts["I checked the included results and original FHIR fields"].firstMatch
        XCTAssertTrue(acknowledgement.exists); revealLabExcerpt(acknowledgement)
        XCTAssertGreaterThanOrEqual(acknowledgement.frame.minY, app.navigationBars.firstMatch.frame.maxY + 12)
        XCTAssertLessThanOrEqual(privacy.frame.maxY, app.frame.maxY - 40)
        snap("638-fhir-xxxl-ack-privacy-footer")
        tap("saveFHIRImport")
        XCTAssertTrue(app.alerts["Save another copy?"].waitForExistence(timeout: 5)); tap("Save another copy")
        XCTAssertTrue(app.staticTexts["fhirImportSaved"].waitForExistence(timeout: 20)); snap("620-fhir-xxxl-complete")
        let savedAction = app.buttons["viewFHIRRecord"].firstMatch; reveal(savedAction); revealLabExcerpt(savedAction); snap("639-fhir-xxxl-complete-action")
        tap("viewFHIRRecord"); XCTAssertTrue(app.staticTexts["12.00 g/dL"].firstMatch.waitForExistence(timeout: 5)); snap("621-fhir-xxxl-open")
        let largeWording = app.staticTexts["Kept as wording"].firstMatch; reveal(largeWording); snap("631-fhir-xxxl-coded")
    }
    func testFHIRReceiptAfterRemovingResults() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding(); openFHIRImport(); try reviewFHIRFixture()
        nativeSwitch("includeFHIRResult-1", enabled: false); nativeSwitch("includeFHIRResult-2", enabled: false)
        nativeSwitch("acknowledgeFHIRResults", enabled: true); tap("saveFHIRImport")
        XCTAssertTrue(app.staticTexts["fhirImportSaved"].waitForExistence(timeout: 20)); tap("viewFHIRRecord")
        let review = app.buttons["reviewSavedLabResults"].firstMatch; reveal(review); review.tap()
        let remove = app.buttons["Remove Synthetic hemoglobin from draft"].firstMatch; reveal(remove); remove.tap(); tap("Remove result")
        nativeSwitch("acknowledgeLabResults", enabled: true); tap("saveLabResults")
        let sourceOnly = app.staticTexts["fhirSourceOnly"].firstMatch; XCTAssertTrue(sourceOnly.waitForExistence(timeout: 5)); reveal(sourceOnly); snap("623-fhir-source-only")
        let receipt = app.buttons["fhirImportReceipt"].firstMatch; reveal(receipt); receipt.tap()
        XCTAssertTrue(fhirFullText.waitForExistence(timeout: 5)); XCTAssertTrue(fhirFullText.label.contains("Lumen-fhir-review.json")); snap("624-fhir-source-only-receipt")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); openLabRecord("Lumen-fhir-review")
        XCTAssertTrue(sourceOnly.waitForExistence(timeout: 5)); reveal(sourceOnly); snap("625-fhir-source-only-relaunch")
        app.navigationBars.buttons.element(boundBy: 0).tap(); openFHIRImport(); try reviewFHIRFixture()
        nativeSwitch("includeFHIRResult-2", enabled: false); nativeSwitch("acknowledgeFHIRResults", enabled: true); tap("saveFHIRImport")
        XCTAssertTrue(app.alerts["Save another copy?"].waitForExistence(timeout: 5)); snap("626-fhir-source-only-duplicate"); tap("Keep reviewing"); tap("cancelFHIRImport"); tap("Discard draft")
    }
    func testFHIRLongSourceFields() throws {
        let method = "BEGIN ORIGINAL METHOD " + String(repeating: "synthetic method wording ", count: 160) + " END ORIGINAL METHOD"
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding(); openFHIRImport(); try chooseLabFile("Lumen-fhir-long", chooseIdentifier: "chooseFHIRFile")
        XCTAssertTrue(app.staticTexts["fhirCoverageCounts"].waitForExistence(timeout: 25))
        nativeSwitch("acknowledgeFHIRCoverage", enabled: true); let next = app.buttons["continueFHIRCoverage"].firstMatch; reveal(next); next.tap()
        let person = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'fhirPerson-'")).firstMatch; reveal(person); person.tap()
        nativeSwitch("acknowledgeFHIRPerson", enabled: true); let review = app.buttons["reviewFHIRResults"].firstMatch; reveal(review); review.tap()
        XCTAssertTrue(app.staticTexts["fhirIncludedCount"].waitForExistence(timeout: 15)); nativeSwitch("acknowledgeFHIRResults", enabled: true); XCTAssertFalse(app.buttons["saveFHIRImport"].isEnabled)
        let fields = app.buttons["fhirResultFields-0"].firstMatch; reveal(fields); fields.tap()
        let methodField = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '/method,'")).firstMatch; reveal(methodField); methodField.tap()
        var retained = ""
        for _ in 0..<10 {
            let text = fhirFullText; XCTAssertTrue(text.waitForExistence(timeout: 5)); retained += text.label
            let next = app.buttons["historyNextPage"].firstMatch
            if !next.exists || !next.isEnabled { break }
            reveal(next); next.tap()
        }
        XCTAssertEqual(retained, "{\"text\":\"" + method + "\"}"); snap("627-fhir-complete-long-method")
        tap("copyFHIRText")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        let edit = app.buttons["editFHIRResult-0"].firstMatch; reveal(edit); edit.tap()
        verifyFHIRCopiedText(in: "labMethod", expected: retained, capture: "627-fhir-full-multipart-native-paste")
        labField("labMethod", value: "Reviewed synthetic method", replacing: true); tap("finishLabResult")
        nativeSwitch("acknowledgeFHIRResults", enabled: true); tap("saveFHIRImport")
        XCTAssertTrue(app.staticTexts["fhirImportSaved"].waitForExistence(timeout: 20)); snap("628-fhir-long-source-saved")
        tap("viewFHIRRecord"); XCTAssertTrue(app.staticTexts["1.2300e-9 mg/L"].firstMatch.waitForExistence(timeout: 5)); snap("629-fhir-long-source-record")
    }
    func openLabImport() {
        tab("Library"); tap("Add document"); tap("Import lab results")
        XCTAssertTrue(app.buttons["chooseLabFile"].waitForExistence(timeout: 5))
    }
    func chooseLabFile(_ name: String, chooseIdentifier: String = "chooseLabFile") throws {
        let choose = app.buttons[chooseIdentifier].firstMatch; reveal(choose); revealLabExcerpt(choose); choose.tap()
        let picker = app.collectionViews["File View"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 25))
        if app.buttons["Browse"].firstMatch.exists { app.buttons["Browse"].firstMatch.tap() }
        if app.buttons["On My iPhone"].firstMatch.exists { app.buttons["On My iPhone"].firstMatch.tap() }
        else if app.staticTexts["On My iPhone"].firstMatch.exists { app.staticTexts["On My iPhone"].firstMatch.tap() }
        let folder = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH '00 Lumen lab checks'")).firstMatch
        if folder.waitForExistence(timeout: 2) {
            for _ in 0..<12 where !(folder.isHittable && folder.frame.minY > 170 && folder.frame.minY < 680) { app.swipeDown(velocity: .slow) }
            folder.tap()
        }
        let cell = app.cells.matching(NSPredicate(format: "identifier BEGINSWITH %@", name)).firstMatch
        for _ in 0..<24 {
            if cell.exists && cell.isHittable && cell.frame.maxY > 220 && cell.frame.minY < 700 { break }
            if cell.exists && cell.frame.maxY < 220 { app.swipeDown(velocity: .slow) } else { app.swipeUp(velocity: .slow) }
        }
        XCTAssertTrue(cell.exists && cell.isHittable, "Seed the small synthetic lab-file fixtures")
        settleLabFrame(cell); cell.tap()
    }
    func continueLabFileMapping(hasSubject: Bool = true) {
        let ready = app.staticTexts["labTableReady"].firstMatch
        // The filename can leave the LazyVStack when this helper follows a
        // separator change at the bottom of an already loaded mapping page.
        if !app.buttons["continueLabMapping"].exists { XCTAssertTrue(ready.waitForExistence(timeout: 20)) }
        XCTAssertFalse(app.alerts.firstMatch.exists)
        let next = app.buttons["continueLabMapping"].firstMatch; reveal(next); XCTAssertTrue(next.isEnabled); next.tap()
        let review = app.buttons["reviewLabImport"].firstMatch
        if hasSubject { let subject = app.buttons["labSubject-0"].firstMatch; reveal(subject); subject.tap() }
        XCTAssertFalse(review.isEnabled)
        nativeSwitch("labPersonChecked", enabled: true); reveal(review); XCTAssertTrue(review.isEnabled); review.tap()
        XCTAssertTrue(app.staticTexts["labImportIncludedCount"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["saveLabImport"].isEnabled)
    }
    func testLabFileImportLifecycle() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding(); openLabImport(); snap("460-lab-import-intro")
        try chooseLabFile("Lumen-lab-table")
        XCTAssertTrue(app.staticTexts["labTableReady"].waitForExistence(timeout: 20)); snap("461-lab-import-columns")
        let result = app.buttons["labColumn-result"].firstMatch; reveal(result); revealLabExcerpt(result); result.tap(); tap("Component")
        let next = app.buttons["continueLabMapping"].firstMatch; reveal(next); XCTAssertFalse(next.isEnabled)
        reveal(result); revealLabExcerpt(result); result.tap(); tap("Your value")
        reveal(next); XCTAssertTrue(next.isEnabled); next.tap()
        let second = app.buttons["labSubject-1"].firstMatch; reveal(second); second.tap()
        nativeSwitch("labPersonChecked", enabled: true)
        let first = app.buttons["labSubject-0"].firstMatch; reveal(first); first.tap()
        XCTAssertTrue(first.isSelected); XCTAssertEqual(app.switches["labPersonChecked"].value as? String, "0"); settleLabFrame(first); snap("462-lab-import-person")
        nativeSwitch("labPersonChecked", enabled: true); let review = app.buttons["reviewLabImport"].firstMatch; reveal(review); settleLabFrame(review); snap("495-lab-import-person-checked"); review.tap()
        XCTAssertTrue(app.staticTexts["labImportIncludedCount"].waitForExistence(timeout: 10)); snap("463-lab-import-review")
        let status = app.staticTexts["Reported status: Preliminary"].firstMatch; reveal(status); settleLabFrame(status); snap("496-lab-import-review-status")
        nativeSwitch("includeLabImport-3", enabled: false)
        nativeSwitch("acknowledgeLabImport", enabled: true); XCTAssertTrue(app.buttons["saveLabImport"].isEnabled)
        let edit = app.buttons["editLabImport-1"].firstMatch; reveal(edit); edit.tap()
        XCTAssertTrue(app.buttons["finishLabResult"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["chooseLabSource"].exists); snap("464-lab-import-edit-source")
        labField("labReportedResult", value: "<4,0", replacing: true); snap("465-lab-import-corrected")
        tap("finishLabResult"); XCTAssertEqual(app.switches["acknowledgeLabImport"].value as? String, "0"); XCTAssertFalse(app.buttons["saveLabImport"].isEnabled)
        let source = app.buttons["labImportSource-1"].firstMatch; reveal(source); source.tap()
        let text = app.staticTexts.matching(NSPredicate(format: "identifier == 'labImportSource-1' AND label BEGINSWITH 'Imported data row 1' ")).firstMatch
        reveal(text); XCTAssertTrue(text.label.contains("\"<5,0\"")); XCTAssertFalse(text.label.contains("UNMAPPED-PRIVATE-CANARY")); snap("466-lab-import-source-before-save")
        tap("cancelLabImport"); XCTAssertTrue(app.alerts["Discard this lab import?"].waitForExistence(timeout: 5)); tap("Keep reviewing")
        let back = app.buttons["labImportBackToMapping"].firstMatch; reveal(back); back.tap()
        XCTAssertTrue(app.alerts["Return to column mapping?"].waitForExistence(timeout: 5)); snap("467-lab-import-protected-review"); tap("Keep reviewing")
        nativeSwitch("acknowledgeLabImport", enabled: true); tap("saveLabImport")
        XCTAssertTrue(app.staticTexts["labImportSaved"].waitForExistence(timeout: 10)); XCTAssertTrue(app.staticTexts["labImportSaved"].label.contains("1 reviewed result")); snap("468-lab-import-complete")
        tap("viewImportedLabRecord"); XCTAssertTrue(app.staticTexts["<4,0 µg/L"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Reported collection wording: 20/10/2026"].exists); snap("469-lab-import-saved-fields")
        let receipt = app.buttons["labImportReceipt"].firstMatch; reveal(receipt); receipt.tap(); snap("470-lab-import-receipt")
        let sharing = app.switches["Use in assistant"].firstMatch; reveal(sharing); XCTAssertEqual(sharing.value as? String, "0")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); openLabRecord("Lumen-lab-table")
        XCTAssertTrue(app.staticTexts["<4,0 µg/L"].exists); snap("471-lab-import-relaunch")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        openLabImport(); try chooseLabFile("Lumen-lab-table"); continueLabFileMapping()
        nativeSwitch("acknowledgeLabImport", enabled: true); tap("saveLabImport")
        XCTAssertTrue(app.alerts["Save another copy?"].waitForExistence(timeout: 5)); snap("472-lab-import-duplicate"); tap("Keep reviewing")
        XCTAssertTrue(app.buttons["saveLabImport"].isEnabled); tap("saveLabImport"); tap("Save another copy")
        XCTAssertTrue(app.staticTexts["labImportSaved"].waitForExistence(timeout: 10)); tap("cancelLabImport")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == 'Lumen-lab-table' AND identifier BEGINSWITH 'library-record-' ")).count, 2)
    }
    func testLabFileImportPresentation() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode", "-lumen.appearance", "dark"]; app.launch()
        finishOnboarding(); openLabImport(); snap("473-lab-import-dark-intro")
        try chooseLabFile("Lumen-lab-literal"); XCTAssertTrue(app.staticTexts["labTableReady"].waitForExistence(timeout: 20)); snap("474-lab-import-dark-columns")
        continueLabFileMapping(hasSubject: false); snap("475-lab-import-dark-review")
        let literal = app.buttons["editLabImport-1"].firstMatch; reveal(literal); literal.tap()
        XCTAssertTrue(app.buttons["finishLabResult"].waitForExistence(timeout: 5)); snap("476-lab-import-dark-literal-source")
        let result = openLabField("labReportedResult"); XCTAssertEqual(result.value as? String, "1.2300e-9"); snap("477-lab-import-dark-literal-result"); tap("finishLabField"); tap("finishLabResult")
        nativeSwitch("acknowledgeLabImport", enabled: true); tap("saveLabImport"); XCTAssertTrue(app.staticTexts["labImportSaved"].waitForExistence(timeout: 10)); snap("478-lab-import-dark-complete"); tap("cancelLabImport")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        openLabImport(); snap("479-lab-import-large-intro"); try chooseLabFile("Lumen-lab-table")
        XCTAssertTrue(app.staticTexts["labTableReady"].waitForExistence(timeout: 20)); snap("480-lab-import-large-columns")
        let subjectColumn = app.buttons["labColumn-subject"].firstMatch; reveal(subjectColumn); snap("481-lab-import-large-subject-column")
        let next = app.buttons["continueLabMapping"].firstMatch; reveal(next); next.tap()
        let group = app.buttons["labSubject-0"].firstMatch; reveal(group); group.tap(); XCTAssertTrue(group.isSelected); settleLabFrame(group); snap("482-lab-import-large-person")
        nativeSwitch("labPersonChecked", enabled: true); let review = app.buttons["reviewLabImport"].firstMatch; reveal(review); review.tap()
        XCTAssertTrue(app.staticTexts["labImportIncludedCount"].waitForExistence(timeout: 10)); snap("483-lab-import-large-review")
        let reported = app.staticTexts["Reported collection wording: 20/10/2026"].firstMatch; revealLabExcerpt(reported); snap("497-lab-import-large-review-timing")
        nativeSwitch("includeLabImport-3", enabled: false)
        let edit = app.buttons["editLabImport-1"].firstMatch; reveal(edit); edit.tap()
        XCTAssertTrue(app.buttons["finishLabResult"].waitForExistence(timeout: 5)); snap("484-lab-import-large-source-editor")
        labField("labReportedResult", value: "<4,0", replacing: true)
        let field = openLabField("labReportedResult"); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); settleLabFrame(field); snap("485-lab-import-large-keyboard"); tap("finishLabField")
        let timing = openLabField("labReportedTiming"); XCTAssertEqual(timing.value as? String, "20/10/2026"); snap("486-lab-import-large-reported-timing"); tap("finishLabField"); tap("finishLabResult")
        nativeSwitch("acknowledgeLabImport", enabled: true); snap("487-lab-import-large-acknowledgement"); tap("saveLabImport")
        XCTAssertTrue(app.staticTexts["labImportSaved"].waitForExistence(timeout: 10)); snap("488-lab-import-large-complete")
        let completedAction = app.buttons["viewImportedLabRecord"].firstMatch; revealLabExcerpt(completedAction); snap("498-lab-import-large-complete-action")
        let footer = app.staticTexts["Keep the original file separately. The saved record contains your included fields and mapped source cells."].firstMatch; revealLabExcerpt(footer); snap("499-lab-import-large-complete-footer"); revealLabExcerpt(completedAction); completedAction.tap()
        XCTAssertTrue(app.staticTexts["<4,0 µg/L"].waitForExistence(timeout: 5)); snap("489-lab-import-large-saved")
    }
    func testLabFileImportFormatsAndCancellation() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding(); openLabImport(); try chooseLabFile("Lumen-lab-invalid")
        XCTAssertTrue(app.alerts["Couldn't read lab file"].waitForExistence(timeout: 20)); snap("490-lab-import-malformed"); tap("OK")
        XCTAssertTrue(app.buttons["chooseLabFile"].exists); XCTAssertFalse(app.buttons["saveLabImport"].exists)
        tap("cancelLabImport"); tap("Discard draft")
        openLabImport(); tap("labSeparator"); tap("Semicolon"); try chooseLabFile("Lumen-lab-regional")
        XCTAssertTrue(app.staticTexts["labTableReady"].waitForExistence(timeout: 20))
        let delimiter = app.buttons["Change separator"].firstMatch; reveal(delimiter); delimiter.tap(); tap("labSeparator"); tap("Comma")
        XCTAssertFalse(app.buttons["continueLabMapping"].isEnabled); XCTAssertTrue(app.staticTexts["labSeparatorNeedsRead"].exists); snap("500-lab-import-separator-needs-read")
        tap("labSeparator"); tap("Semicolon"); continueLabFileMapping(hasSubject: false)
        XCTAssertTrue(app.staticTexts["<5,0 µg/L"].exists); snap("491-lab-import-regional"); tap("cancelLabImport"); tap("Discard draft")
        openLabImport(); try chooseLabFile("Lumen-lab-tab"); continueLabFileMapping(hasSubject: false)
        XCTAssertTrue(app.staticTexts["12.00 mg/L"].exists); snap("492-lab-import-tsv"); tap("cancelLabImport"); tap("Discard draft")
        openLabImport(); try chooseLabFile("Lumen-lab-paged"); continueLabFileMapping(hasSubject: false)
        let selection = app.buttons["labImportSelection"].firstMatch; reveal(selection); selection.tap(); tap("Exclude all results")
        nativeSwitch("includeLabImport-1", enabled: true)
        let nextPage = app.buttons["Next"].firstMatch; reveal(nextPage); nextPage.tap()
        XCTAssertTrue(app.staticTexts["Synthetic row 11"].waitForExistence(timeout: 5)); snap("501-lab-import-next-page")
        let pages = app.buttons["labImportPagePicker"].firstMatch; reveal(pages); pages.tap(); tap("Results 21–21")
        XCTAssertTrue(app.staticTexts["Synthetic row 21"].waitForExistence(timeout: 5)); nativeSwitch("includeLabImport-21", enabled: true); snap("493-lab-import-last-page")
        reveal(pages); pages.tap(); tap("Results 1–10"); XCTAssertEqual(app.switches["includeLabImport-1"].value as? String, "1"); snap("502-lab-import-retained-first-page")
        reveal(pages); pages.tap(); tap("Results 21–21"); XCTAssertEqual(app.switches["includeLabImport-21"].value as? String, "1")
        nativeSwitch("acknowledgeLabImport", enabled: true); XCTAssertTrue(app.buttons["saveLabImport"].isEnabled)
        let back = app.buttons["labImportBackToMapping"].firstMatch; reveal(back); back.tap(); tap("Discard row review")
        XCTAssertTrue(app.staticTexts["labTableReady"].waitForExistence(timeout: 5)); snap("494-lab-import-mapping-return")
        tap("cancelLabImport"); tap("Discard draft"); XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-record-' ")).count, 0)
    }
    func testLabFileImportLimitsAndLargeMapping() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding(); openLabImport(); try chooseLabFile("Lumen-lab-limits"); continueLabFileMapping(hasSubject: false)
        let longSource = app.staticTexts["labImportSourceIssue-1"].firstMatch; reveal(longSource); XCTAssertEqual(longSource.label, "These source cells exceed the \(2000.formatted())-character limit. Exclude this row or map fewer optional columns."); snap("503-lab-import-overlong-source")
        nativeSwitch("acknowledgeLabImport", enabled: true); XCTAssertFalse(app.buttons["saveLabImport"].isEnabled)
        nativeSwitch("includeLabImport-1", enabled: false)
        let invalid = app.buttons["editLabImport-2"].firstMatch; reveal(invalid); invalid.tap()
        XCTAssertTrue(app.buttons["finishLabResult"].waitForExistence(timeout: 5)); XCTAssertFalse(app.buttons["finishLabResult"].isEnabled)
        let hint = app.staticTexts["labReportedResultIssue"].firstMatch; reveal(hint); XCTAssertEqual(hint.label, "Reported result is required."); snap("504-lab-import-missing-result")
        let discarded = openLabField("labReportedResult"); discarded.typeText("Discard this synthetic change")
        tap("cancelLabText"); XCTAssertTrue(app.alerts["Discard this text edit?"].waitForExistence(timeout: 5)); snap("521-lab-import-text-discard"); tap("Discard changes")
        XCTAssertFalse(app.buttons["finishLabResult"].isEnabled); XCTAssertTrue(hint.exists)
        labField("labReportedResult", value: String(repeating: "9", count: 501), searchUp: true)
        reveal(hint); XCTAssertEqual(hint.label, "Reported result exceeds 500 characters."); XCTAssertFalse(app.buttons["finishLabResult"].isEnabled); snap("518-lab-import-specific-field-limit")
        labField("labReportedResult", value: "2.00", replacing: true, searchUp: true, finish: false)
        tap("cancelLabText"); tap("Keep editing"); XCTAssertEqual(app.textViews["labReportedResult"].value as? String, "2.00"); snap("522-lab-import-text-kept"); tap("finishLabField"); tap("finishLabResult")
        labField("labImportTitle", value: String(repeating: "T", count: 501), replacing: true, doneIdentifier: "finishLabImportTitle", searchUp: true)
        let titleHint = app.staticTexts["labImportTitleIssue"].firstMatch; reveal(titleHint); XCTAssertEqual(titleHint.label, "Record title exceeds 500 characters."); snap("505-lab-import-title-limit")
        nativeSwitch("acknowledgeLabImport", enabled: true); XCTAssertFalse(app.buttons["saveLabImport"].isEnabled)
        labField("labImportTitle", value: "Synthetic limits review", replacing: true, doneIdentifier: "finishLabImportTitle", searchUp: true)
        nativeSwitch("acknowledgeLabImport", enabled: true); XCTAssertTrue(app.buttons["saveLabImport"].isEnabled)
        tap("cancelLabImport"); tap("Discard draft")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        openLabImport(); try chooseLabFile("Lumen-lab-long-header"); XCTAssertTrue(app.staticTexts["labTableReady"].waitForExistence(timeout: 20))
        let name = app.buttons["labColumn-test"].firstMatch; reveal(name); name.tap(); tap("Test name recorded by the laboratory")
        revealLabExcerpt(name); XCTAssertEqual(name.value as? String, "Test name recorded by the laboratory"); snap("506-lab-import-large-long-heading")
        let absent = app.buttons["labColumn-method"].firstMatch; reveal(absent); revealLabExcerpt(absent); XCTAssertEqual(absent.value as? String, "Not mapped"); snap("507-lab-import-large-unmapped-menu")
        tap("cancelLabImport"); tap("Discard draft")
    }

    func testLabFileImportValidationPresentation() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding()
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        openLabImport(); try chooseLabFile("Lumen-lab-limits"); continueLabFileMapping(hasSubject: false)
        let source = app.staticTexts["labImportSourceIssue-1"].firstMatch; reveal(source); revealLabExcerpt(source)
        XCTAssertEqual(source.label, "These source cells exceed the \(2000.formatted())-character limit. Exclude this row or map fewer optional columns."); snap("519-lab-import-large-source-limit")
        nativeSwitch("includeLabImport-1", enabled: false)
        let edit = app.buttons["editLabImport-2"].firstMatch; reveal(edit); edit.tap()
        let missing = app.staticTexts["labReportedResultIssue"].firstMatch; reveal(missing); revealLabExcerpt(missing)
        XCTAssertEqual(missing.label, "Reported result is required."); XCTAssertFalse(app.buttons["finishLabResult"].isEnabled); snap("520-lab-import-large-missing-result")
        labField("labReportedResult", value: "2.00", searchUp: true); tap("finishLabResult")
        nativeSwitch("acknowledgeLabImport", enabled: true); XCTAssertTrue(app.buttons["saveLabImport"].isEnabled)
        tap("cancelLabImport"); tap("Discard draft")
    }

    func testLabFileImportSmallScreen() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        XCTAssertEqual(app.frame.width, 375, accuracy: 0.1); XCTAssertEqual(app.frame.height, 667, accuracy: 0.1)
        finishOnboarding(); openLabImport(); snap("508-lab-import-small-intro")
        tap("labSeparator"); tap("Semicolon"); try chooseLabFile("Lumen-lab-regional")
        XCTAssertTrue(app.staticTexts["labTableReady"].waitForExistence(timeout: 20)); snap("509-lab-import-small-columns")
        let next = app.buttons["continueLabMapping"].firstMatch; reveal(next); next.tap()
        XCTAssertFalse(app.buttons["reviewLabImport"].isEnabled)
        nativeSwitch("labPersonChecked", enabled: true); snap("510-lab-import-small-person-check")
        let review = app.buttons["reviewLabImport"].firstMatch; reveal(review); review.tap()
        XCTAssertTrue(app.staticTexts["labImportIncludedCount"].waitForExistence(timeout: 10)); snap("511-lab-import-small-review")
        let source = app.buttons["labImportSource-1"].firstMatch; reveal(source); source.tap()
        let cells = app.staticTexts.matching(NSPredicate(format: "identifier == 'labImportSource-1' AND label BEGINSWITH 'Imported data row 1' ")).firstMatch
        revealLabExcerpt(cells); XCTAssertTrue(cells.label.contains("<5,0")); snap("512-lab-import-small-source")
        let edit = app.buttons["editLabImport-1"].firstMatch; reveal(edit); edit.tap()
        XCTAssertTrue(app.buttons["finishLabResult"].waitForExistence(timeout: 5))
        labField("labReportedResult", value: "<4,0", replacing: true)
        labField("labReportedResult", value: String(repeating: "9", count: 501), replacing: true, finish: false)
        let field = app.textViews["labReportedResult"].firstMatch
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); settleLabFrame(field)
        XCTAssertLessThanOrEqual(field.frame.maxY, app.keyboards.firstMatch.frame.minY + 1); XCTAssertEqual(field.value as? String, String(repeating: "9", count: 501)); snap("523-lab-import-small-long-editor-keyboard")
        labField("labReportedResult", value: "<4,0", replacing: true, finish: false, inOpenEditor: true)
        snap("513-lab-import-small-keyboard"); tap("finishLabField"); tap("finishLabResult")
        nativeSwitch("acknowledgeLabImport", enabled: true); tap("saveLabImport")
        XCTAssertTrue(app.staticTexts["labImportSaved"].waitForExistence(timeout: 10)); snap("514-lab-import-small-complete")
        let view = app.buttons["viewImportedLabRecord"].firstMatch; reveal(view); view.tap()
        XCTAssertTrue(app.staticTexts["<4,0 µg/L"].waitForExistence(timeout: 5)); snap("515-lab-import-small-saved")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); tap("cancelLabImport")
        openLabImport(); tap("labSeparator"); tap("Semicolon"); try chooseLabFile("Lumen-lab-regional"); continueLabFileMapping(hasSubject: false)
        nativeSwitch("acknowledgeLabImport", enabled: true); tap("saveLabImport")
        XCTAssertTrue(app.alerts["Save another copy?"].waitForExistence(timeout: 5)); snap("516-lab-import-small-duplicate"); tap("Keep reviewing")
        tap("cancelLabImport"); tap("Discard draft")
        openRecordImport(); try chooseLabFile("Lumen-lab-regional", chooseIdentifier: "chooseRecordFile")
        XCTAssertTrue(app.staticTexts["recordPreviewReady"].waitForExistence(timeout: 20))
        nativeSwitch("acknowledgeRecordText", enabled: true); tap("saveReviewedRecord")
        XCTAssertTrue(app.alerts["Save another copy?"].waitForExistence(timeout: 5)); snap("517-lab-import-small-general-route-duplicate"); tap("Keep reviewing"); tap("cancelRecordImport")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-record-' ")).count, 1)
    }

    func testLabImportReceiptAfterRemovingResults() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding(); openLabImport(); tap("labSeparator"); tap("Semicolon"); try chooseLabFile("Lumen-lab-regional"); continueLabFileMapping(hasSubject: false)
        nativeSwitch("acknowledgeLabImport", enabled: true); tap("saveLabImport")
        XCTAssertTrue(app.staticTexts["labImportSaved"].waitForExistence(timeout: 10)); tap("viewImportedLabRecord")
        XCTAssertTrue(app.staticTexts["<5,0 µg/L"].waitForExistence(timeout: 5)); let review = app.buttons["reviewSavedLabResults"].firstMatch; reveal(review); review.tap()
        let remove = app.buttons["Remove Ferritin from draft"].firstMatch; reveal(remove); remove.tap(); tap("Remove result")
        nativeSwitch("acknowledgeLabResults", enabled: true); tap("saveLabResults")
        let sourceOnly = app.staticTexts["labImportSourceOnly"].firstMatch; XCTAssertTrue(sourceOnly.waitForExistence(timeout: 5)); reveal(sourceOnly); snap("524-lab-import-removed-transcriptions-keeps-receipt")
        XCTAssertFalse(app.staticTexts["<5,0 µg/L"].exists)
        let receipt = app.buttons["labImportReceipt"].firstMatch; reveal(receipt); receipt.tap()
        let text = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Originally imported mapped cells:' ")).firstMatch; revealLabExcerpt(text)
        XCTAssertTrue(text.label.contains("Lumen-lab-regional.csv")); XCTAssertTrue(text.label.contains("Input SHA-256: dd6b39c9e7f43ee5ef13fff6ddb7fd9893ddf25f70f28e8000d4f3c4aaacdfdc")); snap("525-lab-import-source-only-receipt")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); openLabRecord("Lumen-lab-regional")
        XCTAssertTrue(sourceOnly.waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["<5,0 µg/L"].exists)
        reveal(receipt); receipt.tap(); revealLabExcerpt(text); XCTAssertTrue(text.label.contains("Input SHA-256: dd6b39c9e7f43ee5ef13fff6ddb7fd9893ddf25f70f28e8000d4f3c4aaacdfdc")); snap("526-lab-import-source-only-relaunch")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        openLabImport(); tap("labSeparator"); tap("Semicolon"); try chooseLabFile("Lumen-lab-regional"); continueLabFileMapping(hasSubject: false)
        nativeSwitch("acknowledgeLabImport", enabled: true); tap("saveLabImport")
        XCTAssertTrue(app.alerts["Save another copy?"].waitForExistence(timeout: 5)); snap("527-lab-import-source-only-duplicate"); tap("Keep reviewing"); tap("cancelLabImport"); tap("Discard draft")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-record-' ")).count, 1)
    }

    func prepareLabLibrary() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        finishOnboarding(); openBackupSettings(); try chooseBackupFixture("Lumen-backup-labs")
        _ = backupPreview(); confirmBackupRestore()
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap(); tap("Done"); tab("Library")
    }
    func openLabField(_ identifier: String, searchUp: Bool = false) -> XCUIElement {
        let button = app.buttons["editFull-" + identifier].firstMatch
        if searchUp {
            for _ in 0..<8 where !button.exists || button.frame.isEmpty {
                let top = app.navigationBars.firstMatch.frame.maxY + 24
                let upper = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: top))
                let lower = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: app.frame.maxY - 80))
                upper.press(forDuration: 0.05, thenDragTo: lower)
            }
        }
        reveal(button); button.tap()
        let field = app.textViews[identifier].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); settleLabFrame(field)
        return field
    }
    func labField(_ identifier: String, value: String, replacing: Bool = false, doneIdentifier: String = "finishLabField", searchUp: Bool = false, finish: Bool = true, inOpenEditor: Bool = false, capturePrefix: String? = nil) {
        let field = inOpenEditor ? app.textViews[identifier].firstMatch : openLabField(identifier, searchUp: searchUp)
        if replacing {
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            let longValue = (field.value as? String)?.count == 501
            let selectAll = app.buttons["selectAllLabText"].firstMatch
            XCTAssertTrue(selectAll.waitForExistence(timeout: 5)); XCTAssertTrue(selectAll.isHittable); selectAll.tap()
            if let capturePrefix { snap(capturePrefix + "-selection-keyboard") }
            if longValue { snap("528-lab-import-full-selection-action") }
            field.typeText(XCUIKeyboardKey.delete.rawValue)
            let cleared = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in field.exists && field.value as? String == "" }, object: field)
            let clearing = XCTWaiter.wait(for: [cleared], timeout: 5)
            if clearing != .completed { print(app.debugDescription); snap("lab-field-not-cleared-" + identifier) }
            XCTAssertEqual(clearing, .completed, "Wait for the native field to reflect the complete deletion")
            XCTAssertEqual(field.value as? String, "", "Clear the full selected value before entering the correction")
        } else { field.tap() }
        field.typeText(value)
        let entered = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in field.exists && field.value as? String == value }, object: field)
        let entering = XCTWaiter.wait(for: [entered], timeout: 5)
        if entering != .completed { print(app.debugDescription); snap("lab-field-incomplete-" + identifier) }
        XCTAssertEqual(entering, .completed, "Wait for the native field to reflect all dispatched characters")
        XCTAssertEqual(field.value as? String, value)
        if let capturePrefix {
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            XCTAssertTrue(app.buttons["selectAllLabText"].isHittable && app.buttons[doneIdentifier].isHittable)
            snap(capturePrefix + "-keyboard-done")
        }
        if finish { tap(doneIdentifier) }
    }
    func openLabRecord(_ title: String) {
        let document = app.buttons[title].firstMatch; reveal(document); document.tap()
        let review = app.buttons["reviewSavedLabResults"].firstMatch; reveal(review)
    }
    func settleLabFrame(_ element: XCUIElement, pixelTolerance: CGFloat = 0, timeout: TimeInterval = 8) {
        var frame = CGRect.null
        var stableSince = ProcessInfo.processInfo.systemUptime
        let stable = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            guard element.exists else { return false }
            let next = element.frame, now = ProcessInfo.processInfo.systemUptime
            let equal = pixelTolerance == 0 ? next == frame : !frame.isNull
                && abs(next.minX - frame.minX) <= pixelTolerance && abs(next.minY - frame.minY) <= pixelTolerance
                && abs(next.width - frame.width) <= pixelTolerance && abs(next.height - frame.height) <= pixelTolerance
            if !equal {
                if pixelTolerance > 0 { print("CONTEXT TEXT FRAME SETTLING", frame, "to", next) }
                frame = next; stableSince = now
            }
            return !next.isEmpty && now - stableSince >= 0.5
        }, object: element)
        let result = XCTWaiter.wait(for: [stable], timeout: timeout)
        if result != .completed { snap("unsettled-native-frame"); print(element.debugDescription) }
        XCTAssertEqual(result, .completed)
    }
    func revealLabExcerpt(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5)); settleLabFrame(element)
        for _ in 0..<12 {
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            // A sheet covers the Library tab bar; its background AX node isn't
            // an occluder. Only reserve a tab bar that can actually be touched.
            let bar = app.tabBars.firstMatch
            let bottom = bar.exists && bar.isHittable ? bar.frame.minY - 12 : app.frame.maxY - 40
            if element.frame.minY >= top && element.frame.maxY <= bottom { return }
            // Move only the measured overflow. A full-height drag can alternate
            // a tall label between opposite clipped edges without ever fitting it.
            let above = element.frame.minY < top
            let overflow = above ? top - element.frame.minY : element.frame.maxY - bottom
            let distance = min(bottom - top - 40, max(40, overflow + 12))
            let startY = above ? top + 20 : bottom - 20
            let endY = startY + (above ? distance : -distance)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: startY))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: endY))
            start.press(forDuration: 0.05, thenDragTo: end)
            settleLabFrame(element)
        }
        print("Unreachable lab capture frame: \(element.frame)")
        snap("lab-excerpt-not-fully-visible"); XCTFail("The fixture's complete content must be visible for capture")
    }
    func testReviewedLabRecords() throws {
        try prepareLabLibrary(); openLabRecord("Synthetic laboratory report"); snap("430-labs-before-review"); tap("reviewSavedLabResults")
        XCTAssertFalse(app.buttons["saveLabResults"].isEnabled); snap("431-labs-empty-review"); tap("addLabResult"); tap("chooseLabSource")
        let search = app.searchFields.firstMatch; XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("Ferritin")
        let source = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'labSource-' ")).firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5)); settleLabFrame(search)
        XCTAssertLessThanOrEqual(search.frame.maxY, app.keyboards.firstMatch.frame.minY); snap("432-labs-source-picker"); source.tap()
        XCTAssertTrue(app.staticTexts["labSelectedSource"].label.contains("Ferritin: <5,0 µg/L"))
        tap("labNextSourceLine"); XCTAssertTrue(app.staticTexts["labSelectedSource"].label.contains("Specimen: Serum")); snap("447-labs-wrapped-source")
        labField("labTestName", value: "Ferritin"); labField("labReportedResult", value: "<5,0"); labField("labUnit", value: "µg/L")
        labField("labReference", value: "15–150"); labField("labFlag", value: "L"); snap("433-labs-entered-result")
        tap("finishLabResult"); XCTAssertFalse(app.buttons["saveLabResults"].isEnabled)
        let reviewSource = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'labReviewSource-' ")).firstMatch; reveal(reviewSource); reviewSource.tap()
        let reviewText = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'labReviewSource-' AND label BEGINSWITH 'Ferritin:' ")).firstMatch; revealLabExcerpt(reviewText); XCTAssertTrue(reviewText.label.contains("Specimen: Serum")); snap("448-labs-source-before-save")
        nativeSwitch("acknowledgeLabResults", enabled: true); XCTAssertTrue(app.buttons["saveLabResults"].isEnabled); snap("434-labs-review-ready"); tap("saveLabResults")
        XCTAssertTrue(app.staticTexts["<5,0 µg/L"].waitForExistence(timeout: 5)); snap("435-labs-saved")
        let excerpt = app.buttons["Saved source excerpt"].firstMatch; reveal(excerpt); excerpt.tap()
        let savedSource = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'labSavedSourceText-' ")).firstMatch; revealLabExcerpt(savedSource)
        XCTAssertTrue(savedSource.label.contains("Ferritin: <5,0 µg/L; reported reference")); snap("436-labs-exact-source")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); openLabRecord("Synthetic laboratory report")
        XCTAssertTrue(app.staticTexts["<5,0 µg/L"].exists); tap("reviewSavedLabResults"); nativeSwitch("acknowledgeLabResults", enabled: true)
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editLabResult-' ")).firstMatch; reveal(edit); edit.tap()
        labField("labReportedResult", value: "<4,0", replacing: true); tap("finishLabResult")
        XCTAssertEqual(app.switches["acknowledgeLabResults"].value as? String, "0"); XCTAssertFalse(app.buttons["saveLabResults"].isEnabled); snap("437-labs-edit-resets-review")
        tap("cancelLabReview"); XCTAssertTrue(app.alerts["Discard your lab review?"].waitForExistence(timeout: 5)); tap("Keep reviewing")
        nativeSwitch("acknowledgeLabResults", enabled: true); tap("saveLabResults"); XCTAssertTrue(app.staticTexts["<4,0 µg/L"].waitForExistence(timeout: 5))
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Library"); openLabRecord("Synthetic laboratory report")
        XCTAssertTrue(app.staticTexts["<4,0 µg/L"].exists)
        tap("Document actions"); tap("Edit")
        let body = app.textViews.firstMatch; reveal(body); body.tap(); body.typeKey("a", modifierFlags: .command); body.typeText("Corrected synthetic source. This version replaces the earlier reported values.")
        tap("Save")
        let changed = app.staticTexts["labSavedSourceChanged"].firstMatch; reveal(changed); XCTAssertTrue(changed.exists); snap("438-labs-source-changed")
        tap("reviewSavedLabResults")
        let remove = app.buttons["Remove Ferritin from draft"].firstMatch; reveal(remove); remove.tap(); tap("Remove result")
        nativeSwitch("acknowledgeLabResults", enabled: true); XCTAssertTrue(app.buttons["saveLabResults"].isEnabled); snap("439-labs-remove-preserves-record"); tap("saveLabResults")
        XCTAssertTrue(app.buttons["Add lab results"].waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["<4,0 µg/L"].exists)
    }
    func testLabRecordPresentation() throws {
        try prepareLabLibrary(); openLabRecord("Saved synthetic lab results")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", "dark"]; app.launch(); tab("Library"); openLabRecord("Saved synthetic lab results"); snap("440-labs-dark-saved")
        let excerpt = app.buttons["Saved source excerpt"].firstMatch; reveal(excerpt); excerpt.tap()
        let darkSource = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'labSavedSourceText-' ")).firstMatch; revealLabExcerpt(darkSource); snap("441-labs-dark-source")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); tab("Library"); openLabRecord("Saved synthetic lab results"); snap("442-labs-large-saved")
        let largeExcerpt = app.buttons.matching(NSPredicate(format: "label == %@", "Saved source excerpt")).element(boundBy: 1); reveal(largeExcerpt); largeExcerpt.tap()
        let largeSource = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'labSavedSourceText-' ")).firstMatch; revealLabExcerpt(largeSource); snap("450-labs-large-exact-source")
        let review = app.buttons["reviewSavedLabResults"].firstMatch; reveal(review); review.tap(); settleLabFrame(app.buttons["addLabResult"].firstMatch); snap("443-labs-large-review")
        let checked = app.switches["acknowledgeLabResults"].firstMatch; reveal(checked); snap("444-labs-large-acknowledgement")
        nativeSwitch("acknowledgeLabResults", enabled: true); XCTAssertTrue(app.buttons["saveLabResults"].isEnabled)
        let edit = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editLabResult-' ")).firstMatch; reveal(edit); edit.tap()
        XCTAssertTrue(app.buttons["finishLabResult"].waitForExistence(timeout: 5)); snap("445-labs-large-editor")
        let unit = app.buttons["editFull-labUnit"].firstMatch; reveal(unit); snap("446-labs-large-result-fields")
        labField("labReportedResult", value: "<5,0\nSynthetic qualifier retained.", replacing: true)
        let result = openLabField("labReportedResult")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); settleLabFrame(result); snap("449-labs-large-editing-keyboard"); tap("finishLabField")
        let day = app.switches["labHasCollectionDay"].firstMatch; reveal(day); snap("451-labs-large-collection-day")
    }

    func askLibrary(_ question: String, replies: Int = 1) {
        let input = app.textFields["coachInput"].firstMatch
        let field = input.exists ? input : app.textViews["coachInput"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5)); field.tap(); field.typeText(question); tap("coachSend")
        let count = NSPredicate(format: "count == %d", replies)
        expectation(for: count, evaluatedWith: coachMessages)
        waitForExpectations(timeout: 30)
    }

    func openLibraryReference() {
        let disclosure = app.buttons["libraryReferencesToggle"].firstMatch; reveal(disclosure)
        let source = app.buttons["library-reference-1"].firstMatch
        if disclosure.value as? String == "Collapsed" { disclosure.tap() }
        reveal(source); source.tap()
        XCTAssertTrue(app.navigationBars["Saved reference"].waitForExistence(timeout: 5))
        XCTAssertTrue(referenceExcerpt.label.contains("12.5 mg/L"))
    }

    func testLibraryRetrievalAndWithdrawal() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch()
        try prepareRetrievalLibrary(allShared: true)
        snap("210-library-search-intro")
        askLibrary("Find my walking records.")
        let allMatches = app.buttons["libraryReferencesToggle"].firstMatch; reveal(allMatches); allMatches.tap()
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-reference-' ")).count, 4)
        let fourth = app.buttons["library-reference-4"].firstMatch; reveal(fourth); snap("209-four-literal-library-matches"); fourth.tap()
        XCTAssertTrue(referenceExcerpt.waitForExistence(timeout: 5)); XCTAssertTrue(referenceExcerpt.label.contains("walking route")); tap("Done")
        tap("Conversation actions"); tap("New conversation")
        askLibrary("What does my record say about ferritin?")
        let reply = coachMessages.firstMatch
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
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Assistant")
        openLibraryReference(); snap("217-library-reference-persisted"); tap("Done")
        askLibrary("What does my record say about ferritin?", replies: 2)
        XCTAssertTrue(coachMessages.element(boundBy: 1).label.contains("No match in the shared documents searched"))
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
        XCTAssertEqual(coachMessages.count, 2, "Quoting must not send the draft")
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
        let excerpt = referenceExcerpt
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
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 30))
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
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 5))
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
        XCTAssertEqual(userMessages.count, 1)
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
        XCTAssertEqual(userMessages.count, 1)
    }

    func openScheduledPlan() {
        tab("Assistant"); tap("Conversation actions"); tap("Make a multiweek plan")
        XCTAssertTrue(app.navigationBars["Make a plan"].waitForExistence(timeout: 5))
    }

    func openLibrarySearchSettings() {
        tab("Today"); tap("Settings")
        let link = app.buttons["librarySearchSettings"].firstMatch; reveal(link); link.tap()
        XCTAssertTrue(app.navigationBars["Library search"].waitForExistence(timeout: 5))
    }
    func closeLibrarySearchSettings() {
        app.navigationBars["Library search"].buttons.element(boundBy: 0).tap(); tap("Done")
    }
    func createSemanticNote(title: String, body: String, shared: Bool) {
        tab("Library"); tap("Add document"); tap("Write a note")
        let titleField = app.textFields["Document title"].firstMatch; XCTAssertTrue(titleField.waitForExistence(timeout: 5))
        titleField.tap(); titleField.typeText(title)
        let text = app.textViews.firstMatch; text.tap(); text.typeText(body)
        XCTAssertEqual(text.value as? String, body)
        if shared { nativeSwitch("Use in assistant", enabled: true) }
        tap("Save"); XCTAssertTrue(app.navigationBars["Library"].waitForExistence(timeout: 5))
    }
    func prepareIdentifierNote(_ title: String, _ body: String, shared: Bool = true) {
            // Save first, then consent on the normal detail screen. This avoids
            // asking the harness to scroll a switch behind an active editor.
            tab("Library")
            if !app.buttons[title].waitForExistence(timeout: 1) { createSemanticNote(title: title, body: body, shared: false) }
            let saved = app.buttons[title].firstMatch; reveal(saved); saved.tap()
            nativeSwitch("Use in assistant", enabled: shared)
            app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
    }
    func prepareReviewedLabContext(_ arguments: [String] = []) throws {
        app.terminate(); app.launchArguments = ["-resetForUITests"] + arguments; app.launch(); finishOnboarding()
        openBackupSettings(); try chooseBackupFixture("Lumen-backup-lab-context"); _ = backupPreview(); confirmBackupRestore()
        app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap(); tap("Done")
        tab("Library"); let document = app.buttons["Reviewed source context"].firstMatch; reveal(document); document.tap()
        nativeSwitch("Use in assistant", enabled: true); app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        tab("Assistant")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Provider: Built-in coach.'")).firstMatch.waitForExistence(timeout: 5))
    }
    func openReviewedLabReference() -> XCUIElement {
        let disclosure = app.buttons["libraryReferencesToggle"].firstMatch; reveal(disclosure); disclosure.tap()
        let first = app.buttons["library-reference-1"].firstMatch; reveal(first); first.tap()
        let fact = app.descendants(matching: .any).matching(identifier: "reference-lab-fact-lab-context-ferritin").firstMatch
        XCTAssertTrue(fact.waitForExistence(timeout: 5))
        XCTAssertTrue(fact.label.contains("Reported result: <4,0")); XCTAssertTrue(fact.label.contains("Reported unit: µg/L"))
        XCTAssertTrue(fact.label.contains("Collection day: 2026-10-20")); XCTAssertTrue(fact.label.contains("Saved source excerpt:")); XCTAssertTrue(fact.label.contains("<5,0"))
        return fact
    }
    func testReviewedLabContextLifecycle() throws {
        try prepareReviewedLabContext()
        askLibrary("COHERENCECANARY")
        let reply = coachMessages.firstMatch
        XCTAssertTrue(reply.label.contains("Reported result: <4,0")); XCTAssertTrue(reply.label.contains("Collection day: 2026-10-20")); XCTAssertFalse(reply.label.contains("PRIVATE-LAB-CONTEXT-CANARY"))
        XCTAssertTrue(reply.label.contains("*literal* [source](https://synthetic.invalid)"))
        snap("820-lab-context-literal-reply")
        let fact = openReviewedLabReference(); captureIdentifierText(fact, prefix: "821-lab-context-complete-fields")
        tap("Done"); app.terminate(); app.launchArguments = []; app.launch(); tab("Assistant")
        let restored = openReviewedLabReference(); captureIdentifierText(restored, prefix: "827-lab-context-relaunch-fields")
        let open = app.buttons["Open in Library"].firstMatch; reveal(open); XCTAssertTrue(open.isHittable); snap("822-lab-context-source-actions")
        open.tap(); nativeSwitch("Use in assistant", enabled: false)
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        let retained = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'This saved excerpt and its reviewed fields stay with the earlier reply.'")).firstMatch
        captureIdentifierText(retained, prefix: "828-lab-context-retained-sharing-off"); tap("Done")
        tap("Conversation actions"); tap("New conversation"); askLibrary("Find COHERENCECANARY in Library")
        let withdrawn = coachMessages.firstMatch
        XCTAssertTrue(withdrawn.label.contains("No Library documents are shared with the assistant")); XCTAssertFalse(withdrawn.label.contains("<4,0")); snap("823-lab-context-sharing-off")
        app.terminate(); app.launchArguments = []; app.launch(); tab("Assistant")
        XCTAssertTrue(coachMessages.firstMatch.label.contains("No Library documents are shared with the assistant"))
        tab("Library"); let crowded = app.buttons["Several reviewed results"].firstMatch; reveal(crowded); crowded.tap()
        nativeSwitch("Use in assistant", enabled: true); app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); tab("Assistant")
        tap("Conversation actions"); tap("New conversation"); askLibrary("Ferritin")
        let toggle = app.buttons["libraryReferencesToggle"].firstMatch; reveal(toggle); toggle.tap()
        let source = app.buttons["library-reference-1"].firstMatch; reveal(source); source.tap()
        let omitted = app.staticTexts["reference-lab-facts-omitted"].firstMatch
        XCTAssertTrue(omitted.waitForExistence(timeout: 5)); revealLabExcerpt(omitted); snap("824-lab-context-complete-omission")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "reference-lab-fact-lab-context-overlap-0").firstMatch.exists)
    }
    func testReviewedLabContextPresentation() throws {
        try prepareReviewedLabContext(["-lumen.appearance", "light"])
        for large in [false, true] {
            app.terminate(); app.launchArguments = ["-lumen.appearance", large ? "dark" : "light"] + (large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []); app.launch(); tab("Assistant")
            if !coachMessages.allElementsBoundByIndex.isEmpty { tap("Conversation actions"); tap("New conversation") }
            askLibrary("COHERENCECANARY")
            let prefix = large ? "dark-xxxl" : "light"
            let fact = openReviewedLabReference(); captureIdentifierText(fact, prefix: "825-lab-context-" + prefix + "-full-fields")
            let open = app.buttons["Open in Library"].firstMatch; reveal(open); settleLabFrame(open)
            XCTAssertTrue(open.isHittable && app.buttons["Done"].isHittable); snap("826-lab-context-" + prefix + "-actions"); tap("Done")
        }
    }
    func captureReviewedSourceToFooter(_ prefix: String) {
        let footer = app.staticTexts["Saved text may contain errors. Check names, numbers and units against the original."].firstMatch
        XCTAssertTrue(footer.waitForExistence(timeout: 5))
        // UIKit can clip an oversized text view's AX frame to the screen.
        // Capture ordinary overlapping content drags to a separate end marker;
        // do not infer complete text coverage from that changing frame height.
        for part in 1...64 {
            settleLabFrame(footer)
            let top = app.navigationBars.firstMatch.frame.maxY + 12
            let bottom = app.frame.maxY - 12
            let frame = footer.frame
            print("Reviewed source sweep \(prefix) part\(part): footer \(frame), visible \(top)...\(bottom)")
            snap(prefix + "-part\(part)")
            if frame.minY >= top && frame.maxY <= bottom { return }
            let distance = (bottom - top) * 0.55
            let route = app.buttons["Open in Library"].firstMatch
            let occupied = route.exists ? route.frame.insetBy(dx: -24, dy: -16) : CGRect.null
            let x = app.frame.midX
            var y = bottom - 35
            if occupied.contains(CGPoint(x: x, y: y)) { y = top + distance + 24 }
            if occupied.contains(CGPoint(x: x, y: y)) { y = top + 60 }
            XCTAssertFalse(occupied.contains(CGPoint(x: x, y: y)), "Capture drag must not start on Library navigation")
            let step = min(distance, y - top - 24)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y - step))
            print("Reviewed source drag \(prefix): (\(x),\(y)) to (\(x),\(y - step)); Library action \(occupied)")
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
            XCTAssertTrue(app.navigationBars["Saved reference"].exists, "Reader scrolling must not activate Library navigation")
        }
        XCTFail("The complete source footer was not reached through ordinary overlapping scrolling")
    }
    func testReviewedLabContextSourceStatesPresentation() throws {
        try prepareReviewedLabContext(["-lumen.appearance", "light"])
        for large in [false, true] {
            app.terminate(); app.launchArguments = ["-lumen.appearance", large ? "dark" : "light"] + (large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : []); app.launch(); tab("Assistant")
            if !coachMessages.allElementsBoundByIndex.isEmpty { tap("Conversation actions"); tap("New conversation") }
            let prefix = large ? "dark-xxxl" : "light"
            askLibrary("COHERENCECANARY")
            let reply = coachMessages.firstMatch
            XCTAssertTrue(reply.label.contains("*literal* [source](https://synthetic.invalid)") && reply.label.contains("COHERENCECANARY"))
            captureReviewedLabChat("835-lab-context-" + prefix + "-literal-chat")
            _ = openReviewedLabReference()
            let heading = app.staticTexts["Reference 1"].firstMatch; settleLabFrame(heading)
            XCTAssertTrue(heading.isHittable)
            captureReviewedSourceToFooter("829-lab-context-" + prefix + "-source-through-footer")
            let open = app.buttons["Open in Library"].firstMatch; revealLabExcerpt(open)
            XCTAssertTrue(open.isHittable && app.buttons["Done"].isHittable); snap("830-lab-context-" + prefix + "-source-actions")
            open.tap(); nativeSwitch("Use in assistant", enabled: false)
            app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
            let retained = app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'This saved excerpt and its reviewed fields stay with the earlier reply.'")).firstMatch
            captureIdentifierText(retained, prefix: "831-lab-context-" + prefix + "-retained-caption", contentGestures: true)
            captureReviewedSourceToFooter("831-lab-context-" + prefix + "-retained-sharing-off")
            revealLabExcerpt(app.buttons["Open in Library"].firstMatch)
            XCTAssertTrue(app.buttons["Open in Library"].isHittable && app.buttons["Done"].isHittable); tap("Done")
            tab("Library"); let crowded = app.buttons["Several reviewed results"].firstMatch; reveal(crowded); crowded.tap()
            nativeSwitch("Use in assistant", enabled: true); app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); tab("Assistant")
            tap("Conversation actions"); tap("New conversation"); askLibrary("Ferritin")
            let disclosure = app.buttons["libraryReferencesToggle"].firstMatch; reveal(disclosure); disclosure.tap()
            let source = app.buttons["library-reference-1"].firstMatch; reveal(source); source.tap()
            let omitted = app.staticTexts["reference-lab-facts-omitted"].firstMatch
            XCTAssertTrue(omitted.waitForExistence(timeout: 5)); XCTAssertTrue(omitted.label.hasPrefix("5 overlapping reviewed results"))
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "reference-lab-fact-lab-context-overlap-0").firstMatch.exists)
            captureReviewedSourceToFooter("832-lab-context-" + prefix + "-complete-omission")
            let route = app.buttons["Open in Library"].firstMatch; revealLabExcerpt(route)
            XCTAssertTrue(route.isHittable && app.buttons["Done"].isHittable); snap("833-lab-context-" + prefix + "-omission-actions")
            if !large {
                route.tap(); nativeSwitch("Use in assistant", enabled: false); app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); tap("Done")
                tab("Library"); let original = app.buttons["Reviewed source context"].firstMatch; reveal(original); original.tap()
                nativeSwitch("Use in assistant", enabled: true); app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
            }
        }
    }
    func testLiteralUserQuestionPresentation() throws {
        finishOnboarding()
        for large in [false, true] {
            app.terminate()
            app.launchArguments = ["-lumen.appearance", large ? "dark" : "light"] + (large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
            app.launch(); tab("Assistant")
            let appearance = large ? "dark-xxxl" : "light"
            for (name, question) in [("identifier", "COHERENCECANARY"), ("source-characters", "*literal* [source](https://synthetic.invalid)"), ("short", "Hi")] {
                if userMessages.count > 0 { tap("Conversation actions"); tap("New conversation") }
                askLibrary(question)
                let sent = userMessages.firstMatch
                XCTAssertEqual(userMessages.count, 1); XCTAssertEqual(sent.label, question)
                let review = app.buttons["Review health entries"].firstMatch
                captureIdentifierText(sent, through: review, prefix: "836-user-question-" + appearance + "-" + name, contentGestures: true)
                if !large && name == "short" { XCTAssertLessThan(sent.frame.width, 80, "Short user messages must retain a content-sized bubble") }
            }
        }
    }
    func testReviewedLabContextLiteralChatTransition() throws {
        try prepareReviewedLabContext(["-lumen.appearance", "light"])
        app.terminate()
        app.launchArguments = ["-lumen.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); tab("Assistant"); askLibrary("COHERENCECANARY")
        XCTAssertEqual(userMessages.firstMatch.label, "COHERENCECANARY")
        let reply = coachMessages.firstMatch
        XCTAssertTrue(reply.label.hasPrefix("Matching saved text"))
        XCTAssertTrue(reply.label.contains("Reported result: <4,0") && reply.label.contains("*literal* [source](https://synthetic.invalid)"))
        XCTAssertFalse(reply.label.contains("PRIVATE-LAB-CONTEXT-CANARY"))
        captureReviewedLabChat("837-lab-context-dark-xxxl-current-question-and-reply")
    }
    func captureReviewedLabChat(_ prefix: String) {
        // The native question frame clips when it scrolls offscreen. Capture
        // it while visible, then continue from the shared SwiftUI action.
        // Both sequences include that complete action as an overlap landmark.
        let review = app.buttons["Review health entries"].firstMatch
        captureIdentifierText(userMessages.firstMatch, through: review, prefix: prefix + "-question", contentGestures: true)
        captureIdentifierText(review, through: app.buttons["libraryReferencesToggle"].firstMatch,
                              prefix: prefix + "-reply", contentGestures: true)
    }
    func testProviderTransportFallback() throws {
        app.terminate(); app.launchArguments = ["-providerTransportUITestMode"]; app.launch()
        if app.buttons["Get started"].waitForExistence(timeout: 2) { finishOnboarding() }
        prepareIdentifierNote("Sample one", "Sample TEST-AX1. Exact wording: not detected.")
        tab("Assistant"); tap("Conversation actions"); tap("New conversation")
        for (index, control) in ["Incomplete HTTP control", "Refusal HTTP control"].enumerated() {
            askLibrary("Find sample ID TEST-AX1. " + control + ".", replies: index + 1)
            let reply = coachMessages.element(boundBy: index)
            XCTAssertTrue(reply.label.hasPrefix("Matching saved text")); XCTAssertTrue(reply.label.contains("not detected"))
            XCTAssertFalse(reply.label.contains("SYNTHETIC-INCOMPLETE-ASSERTION"))
        }
        snap("810-provider-incomplete-refusal-fallback")
        askLibrary("Find sample ID TEST-AX1. Complete HTTP control.", replies: 3)
        let accepted = coachMessages.element(boundBy: 2)
        XCTAssertTrue(accepted.label.contains("Synthetic complete HTTP control. Local server only. [1]"))
        snap("811-provider-complete-http-control")
        let input = app.textFields["coachInput"].firstMatch; input.tap(); input.typeText("Find sample ID TEST-AX1. Slow HTTP control."); tap("coachSend")
        let stop = app.buttons["Stop response"].firstMatch; XCTAssertTrue(stop.waitForExistence(timeout: 5)); stop.tap()
        XCTAssertTrue(app.buttons["coachSend"].waitForExistence(timeout: 5))
        let stopped = NSPredicate(format: "exists == false"); expectation(for: stopped, evaluatedWith: stop); waitForExpectations(timeout: 8)
        XCTAssertEqual(coachMessages.count, 3)
        snap("812-provider-http-cancelled")
        app.terminate(); app.launchArguments = []; app.launch(); tab("Assistant")
        XCTAssertEqual(coachMessages.count, 3)
        XCTAssertFalse(coachMessages.allElementsBoundByIndex.contains { $0.label.contains("SYNTHETIC-INCOMPLETE-ASSERTION") })
        tap("Conversation actions"); tap("New conversation"); askLibrary("Find sample ID TEST-AX1")
        XCTAssertTrue(coachMessages.firstMatch.label.contains("not detected"))
        snap("813-provider-regular-lookup-after-relaunch")
    }
    func testProviderCitationRejection() throws {
        app.terminate(); app.launchArguments = ["-libraryCitationUITestMode"]; app.launch()
        if app.buttons["Get started"].waitForExistence(timeout: 2) { finishOnboarding() }
        prepareIdentifierNote("Sample one", "Sample TEST-AX1. Exact wording: not detected.")
        tab("Assistant"); tap("Conversation actions"); tap("New conversation")
        askLibrary("Find sample ID TEST-AX1. Invalid citation control.")
        func assertLiteral(_ index: Int) {
            let reply = coachMessages.element(boundBy: index)
            XCTAssertTrue(reply.label.hasPrefix("Matching saved text"))
            XCTAssertTrue(reply.label.contains("Sample TEST-AX1. Exact wording: not detected."))
            XCTAssertFalse(reply.label.contains("SYNTHETIC-REJECTED-ASSERTION"))
            XCTAssertFalse(reply.label.contains("reference unavailable"))
        }
        assertLiteral(0)
        XCTAssertTrue(app.staticTexts["Library lookup · on this iPhone"].firstMatch.exists)
        snap("800-citation-invalid-literal-fallback")
        let disclosure = app.buttons["libraryReferencesToggle"].firstMatch; reveal(disclosure); disclosure.tap()
        let source = app.buttons["library-reference-1"].firstMatch; reveal(source); source.tap()
        let excerpt = referenceExcerpt
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5)); XCTAssertEqual(excerpt.label, "Sample TEST-AX1. Exact wording: not detected.")
        snap("801-citation-fallback-exact-source"); tap("Done")
        askLibrary("Find sample ID TEST-AX1. Mixed citation control.", replies: 2); assertLiteral(1)
        askLibrary("Find sample ID TEST-AX1. Numbered citation control.", replies: 3); assertLiteral(2)
        askLibrary("Find sample ID TEST-AX1. Current citation control.", replies: 4)
        let accepted = coachMessages.element(boundBy: 3)
        XCTAssertTrue(accepted.label.contains("Synthetic current citation control. No provider request was sent. [1]"))
        XCTAssertFalse(accepted.label.contains("Matching saved text")); snap("802-citation-current-control")
        // Switch off the adapter, retain the saved conversation and exercise
        // ordinary production lookup and sharing withdrawal after relaunch.
        app.terminate(); app.launchArguments = []; app.launch(); tab("Assistant")
        XCTAssertFalse(coachMessages.allElementsBoundByIndex.contains { $0.label.contains("SYNTHETIC-REJECTED-ASSERTION") })
        prepareIdentifierNote("Sample one", "Sample TEST-AX1. Exact wording: not detected.", shared: false)
        tab("Assistant"); tap("Conversation actions"); tap("New conversation")
        askLibrary("Find sample ID TEST-AX1")
        let withdrawn = coachMessages.firstMatch
        XCTAssertTrue(withdrawn.label.contains("No match in the shared documents searched"))
        XCTAssertFalse(withdrawn.label.contains("not detected")); snap("803-citation-withdrawn-regular-lookup")
    }
    func testLiteralIdentifierLookupAndFollowup() throws {
        app.terminate(); app.launchArguments = []; app.launch()
        if app.buttons["Get started"].waitForExistence(timeout: 2) { finishOnboarding() }
        prepareIdentifierNote("Sample one", "Sample TEST-AX1. Exact wording: not detected.")
        prepareIdentifierNote("Sample two", "Sample TEST-AX2. Exact wording: detected.")
        prepareIdentifierNote("Invoice", "Invoice AF-740 totals 62.40 EUR. Payment status: paid.")
        prepareIdentifierNote("Private sample", "Sample TEST-AX9. PRIVATE-ID-CANARY.", shared: false)
        prepareIdentifierNote("Several samples", "Sample ID BX1: first wording.\n\nSample ID BX2: second wording.\n\nSample ID BX3: third wording.")
        let longID = String(repeating: "X", count: 95) + "1"
        prepareIdentifierNote("Long reference", "Sample " + longID + ". Exact wording: not detected.")
        tab("Assistant"); tap("Conversation actions"); tap("New conversation")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Provider: Built-in coach.'")).firstMatch.waitForExistence(timeout: 5))
        askLibrary("What is the wording for sample TEST-AX1?")
        let first = coachMessages.firstMatch
        XCTAssertTrue(first.label.contains("not detected")); XCTAssertFalse(first.label.contains("TEST-AX2")); XCTAssertFalse(first.label.contains("PRIVATE-ID-CANARY"))
        XCTAssertTrue(app.staticTexts["Library lookup · on this iPhone"].firstMatch.exists)
        snap("680-identifier-exact-sample")
        askLibrary("What about TEST-AX3?", replies: 2)
        let missing = coachMessages.element(boundBy: 1)
        XCTAssertTrue(missing.label.contains("No match in the shared documents searched")); XCTAssertFalse(missing.label.contains("TEST-AX1")); XCTAssertFalse(missing.label.contains("TEST-AX2"))
        snap("681-identifier-missing-followup")
        askLibrary("Explain that", replies: 3)
        XCTAssertTrue(coachMessages.element(boundBy: 2).label.contains("No match in the shared documents searched")); snap("688-identifier-missing-followup-chain")
        tap("Conversation actions"); tap("New conversation")
        askLibrary("Find invoice AF-742 and its payment status.")
        XCTAssertTrue(coachMessages.firstMatch.label.contains("No match in the shared documents searched"))
        let emptyDisclosure = app.buttons["libraryReferencesToggle"].firstMatch; reveal(emptyDisclosure); emptyDisclosure.tap()
        XCTAssertFalse(app.buttons["library-reference-1"].exists)
        let empty = app.staticTexts["No matching excerpts were selected."].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5)); settleLabFrame(empty); snap("682-identifier-missing-invoice")
        askLibrary("Find invoice AF-740", replies: 2)
        XCTAssertTrue(coachMessages.element(boundBy: 1).label.contains("62.40 EUR"))
        let disclosure = app.buttons.matching(identifier: "libraryReferencesToggle").allElementsBoundByIndex.last!; reveal(disclosure); disclosure.tap()
        let source = app.buttons["library-reference-1"].firstMatch; reveal(source); source.tap()
        let excerpt = referenceExcerpt
        XCTAssertTrue(excerpt.waitForExistence(timeout: 5)); XCTAssertEqual(excerpt.label, "Invoice AF-740 totals 62.40 EUR. Payment status: paid."); snap("683-identifier-literal-reference")
        let open = app.buttons["Open in Library"].firstMatch; reveal(open); open.tap(); nativeSwitch("Use in assistant", enabled: false)
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); tap("Done")
        tap("Conversation actions"); tap("New conversation")
        askLibrary("Find invoice AF-740")
        XCTAssertTrue(coachMessages.firstMatch.label.contains("No match in the shared documents searched"))
        snap("684-identifier-sharing-off")
        askLibrary("Find sample ID TEST-AX9", replies: 2)
        XCTAssertTrue(coachMessages.element(boundBy: 1).label.contains("No match in the shared documents searched"))
        tap("Conversation actions"); tap("New conversation")
        askLibrary("Compare sample IDs BX1 and BX2 and BX3")
        XCTAssertTrue(coachMessages.firstMatch.label.contains("Ask about fewer at a time")); snap("686-identifier-excerpt-limit")
        askLibrary("Find invoice AF-740-", replies: 2)
        XCTAssertTrue(coachMessages.element(boundBy: 1).label.contains("can't match that identifier format")); snap("687-identifier-format-limit")
        askLibrary("Find sample ID /TEST-AX1", replies: 3)
        XCTAssertTrue(coachMessages.element(boundBy: 2).label.contains("can't match that identifier format")); snap("689-identifier-leading-format")
        app.terminate(); app.launchArguments = []; app.launch(); tab("Assistant")
        tap("Conversation actions"); tap("New conversation"); askLibrary("Find sample identifier TEST-AX3")
        XCTAssertTrue(coachMessages.firstMatch.label.contains("No match in the shared documents searched")); snap("685-identifier-missing-relaunch")
        askLibrary("Find \"" + longID + "\"", replies: 2)
        XCTAssertTrue(coachMessages.element(boundBy: 1).label.contains(longID)); snap("696-identifier-long-exact-match")
    }
    func captureIdentifierText(_ first: XCUIElement, through last: XCUIElement? = nil, prefix: String, contentGestures: Bool = false, topInset: CGFloat = 12, bottomInset: CGFloat = 40, visibleBounds: (() -> CGRect)? = nil) {
        let end = last ?? first
        XCTAssertTrue(first.waitForExistence(timeout: 5) && end.exists)
        func frame() -> CGRect { first.frame.union(end.frame) }
        func bounds() -> (CGFloat, CGFloat) {
            if let visibleBounds {
                let viewport = visibleBounds().intersection(app.frame)
                XCTAssertFalse(viewport.isNull)
                XCTAssertGreaterThan(viewport.height, 44)
                return (viewport.minY, viewport.maxY)
            }
            // The chat's first bubble rests just below native navigation at
            // its upper scroll limit. Measure visible content, rather than
            // requiring the extra inset used by the standalone source sheet.
            let top = app.navigationBars.firstMatch.frame.maxY + (contentGestures ? 2 : topInset)
            let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
            let bar = app.tabBars.firstMatch
            let bottom = input.exists && input.isHittable ? input.frame.minY - 12 : (bar.exists && bar.isHittable ? bar.frame.minY - 12 : app.frame.maxY - bottomInset)
            return (top, bottom)
        }
        func move(down: Bool, distance: CGFloat) {
            let (top, bottom) = bounds()
            var step = min(bottom - top - 40, max(20, distance))
            let x = contentGestures ? app.frame.midX : 10
            var y = down ? top + 20 : bottom - 20
            if contentGestures {
                let controls = [app.buttons["libraryReferencesToggle"].firstMatch, app.buttons["Save to Library"].firstMatch, app.buttons["Review health entries"].firstMatch]
                    .filter(\.exists).map { $0.frame.insetBy(dx: -24, dy: -16) }
                let candidates = down ? [y, bottom - step - 24, (top + bottom) / 2] : [y, top + step + 24, (top + bottom) / 2]
                y = candidates.first { candidate in !controls.contains { $0.contains(CGPoint(x: x, y: candidate)) } } ?? (down ? bottom - 60 : top + 60)
                step = min(step, down ? bottom - y - 20 : y - top - 20)
            }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y))
            let finish = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: x, dy: y + (down ? step : -step)))
            start.press(forDuration: 0.05, thenDragTo: finish)
            let firstFrame = first.frame
            if !contentGestures || (!firstFrame.isEmpty && firstFrame.minY.isFinite && firstFrame.minX.isFinite) {
                settleLabFrame(first, pixelTolerance: contentGestures ? 0.25 : 0)
            }
        }
        if contentGestures {
            // Offscreen native text views expose an empty AX frame. Bring
            // the first marker back into view before asking it to settle.
            for _ in 0..<64 {
                let value = first.frame
                if !value.isEmpty && value.minY.isFinite && value.minX.isFinite { break }
                let (top, bottom) = bounds()
                move(down: true, distance: (bottom - top) * 0.55)
            }
        }
        settleLabFrame(first, pixelTolerance: contentGestures ? 0.25 : 0)
        for _ in 0..<24 {
            let (top, bottom) = bounds(), value = frame()
            if value.minY >= top - 2 && value.minY < bottom - 44 { break }
            move(down: value.minY < top, distance: abs(value.minY - top) + 12)
        }
        let (top, bottom) = bounds()
        XCTAssertGreaterThanOrEqual(frame().minY, top - 2)
        XCTAssertLessThan(frame().minY, bottom - 44)
        var covered: CGFloat = 0
        for part in 1...64 {
            // Native drag settling can overshoot the requested distance. Move
            // back before capturing if that would leave any text unrecorded.
            for _ in 0..<8 {
                let (top, _) = bounds(), value = frame()
                let from = max(0, top - value.minY)
                if from <= covered + 2 { break }
                move(down: true, distance: from - covered + 24)
            }
            let (top, bottom) = bounds(), value = frame()
            let from = max(0, top - value.minY), to = min(value.height, bottom - value.minY)
            XCTAssertLessThanOrEqual(from, covered + 2, "Native capture must not skip text")
            XCTAssertGreaterThan(to, from)
            covered = max(covered, to)
            print("Identifier capture \(prefix) part\(part): \(from)...\(to) of \(value.height) points")
            snap(prefix + "-part\(part)")
            if covered >= value.height - 2 { return }
            move(down: false, distance: (bottom - top) * 0.45)
        }
        XCTFail("Complete identifier text was not captured through normal scrolling")
    }
    func testLiteralIdentifierPresentation() throws {
        app.terminate(); app.launchArguments = ["-lumen.appearance", "light"]; app.launch()
        if app.buttons["Get started"].waitForExistence(timeout: 2) { finishOnboarding() }
        prepareIdentifierNote("Sample one", "Sample TEST-AX1. Exact wording: not detected.")
        prepareIdentifierNote("Several samples", "Sample ID BX1: first wording.\n\nSample ID BX2: second wording.\n\nSample ID BX3: third wording.")
        var lightHeight: CGFloat = 0
        func newQuestion(_ query: String) -> XCUIElement {
            tab("Assistant")
            if coachMessages.firstMatch.exists { tap("Conversation actions"); tap("New conversation") }
            askLibrary(query)
            let reply = coachMessages.firstMatch
            XCTAssertTrue(reply.waitForExistence(timeout: 5)); return reply
        }
        for large in [false, true] {
            app.terminate()
            app.launchArguments = ["-lumen.appearance", large ? "dark" : "light"] + (large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
            app.launch(); tab("Assistant")
            let prefix = large ? "dark-xxxl" : "light"
            let matched = newQuestion("Find sample ID TEST-AX1")
            XCTAssertTrue(matched.label.contains("not detected")); captureIdentifierText(matched, prefix: "690-identifier-" + prefix + "-match")
            let disclosure = app.buttons["libraryReferencesToggle"].firstMatch; reveal(disclosure); disclosure.tap()
            let source = app.buttons["library-reference-1"].firstMatch; reveal(source); source.tap()
            let excerpt = referenceExcerpt
            XCTAssertTrue(excerpt.waitForExistence(timeout: 5)); captureIdentifierText(excerpt, prefix: "691-identifier-" + prefix + "-source")
            let open = app.buttons["Open in Library"].firstMatch; reveal(open); XCTAssertTrue(open.isHittable); snap("692-identifier-" + prefix + "-source-actions"); tap("Done")
            let absent = newQuestion("Find sample ID TEST-AX3")
            XCTAssertTrue(absent.label.contains("No match in the shared documents searched"))
            captureIdentifierText(absent, prefix: "693a-identifier-" + prefix + "-no-match-reply")
            let noSource = app.buttons["libraryReferencesToggle"].firstMatch; reveal(noSource); noSource.tap()
            let empty = app.staticTexts["No matching excerpts were selected."].firstMatch
            XCTAssertTrue(empty.waitForExistence(timeout: 5)); reveal(empty); settleLabFrame(empty)
            XCTAssertFalse(app.buttons["library-reference-1"].exists)
            captureIdentifierText(noSource, through: empty, prefix: "693-identifier-" + prefix + "-no-match-settled")
            let emptySave = app.buttons["Save to Library"].firstMatch; reveal(emptySave); snap("693b-identifier-" + prefix + "-no-match-footer")
            for (query, expected, name) in [
                ("Compare sample IDs BX1 and BX2 and BX3", "Ask about fewer at a time", "capacity"),
                ("Find invoice AF-740-", "can't match that identifier format", "format"),
                ("Find sample ID " + String(repeating: "X", count: 97) + "1", "up to 96 characters", "length"),
                ("Find sample IDs " + (0..<17).map { "X\($0)" }.joined(separator: ", "), "up to 16 identifiers", "count")
            ] {
                let reply = newQuestion(query); XCTAssertTrue(reply.label.contains(expected))
                if name == "capacity" {
                    if large { XCTAssertGreaterThan(reply.frame.height, lightHeight * 1.3) }
                    else { lightHeight = reply.frame.height }
                }
                captureIdentifierText(reply, prefix: "694-identifier-" + prefix + "-" + name)
                let save = app.buttons["Save to Library"].firstMatch; reveal(save); XCTAssertTrue(save.isHittable)
                snap("695-identifier-" + prefix + "-" + name + "-footer")
            }
        }
    }
    func testRelatedTopicSearchLifecycle() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchUITestMode"]; app.launch(); finishOnboarding()
        createSemanticNote(title: "Consultation note", body: "Persistent tiredness and low energy over several weeks.", shared: true)
        createSemanticNote(title: "Private exhausted detail", body: "PRIVATE-SEMANTIC-CANARY Feeling exhausted after exercise.", shared: false)
        tab("Assistant"); askLibrary("What did my saved notes say about feeling exhausted?")
        let first = coachMessages.firstMatch
        XCTAssertTrue(first.label.contains("No match")); snap("390-topic-keyword-default")
        openLibrarySearchSettings(); snap("391-topic-model-off")
        XCTAssertTrue(app.staticTexts["meaningSearchFixtureLabel"].exists)
        tap("meaningSearchDownload")
        XCTAssertTrue(app.buttons["meaningSearchCancel"].waitForExistence(timeout: 5)); snap("392-topic-copy-progress")
        tap("meaningSearchCancel")
        XCTAssertTrue(app.buttons["meaningSearchDownload"].waitForExistence(timeout: 30)); XCTAssertFalse(app.switches["meaningSearchToggle"].exists)
        tap("meaningSearchDownload")
        let toggle = app.switches["meaningSearchToggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 90)); XCTAssertEqual(toggle.value as? String, "1"); snap("393-topic-model-enabled")
        closeLibrarySearchSettings(); tab("Assistant"); askLibrary("What did my saved notes say about feeling exhausted?", replies: 2)
        let reply = coachMessages.element(boundBy: 1)
        XCTAssertTrue(reply.label.contains("Persistent tiredness")); XCTAssertFalse(reply.label.contains("PRIVATE-SEMANTIC-CANARY"))
        let disclosure = app.buttons.matching(identifier: "libraryReferencesToggle").allElementsBoundByIndex.last!; reveal(disclosure); disclosure.tap()
        let method = app.staticTexts["librarySearchMethod"].firstMatch; reveal(method)
        XCTAssertTrue(method.label.contains("English related topics")); snap("394-topic-real-model-result")
        let reference = app.buttons["library-reference-1"].firstMatch; reveal(reference); reference.tap()
        XCTAssertTrue(referenceExcerpt.waitForExistence(timeout: 5)); XCTAssertEqual(referenceExcerpt.label, "Persistent tiredness and low energy over several weeks.")
        snap("395-topic-exact-reference"); tap("Done")
        app.terminate(); app.launchArguments = ["-librarySearchUITestMode"]; app.launch()
        openLibrarySearchSettings(); XCTAssertEqual(app.switches["meaningSearchToggle"].value as? String, "1"); snap("396-topic-relaunched")
        closeLibrarySearchSettings(); tab("Assistant"); askLibrary("What did my saved notes say about feeling exhausted?", replies: 3)
        XCTAssertTrue(coachMessages.element(boundBy: 2).label.contains("Persistent tiredness"))
        openLibrarySearchSettings()
        nativeSwitch("meaningSearchToggle", enabled: false)
        XCTAssertTrue(app.buttons["meaningSearchDelete"].waitForExistence(timeout: 15)); XCTAssertEqual(app.switches["meaningSearchToggle"].value as? String, "0"); snap("397-topic-disabled-kept")
        tap("meaningSearchDelete"); XCTAssertTrue(app.buttons["meaningSearchDownload"].waitForExistence(timeout: 30)); snap("398-topic-model-deleted")
        closeLibrarySearchSettings(); tab("Assistant"); askLibrary("What did my saved notes say about feeling exhausted?", replies: 4)
        XCTAssertTrue(coachMessages.element(boundBy: 3).label.contains("No match"))
        snap("399-topic-keyword-after-delete")
    }
    func testRelatedTopicRemoteInstallAndErase() throws {
        // Actual public pinned download, hash checks, compilation and inference.
        // The separately labelled local lookup path sends no generative request.
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchRemoteUITestMode"]; app.launch(); finishOnboarding()
        createSemanticNote(title: "Consultation note", body: "Persistent tiredness and low energy over several weeks.", shared: true)
        openLibrarySearchSettings(); XCTAssertFalse(app.staticTexts["meaningSearchFixtureLabel"].exists)
        XCTAssertTrue(app.buttons["Download & enable"].exists); snap("413-topic-real-download-before")
        tap("meaningSearchDownload")
        let cancel = app.buttons["meaningSearchCancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); snap("420-topic-real-download-progress"); cancel.tap()
        let retry = app.buttons["meaningSearchDownload"].firstMatch
        XCTAssertTrue(retry.waitForExistence(timeout: 30)); snap("421-topic-real-download-cancelled"); retry.tap()
        XCTAssertTrue(app.switches["meaningSearchToggle"].waitForExistence(timeout: 240)); XCTAssertFalse(app.staticTexts["meaningSearchError"].exists); snap("414-topic-real-download-installed")
        closeLibrarySearchSettings(); tab("Assistant"); askLibrary("What did my saved notes say about feeling exhausted?")
        XCTAssertTrue(coachMessages.firstMatch.label.contains("Persistent tiredness")); snap("415-topic-network-installed-inference")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); tab("Assistant")
        askLibrary("What did my saved notes say about feeling exhausted?", replies: 2)
        XCTAssertTrue(coachMessages.element(boundBy: 1).label.contains("Persistent tiredness")); snap("416-topic-cold-inference")
        tab("Library"); let note = app.buttons["Consultation note"].firstMatch; reveal(note); note.tap(); nativeSwitch("Use in assistant", enabled: false)
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); tab("Assistant")
        askLibrary("What did my saved notes say about feeling exhausted?", replies: 3)
        let withdrawn = coachMessages.element(boundBy: 2)
        XCTAssertTrue(withdrawn.label.contains("No Library documents are shared")); XCTAssertFalse(withdrawn.label.contains("Persistent tiredness")); snap("417-topic-sharing-withdrawn")
        openLibrarySearchSettings(); nativeSwitch("meaningSearchToggle", enabled: false); snap("422-topic-remote-model-disabled-kept")
        let delete = app.buttons["meaningSearchDelete"].firstMatch; reveal(delete); delete.tap()
        XCTAssertTrue(app.buttons["meaningSearchDownload"].waitForExistence(timeout: 30)); snap("423-topic-remote-model-deleted")
        tap("meaningSearchDownload"); XCTAssertTrue(app.switches["meaningSearchToggle"].waitForExistence(timeout: 240))
        closeLibrarySearchSettings()
        tab("Today"); tap("Settings"); let erase = app.buttons["Erase all data"].firstMatch; reveal(erase); erase.tap(); tap("Erase everything")
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 15)); snap("418-topic-erased")
        app.terminate(); app.launchArguments = ["-librarySearchRemoteUITestMode"]; app.launch(); finishOnboarding(); openLibrarySearchSettings()
        XCTAssertTrue(app.buttons["meaningSearchDownload"].waitForExistence(timeout: 30)); XCTAssertFalse(app.switches["meaningSearchToggle"].exists); snap("419-topic-model-absent-after-erase")
    }
    func testRelatedTopicSearchPresentation() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchUITestMode"]; app.launch(); finishOnboarding()
        createSemanticNote(title: "Consultation note", body: "Persistent tiredness and low energy over several weeks.", shared: true)
        openLibrarySearchSettings(); snap("400-topic-light-download")
        tap("meaningSearchDownload"); XCTAssertTrue(app.switches["meaningSearchToggle"].waitForExistence(timeout: 90))
        snap("401-topic-light-installed")
        let modelDetails = app.buttons["Model & license"].firstMatch; reveal(modelDetails); snap("402-topic-sharing-details"); modelDetails.tap()
        XCTAssertTrue(app.staticTexts["miniLMLicenseText"].waitForExistence(timeout: 5)); snap("403-topic-model-license")
        app.navigationBars["Model & license"].buttons.element(boundBy: 0).tap(); closeLibrarySearchSettings(); tab("Assistant")
        askLibrary("What did my saved notes say about feeling exhausted?")
        XCTAssertTrue(coachMessages.firstMatch.label.contains("Persistent tiredness"))
        app.terminate(); app.launchArguments = ["-librarySearchUITestMode", "-lumen.appearance", "dark"]; app.launch()
        openLibrarySearchSettings(); snap("404-topic-dark-controls"); closeLibrarySearchSettings(); tab("Assistant")
        let disclosure = app.buttons["libraryReferencesToggle"].firstMatch; reveal(disclosure); disclosure.tap()
        let method = app.staticTexts["librarySearchMethod"].firstMatch; reveal(method); snap("405-topic-dark-source-method")
        let reference = app.buttons["library-reference-1"].firstMatch; reveal(reference); reference.tap(); snap("406-topic-dark-exact-source"); tap("Done")
        app.terminate(); app.launchArguments = ["-librarySearchUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        openLibrarySearchSettings(); snap("407-topic-large-heading")
        let toggle = app.switches["meaningSearchToggle"].firstMatch; reveal(toggle); XCTAssertEqual(toggle.value as? String, "1"); snap("408-topic-large-controls")
        let privacy = app.staticTexts["Only shared Library text is searched. Topic matching runs on this iPhone; record text isn't sent to the model download host."].firstMatch
        reveal(privacy); snap("409-topic-large-sharing")
        closeLibrarySearchSettings(); tab("Assistant"); reveal(disclosure); disclosure.tap(); reveal(method); snap("410-topic-large-source-method")
        reveal(reference); reference.tap(); XCTAssertTrue(referenceExcerpt.waitForExistence(timeout: 5)); snap("411-topic-large-reference-heading")
        reveal(referenceExcerpt); snap("412-topic-large-excerpt"); tap("Done")
    }
    func testRelatedTopicLargeCoverage() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-librarySearchUITestMode"]; app.launch(); finishOnboarding()
        createSemanticNote(title: "Consultation note", body: "Persistent tiredness and low energy over several weeks.", shared: true)
        openLibrarySearchSettings(); tap("meaningSearchDownload")
        XCTAssertTrue(app.switches["meaningSearchToggle"].waitForExistence(timeout: 90)); closeLibrarySearchSettings(); tab("Assistant")
        askLibrary("What did my saved notes say about feeling exhausted?")
        XCTAssertTrue(coachMessages.firstMatch.label.contains("Persistent tiredness"))
        app.terminate(); app.launchArguments = ["-librarySearchUITestMode", "-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch(); tab("Assistant")
        let disclosure = app.buttons["libraryReferencesToggle"].firstMatch; reveal(disclosure); disclosure.tap()
        let coverage = app.staticTexts["Related-topic search compared the only prepared excerpt."].firstMatch
        reveal(coverage); XCTAssertTrue(coverage.isHittable); snap("424-topic-large-comparison-coverage")
        let reference = app.buttons["library-reference-1"].firstMatch
        reveal(reference); XCTAssertTrue(reference.isHittable); snap("425-topic-large-source-row")
        reference.tap(); XCTAssertTrue(referenceExcerpt.waitForExistence(timeout: 5))
        reveal(referenceExcerpt); XCTAssertEqual(referenceExcerpt.label, "Persistent tiredness and low energy over several weeks.")
        snap("426-topic-large-literal-source")
    }
    func enterPlanGoal(_ text: String, capture: String? = nil) {
        reveal(app.buttons["editScheduledPlanGoal"].firstMatch); tap("editScheduledPlanGoal")
        let editor = app.textViews["scheduledPlanGoal"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); editor.tap(); editor.typeText(text)
        XCTAssertEqual(editor.value as? String, text)
        let done = app.buttons["finishPlanText"].firstMatch
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); XCTAssertTrue(done.isHittable)
        XCTAssertGreaterThanOrEqual(done.frame.height, 44); XCTAssertLessThanOrEqual(done.frame.maxY, app.keyboards.firstMatch.frame.minY + 1)
        if let capture { snap(capture) }; done.tap()
        XCTAssertEqual(app.staticTexts["scheduledPlanGoalPreview"].label, text)
    }
    func testScheduledPlanDelivery() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-scheduledPlanUITestFixture", "valid"]; app.launch()
        finishOnboarding(); openScheduledPlan()
        let goal = "Make time to review my routine over the next two weeks."
        enterPlanGoal(goal, capture: "350-plan-goal-editor"); snap("351-plan-setup")
        reveal(app.buttons["prepareScheduledPlan"].firstMatch); tap("prepareScheduledPlan")
        XCTAssertTrue(app.staticTexts["scheduledPlanCount"].waitForExistence(timeout: 10)); XCTAssertEqual(app.staticTexts["scheduledPlanCount"].label, "2 weeks · 4 dated steps"); snap("352-plan-review")
        let save = app.buttons["saveScheduledPlan"].firstMatch; reveal(save); XCTAssertFalse(save.isEnabled)
        let acknowledge = app.switches["acknowledgeScheduledPlan"].firstMatch; reveal(acknowledge); nativeSwitch("acknowledgeScheduledPlan", enabled: true); XCTAssertTrue(save.isEnabled)
        tap("Jump to week"); tap("Week 1")
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'scheduledPlanAction-' ")).firstMatch; reveal(first); first.tap()
        tap("editFullScheduledAction")
        let editor = app.textViews["scheduledActionText"].firstMatch; XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let changed = "Choose one small step that fits my actual schedule."
        replaceVoiceText(editor, with: changed); snap("353-plan-step-editor")
        app.navigationBars["Step wording"].buttons.element(boundBy: 0).tap()
        app.navigationBars["Plan step"].buttons.element(boundBy: 0).tap()
        reveal(save); XCTAssertFalse(save.isEnabled, "Editing a reviewed step requires a new acknowledgement"); snap("374-plan-edit-needs-review")
        reveal(acknowledge); nativeSwitch("acknowledgeScheduledPlan", enabled: true); snap("354-plan-ready-to-save"); save.tap()
        XCTAssertTrue(app.staticTexts["Plan saved."].waitForExistence(timeout: 5)); snap("355-plan-saved"); tap("View saved plan")
        let completed = app.buttons["Incomplete: " + changed].firstMatch; reveal(completed); completed.tap()
        XCTAssertTrue(app.buttons["Completed: " + changed].exists)
        let share = app.switches["Use in assistant"].firstMatch; reveal(share); XCTAssertEqual(share.value as? String, "0"); snap("356-plan-sharing-off")
        let explanation = app.staticTexts.matching(NSPredicate(format: "label == %@", "When enabled, matching text can be sent with your questions to the AI provider selected in Settings. Turning this off stops future retrieval. Earlier replies and saved copies keep their excerpts." )).firstMatch; reveal(explanation); snap("356b-plan-sharing-explanation")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); tap("finishScheduledPlan")
        app.terminate(); app.launchArguments = []; app.launch(); tab("Library")
        let plan = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).firstMatch
        reveal(plan); XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).count, 1); plan.tap()
        XCTAssertTrue(app.buttons["Completed: " + changed].waitForExistence(timeout: 5)); snap("357-plan-after-relaunch")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); scrollAndTap("Your next steps")
        XCTAssertFalse(app.buttons["Complete " + changed].exists)
        XCTAssertTrue(app.buttons["Complete Review your routine and adjust if needed"].firstMatch.waitForExistence(timeout: 5)); snap("358-plan-agenda")
    }
    func testScheduledPlanCancellationAndFailure() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-scheduledPlanUITestFixture", "invalid"]; app.launch()
        finishOnboarding(); openScheduledPlan(); enterPlanGoal("Review my weekly routine.")
        reveal(app.buttons["prepareScheduledPlan"].firstMatch); tap("prepareScheduledPlan")
        let error = app.staticTexts["scheduledPlanError"].firstMatch; XCTAssertTrue(error.waitForExistence(timeout: 8)); reveal(error); snap("359-plan-invalid-reply")
        XCTAssertFalse(app.staticTexts["scheduledPlanCount"].exists)
        tap("closeScheduledPlan"); tap("Keep planning"); tap("closeScheduledPlan"); tap("Discard draft")
        tab("Library"); XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).count, 0)
        app.terminate(); app.launchArguments = ["-resetForUITests", "-scheduledPlanUITestFixture", "delayed"]; app.launch()
        finishOnboarding(); openScheduledPlan(); enterPlanGoal("Keep a flexible weekly routine.")
        reveal(app.buttons["prepareScheduledPlan"].firstMatch); tap("prepareScheduledPlan"); tap("stopScheduledPlan"); XCTAssertTrue(app.staticTexts["scheduledPlanError"].waitForExistence(timeout: 5))
        let lateDraft = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.app.staticTexts["scheduledPlanCount"].exists }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [lateDraft], timeout: 9), .timedOut, "A stopped preparation must not surface a late draft")
        let template = app.buttons["useScheduledPlanTemplate"].firstMatch; reveal(template); template.tap()
        XCTAssertTrue(app.staticTexts["scheduledPlanCount"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["scheduledPlanCount"].label, "2 weeks · 6 dated steps"); snap("360-plan-explicit-template")
        let revise = app.buttons["Change goal or timeframe"].firstMatch; reveal(revise); revise.tap(); tap("Keep these steps")
        revise.tap(); tap("Change setup")
        XCTAssertEqual(app.staticTexts["scheduledPlanGoalPreview"].label, "Keep a flexible weekly routine.")
        tap("closeScheduledPlan"); tap("Discard draft"); tab("Library")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).count, 0)
    }
    func testScheduledPlanPresentation() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-lumen.appearance", "dark"]; app.launch()
        finishOnboarding(); openScheduledPlan(); enterPlanGoal("Make room to review and adapt my routine."); snap("361-plan-dark-setup")
        let template = app.buttons["useScheduledPlanTemplate"].firstMatch; reveal(template); template.tap()
        XCTAssertTrue(app.staticTexts["scheduledPlanCount"].waitForExistence(timeout: 5)); snap("362-plan-dark-review")
        tap("closeScheduledPlan"); tap("Discard draft")
        app.terminate(); app.launchArguments = ["-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        openScheduledPlan(); enterPlanGoal("Make space for a routine.\nThe last line stays editable.", capture: "363-plan-large-goal-editor")
        let duration = app.buttons["scheduledPlanWeeks"].firstMatch; reveal(duration); duration.tap(); tap("8 weeks")
        reveal(template); snap("364-plan-large-setup"); template.tap()
        XCTAssertTrue(app.staticTexts["scheduledPlanCount"].waitForExistence(timeout: 5)); XCTAssertEqual(app.staticTexts["scheduledPlanCount"].label, "8 weeks · 24 dated steps"); snap("365-plan-large-review")
        tap("Jump to week"); let week = app.buttons["Week 8"].firstMatch; reveal(week); snap("369-plan-week-menu"); week.tap()
        let lastWeek = app.staticTexts["Week 8"].firstMatch; reveal(lastWeek); snap("366-plan-large-last-week")
        let finalDate = Calendar.current.date(byAdding: .day, value: 55, to: Date())!.formatted(date: .complete, time: .omitted)
        let lastAction = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'scheduledPlanAction-' AND label CONTAINS %@", finalDate)).firstMatch
        reveal(lastAction)
        let top = app.navigationBars["Make a plan"].frame.maxY + 12, bottom = app.frame.maxY - 70
        for _ in 0..<10 {
            let f = lastAction.frame
            if f.minY >= top && f.maxY <= bottom { break }
            let upward = f.maxY > bottom
            let shift = min(200, max(40, abs(f.midY - (top + bottom) / 2)))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: (top + bottom) / 2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: upward ? -shift : shift)), withVelocity: .slow, thenHoldForDuration: 0.4)
        }
        XCTAssertGreaterThanOrEqual(lastAction.frame.minY, top); XCTAssertLessThanOrEqual(lastAction.frame.maxY, bottom); snap("366b-plan-large-final-action")
        tap("Jump to week"); let before = app.buttons["Before saving"].firstMatch; reveal(before)
        // Scroll inside the native menu, then let its scroll animation settle.
        app.buttons["Week 7"].firstMatch.swipeUp()
        let menuSettled = expectation(description: "Native week menu settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { menuSettled.fulfill() }; wait(for: [menuSettled], timeout: 2)
        XCTAssertTrue(before.isHittable); snap("369b-plan-before-saving-menu"); before.tap()
        let ack = app.switches["acknowledgeScheduledPlan"].firstMatch; reveal(ack); snap("367-plan-large-confirmation"); XCTAssertFalse(app.buttons["saveScheduledPlan"].isEnabled)
        tap("closeScheduledPlan"); XCTAssertTrue(app.alerts["Discard this plan draft?"].waitForExistence(timeout: 5)); snap("368-plan-large-discard"); tap("Discard draft")
    }
    func testScheduledPlanDatePickerInspection() throws {
        finishOnboarding(); openScheduledPlan(); enterPlanGoal("Make room to review my routine.")
        let template = app.buttons["useScheduledPlanTemplate"].firstMatch; reveal(template); template.tap()
        XCTAssertTrue(app.staticTexts["scheduledPlanCount"].waitForExistence(timeout: 5))
        tap("Jump to week"); tap("Week 1")
        let action = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'scheduledPlanAction-' ")).firstMatch; reveal(action); action.tap()
        let picker = app.descendants(matching: .any).matching(identifier: "scheduledActionDate").firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        if picker.buttons.firstMatch.exists { picker.buttons.firstMatch.tap() } else { picker.tap() }
        snap("370-plan-date-picker-inspection"); print("PLAN_DATE_PICKER_HIERARCHY\n" + app.debugDescription)
    }
    func testScheduledPlanUrgentGuard() throws {
        finishOnboarding(); openScheduledPlan(); enterPlanGoal("Make a plan for chest pain happening now.")
        let template = app.buttons["useScheduledPlanTemplate"].firstMatch; reveal(template); template.tap()
        let error = app.staticTexts["scheduledPlanError"].firstMatch; XCTAssertTrue(error.waitForExistence(timeout: 5)); reveal(error)
        XCTAssertTrue(error.label.contains("local emergency services")); XCTAssertFalse(app.staticTexts["scheduledPlanCount"].exists)
        snap("371-plan-urgent-routing-fixture")
        tap("closeScheduledPlan"); tap("Discard draft"); tab("Library")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).count, 0)
    }
    func testScheduledPlanCalendarEditing() throws {
        finishOnboarding()
        app.terminate(); app.launchArguments = ["-lumen.appearance", "light", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]; app.launch()
        openScheduledPlan(); enterPlanGoal("Review a routine that fits my day.")
        let template = app.buttons["useScheduledPlanTemplate"].firstMatch; reveal(template); template.tap()
        XCTAssertTrue(app.staticTexts["scheduledPlanCount"].waitForExistence(timeout: 5))
        tap("Jump to week"); tap("Before saving")
        let add = app.buttons["Add a step"].firstMatch; reveal(add); add.tap()
        tap("Jump to week"); tap("Week 1")
        let action = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Add step wording'")).firstMatch; reveal(action); action.tap()
        tap("editFullScheduledAction")
        let editor = app.textViews["scheduledActionText"].firstMatch; XCTAssertTrue(editor.waitForExistence(timeout: 5))
        var wording = "Review one small step at a time, and leave room to adapt it to the day.\nKeep the wording and date together.\nFinal line."
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); editor.typeText(wording); XCTAssertEqual(editor.value as? String, wording)
        let done = app.buttons["finishPlanText"].firstMatch
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5)); XCTAssertGreaterThanOrEqual(done.frame.height, 44)
        // XCTest's text injection can hide the software keyboard. Reopen the
        // actual editor, then perform the editing proof only with visible keys.
        tap("finishPlanText"); reveal(app.buttons["editFullScheduledAction"].firstMatch); tap("editFullScheduledAction")
        XCTAssertTrue(editor.waitForExistence(timeout: 5)); XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.keyboards.firstMatch.frame.minY, app.frame.maxY - 150)
        editor.swipeUp(velocity: .slow); editor.swipeUp(velocity: .slow)
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.9)).tap()
        func visibleLetter(_ letter: String) -> String {
            let key = app.keyboards.keys.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch
            XCTAssertTrue(key.exists && key.isHittable)
            XCTAssertGreaterThanOrEqual(key.frame.minY, app.keyboards.firstMatch.frame.minY)
            XCTAssertLessThanOrEqual(key.frame.maxY, app.frame.maxY)
            let literal = key.label; key.tap(); return literal
        }
        let space = app.keyboards.keys["space"].firstMatch; XCTAssertTrue(space.isHittable); space.tap()
        wording += " " + visibleLetter("x"); XCTAssertEqual(editor.value as? String, wording)
        XCTAssertLessThanOrEqual(done.frame.maxY, app.keyboards.firstMatch.frame.minY + 1); snap("372-plan-large-step-keyboard"); snap("381-plan-end-insertion")
        editor.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.35)).tap()
        let marker = visibleLetter("q"), middle = editor.value as? String ?? ""
        XCTAssertEqual(middle.replacingOccurrences(of: marker, with: ""), wording)
        XCTAssertFalse(middle.hasSuffix(marker)); XCTAssertTrue(middle.contains(marker))
        let next = visibleLetter("z"); wording = middle.replacingOccurrences(of: marker, with: marker + next)
        XCTAssertEqual(editor.value as? String, wording)
        XCTAssertLessThan(app.keyboards.firstMatch.frame.minY, app.frame.maxY - 150); snap("382-plan-middle-insertion")
        tap("finishPlanText")
        let fullRoute = app.buttons["editFullScheduledAction"].firstMatch; reveal(fullRoute); snap("384-plan-full-step-route")
        let picker = app.datePickers["scheduledActionDate"].firstMatch; XCTAssertTrue(picker.waitForExistence(timeout: 5)); picker.tap()
        let replanned = Calendar.current.date(byAdding: .day, value: 8, to: Date())!
        if Calendar.current.component(.month, from: replanned) != Calendar.current.component(.month, from: Date()) { tap("DatePicker.NextMonth") }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_GB"); formatter.dateFormat = "EEEE, d MMMM"
        let day = app.buttons[formatter.string(from: replanned)].firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5)); XCTAssertTrue(day.isEnabled); snap("373-plan-large-date-picker"); day.tap()
        app.navigationBars["Plan step"].tap()
        tap("finishScheduledAction")
        tap("Jump to week"); tap("Before saving")
        let save = app.buttons["saveScheduledPlan"].firstMatch; reveal(save); XCTAssertFalse(save.isEnabled)
        nativeSwitch("acknowledgeScheduledPlan", enabled: true); reveal(save); save.tap()
        XCTAssertTrue(app.staticTexts["Plan saved."].waitForExistence(timeout: 5)); snap("375-plan-large-completion")
        let view = app.buttons["View saved plan"].firstMatch; reveal(view); snap("375b-plan-large-completion-actions"); view.tap()
        let expected = "Due " + replanned.formatted(date: .abbreviated, time: .omitted)
        let due = app.staticTexts[expected].firstMatch; reveal(due); XCTAssertTrue(due.exists); snap("376-plan-large-saved-date")
        let sharing = app.staticTexts.matching(NSPredicate(format: "label == %@", "When enabled, matching text can be sent with your questions to the AI provider selected in Settings. Turning this off stops future retrieval. Earlier replies and saved copies keep their excerpts." )).firstMatch
        reveal(sharing); snap("376b-plan-large-sharing-explanation")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); tap("finishScheduledPlan")
        app.terminate(); app.launchArguments = []; app.launch(); tab("Library")
        let plan = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).firstMatch; reveal(plan); plan.tap()
        let restored = app.buttons.matching(NSPredicate(format: "label == %@", "Incomplete: " + wording)).firstMatch; reveal(restored); XCTAssertTrue(restored.exists); reveal(app.staticTexts[expected].firstMatch); snap("377-plan-calendar-date-after-relaunch")
        let setting = app.switches["Use in assistant"].firstMatch; reveal(setting); XCTAssertEqual(setting.value as? String, "0")
        reveal(sharing); snap("377b-plan-full-sharing-explanation")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap(); scrollAndTap("Your next steps")
        reveal(app.staticTexts.matching(NSPredicate(format: "label == %@", wording)).firstMatch); XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", wording)).firstMatch.exists); reveal(app.staticTexts[expected].firstMatch); snap("378-plan-calendar-agenda")
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

    func testSettingsNameRepeatedDiskFailures() throws { settingsNameRepeatedDiskFailures(large: false) }

    func openPersonalPreferences() {
        tap("Settings"); scrollAndTap("Personal context")
        XCTAssertTrue(app.navigationBars["Personal context"].waitForExistence(timeout: 5))
    }
    func preferenceSwitch(_ identifier: String) -> XCUIElement {
        let toggle = app.switches[identifier].firstMatch; reveal(toggle)
        return toggle.switches.firstMatch.exists ? toggle.switches.firstMatch : toggle
    }
    func approveReminderAccess() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.alerts.buttons["Allow"].firstMatch
        if allow.waitForExistence(timeout: 5) { allow.tap() }
    }
    func capturePreferenceAlert(_ alert: XCUIElement, prefix: String) {
        snap(prefix + "-initial")
        let scroll = alert.scrollViews.firstMatch
        if scroll.exists {
            for step in 1...8 {
                let frame = scroll.frame
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.maxY - 30))
                let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: max(frame.minY + 30, frame.maxY - 130)))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
                snap(prefix + "-body-\(step)")
                let bar = scroll.otherElements.matching(NSPredicate(format: "label BEGINSWITH 'Vertical scroll bar'")).firstMatch
                if bar.exists && (bar.value as? String ?? "").contains("100") { break }
            }
        }
        for action in alert.buttons.allElementsBoundByIndex {
            print("PREFERENCE ALERT ACTION FRAME", prefix, action.label, action.frame, "application", app.frame, "alert", alert.frame)
            XCTAssertTrue(action.isHittable, "The alert action must remain reachable: \(action.label)")
            XCTAssertTrue(app.frame.insetBy(dx: -0.5, dy: -0.5).contains(action.frame),
                          "The complete alert action must fit on screen: \(action.label)")
            XCTAssertTrue(alert.frame.insetBy(dx: -0.5, dy: -0.5).contains(action.frame),
                          "The complete action must fit inside its alert: \(action.label)")
        }
    }
    func relaunchPreferences(large: Bool, personal: Bool) {
        app.terminate()
        app.launchArguments = large ? ["-lumen.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : ["-lumen.appearance", "light"]
        app.launch()
        if personal { openPersonalPreferences() } else { openHealthConnections() }
    }
    func capturePreferenceDisclosure(_ identifier: String, prefix: String, navigationTitle: String? = nil, bottomLimit: CGFloat? = nil) {
        let text = app.staticTexts[identifier].firstMatch
        for _ in 0..<24 where !text.exists { app.swipeUp(velocity: .slow) }
        XCTAssertTrue(text.exists)
        let contextBar = app.navigationBars["Personal context"].firstMatch
        let navigation = navigationTitle.map { app.navigationBars[$0] } ?? (contextBar.exists ? contextBar : app.navigationBars.firstMatch)
        // The compact verification phone has a physical Home button and no
        // bottom safe area: its measured native footer ends at exactly667.
        let bottom = min(app.frame.maxY - (app.frame.height <= 667 ? 0 : 24), bottomLimit ?? app.frame.maxY)
        let top = navigation.frame.maxY + 16
        func drag(up: Bool, distance: CGFloat) {
            let startY = up ? bottom - 16 : top + 16
            let endY = startY + (up ? -distance : distance)
            let a = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: startY))
            let b = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: endY))
            a.press(forDuration: 0.05, thenDragTo: b, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        for _ in 0..<16 {
            let y = text.frame.minY
            if y >= top && y < top + 100 { break }
            if text.frame.minY >= top && text.frame.maxY <= bottom { break }
            drag(up: y > top, distance: max(32, min(150, abs(y - top))))
            if abs(text.frame.minY - y) < 1 { break }
        }
        XCTAssertGreaterThanOrEqual(text.frame.minY, top - 2, "Start with the complete disclosure heading")
        var covered: CGFloat = 0
        for step in 0..<32 {
            let value = text.frame
            let from = max(0, top - value.minY), to = min(value.height, bottom - value.minY)
            XCTAssertLessThanOrEqual(from, covered + 2, "Disclosure captures must not skip text")
            XCTAssertGreaterThan(to, from)
            covered = max(covered, to)
            print("PREFERENCE DISCLOSURE FRAME", identifier, text.frame, "application", app.frame, "viewport", top, bottom)
            snap(prefix + "-segment-\(step)")
            if covered >= value.height - 2 { return }
            drag(up: true, distance: min(200, bottom - top - 40))
        }
        XCTFail("Complete preference disclosure was not reached")
    }
    func testPersonalContextCheckedRecovery() throws { personalContextCheckedRecovery(large: false) }
    func testPersonalContextCheckedRecoveryLarge() throws { personalContextCheckedRecovery(large: true) }
    func testPersonalContextSoftwareKeyboard() throws { try personalContextSoftwareKeyboard(large: false) }
    func testPersonalContextSoftwareKeyboardLarge() throws { try personalContextSoftwareKeyboard(large: true) }
    func personalContextSoftwareKeyboard(large: Bool) throws {
        quickFault("none:0", large: large); openPersonalPreferences()
        let focus = app.descendants(matching: .any).matching(identifier: "personalFocus").firstMatch
        reveal(focus); focus.tap()
        // Actual software-key taps keep this distinct from hardware-assisted
        // typeText: offscreen keyboard AX nodes are not occlusion evidence.
        for letter in ["w", "a", "l", "k"] {
            let key = app.keyboards.keys.matching(NSPredicate(format: "label ==[c] %@", letter)).firstMatch
            XCTAssertTrue(key.waitForExistence(timeout: 5)); XCTAssertTrue(key.isHittable)
            XCTAssertTrue(key.frame.intersects(app.frame)); key.tap()
        }
        let strip = app.otherElements["SystemInputAssistantView"].firstMatch
        XCTAssertTrue(strip.exists && strip.frame.intersects(app.frame))
        XCTAssertTrue(app.buttons["finishContextEditing"].isHittable)
        let typed = focus.value as? String; XCTAssertTrue(typed?.lowercased().contains("walk") == true)
        snap("1008-context-visible-software-keyboard")
        finishContextInput(); XCTAssertEqual(focus.value as? String, typed)
        let cancel = app.buttons["Cancel"].firstMatch; XCTAssertTrue(cancel.isHittable)
        XCTAssertTrue(app.buttons["savePersonalContext"].isEnabled); snap("1008-context-keyboard-finished-draft")
        cancel.tap()
        let discard = app.alerts["Discard context changes?"]; XCTAssertTrue(discard.waitForExistence(timeout: 5))
        capturePreferenceAlert(discard, prefix: "1008-context-keyboard-discard-choice")
        discard.buttons["Keep draft"].tap(); reveal(focus, towardsTop: true)
        XCTAssertEqual(focus.value as? String, typed)
        snap("1008-context-keyboard-kept-draft")
    }
    func finishContextInput() {
        let done = app.buttons["finishContextEditing"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5)); XCTAssertTrue(done.isHittable)
        done.tap()
        let keyboard = app.keyboards.firstMatch
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            !keyboard.exists || keyboard.frame.minY >= self.app.frame.maxY
        }, object: keyboard)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
    }
    func testPersonalContextFieldLabelsLarge() throws {
        quickFault("none:0", large: true); openPersonalPreferences()
        let labels = ["What would you like to work on?", "Food preferences", "Allergies you want to note",
                      "Injuries or activity limitations", "Schedule and available time", "Anything else to remember"]
        for (index, label) in labels.enumerated() {
            capturePreferenceDisclosure(label, prefix: "1007-context-field-\(index)")
        }
        let focus = app.descendants(matching: .any).matching(identifier: "personalFocus").firstMatch
        reveal(focus, towardsTop: true); focus.tap(); focus.typeText("Synthetic routine with time for a short walk")
        XCTAssertTrue(app.keyboards.firstMatch.exists); snap("1007-context-field-keyboard")
        finishContextInput()
        XCTAssertEqual(focus.value as? String, "Synthetic routine with time for a short walk")
        let sharing = app.switches["personalContextSharing"].firstMatch
        reveal(sharing); XCTAssertTrue(sharing.isHittable)
        // UIKit can retain offscreen keyboard AX nodes after dismissal.
        XCTAssertTrue(!app.keyboards.firstMatch.exists || app.keyboards.firstMatch.frame.minY >= app.frame.maxY)
        snap("1007-context-field-scrolled-sharing")
        nativeSwitch("personalContextSharing", enabled: true)
        let unsaved = app.staticTexts["personalContextUnsaved"].firstMatch; reveal(unsaved); XCTAssertTrue(unsaved.exists)
        snap("1007-context-field-sharing-changed")
    }
    func personalContextCheckedRecovery(large: Bool) {
        quickFault("personal-context:1,2", large: large); openPersonalPreferences()
        let focus = app.descendants(matching: .any).matching(identifier: "personalFocus").firstMatch
        reveal(focus); focus.tap(); focus.typeText("Synthetic steady routine")
        snap("980-context-keyboard-draft")
        finishContextInput()
        nativeSwitch("personalContextSharing", enabled: true)
        let saved = app.staticTexts["personalContextSavedSharing"]
        reveal(saved); XCTAssertEqual(saved.label, "Saved sharing: Off"); snap("980-context-unsaved-sharing")
        tap("savePersonalContext")
        let alert = app.alerts["Couldn’t save context"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); capturePreferenceAlert(alert, prefix: "981-context-first-failure")
        alert.buttons["Try again"].tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap("982-context-repeated-failure")
        alert.buttons["Not now"].tap()
        reveal(focus, towardsTop: true)
        XCTAssertEqual(focus.value as? String, "Synthetic steady routine")
        reveal(saved); XCTAssertEqual(saved.label, "Saved sharing: Off")
        let unsaved = app.staticTexts["personalContextUnsaved"].firstMatch; reveal(unsaved); XCTAssertTrue(unsaved.exists); snap("983-context-retained-draft")
        tap("savePersonalContext"); XCTAssertTrue(app.navigationBars["Personal context"].waitForNonExistence(timeout: 5))
        relaunchPreferences(large: large, personal: true)
        reveal(focus); XCTAssertEqual(focus.value as? String, "Synthetic steady routine"); reveal(saved); XCTAssertEqual(saved.label, "Saved sharing: On"); snap("984-context-saved-relaunch")
        reveal(focus, towardsTop: true); focus.tap(); focus.typeText(" draft"); finishContextInput()
        let discardedDraft = focus.value as? String
        XCTAssertTrue(discardedDraft?.contains("draft") == true)
        tap("Cancel")
        let discard = app.alerts["Discard context changes?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        Thread.sleep(forTimeInterval: 0.5) // Settle only the confirmation animation before its screenshot.
        capturePreferenceAlert(discard, prefix: "985-context-discard-choice")
        discard.buttons["Keep draft"].tap(); reveal(focus, towardsTop: true)
        XCTAssertEqual(focus.value as? String, discardedDraft)
        XCTAssertTrue(app.buttons["savePersonalContext"].isEnabled)
        snap("985-context-kept-draft")
        tap("Cancel"); XCTAssertTrue(discard.waitForExistence(timeout: 5)); snap("985-context-discard-reopened")
        discard.buttons["Discard"].tap()
        XCTAssertTrue(app.navigationBars["Personal context"].waitForNonExistence(timeout: 5))
        relaunchPreferences(large: large, personal: true)
        reveal(focus); XCTAssertEqual(focus.value as? String, "Synthetic steady routine"); snap("986-context-discard-relaunch")
        capturePreferenceDisclosure("personalContextDisclosure", prefix: "1004-context-disclosure")
    }
    func testPersonalContextWithdrawalFailure() throws {
        quickFault("personal-context:2", large: true); openPersonalPreferences()
        let focus = app.descendants(matching: .any).matching(identifier: "personalFocus").firstMatch
        reveal(focus); focus.tap(); focus.typeText("Synthetic private reference")
        finishContextInput()
        nativeSwitch("personalContextSharing", enabled: true); tap("savePersonalContext")
        XCTAssertTrue(app.navigationBars["Personal context"].waitForNonExistence(timeout: 5)); scrollAndTap("Personal context")
        nativeSwitch("personalContextSharing", enabled: false); tap("savePersonalContext")
        let alert = app.alerts["Couldn’t save context"]; XCTAssertTrue(alert.waitForExistence(timeout: 5))
        capturePreferenceAlert(alert, prefix: "987-context-withdrawal-failed"); alert.buttons["Not now"].tap()
        let saved = app.staticTexts["personalContextSavedSharing"]; reveal(saved); XCTAssertEqual(saved.label, "Saved sharing: On"); snap("988-context-saved-choice-unchanged")
        tap("savePersonalContext"); XCTAssertTrue(app.navigationBars["Personal context"].waitForNonExistence(timeout: 5))
        relaunchPreferences(large: true, personal: true); reveal(saved); XCTAssertEqual(saved.label, "Saved sharing: Off")
        snap("989-context-withdrawn-relaunch"); reveal(focus, towardsTop: true)
        XCTAssertEqual(focus.value as? String, "Synthetic private reference"); snap("989-context-withdrawn-notes-retained")
    }
    func testReminderCheckedRecovery() throws { reminderCheckedRecovery(large: false) }
    func testReminderCheckedRecoveryLarge() throws { reminderCheckedRecovery(large: true) }
    func selectReminderHour(_ label: String) {
        let option = app.buttons[label].firstMatch
        for _ in 0..<16 {
            if option.exists && option.isHittable { option.tap(); return }
            let hours = app.buttons.matching(NSPredicate(format: "label MATCHES '[0-9]{2}:00'")).allElementsBoundByIndex.filter { $0.isHittable }
            guard let first = hours.first else { break }
            let menu = app.collectionViews.containing(.button, identifier: first.label).firstMatch
            guard menu.exists else { break }
            var popup = menu.frame
            for container in app.otherElements.containing(.button, identifier: first.label).allElementsBoundByIndex {
                let frame = container.frame
                if frame.width > 100 && frame.width < app.frame.width && frame.height > 60 {
                    if frame.width * frame.height < popup.width * popup.height { popup = frame }
                }
            }
            let top = max(app.frame.minY + 24, popup.minY + 24), bottom = min(app.frame.maxY - 24, popup.maxY - 24)
            guard bottom - top > 60 else { break }
            let upper = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: popup.midX, dy: top))
            let lower = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: popup.midX, dy: bottom))
            if label < first.label { upper.press(forDuration: 0.05, thenDragTo: lower) }
            else { lower.press(forDuration: 0.05, thenDragTo: upper) }
        }
        print(app.debugDescription); XCTFail("Reminder hour was not reachable: " + label)
    }
    func reminderCheckedRecovery(large: Bool) {
        quickFault("reminder-preferences:1,3,5", large: large); openHealthConnections()
        preferenceSwitch("contextualCheckIns").tap(); approveReminderAccess()
        let enabledError = app.alerts["Couldn’t save reminders"]
        XCTAssertTrue(enabledError.waitForExistence(timeout: 10)); capturePreferenceAlert(enabledError, prefix: "990-reminder-enable-failed")
        enabledError.buttons["Not now"].tap(); XCTAssertEqual(app.switches["contextualCheckIns"].firstMatch.value as? String, "0"); snap("991-reminder-enable-unchanged")
        preferenceSwitch("contextualCheckIns").tap(); approveReminderAccess()
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '1'"), object: app.switches["contextualCheckIns"].firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 10), .completed)
        preferenceSwitch("reminderDetails").tap()
        let detailsError = app.alerts["Couldn’t save lock-screen details"]; XCTAssertTrue(detailsError.waitForExistence(timeout: 5)); capturePreferenceAlert(detailsError, prefix: "992-reminder-details-failed")
        detailsError.buttons["Not now"].tap(); XCTAssertEqual(app.switches["reminderDetails"].firstMatch.value as? String, "0"); snap("993-reminder-details-unchanged")
        preferenceSwitch("reminderDetails").tap()
        let quiet = app.buttons["reminderQuietStart"].firstMatch; reveal(quiet, towardsTop: true); quiet.tap(); selectReminderHour("20:00")
        let quietError = app.alerts["Couldn’t save quiet hours start"]; XCTAssertTrue(quietError.waitForExistence(timeout: 5)); capturePreferenceAlert(quietError, prefix: "994-reminder-quiet-failed")
        quietError.buttons["Try again"].tap(); XCTAssertTrue(quietError.waitForNonExistence(timeout: 5))
        snap("995-reminder-settings-retried")
        relaunchPreferences(large: large, personal: false)
        let start = app.buttons["reminderQuietStart"].firstMatch; reveal(start); XCTAssertTrue((start.label + (start.value as? String ?? "")).contains("20:00"))
        let checkIns = app.switches["contextualCheckIns"].firstMatch; reveal(checkIns, towardsTop: true); XCTAssertEqual(checkIns.value as? String, "1")
        nativeSwitch("reminderDetails", enabled: false); nativeSwitch("contextualCheckIns", enabled: false, towardsTop: true); snap("996-reminders-disabled")
        relaunchPreferences(large: large, personal: false)
        let toggle = app.switches["contextualCheckIns"].firstMatch; reveal(toggle); XCTAssertEqual(toggle.value as? String, "0")
        let details = app.switches["reminderDetails"].firstMatch; reveal(details); XCTAssertEqual(details.value as? String, "0"); snap("997-reminders-private-relaunch")
        capturePreferenceDisclosure("reminderDisclosure", prefix: "1005-reminder-disclosure")
    }
    func testReminderOnboardingCheckedFailure() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-quick-save-fault", "reminder-preferences:1"]; app.launch()
        finishOnboarding(reminderAction: { [self] in
            tap("Turn on reminders"); approveReminderAccess()
            let alert = app.alerts["Couldn’t save reminders"]; XCTAssertTrue(alert.waitForExistence(timeout: 10)); snap("998-onboarding-reminders-failed"); alert.buttons["OK"].tap()
            XCTAssertTrue(app.buttons["Turn on reminders"].exists); XCTAssertFalse(app.buttons["Start using Lumen"].exists); snap("998-onboarding-reminders-retained")
            tap("Turn on reminders"); approveReminderAccess()
        })
        relaunchPreferences(large: false, personal: false)
        let toggle = app.switches["contextualCheckIns"].firstMatch; reveal(toggle); XCTAssertEqual(toggle.value as? String, "1"); snap("998-onboarding-reminders-relaunch")
    }
    func testReminderSettingsCheckedFailure() throws {
        quickFault("reminder-preferences:1"); tap("Settings")
        let enable = app.buttons["settingsEnableReminders"].firstMatch; reveal(enable); enable.tap(); approveReminderAccess()
        let alert = app.alerts["Couldn’t save reminders"]; XCTAssertTrue(alert.waitForExistence(timeout: 10)); snap("999-settings-reminders-failed"); alert.buttons["Not now"].tap()
        XCTAssertTrue(enable.exists); snap("999-settings-reminders-unchanged"); enable.tap(); approveReminderAccess()
        XCTAssertTrue(enable.waitForNonExistence(timeout: 10))
        relaunchPreferences(large: false, personal: false)
        let toggle = app.switches["contextualCheckIns"].firstMatch; reveal(toggle); XCTAssertEqual(toggle.value as? String, "1"); snap("999-settings-reminders-relaunch")
    }
    func testPreferenceNativeBackendProbe() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-preference-native-probe"]; app.launch(); approveReminderAccess()
        let status = app.staticTexts["preferenceProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Preference checks passed' OR label BEGINSWITH 'Preference checks failed'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 45), .completed)
        XCTAssertEqual(status.label, "Preference checks passed"); snap("1000-preference-native-report")
    }

    func testDurableHealthNativeCombinedFailure() throws {
        try durableHealthNativeProbe(receipt: false)
    }

    func testHealthLocalCorruptWaterBaseline() throws { try healthLocalDataBaseline("water") }
    func testHealthLocalWaterRecovery() throws { try healthLocalDataRecovery("water") }
    func testHealthPreviousCopyRecovery() throws { try healthLocalDataRecovery("previous-copy") }
    func testHealthPreviousCopyTaskCancellation() throws { try healthLocalDataRecovery("previous-copy") }
    func testBackupPhotoBindingChecks() throws {
        app.terminate(); app.launchArguments = ["-resetForUITests", "-health-write-native-probe", "-health-photo-binding-checks"]; app.launch()
        let status = app.staticTexts["healthWriteProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Backup photo checks passed' OR label BEGINSWITH 'Backup photo checks failed'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        XCTAssertEqual(status.label, "Backup photo checks passed"); snap("backup-photo-binding-checks-passed")
    }
    func testHealthBackupFileRecoveryLegacy() throws { try healthBackupFileRecovery("legacy") }
    func testHealthBackupFileRecoveryEncrypted() throws { try healthBackupFileRecovery("encrypted") }
    func testHealthBackupFileRecoveryReadable() throws { try healthBackupFileRecovery("readable") }
    func testHealthBackupFileRecoveryCommitLegacy() throws { try healthBackupFileRecovery("legacy") }
    func testHealthBackupFileRecoveryCommitEncrypted() throws { try healthBackupFileRecovery("encrypted") }
    func testHealthBackupFileRecoveryCommitReadable() throws { try healthBackupFileRecovery("readable") }
    func testHealthBackupFileRecoveryLegacyCancel() throws { try healthBackupFileRecovery("legacy") }
    func testHealthBackupFileRecoveryEncryptedCancel() throws { try healthBackupFileRecovery("encrypted") }
    func testHealthBackupFileRecoveryReadableCancel() throws { try healthBackupFileRecovery("readable") }
    func testHealthBackupFileRecoveryLegacyBack() throws { try healthBackupFileRecovery("legacy") }
    func testHealthBackupFileRecoveryEncryptedBack() throws { try healthBackupFileRecovery("encrypted") }
    func testHealthBackupFileRecoveryReadableBack() throws { try healthBackupFileRecovery("readable") }
    func testHealthBackupFileReadLegacy() throws { try healthBackupFileRead("legacy") }
    func testHealthBackupFileReadEncrypted() throws { try healthBackupFileRead("encrypted") }
    func testHealthBackupFileReadReadable() throws { try healthBackupFileRead("readable") }
    func testHealthOriginalImportBackLegacy() throws { try healthOriginalImportBack("legacy") }
    func testHealthOriginalImportBackEncrypted() throws { try healthOriginalImportBack("encrypted") }
    func testHealthOriginalImportBackReadable() throws { try healthOriginalImportBack("readable") }
    func testHealthOriginalImportCancelLegacy() throws { try healthOriginalImportBack("legacy", cancel: true) }
    func testHealthOriginalImportCancelEncrypted() throws { try healthOriginalImportBack("encrypted", cancel: true) }
    func testHealthOriginalImportCancelReadable() throws { try healthOriginalImportBack("readable", cancel: true) }
    func testHealthOriginalImportCopyCancelLegacy() throws { try healthOriginalImportBack("legacy", cancel: true, copying: true) }
    func testHealthOriginalImportCopyCancelEncrypted() throws { try healthOriginalImportBack("encrypted", cancel: true, copying: true) }
    func testHealthOriginalImportCopyCancelReadable() throws { try healthOriginalImportBack("readable", cancel: true, copying: true) }
    func testHealthOriginalImportCopyBackLegacy() throws { try healthOriginalImportBack("legacy", copying: true) }
    func testHealthOriginalImportCopyBackEncrypted() throws { try healthOriginalImportBack("encrypted", copying: true) }
    func testHealthOriginalImportCopyBackReadable() throws { try healthOriginalImportBack("readable", copying: true) }
    func testHealthOriginalImportPayloadBackLegacy() throws { try healthOriginalImportBack("legacy", payload: true) }
    func testHealthOriginalImportPayloadBackReadable() throws { try healthOriginalImportBack("readable", payload: true) }
    func testHealthOriginalImportPayloadCancelLegacy() throws { try healthOriginalImportBack("legacy", cancel: true, payload: true) }
    func testHealthOriginalImportPayloadCancelReadable() throws { try healthOriginalImportBack("readable", cancel: true, payload: true) }
    func testHealthOriginalImportPayloadLifetimeLegacy() throws { try healthOriginalImportBack("legacy", cancel: true, payload: true, lifetime: true) }
    func testHealthOriginalImportPayloadLifetimeReadable() throws { try healthOriginalImportBack("readable", cancel: true, payload: true, lifetime: true) }
    func testHealthOriginalImportDecryptCancelEncrypted() throws { try healthOriginalImportDecrypt(cancel: true) }
    func testHealthOriginalImportDecryptBackEncrypted() throws { try healthOriginalImportDecrypt(cancel: false) }
    func testHealthOriginalImportUnlockCancelEncrypted() throws { try healthOriginalImportDecrypt(cancel: true, unlocking: true) }
    func testHealthOriginalImportUnlockWrongCancelEncrypted() throws { try healthOriginalImportDecrypt(cancel: true, unlocking: true, wrongPassword: true) }
    private func healthOriginalImportDecrypt(cancel: Bool, unlocking: Bool = false, wrongPassword: Bool = false) throws {
        executionTimeAllowance = 600
        openBackupSettings()
        try chooseBackupFixture("Lumen-encrypted-read-baseline")
        unlockBackup(value: wrongPassword ? "Wrong synthetic encrypted passphrase 61" : "Synthetic encrypted read passphrase 61")
        let state = app.descendants(matching: .any).matching(identifier: "healthImportReadState").firstMatch
        func phase(_ value: String, timeout: TimeInterval = 10) {
            XCTAssertTrue(state.waitForExistence(timeout: 10))
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: state)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
        }
        // File selection registers1; the actual password job registers2.
        phase("held-2")
        let prefix = (unlocking ? "original-unlock-" : "original-decrypt-") + (wrongPassword ? "wrong-" : "") + (cancel ? "cancel" : "back")
        snap(prefix + "-held"); phase("observed-2")
        let cancelButton = app.buttons["cancelBackupOperation"].firstMatch
        XCTAssertTrue(cancelButton.exists && cancelButton.isEnabled)
        let started = Date()
        if cancel { cancelButton.tap() }
        else { app.navigationBars["Backup & restore"].buttons.element(boundBy: 0).tap() }
        let parent = cancel ? "Backup & restore" : "Settings"
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            app.navigationBars[parent].exists && state.exists && state.value as? String == "closed-2" && !cancelButton.exists
        }, object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 3), .completed)
        let elapsed = Date().timeIntervalSince(started); XCTAssertLessThan(elapsed, 3)
        var stableSeconds: TimeInterval = 0
        var message = ""
        if cancel {
            let cancelled = app.staticTexts["Cancelled. Your records haven’t changed."].firstMatch
            XCTAssertTrue(cancelled.waitForExistence(timeout: 5)); message = cancelled.label
            let field = app.secureTextFields["unlockBackupPassword"].firstMatch
            reveal(field); XCTAssertTrue(field.exists && field.isEnabled)
            XCTAssertFalse(app.buttons["unlockBackup"].isEnabled)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "backupProgress").firstMatch.exists)
            snap(prefix + "-stopped")
            let late = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
                cancelButton.exists || app.descendants(matching: .any).matching(identifier: "backupProgress").firstMatch.exists
                || app.buttons["reviewBackupHealthRecovery"].firstMatch.exists
            }, object: app)
            late.isInverted = true
            let stableStart = Date(); XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 4), .completed)
            stableSeconds = Date().timeIntervalSince(stableStart)
        } else {
            snap(prefix + "-stopped")
            let reopen = app.buttons["backupSettings"].firstMatch; reveal(reopen); reopen.tap()
            XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
            try chooseBackupFixture("Lumen-encrypted-read-baseline")
        }
        // Cancel retries the same original without Files reselection; Back
        // selects a new owned original. Both use a fresh password/read job.
        unlockBackup(value: "Synthetic encrypted read passphrase 61")
        phase(cancel ? "held-3" : "held-4")
        snap(prefix + "-retry-held")
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
        let link = app.buttons["reviewBackupHealthRecovery"].firstMatch; reveal(link); XCTAssertTrue(link.exists); link.tap()
        let filename = app.staticTexts["recoveryFileName"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10)); XCTAssertEqual(filename.label, "Lumen-encrypted-read-baseline.lumenbackup")
        let observedFileName = filename.label
        let choice = app.switches["recoverFile-water"].firstMatch; reveal(choice); XCTAssertEqual(choice.value as? String, "0")
        snap(prefix + "-retry-off")
        let records = app.buttons["reviewFile-water"].firstMatch; reveal(records, towardsTop: true); records.tap()
        let record = app.buttons["recoveryRecord-0"].firstMatch; XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        let amount = app.descendants(matching: .any).matching(identifier: "recoveryField-0").firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10)); XCTAssertTrue(amount.label.contains("137 mL"))
        let observedAmount = amount.label
        snap(prefix + "-retry-detail")
        // Keep the real detail alive while the host observes the successful
        // preview's owned original and extracted directory after stream close.
        let premature = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in app.alerts.firstMatch.exists }, object: app)
        premature.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [premature], timeout: 3), .completed)
        for title in ["Water history", "Review recovery", "Backup & restore"] {
            app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        }
        let choose = app.buttons["chooseBackup"].firstMatch; reveal(choose, towardsTop: true)
        XCTAssertTrue(choose.exists && choose.isEnabled)
        XCTAssertFalse(app.secureTextFields["unlockBackupPassword"].firstMatch.exists)
        XCTAssertFalse(app.buttons["reviewBackupHealthRecovery"].firstMatch.exists)
        snap(prefix + "-final-parent")
        let revived = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            app.buttons["cancelBackupOperation"].firstMatch.exists || app.buttons["reviewBackupHealthRecovery"].firstMatch.exists
        }, object: app)
        revived.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [revived], timeout: 4), .completed)
        let data = try JSONSerialization.data(withJSONObject: ["scope": "selected-import", "boundary": unlocking ? "encrypted-unlock" : "encrypted-record", "wrongPasswordFirst": wrongPassword, "action": cancel ? "cancel" : "back", "parent": parent, "stopToClosedSeconds": elapsed, "cancelMessage": message, "cancelledReadyStableSeconds": stableSeconds, "retryAmount": observedAmount, "fileName": observedFileName, "finalParent": "Backup & restore"], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "original-decrypt-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHealthOriginalImportPayloadMalformedLegacy() throws { try healthOriginalImportMalformed("legacy") }
    func testHealthOriginalImportPayloadMalformedReadable() throws { try healthOriginalImportMalformed("readable") }
    func testHealthOriginalImportCopyDeniedLegacy() throws { try healthOriginalImportMalformed("legacy", denied: true) }
    func testHealthOriginalImportCopyDeniedEncrypted() throws { try healthOriginalImportMalformed("encrypted", denied: true) }
    func testHealthOriginalImportCopyDeniedReadable() throws { try healthOriginalImportMalformed("readable", denied: true) }
    func testHealthOriginalImportCopyDeniedLegacyDark() throws { try healthOriginalImportMalformed("legacy", denied: true) }
    func testHealthOriginalImportCopyDeniedEncryptedDark() throws { try healthOriginalImportMalformed("encrypted", denied: true) }
    func testHealthOriginalImportCopyDeniedReadableDark() throws { try healthOriginalImportMalformed("readable", denied: true) }
    func testHealthOriginalImportCopyDeniedLegacyLargest() throws { try healthOriginalImportMalformed("legacy", denied: true) }
    func testHealthOriginalImportCopyDeniedEncryptedLargest() throws { try healthOriginalImportMalformed("encrypted", denied: true) }
    func testHealthOriginalImportCopyDeniedReadableLargest() throws { try healthOriginalImportMalformed("readable", denied: true) }
    private func healthOriginalImportMalformed(_ kind: String, denied: Bool = false) throws {
        executionTimeAllowance = 600
        let readable = kind == "readable", prefix = (denied ? "original-denied-" : "original-malformed-") + kind
        let healthyName = readable ? "Lumen-readable-health-small" : "Lumen-backup-health-" + kind + "-small"
        if readable { openReadableRecovery(); try chooseReadableFixture(denied ? healthyName : "Lumen-readable-health-malformed") }
        else { openBackupSettings(); try chooseBackupFixture(denied ? healthyName : "Lumen-backup-health-malformed") }
        let state = app.descendants(matching: .any).matching(identifier: "healthImportReadState").firstMatch
        func phase(_ value: String) {
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: state)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 15), .completed)
        }
        XCTAssertTrue(state.waitForExistence(timeout: 10)); phase("held-1")
        let observedTraits = state.label
        let expectedAppearance = name.contains("Dark") || name.contains("Largest") ? "dark" : "light"
        let expectedType = name.contains("Largest") ? "accessibility5" : "large"
        if denied { XCTAssertEqual(observedTraits, "Import read check; appearance=\(expectedAppearance); type=\(expectedType)") }
        snap(prefix + "-held"); phase("observed-1"); snap(prefix + "-observed")
        let title = readable ? "Couldn't read export" : "Couldn’t open backup"
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: 20))
        let expected = readable
            ? "Choose a readable Lumen JSON file made with Export my data. Use Backup & restore for backup files."
            : "This file isn’t a valid Lumen backup. Choose a file created from Backup & restore. Older data exports can’t be restored here."
        let observedError = denied ? alert.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: "\n") : expected
        var errorFrames: [String: Any] = [:]
        if denied {
            let body = alert.staticTexts["Lumen couldn’t read this file. Keep the original and choose it again. No records were imported."]
            XCTAssertTrue(body.exists)
            XCTAssertFalse(observedError.contains("selected-backup")); XCTAssertFalse(observedError.contains("LumenBackupWork-v1-"))
            settleLabFrame(alert, pixelTolerance: 1)
            let action = alert.buttons["OK"]
            XCTAssertTrue(action.isHittable)
            XCTAssertTrue(app.frame.insetBy(dx: -0.5, dy: -0.5).contains(action.frame))
            XCTAssertTrue(alert.frame.insetBy(dx: -0.5, dy: -0.5).contains(action.frame))
            func frame(_ value: CGRect) -> [String: Double] {
                ["x": value.minX, "y": value.minY, "width": value.width, "height": value.height]
            }
            let fits = alert.frame.insetBy(dx: -0.5, dy: -0.5).contains(body.frame) && app.frame.insetBy(dx: -0.5, dy: -0.5).contains(body.frame)
            errorFrames = ["application": frame(app.frame), "alert": frame(alert.frame), "body": frame(body.frame),
                "action": frame(action.frame), "bodyFitsWithoutScrolling": fits, "actionHittable": action.isHittable]
            if name.contains("Largest") || !fits { capturePreferenceAlert(alert, prefix: prefix + "-error-full") }
        }
        else { XCTAssertTrue(alert.staticTexts[expected].exists) }
        snap(prefix + "-error")
        if denied {
            let layout: [String: Any] = ["scope": "selected-original-denied-error-layout", "format": kind,
                "errorTitle": title, "errorMessage": observedError, "observedTraits": observedTraits,
                "expectedAppearance": expectedAppearance, "expectedType": expectedType, "errorFrames": errorFrames,
                "largestOverlappingCapturesRequired": name.contains("Largest")]
            let capture = XCTAttachment(data: try JSONSerialization.data(withJSONObject: layout, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            capture.name = "original-denied-error-layout-readback"; capture.lifetime = .keepAlways; add(capture)
        }
        alert.buttons["OK"].tap()
        let instructions = app.staticTexts["importReadFailureInstructions"].firstMatch
        if denied {
            snap(prefix + "-instructions-initial")
            capturePreferenceDisclosure("importReadFailureInstructions", prefix: prefix + "-instructions",
                                        navigationTitle: readable ? "Recover export" : "Backup & restore",
                                        bottomLimit: state.frame.minY - 12)
            XCTAssertEqual(instructions.label, "Lumen couldn’t read this file. Keep the original and choose it again. No records were imported.")
        }
        let choose = app.buttons[readable ? "chooseReadableExport" : "chooseBackup"].firstMatch
        reveal(choose); XCTAssertTrue(choose.exists && choose.isEnabled)
        let link = app.buttons[readable ? "reviewReadableHealthRecovery" : "reviewBackupHealthRecovery"].firstMatch
        XCTAssertFalse(link.exists); XCTAssertFalse(app.secureTextFields["unlockBackupPassword"].firstMatch.exists)
        phase("closed-1"); snap(prefix + "-ready")
        func idle() {
            let late = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
                app.alerts.firstMatch.exists || app.buttons[readable ? "cancelReadableOperation" : "cancelBackupOperation"].firstMatch.exists
            }, object: app)
            late.isInverted = true; XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 4), .completed)
        }
        idle()
        if readable { try chooseReadableFixture(healthyName) }
        else { try chooseBackupFixture(healthyName) }
        phase("held-2"); snap(prefix + "-retry-held")
        if denied { XCTAssertFalse(instructions.exists, "A fresh selection clears the previous failure instruction") }
        if readable { waitForReadableReview() }
        else {
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
        }
        // Readable preview scrolls to file metadata below its recovery link.
        reveal(link, towardsTop: readable); XCTAssertTrue(link.exists); link.tap()
        let filename = app.staticTexts["recoveryFileName"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10))
        XCTAssertEqual(filename.label, healthyName + (kind == "encrypted" ? ".lumenbackup" : ".json"))
        let observedFilename = filename.label
        let choice = app.switches["recoverFile-water"].firstMatch; reveal(choice); XCTAssertEqual(choice.value as? String, "0")
        snap(prefix + "-retry-off")
        let records = app.buttons["reviewFile-water"].firstMatch; reveal(records, towardsTop: true); records.tap()
        let record = app.buttons["recoveryRecord-0"].firstMatch; XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        let amount = app.descendants(matching: .any).matching(identifier: "recoveryField-0").firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10)); XCTAssertTrue(amount.label.contains("246 mL")); snap(prefix + "-retry-detail")
        for title in ["Water history", "Review recovery", readable ? "Recover export" : "Backup & restore"] {
            app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        }
        // Readable recovery closes and resets its parent form on Back; its
        // chooser follows the intro. Backup keeps its earlier chooser offset.
        reveal(choose, towardsTop: !readable); XCTAssertTrue(choose.exists && choose.isEnabled); XCTAssertFalse(link.exists)
        snap(prefix + "-final-parent"); idle()
        let data: [String: Any] = ["scope": denied ? "selected-original-copy-denied-read" : "selected-original-malformed-payload", "format": kind,
            "errorTitle": title, "errorMessage": observedError, "retryFilename": observedFilename,
            "observedTraits": observedTraits, "expectedAppearance": expectedAppearance, "expectedType": expectedType, "errorFrames": errorFrames,
            "retryAmount": "246 mL", "retryChoiceOff": true, "recoveryCommitted": false,
            "persistentReadInstructionsVerified": denied, "persistentReadInstructionsClearedOnRetry": denied,
            "idleAfterFailureSeconds": 4, "idleAfterFinalParentSeconds": 4]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: data, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = denied ? "original-denied-readback" : "original-malformed-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func healthOriginalImportBack(_ kind: String, cancel: Bool = false, copying: Bool = false, payload: Bool = false, lifetime: Bool = false) throws {
        executionTimeAllowance = 600
        if kind == "readable" { openReadableRecovery() } else { openBackupSettings() }
        func choose() throws {
            if kind == "readable" { try chooseReadableFixture("Lumen-readable-health-small") }
            else { try chooseBackupFixture("Lumen-backup-health-" + kind + "-small") }
        }
        try choose()
        let state = app.descendants(matching: .any).matching(identifier: "healthImportReadState").firstMatch
        func phase(_ value: String, timeout: TimeInterval) {
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: state)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
        }
        XCTAssertTrue(state.waitForExistence(timeout: 10)); phase("held-1", timeout: 10)
        let prefix = lifetime ? "original-lifetime-" + kind : "original-import-" + (payload ? "payload-" : copying ? "copy-" : "") + (cancel ? "cancel-" : "") + kind
        snap(prefix + "-held"); phase("observed-1", timeout: 10)
        let importTitle = kind == "readable" ? "Recover export" : "Backup & restore"
        let cancelButton = app.buttons[kind == "readable" ? "cancelReadableOperation" : "cancelBackupOperation"].firstMatch
        if cancel { XCTAssertTrue(cancelButton.exists && cancelButton.isEnabled) }
        let started = Date()
        if cancel { cancelButton.tap() }
        else { app.navigationBars[importTitle].buttons.element(boundBy: 0).tap() }
        let parent = cancel ? importTitle : kind == "readable" ? "Backup & restore" : "Settings"
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            app.navigationBars[parent].exists && state.exists && state.value as? String == "closed-1" && (!cancel || !cancelButton.exists)
        }, object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 3), .completed)
        let elapsed = Date().timeIntervalSince(started); XCTAssertLessThan(elapsed, 3)
        var observedMessage = ""
        var cancelledReadyStableSeconds: TimeInterval = 0
        if cancel {
            let expectedMessage = kind == "readable" ? "Cancelled. Your saved data hasn't changed." : "Cancelled. Your records haven’t changed."
            let message = app.staticTexts[expectedMessage].firstMatch
            XCTAssertTrue(message.waitForExistence(timeout: 5)); observedMessage = message.label
            XCTAssertEqual(observedMessage, expectedMessage)
            let choose = app.buttons[kind == "readable" ? "chooseReadableExport" : "chooseBackup"].firstMatch
            reveal(choose, towardsTop: true); XCTAssertTrue(choose.exists && choose.isEnabled)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: kind == "readable" ? "readableProgress" : "backupProgress").firstMatch.exists)
            snap(prefix + "-cancelled-ready")
            if payload {
                // Keep the actual ready page idle while checking that abandoned
                // work cannot revive progress or publish a late preview. The
                // host independently audits cleanup during this same window.
                let lateWork = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
                    cancelButton.exists || app.descendants(matching: .any).matching(identifier: kind == "readable" ? "readableProgress" : "backupProgress").firstMatch.exists
                    || app.buttons[kind == "readable" ? "reviewReadableHealthRecovery" : "reviewBackupHealthRecovery"].firstMatch.exists
                }, object: app)
                lateWork.isInverted = true
                let stableStarted = Date()
                XCTAssertEqual(XCTWaiter.wait(for: [lateWork], timeout: 4), .completed)
                cancelledReadyStableSeconds = Date().timeIntervalSince(stableStarted)
            }
        } else {
            snap(prefix + "-back-closed")
            let reopen = app.buttons[kind == "readable" ? "readableRecovery" : "backupSettings"].firstMatch
            reveal(reopen); XCTAssertTrue(reopen.exists && reopen.isEnabled); reopen.tap()
            XCTAssertTrue(app.navigationBars[importTitle].waitForExistence(timeout: 5))
        }
        try choose(); phase("held-2", timeout: 10)
        snap(prefix + "-retry-held")
        if kind == "readable" { waitForReadableReview() }
        else {
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
        }
        let link = app.buttons[kind == "readable" ? "reviewReadableHealthRecovery" : "reviewBackupHealthRecovery"].firstMatch
        reveal(link); XCTAssertTrue(link.exists); link.tap()
        let filename = app.staticTexts["recoveryFileName"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10))
        let expectedName = kind == "readable" ? "Lumen-readable-health-small.json" : "Lumen-backup-health-" + kind + "-small." + (kind == "encrypted" ? "lumenbackup" : "json")
        XCTAssertEqual(filename.label, expectedName)
        let choice = app.switches["recoverFile-water"].firstMatch; reveal(choice); XCTAssertEqual(choice.value as? String, "0")
        snap(prefix + "-retry-off")
        if lifetime {
            nativeSwitch("recoverFile-water", enabled: true)
            XCTAssertEqual(choice.value as? String, "1")
            snap(prefix + "-retry-selected")
        }
        let records = app.buttons["reviewFile-water"].firstMatch; reveal(records, towardsTop: true); records.tap()
        let record = app.buttons["recoveryRecord-0"].firstMatch; XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        let amount = app.descendants(matching: .any).matching(identifier: "recoveryField-0").firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10)); XCTAssertTrue(amount.label.contains("246 mL"))
        let observedAmount = amount.label
        snap(prefix + "-retry-detail")
        var reselectedAmount = ""
        if lifetime {
            func idle(_ seconds: TimeInterval) {
                let late = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in app.alerts.firstMatch.exists }, object: app)
                late.isInverted = true
                XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: seconds), .completed)
            }
            func closeReview(_ tag: String) {
                for title in ["Water history", "Review recovery", importTitle] {
                    app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
                    XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
                }
                let choose = app.buttons[kind == "readable" ? "chooseReadableExport" : "chooseBackup"].firstMatch
                reveal(choose, towardsTop: true); XCTAssertTrue(choose.exists && choose.isEnabled)
                XCTAssertFalse(link.exists); XCTAssertFalse(cancelButton.exists)
                snap(prefix + tag); idle(4)
            }
            idle(3); closeReview("-first-parent")
            try choose(); phase("held-3", timeout: 10)
            snap(prefix + "-reselected-held")
            if kind == "readable" { waitForReadableReview() }
            else { XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30)) }
            reveal(link); XCTAssertTrue(link.exists); link.tap()
            XCTAssertTrue(filename.waitForExistence(timeout: 10)); XCTAssertEqual(filename.label, expectedName)
            reveal(choice); XCTAssertEqual(choice.value as? String, "0", "A new file review must not inherit the previously enabled recovery choice")
            snap(prefix + "-reselected-off")
            reveal(records, towardsTop: true); records.tap()
            XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
            XCTAssertTrue(amount.waitForExistence(timeout: 10)); XCTAssertTrue(amount.label.contains("246 mL"))
            reselectedAmount = amount.label
            snap(prefix + "-reselected-detail")
            idle(3); closeReview("-final-parent")
        }
        var readback: [String: Any] = ["scope": "selected-import", "action": cancel ? "cancel" : "back", "format": kind, "fileName": expectedName, "stopToClosedSeconds": elapsed, "stopStartedUnix": started.timeIntervalSince1970, "parent": parent, "retryAmount": observedAmount, "cancelMessage": observedMessage, "finalLifetimeChecked": lifetime, "reselectedAmount": reselectedAmount, "reselectedChoiceInitiallyOff": lifetime]
        readback["readBoundary"] = payload ? "original-payload" : copying ? "original-copy" : "selected-source"
        readback["cancelledReadyStableSeconds"] = cancelledReadyStableSeconds
        if !cancel { readback["backToClosedSeconds"] = elapsed; readback["backStartedUnix"] = started.timeIntervalSince1970 }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "original-import-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHealthBackupFileReadOwnerUnwindLegacy() throws { try healthBackupFileRead("legacy", ownerUnwind: true) }
    func testHealthBackupFileReadOwnerUnwindEncrypted() throws { try healthBackupFileRead("encrypted", ownerUnwind: true) }
    func testHealthBackupFileReadOwnerUnwindReadable() throws { try healthBackupFileRead("readable", ownerUnwind: true) }
    func testHealthBackupPhotoOwnerUnwindLegacy() throws { try healthBackupPhotoOwnerUnwind("legacy") }
    func testHealthBackupPhotoOwnerUnwindEncrypted() throws { try healthBackupPhotoOwnerUnwind("encrypted") }
    func testHealthBackupPhotoChangeLegacyInPlace() throws { try healthBackupPhotoOwnerUnwind("legacy", mode: "in-place") }
    func testHealthBackupPhotoChangeLegacyReplacement() throws { try healthBackupPhotoOwnerUnwind("legacy", mode: "replacement") }
    func testHealthBackupPhotoChangeEncryptedInPlace() throws { try healthBackupPhotoOwnerUnwind("encrypted", mode: "in-place") }
    func testHealthBackupPhotoChangeEncryptedReplacement() throws { try healthBackupPhotoOwnerUnwind("encrypted", mode: "replacement") }
    private func healthBackupPhotoOwnerUnwind(_ kind: String, mode: String? = nil) throws {
        executionTimeAllowance = 360
        let prefix = mode.map { "selected-photo-change-" + kind + "-" + $0 } ?? "selected-photo-" + kind
        let expectedName = "Lumen-backup-health-photo-" + kind + (kind == "encrypted" ? ".lumenbackup" : ".json")
        let state = app.descendants(matching: .any).matching(identifier: "healthReadControlState").firstMatch
        let loading = app.descendants(matching: .any).matching(identifier: "recoveryPhotoLoading").firstMatch
        let link = app.buttons["reviewBackupHealthRecovery"].firstMatch
        func phase(_ value: String, object: XCUIElement, timeout: TimeInterval = 15) {
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: object)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
        }
        func idle(_ seconds: TimeInterval) {
            let late = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in app.alerts.firstMatch.exists }, object: app)
            late.isInverted = true; XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: seconds), .completed)
        }
        func openPhoto(_ tag: String) throws -> String {
            try chooseBackupFixture("Lumen-backup-health-photo-" + kind)
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
            reveal(link); XCTAssertTrue(link.exists); link.tap()
            let filename = app.staticTexts["recoveryFileName"].firstMatch
            XCTAssertTrue(filename.waitForExistence(timeout: 10)); XCTAssertEqual(filename.label, expectedName)
            let choice = app.switches["recoverFile-water"].firstMatch; reveal(choice); XCTAssertEqual(choice.value as? String, "0")
            snap(prefix + tag + "-source")
            let records = app.buttons["reviewFile-meals"].firstMatch; reveal(records); records.tap()
            let meal = app.buttons["recoveryRecord-0"].firstMatch; XCTAssertTrue(meal.waitForExistence(timeout: 10)); meal.tap()
            let mealTitle = app.navigationBars.firstMatch.identifier
            let photoLink = app.buttons["recoveryChild-0"].firstMatch; reveal(photoLink); XCTAssertTrue(photoLink.exists); photoLink.tap()
            XCTAssertTrue(loading.waitForExistence(timeout: 10))
            return mealTitle
        }
        func parent(_ title: String) {
            app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
        }
        openBackupSettings()
        let firstMealTitle = try openPhoto("-first")
        let choose = app.buttons["chooseBackup"].firstMatch
        phase("held-1", object: loading); snap(prefix + "-held")
        let mealTitle: String
        var rejectedMessage = ""
        if mode != nil {
            let issue = app.staticTexts["This photo changed or couldn't be opened. Return to choose the file again."].firstMatch
            XCTAssertTrue(issue.waitForExistence(timeout: 30)); phase("closed-1", object: state)
            XCTAssertFalse(app.images["recoveryMealPhoto"].exists)
            rejectedMessage = issue.label
            snap(prefix + "-rejected"); idle(4)
            parent(firstMealTitle)
            let photoLink = app.buttons["recoveryChild-0"].firstMatch; reveal(photoLink); XCTAssertTrue(photoLink.exists); photoLink.tap()
            XCTAssertTrue(loading.waitForExistence(timeout: 10)); mealTitle = firstMealTitle
        } else {
            phase("observed-1", object: loading)
            parent(firstMealTitle); phase("unwinding-1", object: state)
            for title in ["Meal history", "Review recovery", "Backup & restore"] { parent(title) }
            XCTAssertFalse(link.exists); snap(prefix + "-owner-closed-worker-held")
            reveal(choose, towardsTop: true); XCTAssertTrue(choose.exists && choose.isEnabled)
            snap(prefix + "-worker-finished-parent"); idle(4)
            mealTitle = try openPhoto("-retry")
        }
        phase("held-2", object: loading); XCTAssertFalse(app.images["recoveryMealPhoto"].exists); snap(prefix + "-retry-held")
        let photo = app.images["recoveryMealPhoto"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30)); reveal(photo); alignHealthRecordPhoto(photo)
        XCTAssertTrue(photo.frame.width > 0 && photo.frame.height > photo.frame.width && app.frame.contains(photo.frame))
        XCTAssertEqual(photo.label, "Meal photo from this file")
        let photoLabel = photo.label
        let frame = photo.frame
        snap(prefix + "-retry-image"); idle(3)
        for title in [mealTitle, "Meal history", "Review recovery", "Backup & restore"] { parent(title) }
        XCTAssertFalse(link.exists); reveal(choose, towardsTop: true); XCTAssertTrue(choose.exists && choose.isEnabled)
        snap(prefix + "-final-parent"); idle(4)
        let readback: [String: Any] = ["scope": "selected-photo", "format": kind, "fileName": expectedName,
            "photoLabel": photoLabel, "waterRecoveryInitiallyOff": true, "ownerUnwind": mode == nil,
            "mutation": mode ?? "none", "rejectedMessage": rejectedMessage,
            "x": frame.minX, "y": frame.minY, "width": frame.width, "height": frame.height,
            "timingScope": mode == nil ? "Finite artificial cancellation-unwind hold; no cancellation latency measured" : "Host-held source-change/restoration reads; no cancellation latency measured"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "selected-photo-owner-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func healthBackupFileRead(_ kind: String, ownerUnwind: Bool = false) throws {
        executionTimeAllowance = 300
        if kind == "readable" {
            openReadableRecovery(); try chooseReadableFixture("Lumen-readable-health-small"); waitForReadableReview()
        } else {
            openBackupSettings(); try chooseBackupFixture("Lumen-backup-health-" + kind + "-small")
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
        }
        let link = app.buttons[kind == "readable" ? "reviewReadableHealthRecovery" : "reviewBackupHealthRecovery"].firstMatch
        reveal(link); XCTAssertTrue(link.waitForExistence(timeout: 10)); link.tap()
        let filename = app.staticTexts["recoveryFileName"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10))
        let expectedName = kind == "readable" ? "Lumen-readable-health-small.json" : "Lumen-backup-health-" + kind + "-small." + (kind == "encrypted" ? "lumenbackup" : "json")
        XCTAssertEqual(filename.label, expectedName)
        snap("selected-record-" + kind + "-source")
        let records = app.buttons["reviewFile-water"].firstMatch; reveal(records); records.tap()
        let loading = app.descendants(matching: .any).matching(identifier: "fileRecordsLoading").firstMatch
        func phase(_ value: String, object: XCUIElement, timeout: TimeInterval) {
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: object)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
        }
        XCTAssertTrue(loading.waitForExistence(timeout: 10)); phase("held-1", object: loading, timeout: 10)
        snap("selected-record-" + kind + "-held"); phase("observed-1", object: loading, timeout: 10)
        let started = Date()
        app.navigationBars["Water history"].buttons.element(boundBy: 0).tap()
        let state = app.descendants(matching: .any).matching(identifier: "healthReadControlState").firstMatch
        if ownerUnwind {
            phase("unwinding-1", object: state, timeout: 10)
            let parent = kind == "readable" ? "Recover export" : "Backup & restore"
            app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars[parent].waitForExistence(timeout: 5))
            snap("selected-record-" + kind + "-owner-closed-worker-held")
            // The review's debug indicator leaves the hierarchy with review.
            // The host observes the live reader and releases its unwind delay
            // during this parent window; it checks closure before retry release.
            let choose = app.buttons[kind == "readable" ? "chooseReadableExport" : "chooseBackup"].firstMatch
            reveal(choose, towardsTop: true); XCTAssertTrue(choose.exists && choose.isEnabled)
            XCTAssertFalse(link.exists)
            snap("selected-record-" + kind + "-worker-finished-parent")
            let late = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in app.alerts.firstMatch.exists || link.exists }, object: app)
            late.isInverted = true
            XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 4), .completed)
            if kind == "readable" { try chooseReadableFixture("Lumen-readable-health-small"); waitForReadableReview() }
            else {
                try chooseBackupFixture("Lumen-backup-health-" + kind + "-small")
                if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
                XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
            }
            reveal(link); XCTAssertTrue(link.exists); link.tap()
        }
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            app.navigationBars["Review recovery"].exists && state.exists && state.value as? String == "closed-1"
        }, object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 3), .completed)
        let elapsed = Date().timeIntervalSince(started)
        if !ownerUnwind { XCTAssertLessThan(elapsed, 3) }
        let choice = app.switches["recoverFile-water"].firstMatch; reveal(choice)
        XCTAssertEqual(choice.value as? String, "0")
        snap("selected-record-" + kind + "-back-closed")
        reveal(records, towardsTop: true); records.tap()
        XCTAssertTrue(loading.waitForExistence(timeout: 5)); phase("held-2", object: loading, timeout: 10)
        snap("selected-record-" + kind + "-retry-held")
        let record = app.buttons["recoveryRecord-0"].firstMatch; XCTAssertTrue(record.waitForExistence(timeout: 30)); record.tap()
        let amount = app.descendants(matching: .any).matching(identifier: "recoveryField-0").firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10)); XCTAssertTrue(amount.label.contains("246 mL"))
        XCTAssertFalse(app.staticTexts["This file changed or couldn't be opened. Return to choose the file again."].exists)
        snap("selected-record-" + kind + "-retry-detail")
        let observedAmount = amount.label
        if ownerUnwind {
            let inspect = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in app.alerts.firstMatch.exists }, object: app)
            inspect.isInverted = true; XCTAssertEqual(XCTWaiter.wait(for: [inspect], timeout: 3), .completed)
            for title in ["Water history", "Review recovery", kind == "readable" ? "Recover export" : "Backup & restore"] {
                app.navigationBars.firstMatch.buttons.element(boundBy: 0).tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 5))
            }
            XCTAssertFalse(link.exists)
            snap("selected-record-" + kind + "-final-parent")
            let late = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in app.alerts.firstMatch.exists || link.exists }, object: app)
            late.isInverted = true; XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 4), .completed)
        }
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: ["scope": "selected-record", "format": kind, "fileName": expectedName, "backToClosedSeconds": elapsed, "retryAmount": observedAmount, "ownerUnwind": ownerUnwind, "timingScope": ownerUnwind ? "Deliberate host-held cancellation unwind plus fresh selection; not cancellation latency" : "Back to closed reader"], options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "selected-record-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHealthBackupFileRecoveryAllCommitLegacy() throws { try healthBackupMultipleDomains("legacy") }
    func testHealthBackupFileRecoveryEmptyLegacy() throws { try healthBackupEmptyDomains("legacy") }
    func testHealthBackupFileRecoveryEmptyEncrypted() throws { try healthBackupEmptyDomains("encrypted") }
    func testHealthBackupFileRecoveryEmptyReadable() throws { try healthBackupEmptyDomains("readable") }
    private func healthBackupEmptyDomains(_ kind: String) throws {
        executionTimeAllowance = 420
        let base = kind == "readable" ? "Lumen-readable-health-small" : "Lumen-backup-health-" + kind + "-small"
        let prefix = "health-empty-" + kind
        if kind == "readable" { openReadableRecovery(); try chooseReadableFixture(base); waitForReadableReview() }
        else {
            openBackupSettings(); try chooseBackupFixture(base)
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
        }
        let link = app.buttons[kind == "readable" ? "reviewReadableHealthRecovery" : "reviewBackupHealthRecovery"].firstMatch
        reveal(link); link.tap()
        let filename = app.staticTexts["recoveryFileName"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10)); XCTAssertEqual(filename.label, base + (kind == "encrypted" ? ".lumenbackup" : ".json"))
        snap(prefix + "-source"); Thread.sleep(forTimeInterval: 3)
        for domain in ["water", "goals"] {
            let review = app.buttons["reviewFile-" + domain].firstMatch
            reveal(review); XCTAssertTrue(review.exists)
            XCTAssertFalse(app.switches["recoverFile-" + domain].exists); snap(prefix + "-healthy-" + domain)
        }
        let domains = ["meals", "workouts"]
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "meals"); XCTAssertEqual(choice.value as? String, "0"); snap(prefix + "-off-" + domain)
            let review = app.buttons["reviewFile-" + domain].firstMatch; reveal(review); review.tap()
            XCTAssertTrue(app.staticTexts["No records in this file."].waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["recoveryRecord-0"].exists); snap(prefix + "-empty-" + domain)
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        let confirm = app.buttons["confirmFileRecovery"].firstMatch; reveal(confirm); XCTAssertFalse(confirm.isEnabled)
        for domain in domains { nativeSwitch("recoverFile-" + domain, enabled: true, towardsTop: domain == "meals") }
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); snap(prefix + "-selected"); confirm.tap()
        let alert = app.alerts["Replace selected data?"]; XCTAssertTrue(alert.waitForExistence(timeout: 5))
        snap(prefix + "-confirmation"); alert.buttons["Not now"].tap()
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "meals"); XCTAssertEqual(choice.value as? String, "1")
        }
        snap(prefix + "-not-now"); Thread.sleep(forTimeInterval: 3)
        reveal(confirm); confirm.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
        let busy = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryBusy").firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 10))
        for value in ["held-1", "observed-1"] {
            let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 15), .completed); snap(prefix + "-" + value)
        }
        let success = app.descendants(matching: .any).matching(identifier: "fileHealthRecovered").firstMatch
        reveal(success, towardsTop: true); XCTAssertTrue(success.waitForExistence(timeout: 30)); snap(prefix + "-success")
        app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars[kind == "readable" ? "Recover export" : "Backup & restore"].waitForExistence(timeout: 5))
        snap(prefix + "-parent"); Thread.sleep(forTimeInterval: 4)
        let readback: [String: Any] = ["scope": "selected-file-empty-meals-workouts", "format": kind, "domains": domains, "initialChoicesOff": true, "emptyListsReviewed": 2, "healthyWaterGoalsChoicesAbsent": true, "successObserved": true]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "empty-recovery-readback"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launchArguments = []; app.launch(); openBackupSettings()
        XCTAssertFalse(app.staticTexts["Saved health data couldn't be opened."].exists); snap(prefix + "-relaunch")
    }
    @MainActor
    func testReduceMotionSettingsDiscovery() throws {
        executionTimeAllowance = 180
        #if targetEnvironment(simulator)
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        let before = UIAccessibility.isReduceMotionEnabled
        var pages: [[String: Any]] = []
        func capture(_ name: String) {
            pages.append(["page": name, "at": Date().timeIntervalSince1970,
                          "tree": settings.debugDescription])
            let image = XCTAttachment(screenshot: settings.screenshot())
            image.name = "reduce-motion-discovery-" + name
            image.lifetime = .keepAlways; add(image)
        }
        func openObserved(_ label: String) -> Bool {
            let row = settings.staticTexts[label].firstMatch
            for _ in 0..<6 {
                if row.exists && row.isHittable { row.tap(); return true }
                settings.swipeUp()
            }
            return false
        }
        settings.launch()
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 10))
        capture("initial")
        var motion = settings.switches["Reduce Motion"].firstMatch
        if !motion.exists, openObserved("Accessibility") { capture("accessibility") }
        if !motion.exists, openObserved("Motion") { capture("motion") }
        motion = settings.switches["Reduce Motion"].firstMatch
        let found = motion.exists
        if found { capture("switch-observed") } else { capture("navigation-endpoint") }
        let report: [String: Any] = [
            "scope": "Read-only simulator Settings discovery; no preference toggle or motion behavior acceptance",
            "beforeUIKitReduceMotion": before,
            "afterUIKitReduceMotion": UIAccessibility.isReduceMotionEnabled,
            "motionSwitchFound": found,
            "motionSwitchValue": found ? (motion.value as? String ?? "unavailable") : "not-found",
            "pages": pages
        ]
        let data = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        data.name = "reduce-motion-settings-discovery-readback"; data.lifetime = .keepAlways; add(data)
        XCTAssertEqual(before, UIAccessibility.isReduceMotionEnabled)
        #else
        XCTFail("Settings discovery is authorized for the dedicated simulator only")
        #endif
    }

    @MainActor
    func testReduceMotionSettingsCapability() throws {
        try withObservedReduceMotion(returnToProduct: false) { _ in }
        var observedExpectedFailure = false
        do {
            try withObservedReduceMotion(returnToProduct: false) { _ in
                throw NSError(domain: "LumenExpectedMotionBodyFailure", code: 42)
            }
        } catch {
            observedExpectedFailure = error.localizedDescription.contains("LumenExpectedMotionBodyFailure")
        }
        XCTAssertTrue(observedExpectedFailure, "The deliberate throwing-body trial must fail after restoring the original preference")
    }

    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackEncryptedReduceMotion() throws {
        try withObservedReduceMotion(returnToProduct: true) { sample in
            try withoutActuallyEscaping(sample) { synchronousSample in
                try healthBackupPhotoFaultErrorBack("encrypted", motionSample: synchronousSample)
            }
        }
    }

    @MainActor
    private func withObservedReduceMotion(returnToProduct: Bool,
        body: (_ sample: (String) throws -> Void) throws -> Void) throws {
        #if targetEnvironment(simulator)
        executionTimeAllowance = 720
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        var samples: [[String: Any]] = []
        var original: Bool?
        var restorationNeeded = false
        var failure: String?
        var restorationError: String?
        let prefix = returnToProduct ? "reduce-motion-enabled-recovery" : "reduce-motion-capability"
        func problem(_ message: String) -> NSError {
            NSError(domain: "LumenReduceMotion", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: message])
        }
        func openMotion() throws -> XCUIElement {
            settings.activate()
            guard settings.wait(for: .runningForeground, timeout: 10) else { throw problem("Settings did not become foreground") }
            let control = settings.switches.matching(identifier: "REDUCE_MOTION").firstMatch
            if !control.exists {
                if settings.navigationBars["Accessibility"].exists {
                    let motion = settings.buttons["MOTION_TITLE"].firstMatch
                    guard motion.exists && motion.isHittable else { throw problem("Observed Motion row unavailable") }
                    motion.tap()
                } else {
                    let accessibility = settings.buttons["com.apple.settings.accessibility"].firstMatch
                    guard accessibility.exists && accessibility.isHittable else { throw problem("Observed Accessibility row unavailable") }
                    accessibility.tap()
                    let motion = settings.buttons["MOTION_TITLE"].firstMatch
                    guard motion.waitForExistence(timeout: 5) && motion.isHittable else { throw problem("Observed Motion row unavailable") }
                    motion.tap()
                }
            }
            guard control.waitForExistence(timeout: 5), control.isHittable else { throw problem("Observed Reduce Motion switch unavailable") }
            return control
        }
        func waitForPreference(_ enabled: Bool, control: XCUIElement) throws {
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline {
                let switchValue = control.value as? String ?? "unavailable"
                let systemValue = UIAccessibility.isReduceMotionEnabled
                if systemValue == enabled, switchValue == (enabled ? "1" : "0") { return }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            samples.append(["phase": "preference-timeout", "at": Date().timeIntervalSince1970,
                            "requested": enabled, "switch": control.value as? String ?? "unavailable",
                            "uikit": UIAccessibility.isReduceMotionEnabled])
            capture("preference-timeout")
            throw problem("Actual Settings switch/public UIKit preference did not match requested state")
        }
        func tapObservedThumb(_ control: XCUIElement) throws {
            // Source189 actual AX tree separates the broad labelled row from
            // its nested63-point switch. Hit that observed switch itself.
            let thumb = control.switches.firstMatch
            guard thumb.exists && thumb.isHittable else { throw problem("Observed nested Reduce Motion switch unavailable") }
            thumb.tap()
        }
        func capture(_ phase: String) {
            let image = XCTAttachment(screenshot: settings.screenshot())
            image.name = prefix + "-" + phase; image.lifetime = .keepAlways; add(image)
        }
        func report(_ phase: String) throws {
            let value: [String: Any] = ["scope": "Observed Settings enable/restore and public UIKit preference samples; no continuous motion behavior acceptance",
                "phase": phase, "original": (original as Any?) ?? NSNull(),
                "restored": original.map { UIAccessibility.isReduceMotionEnabled == $0 } ?? false,
                "finalUIKitReduceMotion": UIAccessibility.isReduceMotionEnabled,
                "samples": samples, "failure": (failure as Any?) ?? NSNull(),
                "restorationError": (restorationError as Any?) ?? NSNull()]
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = prefix + "-readback-" + phase; attachment.lifetime = .keepAlways; add(attachment)
        }
        func restore() throws {
            guard let original else { return }
            let control = try openMotion()
            guard let current = control.value as? String, ["0", "1"].contains(current) else { throw problem("Restoration switch value unavailable") }
            if current != (original ? "1" : "0") { try tapObservedThumb(control) }
            try waitForPreference(original, control: control)
            samples.append(["phase": "restored", "at": Date().timeIntervalSince1970,
                            "switch": control.value as? String ?? "unavailable",
                            "uikit": UIAccessibility.isReduceMotionEnabled])
            capture("restored"); restorationNeeded = false
        }
        // XCTest teardown also runs when an ordinary recovery assertion aborts
        // the test before its Swift body can return or throw.
        addTeardownBlock { @MainActor in
            guard restorationNeeded else { return }
            do { try restore() }
            catch { restorationError = String(describing: error) }
            try report("teardown-fallback")
            if restorationNeeded { throw problem("Reduce Motion original-state restoration remains unverified") }
        }
        do {
            settings.launch()
            let control = try openMotion()
            guard let value = control.value as? String, ["0", "1"].contains(value) else { throw problem("Initial switch value unavailable") }
            original = value == "1"
            guard UIAccessibility.isReduceMotionEnabled == original else { throw problem("Initial actual switch/UIKit preference disagree") }
            samples.append(["phase": "original", "at": Date().timeIntervalSince1970,
                            "switch": value, "uikit": UIAccessibility.isReduceMotionEnabled])
            capture("original"); restorationNeeded = true
            if value == "0" { try tapObservedThumb(control) }
            samples.append(["phase": "enable-requested", "at": Date().timeIntervalSince1970,
                            "switch": control.value as? String ?? "unavailable",
                            "uikit": UIAccessibility.isReduceMotionEnabled])
            capture("enable-requested")
            try waitForPreference(true, control: control)
            samples.append(["phase": "enabled", "at": Date().timeIntervalSince1970,
                            "switch": control.value as? String ?? "unavailable",
                            "uikit": UIAccessibility.isReduceMotionEnabled])
            capture("enabled")
            if returnToProduct { app.activate() }
            try body { phase in
                let enabled = UIAccessibility.isReduceMotionEnabled
                samples.append(["phase": phase, "at": Date().timeIntervalSince1970, "uikit": enabled])
                guard enabled else { throw problem("Reduce Motion off at declared recovery sample: " + phase) }
            }
        } catch { failure = String(describing: error) }
        do { try restore() } catch { restorationError = String(describing: error) }
        try report("terminal")
        if let failure { throw problem(failure) }
        if let restorationError { throw problem(restorationError) }
        guard original != nil, !restorationNeeded else { throw problem("Original preference restoration unverified") }
        #else
        XCTFail("Reduce Motion verification is authorized for the dedicated simulator only")
        #endif
    }

    // Pending follow-on draft, outside frozen Source182. Future setup must add
    // -health-read-ui -health-read-scope selected-record ONLY for these tests.
    // Existing actual reader/closed-owner observations avoid new app instrumentation.
    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultVoiceOverCapability() throws {
        executionTimeAllowance = 180
        #if targetEnvironment(simulator)
        guard #available(iOS 27.0, *) else {
            XCTFail("The simulator VoiceOver capability probe requires iOS27")
            return
        }
        XCTAssertEqual(app.state, .runningForeground)
        let service = XCUIDevice.shared.voiceOverService
        let originallyEnabled = service.isEnabled
        var observations: [[String: Any]] = []
        var failure: String?
        var restored = false
        // Restore the selected simulator's previous state even if an observation throws.
        defer {
            if service.isEnabled != originallyEnabled {
                if originallyEnabled { try? service.enable() } else { try? service.disable() }
            }
        }
        do {
            if !originallyEnabled { try service.enable() }
            guard service.isEnabled else {
                throw NSError(domain: "LumenVoiceOverProbe", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "VoiceOver did not enable"])
            }
            let first = try service.currentSpeech()
            observations.append(["action": "current", "utterance": first.utterance,
                                 "at": Date().timeIntervalSince1970])
            for ordinal in 1...4 {
                let output = try service.moveForward()
                observations.append(["action": "forward", "ordinal": ordinal,
                                     "utterance": output.utterance, "at": Date().timeIntervalSince1970])
            }
            let previous = try service.moveBackward()
            observations.append(["action": "backward", "utterance": previous.utterance,
                                 "at": Date().timeIntervalSince1970])
            snap("health-voiceover-capability-enabled")
        } catch {
            failure = String(describing: error)
        }
        do {
            if service.isEnabled != originallyEnabled {
                if originallyEnabled { try service.enable() } else { try service.disable() }
            }
            restored = service.isEnabled == originallyEnabled
        } catch {
            failure = [failure, "Restoration failed: \(error)"].compactMap { $0 }.joined(separator: "; ")
        }
        let utterances = observations.compactMap { $0["utterance"] as? String }
        let report: [String: Any] = [
            "scope": "Simulator VoiceOver service capability only; no recovery-error accessibility acceptance",
            "originallyEnabled": originallyEnabled, "restored": restored,
            "enabledAfterRestoration": service.isEnabled, "observations": observations,
            "failure": (failure as Any?) ?? NSNull()
        ]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "health-voiceover-capability-readback"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertNil(failure)
        XCTAssertTrue(restored, "Restore the simulator's original VoiceOver setting")
        XCTAssertEqual(observations.count, 6)
        XCTAssertTrue(utterances.allSatisfy { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        XCTAssertGreaterThanOrEqual(Set(utterances).count, 2, "Actual speech must change as VoiceOver focus moves")
        #else
        XCTFail("This probe is authorized for the dedicated simulator only")
        #endif
    }

// Actual held-work Cancel/Back routes; paired with the independent frozen-source host verifier.
    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackLegacyHeldCancel() throws { try healthBackupPhotoFaultErrorHeld("legacy", action: "cancel") }
    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackLegacyHeldBack() throws { try healthBackupPhotoFaultErrorHeld("legacy", action: "back") }
    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackEncryptedHeldCancel() throws { try healthBackupPhotoFaultErrorHeld("encrypted", action: "cancel") }
    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackEncryptedHeldBack() throws { try healthBackupPhotoFaultErrorHeld("encrypted", action: "back") }
    @MainActor
    private func healthBackupPhotoFaultErrorHeld(_ kind: String, action: String) throws {
        executionTimeAllowance = 600
        let base = "Lumen-backup-health-matrix-two-" + kind
        let prefix = "health-error-held-" + kind
        func selectOriginal() throws {
            try chooseBackupFixture(base)
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
            let link = app.buttons["reviewBackupHealthRecovery"].firstMatch
            reveal(link); link.tap()
            let filename = app.staticTexts["recoveryFileName"].firstMatch
            XCTAssertTrue(filename.waitForExistence(timeout: 10))
            XCTAssertEqual(filename.label, base + (kind == "encrypted" ? ".lumenbackup" : ".json"))
        }
        openBackupSettings(); try selectOriginal()
        snap(prefix + "-source"); Thread.sleep(forTimeInterval: 3)
        let reviewMeals = app.buttons["reviewFile-meals"].firstMatch
        reveal(reviewMeals); reviewMeals.tap()
        let readerState = app.descendants(matching: .any).matching(identifier: "fileRecordsLoading").firstMatch
        XCTAssertTrue(readerState.waitForExistence(timeout: 10))
        for phase in ["held-1", "observed-1"] {
            let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", phase), object: readerState)
            XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 15), .completed)
            snap(prefix + "-record-" + phase)
        }
        let firstRecord = app.buttons["recoveryRecord-0"].firstMatch
        XCTAssertTrue(firstRecord.waitForExistence(timeout: 10))
        snap(prefix + "-record-read")
        // The loaded native record list establishes the completed actual read.
        // Return directly to review without revisiting a list .task via a child.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let domains = ["meals", "workouts"]
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "meals"); XCTAssertEqual(choice.value as? String, "0")
            nativeSwitch("recoverFile-" + domain, enabled: true)
        }
        let confirm = app.buttons["confirmFileRecovery"].firstMatch
        let alert = app.alerts["Replace selected data?"]
        let failure = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryError").firstMatch
        let success = app.descendants(matching: .any).matching(identifier: "fileHealthRecovered").firstMatch
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Recover"].tap()
        // The app must expose the genuine failure before any test scrolling.
        XCTAssertTrue(failure.waitForExistence(timeout: 30)); XCTAssertTrue(failure.isHittable)
        XCTAssertGreaterThanOrEqual(failure.frame.minY, app.navigationBars["Review recovery"].frame.maxY)
        XCTAssertLessThanOrEqual(failure.frame.maxY, app.frame.maxY - 20)
        XCTAssertTrue(failure.label.contains("Recovery couldn't finish"))
        XCTAssertTrue(failure.label.contains("Your current files haven't been replaced."))
        XCTAssertFalse(success.exists); snap(prefix + "-failed"); Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(action == "cancel" || action == "back")
        nativeSwitch("Recover without meal photos", enabled: true, towardsTop: true)
        reveal(confirm); confirm.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Recover"].tap()
        let busy = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryBusy").firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 10)); XCTAssertFalse(failure.exists)
        let cancel = app.buttons["cancelFileRecovery"].firstMatch
        // No test reveal/scroll is permitted before the actual busy Cancel frame.
        snap(prefix + "-busy-before-visibility-check")
        XCTAssertTrue(cancel.waitForExistence(timeout: 5)); settleLabFrame(cancel)
        let cancelFrame = cancel.frame
        let navigationBottom = app.navigationBars["Review recovery"].frame.maxY
        let appBottom = app.frame.maxY
        var phaseCancelFrames: [String: String] = [:]
        XCTAssertTrue(cancel.isHittable)
        XCTAssertGreaterThanOrEqual(cancelFrame.minY, app.navigationBars["Review recovery"].frame.maxY)
        XCTAssertLessThanOrEqual(cancelFrame.maxY, app.frame.maxY - 20)
        XCTAssertGreaterThan(cancelFrame.height, 0)
        snap(prefix + "-cancel-visible")
        for phase in ["held-2", "observed-2"] {
            let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", phase), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 15), .completed)
            XCTAssertTrue(cancel.isHittable)
            XCTAssertGreaterThanOrEqual(cancel.frame.minY, navigationBottom)
            XCTAssertLessThanOrEqual(cancel.frame.maxY, appBottom - 20)
            phaseCancelFrames[phase] = String(describing: cancel.frame)
            snap(prefix + "-" + phase)
        }
        if action == "cancel" {
            cancel.tap()
            XCTAssertTrue(confirm.waitForExistence(timeout: 10)); XCTAssertTrue(confirm.isEnabled)
            XCTAssertFalse(busy.exists); XCTAssertFalse(failure.exists); XCTAssertFalse(success.exists)
            XCTAssertFalse(app.alerts.firstMatch.exists); settleLabFrame(confirm)
            let idleFrame = confirm.frame
            snap(prefix + "-cancelled"); Thread.sleep(forTimeInterval: 3)
            XCTAssertTrue(confirm.exists && confirm.isEnabled); XCTAssertFalse(busy.exists)
            XCTAssertEqual(confirm.frame.minY, idleFrame.minY, accuracy: 1)
            XCTAssertFalse(app.alerts.firstMatch.exists); XCTAssertFalse(failure.exists); XCTAssertFalse(success.exists)
            snap(prefix + "-cancelled-sample")
            for domain in domains {
                let selected = app.switches["recoverFile-" + domain].firstMatch
                reveal(selected, towardsTop: domain == "meals"); XCTAssertEqual(selected.value as? String, "1")
            }
            let omission = app.switches["Recover without meal photos"].firstMatch
            reveal(omission, towardsTop: true); XCTAssertEqual(omission.value as? String, "1")
            snap(prefix + "-cancelled-choices")
        } else {
            app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 3))
            XCTAssertFalse(failure.exists); XCTAssertFalse(success.exists)
            let choose = app.buttons["chooseBackup"].firstMatch
            reveal(choose); XCTAssertTrue(choose.isEnabled && choose.isHittable)
            XCTAssertFalse(app.alerts.firstMatch.exists)
            snap(prefix + "-back-parent"); Thread.sleep(forTimeInterval: 3)
            XCTAssertTrue(app.navigationBars["Backup & restore"].exists && choose.exists && choose.isEnabled)
            XCTAssertFalse(app.alerts.firstMatch.exists); XCTAssertFalse(failure.exists); XCTAssertFalse(success.exists)
            snap(prefix + "-back-parent-sample")
            try selectOriginal()
            snap(prefix + "-reselected-source"); Thread.sleep(forTimeInterval: 3)
            for domain in domains {
                let fresh = app.switches["recoverFile-" + domain].firstMatch
                reveal(fresh, towardsTop: domain == "meals"); XCTAssertEqual(fresh.value as? String, "0")
            }
            let omission = app.switches["Recover without meal photos"].firstMatch
            reveal(omission, towardsTop: true); XCTAssertEqual(omission.value as? String, "0")
            reveal(confirm); XCTAssertFalse(confirm.isEnabled)
            XCTAssertFalse(failure.exists); XCTAssertFalse(success.exists)
            snap(prefix + "-fresh-off")
            for domain in domains { nativeSwitch("recoverFile-" + domain, enabled: true, towardsTop: domain == "meals") }
        }
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
        XCTAssertTrue(busy.waitForExistence(timeout: 10)); XCTAssertFalse(failure.exists)
        for phase in ["held-3", "observed-3"] {
            let state = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", phase), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [state], timeout: 15), .completed)
            snap(prefix + "-" + phase)
        }
        reveal(success, towardsTop: true); XCTAssertTrue(success.waitForExistence(timeout: 30))
        XCTAssertFalse(failure.exists); snap(prefix + "-success")
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "success-observed"), object: success)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 35), .completed)
        app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
        snap(prefix + "-parent"); Thread.sleep(forTimeInterval: 4)
        let readback: [String: Any] = ["scope": "genuine-error-held-cancel-back-retry", "format": kind, "action": action,
            "cancelFrame": String(describing: cancelFrame), "cancelVisibleBeforeTestScroll": true,
            "usableNavigationBottom": Double(navigationBottom), "appBottom": Double(appBottom), "lowerReserve": 20,
            "phaseCancelFrames": phaseCancelFrames,
            "cancelledControlOrdinal": 2, "retryControlOrdinal": 3,
            "retryOmission": action == "cancel", "silenceSampleIntervalSeconds": 3, "silenceSampling": "Endpoint samples, not continuous/all-interleaving silence", "successObserved": true]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "error-held-readback"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launchArguments = []; app.launch(); openBackupSettings()
        XCTAssertFalse(app.staticTexts["Saved health data couldn't be opened."].exists); snap(prefix + "-relaunch")
    }

    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackLegacyOriginData() throws { try healthBackupPhotoFaultErrorBack("legacy") }
    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackEncryptedOriginString() throws { try healthBackupPhotoFaultErrorBack("encrypted") }
    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackLegacy() throws { try healthBackupPhotoFaultErrorBack("legacy") }
    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackEncrypted() throws { try healthBackupPhotoFaultErrorBack("encrypted") }
    @MainActor
    func testHealthBackupFileRecoveryPhotoFaultErrorBackEncryptedVoiceOver() throws {
        try healthBackupPhotoFaultErrorBack("encrypted", voiceOver: true)
    }
    @MainActor
    private func healthBackupPhotoFaultErrorBack(_ kind: String, voiceOver: Bool = false,
        motionSample: ((String) throws -> Void)? = nil) throws {
        executionTimeAllowance = 600
        let base = "Lumen-backup-health-matrix-two-" + kind
        let prefix = "health-error-state-" + kind
        func selectOriginal() throws {
            try chooseBackupFixture(base)
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
            let link = app.buttons["reviewBackupHealthRecovery"].firstMatch
            reveal(link); link.tap()
            let filename = app.staticTexts["recoveryFileName"].firstMatch
            XCTAssertTrue(filename.waitForExistence(timeout: 10))
            XCTAssertEqual(filename.label, base + (kind == "encrypted" ? ".lumenbackup" : ".json"))
        }
        try motionSample?("before-original-selection")
        openBackupSettings(); try selectOriginal()
        snap(prefix + "-source"); Thread.sleep(forTimeInterval: 3)
        if name.contains("Origin") {
            let older = app.staticTexts["Older saved data couldn't be opened."].firstMatch
            reveal(older); XCTAssertTrue(older.waitForExistence(timeout: 10))
            captureIdentifierText(older, prefix: prefix + "-older-data-row")
        }
        let reviewMeals = app.buttons["reviewFile-meals"].firstMatch
        reveal(reviewMeals); reviewMeals.tap()
        let readerState = app.descendants(matching: .any).matching(identifier: "fileRecordsLoading").firstMatch
        XCTAssertTrue(readerState.waitForExistence(timeout: 10))
        for phase in ["held-1", "observed-1"] {
            let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", phase), object: readerState)
            XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 15), .completed)
            snap(prefix + "-record-" + phase)
        }
        let firstRecord = app.buttons["recoveryRecord-0"].firstMatch
        XCTAssertTrue(firstRecord.waitForExistence(timeout: 10))
        snap(prefix + "-record-read")
        // The loaded native record list establishes the completed actual read.
        // Return directly to review without revisiting a list .task via a child.
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let domains = ["meals", "workouts"]
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "meals"); XCTAssertEqual(choice.value as? String, "0")
            nativeSwitch("recoverFile-" + domain, enabled: true)
        }
        let confirm = app.buttons["confirmFileRecovery"].firstMatch
        let alert = app.alerts["Replace selected data?"]
        let failure = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryError").firstMatch
        let success = app.descendants(matching: .any).matching(identifier: "fileHealthRecovered").firstMatch
        var voiceOverReadback: [String: Any] = [:]
        func confirmWithVoiceOver() throws -> [String: Any] {
            #if targetEnvironment(simulator)
            guard #available(iOS 27.0, *) else { throw NSError(domain: "LumenVoiceOver", code: 1) }
            let service = XCUIDevice.shared.voiceOverService
            let original = service.isEnabled
            var speech: [[String: Any]] = []
            defer {
                if service.isEnabled != original {
                    if original { try? service.enable() } else { try? service.disable() }
                }
            }
            func record(_ action: String, _ utterance: String) {
                speech.append(["action": action, "utterance": utterance, "at": Date().timeIntervalSince1970])
            }
            do {
                if !original { try service.enable() }
                var current = try service.currentSpeech().utterance
                record("confirmation-current", current)
                for _ in 0..<20 {
                    if current == "Recover Button" { break }
                    current = try service.moveForward().utterance
                    record("confirmation-forward", current)
                }
                guard current == "Recover Button" else { throw NSError(domain: "LumenVoiceOver", code: 2, userInfo: [NSLocalizedDescriptionKey: "Recover was not reached with VoiceOver focus"]) }
                // A real double tap activates the element selected by VoiceOver.
                alert.buttons["Recover"].doubleTap()
                guard failure.waitForExistence(timeout: 30) else { throw NSError(domain: "LumenVoiceOver", code: 3) }
                current = try service.currentSpeech().utterance
                record("genuine-error-current", current)
                snap(prefix + "-voiceover-error-focus")
                // Record later service output before attributing a short string to
                // the app. Full spoken-body acceptance remains a separate result.
                var errorSpeech = [current]
                for delay in [2.0, 4.0] {
                    Thread.sleep(forTimeInterval: delay)
                    let later = try service.currentSpeech().utterance
                    errorSpeech.append(later)
                    record("genuine-error-later-current", later)
                }
                guard errorSpeech.allSatisfy({ $0.hasPrefix("Recovery couldn't finish") }) else {
                    throw NSError(domain: "LumenVoiceOver", code: 4, userInfo: [NSLocalizedDescriptionKey: "VoiceOver focus did not remain on the genuine error during the declared samples"])
                }
                let next = try service.moveForward().utterance
                record("error-forward", next)
                guard next.contains("Recover selected data"), next.contains("Button") else { throw NSError(domain: "LumenVoiceOver", code: 5) }
                let back = try service.moveBackward().utterance
                record("error-backward", back)
                guard back.contains("Recovery couldn't finish") else { throw NSError(domain: "LumenVoiceOver", code: 6) }
                if service.isEnabled != original {
                    if original { try service.enable() } else { try service.disable() }
                }
                guard service.isEnabled == original else { throw NSError(domain: "LumenVoiceOver", code: 7) }
                return ["observations": speech, "originallyEnabled": original,
                        "restored": true, "enabledAfterRestoration": service.isEnabled,
                        "errorAccessibilityLabel": failure.label,
                        "completePreservationMessageReturned": errorSpeech.contains { $0.contains("Your current files haven't been replaced.") },
                        "sampledErrorSpeechLengths": errorSpeech.map(\.count),
                        "scope": "Actual genuine-error heading-prefix automatic focus, six-second sampled stability and adjacent retry order only. Full spoken preservation body is accepted only if completePreservationMessageReturned is true. Queried speech is not automatic announcement history, acoustic audio or duplicate-count evidence."]
            } catch {
                var restorationError: String?
                do {
                    if service.isEnabled != original {
                        if original { try service.enable() } else { try service.disable() }
                    }
                } catch { restorationError = String(describing: error) }
                let diagnostic: [String: Any] = ["observations": speech, "failure": String(describing: error), "originallyEnabled": original,
                                               "enabledAfterRestoration": service.isEnabled, "restored": service.isEnabled == original,
                                               "restorationError": (restorationError as Any?) ?? NSNull()]
                let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: diagnostic, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
                attachment.name = "health-voiceover-genuine-error-failure"; attachment.lifetime = .keepAlways; add(attachment)
                throw error
            }
            #else
            throw NSError(domain: "LumenVoiceOver", code: 8)
            #endif
        }
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        if name.contains("Origin") {
            XCTAssertTrue(alert.staticTexts.matching(NSPredicate(format: "label == %@",
                "Selected data will be replaced by records from this file. The older saved data will stay in a private recovery copy on this iPhone.")).firstMatch.exists)
            snap(prefix + "-older-data-confirmation")
        }
        try motionSample?("before-genuine-error")
        if voiceOver { voiceOverReadback = try confirmWithVoiceOver() }
        else { alert.buttons["Recover"].tap() }
        // The app must expose the genuine failure before any test scrolling.
        XCTAssertTrue(failure.waitForExistence(timeout: 30)); XCTAssertTrue(failure.isHittable)
        XCTAssertGreaterThanOrEqual(failure.frame.minY, app.navigationBars["Review recovery"].frame.maxY)
        XCTAssertLessThanOrEqual(failure.frame.maxY, app.frame.maxY - 20)
        XCTAssertTrue(failure.label.contains("Recovery couldn't finish"))
        XCTAssertTrue(failure.label.contains(name.contains("Origin") ? "Lumen hasn't replaced your saved data." : "Your current files haven't been replaced."))
        try motionSample?("genuine-error-before-test-scroll")
        XCTAssertFalse(success.exists); snap(prefix + "-failed"); Thread.sleep(forTimeInterval: 3)
        let choice = app.switches["recoverFile-meals"].firstMatch
        reveal(choice, towardsTop: true); XCTAssertEqual(choice.value as? String, "1")
        settleLabFrame(choice)
        let firstFrame = choice.frame
        XCTAssertTrue(choice.isHittable)
        XCTAssertGreaterThan(firstFrame.midY, app.navigationBars["Review recovery"].frame.maxY)
        XCTAssertLessThan(firstFrame.midY, app.frame.maxY - 40)
        snap(prefix + "-deliberate-scroll")
        Thread.sleep(forTimeInterval: 1)
        XCTAssertTrue(choice.exists && choice.isHittable)
        XCTAssertEqual(choice.frame.minY, firstFrame.minY, accuracy: 1)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertTrue(choice.exists && choice.isHittable)
        XCTAssertEqual(choice.frame.minY, firstFrame.minY, accuracy: 1)
        XCTAssertEqual(choice.value as? String, "1")
        try motionSample?("deliberate-scroll-endpoint"); snap(prefix + "-scroll-stays")
        let omission = app.switches["Recover without meal photos"].firstMatch
        nativeSwitch("Recover without meal photos", enabled: true)
        reveal(confirm); confirm.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Not now"].tap()
        for domain in domains {
            let selected = app.switches["recoverFile-" + domain].firstMatch
            reveal(selected, towardsTop: domain == "meals"); XCTAssertEqual(selected.value as? String, "1")
        }
        reveal(omission, towardsTop: true); XCTAssertEqual(omission.value as? String, "1")
        try motionSample?("after-not-now"); snap(prefix + "-omission-not-now"); Thread.sleep(forTimeInterval: 3)
        reveal(failure); XCTAssertTrue(failure.exists); snap(prefix + "-before-back")
        app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 3))
        let choose = app.buttons["chooseBackup"].firstMatch
        reveal(choose); XCTAssertTrue(choose.isEnabled)
        XCTAssertFalse(failure.exists); XCTAssertFalse(success.exists)
        try motionSample?("after-back"); snap(prefix + "-back-parent"); Thread.sleep(forTimeInterval: 3)
        try selectOriginal()
        snap(prefix + "-reselected-source"); Thread.sleep(forTimeInterval: 3)
        for domain in domains {
            let fresh = app.switches["recoverFile-" + domain].firstMatch
            reveal(fresh, towardsTop: domain == "meals"); XCTAssertEqual(fresh.value as? String, "0")
        }
        reveal(omission, towardsTop: true); XCTAssertEqual(omission.value as? String, "0")
        reveal(confirm); XCTAssertFalse(confirm.isEnabled)
        XCTAssertFalse(failure.exists); XCTAssertFalse(success.exists)
        try motionSample?("fresh-source-defaults"); snap(prefix + "-fresh-off")
        for domain in domains { nativeSwitch("recoverFile-" + domain, enabled: true, towardsTop: domain == "meals") }
        reveal(omission, towardsTop: true); XCTAssertEqual(omission.value as? String, "0")
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
        let busy = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryBusy").firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 10)); XCTAssertFalse(failure.exists)
        for phase in ["held-2", "observed-2"] {
            let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", phase), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 15), .completed)
            snap(prefix + "-" + phase)
        }
        reveal(success, towardsTop: true); XCTAssertTrue(success.waitForExistence(timeout: 30))
        try motionSample?("recovered-before-success-ack"); XCTAssertFalse(failure.exists); snap(prefix + "-success")
        let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "success-observed"), object: success)
        XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 35), .completed)
        app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
        snap(prefix + "-parent"); Thread.sleep(forTimeInterval: 4)
        let readback: [String: Any] = ["scope": "genuine-recovery-error-scroll-back-reselect", "format": kind,
            "scrollFrame": String(describing: firstFrame), "boundedScrollObservationSeconds": 3,
            "initialChoicesOff": true, "failedBeforeTestScroll": true, "omissionNotNowRetained": true,
            "backAtGenuineFailure": true, "freshChoicesAndOmissionOff": true,
            "retryWithoutOmission": true, "successObserved": true, "voiceOver": voiceOverReadback]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "error-state-readback"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launchArguments = []; app.launch(); openBackupSettings()
        try motionSample?("relaunch"); XCTAssertFalse(app.staticTexts["Saved health data couldn't be opened."].exists); snap(prefix + "-relaunch")
    }

    func testHealthBackupFileRecoveryPhotoFaultMissingLegacy() throws { try healthBackupPhotoFault("legacy", fault: "missing") }
    func testHealthBackupFileRecoveryPhotoFaultMissingEncrypted() throws { try healthBackupPhotoFault("encrypted", fault: "missing") }
    func testHealthBackupFileRecoveryPhotoFaultDamagedLegacy() throws { try healthBackupPhotoFault("legacy", fault: "damaged") }
    func testHealthBackupFileRecoveryPhotoFaultDamagedEncrypted() throws { try healthBackupPhotoFault("encrypted", fault: "damaged") }
    func testHealthBackupFileRecoveryPhotoFaultMissingEncryptedDark() throws { try healthBackupPhotoFault("encrypted", fault: "missing") }
    func testHealthBackupFileRecoveryPhotoFaultMissingEncryptedLargest() throws { try healthBackupPhotoFault("encrypted", fault: "missing") }
    private func healthBackupPhotoFault(_ kind: String, fault: String) throws {
        executionTimeAllowance = name.contains("Largest") ? 900 : 600
        let base = "Lumen-backup-health-matrix-two-" + kind
        let prefix = "health-photo-fault-" + fault + "-" + kind
        do {
            openBackupSettings(); try chooseBackupFixture(base)
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
        }
        let link = app.buttons["reviewBackupHealthRecovery"].firstMatch
        reveal(link); link.tap()
        let filename = app.staticTexts["recoveryFileName"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10)); XCTAssertEqual(filename.label, base + (kind == "encrypted" ? ".lumenbackup" : ".json"))
        snap(prefix + "-source"); Thread.sleep(forTimeInterval: 3)
        for domain in ["water", "goals"] {
            let review = app.buttons["reviewFile-" + domain].firstMatch
            reveal(review); XCTAssertTrue(review.exists)
            XCTAssertFalse(app.switches["recoverFile-" + domain].exists); snap(prefix + "-healthy-" + domain)
        }
        let domains = ["meals", "workouts"]
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "meals"); XCTAssertEqual(choice.value as? String, "0"); snap(prefix + "-off-" + domain)
            let review = app.buttons["reviewFile-" + domain].firstMatch; reveal(review); review.tap()
            if domain == "meals" {
                for index in 0..<2 {
                    let record = app.buttons["recoveryRecord-" + String(index)].firstMatch
                    XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
                    let field = app.descendants(matching: .any).matching(identifier: "recoveryField-0").firstMatch
                    XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(field.label.contains(index == 0 ? "Lunch" : "Snack"))
                    snap(prefix + "-meal-" + String(index))
                    let child = app.buttons["recoveryChild-0"].firstMatch
                    do {
                        reveal(child); XCTAssertTrue(child.exists); child.tap()
                        if index == 0 {
                            let failure = app.staticTexts["This photo changed or couldn't be opened. Return to choose the file again."].firstMatch
                            XCTAssertTrue(failure.waitForExistence(timeout: 10))
                            XCTAssertFalse(app.images["recoveryMealPhoto"].exists)
                        } else { XCTAssertTrue(app.images["recoveryMealPhoto"].waitForExistence(timeout: 10)) }
                        snap(prefix + "-photo-" + String(index)); app.navigationBars.buttons.element(boundBy: 0).tap()
                    }
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                }
            } else {
                XCTAssertTrue(app.staticTexts["No records in this file."].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["recoveryRecord-0"].exists); snap(prefix + "-empty-" + domain)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        let confirm = app.buttons["confirmFileRecovery"].firstMatch; reveal(confirm); XCTAssertFalse(confirm.isEnabled)
        for domain in domains { nativeSwitch("recoverFile-" + domain, enabled: true, towardsTop: domain == "meals") }
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); snap(prefix + "-selected"); confirm.tap()
        let alert = app.alerts["Replace selected data?"]; XCTAssertTrue(alert.waitForExistence(timeout: 5))
        snap(prefix + "-confirmation"); alert.buttons["Not now"].tap()
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "meals"); XCTAssertEqual(choice.value as? String, "1")
        }
        snap(prefix + "-not-now"); Thread.sleep(forTimeInterval: 3)
        reveal(confirm); confirm.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
        let failure = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryError").firstMatch
        for attempt in 1...2 {
            // No reveal, swipe or search action before the first error frame:
            // the app itself must bring the genuine failure into view.
            XCTAssertTrue(failure.waitForExistence(timeout: 30))
            XCTAssertTrue(failure.isHittable)
            let usableTop = app.navigationBars["Review recovery"].frame.maxY
            XCTAssertGreaterThanOrEqual(failure.frame.minY, usableTop)
            if !name.contains("Largest") { XCTAssertLessThanOrEqual(failure.frame.maxY, app.frame.maxY - 20) }
            else { XCTAssertLessThan(failure.frame.minY, app.frame.maxY - 160) }
            XCTAssertTrue(failure.label.contains("Recovery couldn't finish"))
            XCTAssertTrue(failure.label.contains("Your current files haven't been replaced."))
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "fileHealthRecovered").firstMatch.exists)
            snap(prefix + (attempt == 1 ? "-failed" : "-failed-repeat"))
            Thread.sleep(forTimeInterval: 3)
            if name.contains("Largest") {
                let consequences = app.staticTexts["Replaced files stay in a private copy on this iPhone. For meal recovery, this includes any old photos."].firstMatch
                let pendingHealth = app.staticTexts["Recovered entries won't be added to Apple Health. Earlier pending Health saves won't restart; pending removals can finish."].firstMatch
                // Native Form virtualizes distant rows at accessibility sizes.
                // Cover each actual row before revealing the next one, rather
                // than requiring both ends of the whole section to exist.
                for (row, element) in [consequences, pendingHealth, failure, confirm].enumerated() {
                    reveal(element, towardsTop: row == 0)
                    let captureBottom: CGFloat = row == 3 ? 20 : 40
                    if row == 3 { print("Recovery retry capture input", element.frame, "app", app.frame, "bottomInset", captureBottom) }
                    captureIdentifierText(element, prefix: prefix + "-failure-content-" + String(attempt) + "-row" + String(row), bottomInset: captureBottom)
                    if row == 3 { print("Recovery retry capture completed", element.frame, "app", app.frame, "bottomInset", captureBottom) }
                }
            }
            if attempt == 1 {
                reveal(confirm); confirm.tap()
                XCTAssertTrue(alert.waitForExistence(timeout: 5))
                alert.buttons["Recover"].tap()
            }
        }
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "meals"); XCTAssertEqual(choice.value as? String, "1")
        }
        let omission = app.switches["Recover without meal photos"].firstMatch
        reveal(omission, towardsTop: true); XCTAssertEqual(omission.value as? String, "0")
        nativeSwitch("Recover without meal photos", enabled: true)
        snap(prefix + "-explicit-omission")
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Not now"].tap()
        reveal(omission, towardsTop: true); XCTAssertEqual(omission.value as? String, "1")
        snap(prefix + "-omission-not-now"); Thread.sleep(forTimeInterval: 3)
        reveal(confirm); confirm.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
        let busy = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryBusy").firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 10))
        XCTAssertFalse(failure.exists, "A fresh recovery attempt clears the prior failure")
        for value in ["held-3", "observed-3"] {
            let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 15), .completed); snap(prefix + "-" + value)
        }
        let success = app.descendants(matching: .any).matching(identifier: "fileHealthRecovered").firstMatch
        reveal(success, towardsTop: true); XCTAssertTrue(success.waitForExistence(timeout: 30))
        XCTAssertFalse(failure.exists, "Success must not retain a stale failure")
        snap(prefix + "-success")
        let observedSuccess = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "success-observed"), object: success)
        XCTAssertEqual(XCTWaiter.wait(for: [observedSuccess], timeout: 35), .completed,
                       "The host must audit the actual open review before Back closes its source")
        app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Backup & restore"].waitForExistence(timeout: 5))
        snap(prefix + "-parent"); Thread.sleep(forTimeInterval: 4)
        let readback: [String: Any] = ["scope": "selected-file-extracted-photo-fault-omission", "format": kind, "domains": domains, "initialChoicesOff": true, "fault": fault, "mealsReviewed": 2, "photosReviewed": 1, "unavailablePhotoReviewed": true, "failedWithoutOmission": true, "repeatedFailureWithoutTestScroll": true, "explicitPhotoOmission": true, "healthyWaterGoalsChoicesAbsent": true, "successObserved": true]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "photo-fault-readback"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launchArguments = []; app.launch(); openBackupSettings()
        XCTAssertFalse(app.staticTexts["Saved health data couldn't be opened."].exists); snap(prefix + "-relaunch")
    }

    func testHealthBackupFileRecoveryPhotoMatrixZeroLegacy() throws { try healthBackupPhotoMatrix("legacy", mode: "zero") }
    func testHealthBackupFileRecoveryPhotoMatrixZeroEncrypted() throws { try healthBackupPhotoMatrix("encrypted", mode: "zero") }
    func testHealthBackupFileRecoveryPhotoMatrixZeroReadable() throws { try healthBackupPhotoMatrix("readable", mode: "zero") }
    func testHealthBackupFileRecoveryPhotoMatrixTwoLegacy() throws { try healthBackupPhotoMatrix("legacy", mode: "two") }
    func testHealthBackupFileRecoveryPhotoMatrixTwoEncrypted() throws { try healthBackupPhotoMatrix("encrypted", mode: "two") }
    func testHealthBackupFileRecoveryPhotoMatrixTwoReadable() throws { try healthBackupPhotoMatrix("readable", mode: "two") }
    private func healthBackupPhotoMatrix(_ kind: String, mode: String) throws {
        executionTimeAllowance = 420
        let base = kind == "readable" ? "Lumen-readable-health-matrix-" + mode : "Lumen-backup-health-matrix-" + mode + "-" + kind
        let prefix = "health-matrix-" + mode + "-" + kind
        if kind == "readable" { openReadableRecovery(); try chooseReadableFixture(base); waitForReadableReview() }
        else {
            openBackupSettings(); try chooseBackupFixture(base)
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
        }
        let link = app.buttons[kind == "readable" ? "reviewReadableHealthRecovery" : "reviewBackupHealthRecovery"].firstMatch
        reveal(link); link.tap()
        let filename = app.staticTexts["recoveryFileName"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10)); XCTAssertEqual(filename.label, base + (kind == "encrypted" ? ".lumenbackup" : ".json"))
        snap(prefix + "-source"); Thread.sleep(forTimeInterval: 3)
        for domain in ["water", "goals"] {
            let review = app.buttons["reviewFile-" + domain].firstMatch
            reveal(review); XCTAssertTrue(review.exists)
            XCTAssertFalse(app.switches["recoverFile-" + domain].exists); snap(prefix + "-healthy-" + domain)
        }
        let domains = ["meals", "workouts"]
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "meals"); XCTAssertEqual(choice.value as? String, "0"); snap(prefix + "-off-" + domain)
            let review = app.buttons["reviewFile-" + domain].firstMatch; reveal(review); review.tap()
            if domain == "meals" {
                for index in 0..<2 {
                    let record = app.buttons["recoveryRecord-" + String(index)].firstMatch
                    XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
                    let field = app.descendants(matching: .any).matching(identifier: "recoveryField-0").firstMatch
                    XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(field.label.contains(index == 0 ? "Lunch" : "Snack"))
                    snap(prefix + "-meal-" + String(index))
                    let child = app.buttons["recoveryChild-0"].firstMatch
                    if mode == "two" && kind != "readable" {
                        reveal(child); XCTAssertTrue(child.exists); child.tap()
                        XCTAssertTrue(app.images["recoveryMealPhoto"].waitForExistence(timeout: 10))
                        snap(prefix + "-photo-" + String(index)); app.navigationBars.buttons.element(boundBy: 0).tap()
                    } else { XCTAssertFalse(child.exists) }
                    app.navigationBars.buttons.element(boundBy: 0).tap()
                }
            } else {
                XCTAssertTrue(app.staticTexts["No records in this file."].waitForExistence(timeout: 10))
                XCTAssertFalse(app.buttons["recoveryRecord-0"].exists); snap(prefix + "-empty-" + domain)
            }
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        let confirm = app.buttons["confirmFileRecovery"].firstMatch; reveal(confirm); XCTAssertFalse(confirm.isEnabled)
        for domain in domains { nativeSwitch("recoverFile-" + domain, enabled: true, towardsTop: domain == "meals") }
        if kind == "readable" && mode == "two" {
            reveal(confirm); XCTAssertFalse(confirm.isEnabled)
            nativeSwitch("Recover without meal photos", enabled: true, towardsTop: true)
        }
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); snap(prefix + "-selected"); confirm.tap()
        let alert = app.alerts["Replace selected data?"]; XCTAssertTrue(alert.waitForExistence(timeout: 5))
        snap(prefix + "-confirmation"); alert.buttons["Not now"].tap()
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "meals"); XCTAssertEqual(choice.value as? String, "1")
        }
        snap(prefix + "-not-now"); Thread.sleep(forTimeInterval: 3)
        reveal(confirm); confirm.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
        let busy = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryBusy").firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 10))
        for value in ["held-1", "observed-1"] {
            let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 15), .completed); snap(prefix + "-" + value)
        }
        let success = app.descendants(matching: .any).matching(identifier: "fileHealthRecovered").firstMatch
        reveal(success, towardsTop: true); XCTAssertTrue(success.waitForExistence(timeout: 30)); snap(prefix + "-success")
        app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars[kind == "readable" ? "Recover export" : "Backup & restore"].waitForExistence(timeout: 5))
        snap(prefix + "-parent"); Thread.sleep(forTimeInterval: 4)
        let readback: [String: Any] = ["scope": "selected-file-photo-matrix", "format": kind, "domains": domains, "initialChoicesOff": true, "photoMode": mode, "mealsReviewed": 2, "photosReviewed": mode == "two" && kind != "readable" ? 2 : 0, "explicitPhotoOmission": mode == "two" && kind == "readable", "healthyWaterGoalsChoicesAbsent": true, "successObserved": true]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "photo-matrix-readback"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launchArguments = []; app.launch(); openBackupSettings()
        XCTAssertFalse(app.staticTexts["Saved health data couldn't be opened."].exists); snap(prefix + "-relaunch")
    }
    func testHealthBackupHealthyMergeLegacy() throws { try healthBackupHealthyMerge("legacy") }
    func testHealthBackupHealthyMergeEncrypted() throws { try healthBackupHealthyMerge("encrypted") }
    func testHealthBackupHealthyMergeReadable() throws { try healthBackupHealthyMerge("readable") }
    func testHealthBackupHealthyMergePreferencesLegacy() throws { try healthBackupHealthyMerge("legacy", preferences: true) }
    func testHealthBackupHealthyMergePreferencesEncrypted() throws { try healthBackupHealthyMerge("encrypted", preferences: true) }
    func testHealthBackupHealthyMergePreferencesReadable() throws { try healthBackupHealthyMerge("readable", preferences: true) }
    private func healthBackupHealthyMerge(_ kind: String, preferences: Bool = false) throws {
        executionTimeAllowance = 420
        let base = kind == "readable" ? "Lumen-readable-health-multi" : "Lumen-backup-health-multi-" + kind
        let prefix = "health-merge-" + kind
        if kind == "readable" { openReadableRecovery() } else { openBackupSettings() }
        for attempt in ["first", "repeat"] {
            if kind == "readable" {
                try chooseReadableFixture(base); waitForReadableReview()
                XCTAssertFalse(app.buttons["reviewReadableHealthRecovery"].exists)
                for key in ["meals", "workouts", "water"] {
                    let choice = app.switches["recoverReadable-" + key].firstMatch
                    reveal(choice); XCTAssertEqual(choice.value as? String, "1")
                }
                for key in ["profile", "goals", "habits", "personal-context"] {
                    let choice = app.switches["recoverReadable-" + key].firstMatch
                    reveal(choice); XCTAssertEqual(choice.value as? String, "0")
                    if preferences { nativeSwitch("recoverReadable-" + key, enabled: true) }
                }
                snap(prefix + "-" + attempt + "-preview"); Thread.sleep(forTimeInterval: 4)
                let add = app.buttons["recoverReadableData"].firstMatch; reveal(add); add.tap()
                let alert = app.alerts["Add selected data?"]; XCTAssertTrue(alert.waitForExistence(timeout: 5))
                snap(prefix + "-" + attempt + "-confirm"); alert.buttons["Keep reviewing"].tap()
                add.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Add data"].tap()
                let status = app.staticTexts["readableStatus"].firstMatch
                XCTAssertTrue(status.waitForExistence(timeout: 60)); reveal(status); XCTAssertTrue(status.label.contains("Selected data is saved"))
            } else {
                try chooseBackupFixture(base)
                if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
                _ = backupPreview(); XCTAssertFalse(app.buttons["reviewBackupHealthRecovery"].exists)
                let choice = app.switches["Restore profile & preferences"].firstMatch
                reveal(choice); XCTAssertEqual(choice.value as? String, "0")
                if preferences { nativeSwitch("Restore profile & preferences", enabled: true) }
                snap(prefix + "-" + attempt + "-preview"); Thread.sleep(forTimeInterval: 4)
                let restore = app.buttons["restoreBackup"].firstMatch; reveal(restore); restore.tap()
                let alert = app.alerts["Restore missing records?"]; XCTAssertTrue(alert.waitForExistence(timeout: 5))
                snap(prefix + "-" + attempt + "-confirm"); alert.buttons["Cancel"].tap()
                restore.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Restore records"].tap()
                XCTAssertTrue(app.staticTexts["backupRestored"].waitForExistence(timeout: 60))
            }
            snap(prefix + "-" + attempt + "-complete"); Thread.sleep(forTimeInterval: 5)
            if kind == "readable" && attempt == "first" {
                tap("finishReadableRecovery")
                let recover = app.buttons["readableRecovery"].firstMatch; reveal(recover); recover.tap()
            }
        }
        let readback: [String: Any] = ["scope": preferences ? "ordinary-healthy-preferences-repeat" : "ordinary-healthy-merge-repeat", "format": kind, "attempts": 2, "preferencesOff": !preferences, "confirmationCancelledBeforeCommit": true]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "healthy-merge-readback"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launchArguments = []; app.launch(); openBackupSettings()
        XCTAssertFalse(app.staticTexts["Saved health data couldn't be opened."].exists); snap(prefix + "-relaunch")
    }
    func testHealthBackupFileRecoveryAllCommitEncrypted() throws { try healthBackupMultipleDomains("encrypted") }
    func testHealthBackupFileRecoveryAllCommitReadable() throws { try healthBackupMultipleDomains("readable") }
    private func healthBackupMultipleDomains(_ kind: String) throws {
        executionTimeAllowance = 420
        let base = kind == "readable" ? "Lumen-readable-health-multi" : "Lumen-backup-health-multi-" + kind
        let prefix = "health-multi-" + kind
        if kind == "readable" { openReadableRecovery(); try chooseReadableFixture(base); waitForReadableReview() }
        else {
            openBackupSettings(); try chooseBackupFixture(base)
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
        }
        let link = app.buttons[kind == "readable" ? "reviewReadableHealthRecovery" : "reviewBackupHealthRecovery"].firstMatch
        reveal(link); XCTAssertTrue(link.waitForExistence(timeout: 10)); link.tap()
        let filename = app.staticTexts["recoveryFileName"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10)); XCTAssertEqual(filename.label, base + (kind == "encrypted" ? ".lumenbackup" : ".json"))
        snap(prefix + "-source"); Thread.sleep(forTimeInterval: 3)
        let domains = ["water", "meals", "workouts", "goals"]
        let confirm = app.buttons["confirmFileRecovery"].firstMatch
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice); XCTAssertTrue(choice.exists); XCTAssertEqual(choice.value as? String, "0")
            snap(prefix + "-off-" + domain)
        }
        reveal(confirm); XCTAssertFalse(confirm.isEnabled)
        for (domain, expected) in [("water", "246 mL"), ("meals", "Lunch"), ("workouts", "Recovered walk"), ("goals", "321 steps")] {
            let review = app.buttons["reviewFile-" + domain].firstMatch
            reveal(review, towardsTop: domain == "water"); review.tap()
            let record = app.buttons["recoveryRecord-0"].firstMatch
            XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
            let field = app.descendants(matching: .any).matching(identifier: "recoveryField-0").firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 5)); XCTAssertTrue(field.label.contains(expected), field.label)
            snap(prefix + "-record-" + domain)
            if domain == "meals" && kind != "readable" {
                let photo = app.buttons["recoveryChild-1"].firstMatch
                reveal(photo); XCTAssertTrue(photo.exists); photo.tap()
                XCTAssertTrue(app.images["recoveryMealPhoto"].waitForExistence(timeout: 10))
                snap(prefix + "-shared-photo"); app.navigationBars.buttons.element(boundBy: 0).tap()
            }
            app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        for domain in domains { nativeSwitch("recoverFile-" + domain, enabled: true, towardsTop: domain == "water") }
        if kind == "readable" {
            reveal(confirm); XCTAssertFalse(confirm.isEnabled)
            nativeSwitch("Recover without meal photos", enabled: true, towardsTop: true)
        }
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); snap(prefix + "-selected"); confirm.tap()
        let alert = app.alerts["Replace selected data?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap(prefix + "-confirmation"); alert.buttons["Not now"].tap()
        for domain in domains {
            let choice = app.switches["recoverFile-" + domain].firstMatch
            reveal(choice, towardsTop: domain == "water"); XCTAssertEqual(choice.value as? String, "1")
        }
        snap(prefix + "-not-now"); Thread.sleep(forTimeInterval: 3)
        reveal(confirm); confirm.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
        let busy = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryBusy").firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 10))
        for value in ["held-1", "observed-1"] {
            let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 15), .completed); snap(prefix + "-" + value)
        }
        let success = app.descendants(matching: .any).matching(identifier: "fileHealthRecovered").firstMatch
        reveal(success, towardsTop: true); XCTAssertTrue(success.waitForExistence(timeout: 30)); snap(prefix + "-success")
        app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars[kind == "readable" ? "Recover export" : "Backup & restore"].waitForExistence(timeout: 5)); snap(prefix + "-parent")
        Thread.sleep(forTimeInterval: 4)
        let readback: [String: Any] = ["scope": "selected-file-four-domain-recovery", "format": kind, "domains": domains,
            "initialChoicesOff": true, "notNowPreservedSelection": true, "successObserved": true, "sharedPhotoReviewed": kind != "readable", "explicitPhotoOmission": kind == "readable"]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "four-domain-recovery-readback"; attachment.lifetime = .keepAlways; add(attachment)
        app.terminate(); app.launchArguments = []; app.launch(); openBackupSettings()
        XCTAssertFalse(app.staticTexts["Saved health data couldn't be opened."].exists); snap(prefix + "-relaunch")
    }
    private func healthBackupFileRecovery(_ kind: String) throws {
        let leaving = healthFileRecoveryLeavesReview
        let commitLifetime = name.contains("RecoveryCommit")
        executionTimeAllowance = leaving || commitLifetime ? 600 : 240
        if kind == "readable" {
            openReadableRecovery(); try chooseReadableFixture("Lumen-readable-health-small"); waitForReadableReview()
        } else {
            openBackupSettings(); try chooseBackupFixture("Lumen-backup-health-" + kind + "-small")
            if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
        }
        let link = app.buttons[kind == "readable" ? "reviewReadableHealthRecovery" : "reviewBackupHealthRecovery"].firstMatch
        reveal(link); XCTAssertTrue(link.waitForExistence(timeout: 10)); link.tap()
        let filename = app.staticTexts["recoveryFileName"].firstMatch
        XCTAssertTrue(filename.waitForExistence(timeout: 10))
        XCTAssertEqual(filename.label, kind == "readable" ? "Lumen-readable-health-small.json" : "Lumen-backup-health-" + kind + "-small." + (kind == "encrypted" ? "lumenbackup" : "json"))
        snap("health-file-" + kind + "-source")
        let choice = app.switches["recoverFile-water"].firstMatch
        reveal(choice); XCTAssertEqual(choice.value as? String, "0"); snap("health-file-" + kind + "-off")
        let review = app.buttons["reviewFile-water"].firstMatch
        reveal(review, towardsTop: true); review.tap()
        let record = app.buttons["recoveryRecord-0"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 10)); record.tap()
        let amount = app.descendants(matching: .any).matching(identifier: "recoveryField-0").firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 5)); XCTAssertTrue(amount.label.contains("246 mL"))
        snap("health-file-" + kind + "-record")
        app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(choice); nativeSwitch("recoverFile-water", enabled: true); XCTAssertEqual(choice.value as? String, "1")
        snap("health-file-" + kind + "-on")
        let confirm = app.buttons["confirmFileRecovery"].firstMatch
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); confirm.tap()
        let alert = app.alerts["Replace selected data?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap("health-file-" + kind + "-confirmation")
        alert.buttons["Not now"].tap()
        reveal(choice, towardsTop: true); XCTAssertEqual(choice.value as? String, "1")
        reveal(confirm); confirm.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
        if commitLifetime {
            let busy = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryBusy").firstMatch
            XCTAssertTrue(busy.waitForExistence(timeout: 10))
            for value in ["held-1", "observed-1"] {
                let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: busy)
                XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 15), .completed)
                snap("health-commit-" + kind + (value == "held-1" ? "-held" : "-observed"))
            }
        } else if name.contains("Cancel") || leaving {
            let busy = app.descendants(matching: .any).matching(identifier: "fileHealthRecoveryBusy").firstMatch
            XCTAssertTrue(busy.waitForExistence(timeout: 5))
            let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "held-1"), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 10), .completed)
            let cancel = app.buttons["cancelFileRecovery"].firstMatch
            reveal(cancel); XCTAssertTrue(cancel.isHittable); snap("health-file-" + kind + "-cancel-held")
            let observed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "observed-1"), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [observed], timeout: 10), .completed)
            if leaving {
                app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
                XCTAssertTrue(app.navigationBars[kind == "readable" ? "Recover export" : "Backup & restore"].waitForExistence(timeout: 3), "Back must return to the actual import screen")
                let choose = app.buttons[kind == "readable" ? "chooseReadableExport" : "chooseBackup"].firstMatch
                reveal(choose); XCTAssertTrue(choose.isEnabled)
                snap("health-file-" + kind + "-back-import-screen")
                if kind == "readable" {
                    try chooseReadableFixture("Lumen-readable-health-small"); waitForReadableReview()
                } else {
                    try chooseBackupFixture("Lumen-backup-health-" + kind + "-small")
                    if kind == "encrypted" { unlockBackup(value: "Synthetic backup passphrase 42") }
                    XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "backupPreviewKind").firstMatch.waitForExistence(timeout: 30))
                }
                reveal(link); link.tap(); XCTAssertTrue(filename.waitForExistence(timeout: 10))
                reveal(choice); XCTAssertEqual(choice.value as? String, "0")
                reveal(confirm); XCTAssertFalse(confirm.isEnabled)
                snap("health-file-" + kind + "-back-reselected-off")
                nativeSwitch("recoverFile-water", enabled: true, towardsTop: true)
            } else {
                cancel.tap()
                XCTAssertTrue(confirm.waitForExistence(timeout: 3), "Cancel must reach held selected-file transaction preparation")
                reveal(choice, towardsTop: true); XCTAssertEqual(choice.value as? String, "1")
                snap("health-file-" + kind + "-cancel-retained-selection")
            }
            reveal(confirm); XCTAssertTrue(confirm.isEnabled); confirm.tap()
            XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
            let retry = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "held-2"), object: busy)
            XCTAssertEqual(XCTWaiter.wait(for: [retry], timeout: 10), .completed)
            reveal(cancel); snap("health-file-" + kind + "-retry-held")
        }
        let success = app.descendants(matching: .any).matching(identifier: "fileHealthRecovered").firstMatch
        reveal(success, towardsTop: true); XCTAssertTrue(success.waitForExistence(timeout: 30))
        snap("health-file-" + kind + "-success")
        if commitLifetime {
            app.navigationBars["Review recovery"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars[kind == "readable" ? "Recover export" : "Backup & restore"].waitForExistence(timeout: 5))
            let choose = app.buttons[kind == "readable" ? "chooseReadableExport" : "chooseBackup"].firstMatch
            reveal(choose, towardsTop: true); XCTAssertTrue(choose.exists && choose.isEnabled); XCTAssertFalse(link.exists)
            snap("health-commit-" + kind + "-final-parent")
            let late = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in app.alerts.firstMatch.exists || link.exists }, object: app)
            late.isInverted = true; XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 4), .completed)
            let readback: [String: Any] = ["scope": "selected-file-water-commit", "format": kind,
                "reviewedAmount": "246 mL", "initialChoiceOff": true, "notNowPreservesSelection": true,
                "actualSuccessObserved": true, "returnedToImportParent": true]
            let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
            attachment.name = "selected-file-commit-readback"; attachment.lifetime = .keepAlways; add(attachment)
        }
        app.terminate(); app.launchArguments = []; app.launch()
        openBackupSettings()
        XCTAssertFalse(app.staticTexts["Saved health data couldn't be opened."].exists)
        snap("health-file-" + kind + "-relaunch")
    }
    func testHealthRecoveryScreen() throws { try healthRecoveryScreen() }
    func testDailyCacheRejectsLink() throws {
        executionTimeAllowance = 120
        let manage = app.buttons["manageDailyCache"].firstMatch
        reveal(manage); XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
        let issue = app.staticTexts["dailyCacheIssue"].firstMatch
        let expected = "Saved readings couldn't be checked safely. Nothing was replaced. Check saved readings to retry."
        func checkRejected() {
            XCTAssertTrue(issue.waitForExistence(timeout: 10)); XCTAssertEqual(issue.label, expected)
            let clear = app.buttons["reviewClearDailyCache"].firstMatch
            reveal(clear); XCTAssertTrue(clear.exists); XCTAssertFalse(clear.isEnabled)
            XCTAssertFalse(app.staticTexts["dailyCacheFileState"].exists)
            XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "dailyCacheSaved").firstMatch.exists)
        }
        checkRejected(); snap("daily-cache-link-initial"); Thread.sleep(forTimeInterval: 3)
        for index in 1...2 {
            let retry = app.buttons["inspectDailyCache"].firstMatch
            reveal(retry); XCTAssertTrue(retry.isEnabled); retry.tap()
            checkRejected(); snap("daily-cache-link-retry-" + String(index)); Thread.sleep(forTimeInterval: 3)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(manage.waitForExistence(timeout: 10)); snap("daily-cache-link-parent")
        Thread.sleep(forTimeInterval: 4)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "dailyCacheSaved").firstMatch.exists)
        let readback: [String: Any] = ["scope": "native-link-cache-rejection", "issue": expected, "retries": 2,
                                     "clearDisabled": true, "noSavedState": true, "finalRecoveryParentVisible": manage.exists]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "daily-cache-link-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDailyCacheClearCorrupt() throws { try dailyCacheClear(kind: "corrupt") }
    func testDailyCacheClearDirectory() throws { try dailyCacheClear(kind: "directory") }
    func testDailyCacheClearMissing() throws { try dailyCacheClear(kind: "missing") }
    func testDailyCacheClearHealthy() throws { try dailyCacheClear(kind: "healthy") }
    private func dailyCacheClear(kind: String) throws {
        executionTimeAllowance = 180
        let observedFixture = kind != "corrupt"
        let prefix = observedFixture ? "daily-cache-" + kind : "daily-cache"
        func capture(_ step: String) { snap(prefix + step) }
        let manage = app.buttons["manageDailyCache"].firstMatch
        reveal(manage); XCTAssertTrue(manage.waitForExistence(timeout: 10)); XCTAssertTrue(manage.isEnabled); manage.tap()
        let state = app.staticTexts["dailyCacheFileState"].firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 10)); XCTAssertEqual(state.label, kind == "missing" ? "No saved snapshot" : kind == "healthy" ? "Saved snapshot opens" : "Saved snapshot couldn't be opened")
        let initialLabel = state.label
        snap(observedFixture ? prefix + "-initial" : "daily-cache-corrupt-initial")
        if observedFixture { Thread.sleep(forTimeInterval: 3) } // Host captures the real pre-action tree.
        let review = app.buttons["reviewClearDailyCache"].firstMatch; reveal(review); XCTAssertTrue(review.isEnabled); review.tap()
        let consequence = app.staticTexts["dailyCacheConsequence"].firstMatch
        XCTAssertTrue(consequence.waitForExistence(timeout: 10))
        XCTAssertEqual(consequence.label, "The saved daily snapshot will become unknown. This doesn't delete local logs, imported days or sleep history.")
        let consequenceLabel = consequence.label
        capture("-clear-review")
        let confirm = app.buttons["confirmClearDailyCache"].firstMatch
        reveal(confirm); confirm.tap()
        let alert = app.alerts["Clear saved readings?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); capture("-clear-confirmation")
        alert.buttons["Not now"].tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["dailyCacheSaved"].exists)
        capture("-clear-not-now")
        if observedFixture { Thread.sleep(forTimeInterval: 3) } // Host checks dismissal before confirmation.
        confirm.tap(); XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Clear readings"].tap()
        let progress = app.descendants(matching: .any).matching(identifier: "dailyCacheProgress").firstMatch
        XCTAssertTrue(progress.waitForExistence(timeout: 5))
        let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "held-1"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 10), .completed)
        let heldValue = progress.value as? String ?? ""
        capture("-clear-held")
        let saved = app.descendants(matching: .any).matching(identifier: "dailyCacheSaved").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 35)); XCTAssertEqual(saved.label, "Saved snapshot cleared")
        let savedLabel = saved.label
        capture("-clear-saved")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["manageDailyCache"].waitForExistence(timeout: 10)); capture("-clear-parent")
        let idleStart = Date()
        let lateBusy = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: progress)
        lateBusy.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [lateBusy], timeout: 4), .completed)
        let readback: [String: Any] = ["scope": "native-" + kind + "-cache-explicit-clear", "initialState": initialLabel,
            "consequence": consequenceLabel, "notNowReturnedToReview": true, "heldValue": heldValue,
            "savedLabel": savedLabel, "finalRecoveryParentVisible": app.buttons["manageDailyCache"].exists,
            "idleAfterParentSeconds": Date().timeIntervalSince(idleStart)]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "daily-cache-clear-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDailyCacheClearCorruptCancel() throws { try dailyCacheInterruptedClear(leaving: false) }
    func testDailyCacheRebuildHealthKit() throws { try dailyCacheRebuildHealthKit(recorded: false) }
    func testDailyCacheRebuildHealthKitRecorded() throws { try dailyCacheRebuildHealthKit(recorded: true) }
    func testDailyCacheRebuildHealthKitRecordedLargestDetails() throws { try dailyCacheRebuildHealthKit(recorded: true) }
    func testDailyCacheRebuildHealthKitRecordedNormalDetails() throws { try dailyCacheRebuildHealthKit(recorded: true) }
    func testDailyCacheRebuildHealthKitRecordedDarkDetails() throws { try dailyCacheRebuildHealthKit(recorded: true) }
    func testDailyCacheRebuildHealthKitRecordedMainNormalDetails() throws { try dailyCacheRebuildHealthKit(recorded: true) }
    func testDailyCacheRebuildHealthKitRecordedMainDarkDetails() throws { try dailyCacheRebuildHealthKit(recorded: true) }
    func testDailyCacheRebuildHealthKitRecordedMainLargestDetails() throws { try dailyCacheRebuildHealthKit(recorded: true) }
    private func dailyCacheRebuildHealthKit(recorded: Bool) throws {
        let fullDetails = name.contains("Details")
        let largestDetails = name.contains("LargestDetails")
        let mainPhone = name.contains("Main")
        executionTimeAllowance = fullDetails ? 1800 : 360
        if fullDetails {
            XCTAssertEqual(app.frame.width, mainPhone ? 402 : 375)
            XCTAssertEqual(app.frame.height, mainPhone ? 874 : 667)
        }
        let manage = app.buttons["manageDailyCache"].firstMatch
        let selectAll = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Select All'")).firstMatch
        if selectAll.waitForExistence(timeout: 6) { selectAll.tap() }
        for step in 0..<4 {
            if app.navigationBars["Recover health data"].exists && app.navigationBars["Recover health data"].isHittable { break }
            let range = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'All Recorded Data and Future Data'")).firstMatch
            if range.exists && range.isHittable { range.tap() }
            let actions = app.buttons.matching(NSPredicate(format: "identifier == 'UIA.Health.Allow.Button' OR label == 'Allow' OR label == 'Continue'"))
            func visiblePermissionAction() -> XCUIElement? {
                actions.allElementsBoundByIndex.first { $0.exists && $0.isHittable && $0.isEnabled }
            }
            for _ in 0..<10 where visiblePermissionAction() == nil {
                // At accessibility sizes the historical-data option begins
                // offscreen. Select it when scrolling has actually revealed it.
                if range.exists && range.isHittable { range.tap() }
                if visiblePermissionAction() == nil { app.swipeUp(velocity: .slow) }
            }
            guard let approve = visiblePermissionAction() else {
                snap("daily-cache-health-permission-unavailable-" + String(step)); print(app.debugDescription)
                XCTFail("A visible enabled native Health permission action is required"); return
            }
            snap("daily-cache-health-permission-" + String(step)); approve.tap()
        }
        reveal(manage)
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        if recorded {
            let seed = app.buttons["checkHealthCopies"].firstMatch
            reveal(seed)
            let ready = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "sdk-seed-ready"), object: seed)
            XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 15), .completed)
        }
        reveal(manage, towardsTop: recorded); manage.tap()
        let state = app.staticTexts["dailyCacheFileState"].firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 10)); XCTAssertEqual(state.label, "Saved snapshot couldn't be opened")
        if fullDetails {
            captureIdentifierText(state, prefix: "daily-initial-state")
            let scope = app.staticTexts["dailyCacheBackupScope"].firstMatch
            reveal(scope); captureIdentifierText(scope, prefix: "daily-initial-backup-scope")
        }
        let query = app.buttons["checkDailyCacheHealth"].firstMatch
        reveal(query)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: query)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        snap("daily-cache-health-initial"); query.tap()
        let confirm = app.buttons["confirmRebuildDailyCache"].firstMatch
        var controlLabels: [String: String] = [:]
        let consequence = app.staticTexts["dailyCacheConsequence"].firstMatch
        reveal(consequence, towardsTop: true)
        XCTAssertEqual(consequence.label, "These Apple Health results will replace the saved daily snapshot.")
        snap("daily-cache-health-review")
        if fullDetails {
            captureIdentifierText(consequence, prefix: "daily-review-consequence")
            for identifier in ["dailyCacheRetainedConsequence", "dailyCacheReturnedCount", "dailyCacheNoDataCount", "dailyCacheFailedCount", "dailyCacheQueryFrom", "dailyCacheQueryThrough", "dailyCacheQueryScope"] {
                let item = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
                reveal(item); captureIdentifierText(item, prefix: "daily-review-" + identifier)
            }
            // Review the scrollable native confirmation before the lengthy
            // metric-detail pass, so capture problems fail at the first screen.
            reveal(confirm); confirm.tap()
            let alert = app.alerts["Replace saved readings?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            let title = alert.staticTexts["Replace saved readings?"].firstMatch
            let message = alert.staticTexts["This changes the saved daily snapshot only. Your records and settings stay."].firstMatch
            let scroll = alert.scrollViews.firstMatch
            XCTAssertTrue(scroll.exists)
            let viewport: () -> CGRect = {
                let frame = scroll.frame.intersection(alert.frame)
                let bottom = min(frame.maxY, min(alert.buttons["Rebuild"].frame.minY, alert.buttons["Not now"].frame.minY))
                return CGRect(x: frame.minX, y: frame.minY + 1, width: frame.width, height: bottom - frame.minY - 2)
            }
            controlLabels["confirmationTitle"] = title.label
            controlLabels["confirmationMessage"] = message.label
            captureIdentifierText(title, prefix: "daily-confirmation-title", contentGestures: true, visibleBounds: viewport)
            captureIdentifierText(message, prefix: "daily-confirmation-message", contentGestures: true, visibleBounds: viewport)
            for (label, prefix) in [("Rebuild", "daily-confirmation-rebuild"), ("Not now", "daily-confirmation-not-now")] {
                let button = alert.buttons[label]
                controlLabels[label == "Rebuild" ? "rebuildAction" : "notNowAction"] = button.label
                captureIdentifierText(button, prefix: prefix, bottomInset: 12)
            }
            snap("daily-cache-health-confirmation"); alert.buttons["Not now"].tap()
            reveal(confirm); XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            XCTAssertFalse(app.staticTexts["dailyCacheSaved"].exists)
            snap("daily-cache-health-not-now")
        }
        let readings = app.buttons["reviewDailyCacheReadings"].firstMatch
        reveal(readings, towardsTop: fullDetails); readings.tap()
        var values: [String: String] = [:]
        var details: [String: [String: String]] = [:]
        var valueHeights: [String: Double] = [:]
        let keys = ["steps", "activeEnergy", "restingEnergy", "exercise", "stand", "restingHR", "hrv", "heartRate",
                    "respiratoryRate", "spo2", "vo2max", "weight", "bodyFat", "calories", "protein", "carbs", "fat", "water"]
        for key in keys {
            let value = app.staticTexts["dailyCacheValue-" + key].firstMatch
            reveal(value); XCTAssertTrue(value.exists && value.isHittable)
            if fullDetails {
                let heading = app.staticTexts["dailyCacheHeading-" + key].firstMatch
                // Native pinned section headers begin at the navigation bar's
                // lower edge. Preserve full coverage without an extra inset.
                reveal(heading, towardsTop: true); captureIdentifierText(heading, prefix: "daily-detail-" + key + "-heading", topInset: 0)
                details[key, default: [:]]["Heading"] = heading.label
                reveal(value)
            }
            values[key] = value.label; snap("daily-cache-health-reading-" + key)
            if fullDetails {
                valueHeights[key] = value.frame.height
                captureIdentifierText(value, prefix: "daily-detail-" + key + "-value")
                var fields = ["Outcome", "Checked", "Start", "End"]
                if ["steps", "weight", "heartRate"].contains(key) { fields.insert("Source", at: 0); fields.append("Period") }
                for field in fields {
                    let identifier = "dailyCache" + field + "-" + key + (field == "Period" ? "-0" : "")
                    let item = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
                    reveal(item); XCTAssertTrue(item.exists && item.isHittable)
                    details[key, default: [:]][field] = item.label
                    // This form has no bottom toolbar. Its final AX label
                    // includes padding below the visible text; retain the
                    // complete frame inside the display with a 12pt margin.
                    captureIdentifierText(item, prefix: "daily-detail-" + key + "-" + field.lowercased(), bottomInset: 12)
                }
            }
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(confirm); XCTAssertTrue(confirm.waitForExistence(timeout: 10)); confirm.tap()
        let alert = app.alerts["Replace saved readings?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        if !fullDetails {
            snap("daily-cache-health-confirmation"); alert.buttons["Not now"].tap()
            reveal(confirm); XCTAssertTrue(confirm.waitForExistence(timeout: 5)); XCTAssertFalse(app.staticTexts["dailyCacheSaved"].exists)
            snap("daily-cache-health-not-now"); confirm.tap()
        }
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Rebuild"].tap()
        let progress = app.descendants(matching: .any).matching(identifier: "dailyCacheProgress").firstMatch
        let cancel = app.buttons["cancelDailyCache"].firstMatch
        reveal(fullDetails ? cancel : progress)
        let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "held-1"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 10), .completed)
        if fullDetails {
            controlLabels["heldProgress"] = progress.label; controlLabels["heldCancel"] = cancel.label
            // Both complete controls precede the host's existing release marker.
            // Keep the real worker's original finite30second barrier unchanged.
            captureIdentifierText(progress, through: cancel, prefix: "daily-held-progress-and-cancel", bottomInset: 12)
        }
        snap("daily-cache-health-held")
        let saved = app.descendants(matching: .any).matching(identifier: "dailyCacheSaved").firstMatch
        reveal(saved, towardsTop: true)
        XCTAssertTrue(saved.waitForExistence(timeout: 35)); XCTAssertEqual(saved.label, "Saved snapshot rebuilt")
        let savedLabel = saved.label; snap("daily-cache-health-saved")
        if fullDetails {
            let explanation = app.staticTexts["Local logs, imported days and sleep history aren't deleted."].firstMatch
            let unresolved = app.staticTexts["Water history couldn't be opened. Changes to this data are paused. Lumen hasn't replaced the saved data."].firstMatch
            let check = app.buttons["Check saved readings"].firstMatch
            for (key, item, prefix) in [("savedState", saved, "daily-saved-state"),
                                        ("savedExplanation", explanation, "daily-saved-explanation"),
                                        ("savedUnavailableDomain", unresolved, "daily-saved-unavailable-domain"),
                                        ("savedCheckAction", check, "daily-saved-check-action")] {
                reveal(item); XCTAssertTrue(item.exists && item.isHittable)
                controlLabels[key] = item.label
                captureIdentifierText(item, prefix: prefix, bottomInset: 12)
            }
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
        reveal(app.buttons["manageDailyCache"].firstMatch)
        XCTAssertTrue(app.buttons["manageDailyCache"].waitForExistence(timeout: 10)); snap("daily-cache-health-parent")
        let late = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: progress); late.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 4), .completed)
        if largestDetails { XCTAssertGreaterThan(valueHeights["steps"] ?? 0, 40, "Actual accessibility text must enlarge the native value") }
        let report: [String: Any] = ["scope": "actual-simulator-HealthKit-cache-rebuild", "reviewedValues": values,
            "fullDetails": details, "valueHeights": valueHeights, "largestDetailsRequested": largestDetails,
            "fullControlLabels": controlLabels,
            "fullDetailsRequested": fullDetails, "mainPhoneRequested": mainPhone,
            "requestedAppearance": largestDetails || name.contains("DarkDetails") ? "dark" : "light",
            "requestedContentSize": largestDetails ? "UICTContentSizeCategoryAccessibilityXXXL" : "UICTContentSizeCategoryL",
            "logicalWidth": app.frame.width, "logicalHeight": app.frame.height,
            "savedLabel": savedLabel, "notNowReturnedToReview": true, "heldValue": "held-1",
            "finalRecoveryParentVisible": app.buttons["manageDailyCache"].exists, "idleSeconds": 4]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "daily-cache-health-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDailyCacheHealthQueryCancel() throws { try dailyCacheInterruptedHealthQuery(leaving: false) }
    func testDailyCacheHealthQueryBack() throws { try dailyCacheInterruptedHealthQuery(leaving: true) }
    private func dailyCacheInterruptedHealthQuery(leaving: Bool) throws {
        executionTimeAllowance = 150
        func enter() {
            let manage = app.buttons["manageDailyCache"].firstMatch
            XCTAssertTrue(manage.waitForExistence(timeout: 12)); reveal(manage); manage.tap()
            let state = app.staticTexts["dailyCacheFileState"].firstMatch
            XCTAssertTrue(state.waitForExistence(timeout: 10)); XCTAssertEqual(state.label, "Saved snapshot couldn't be opened")
        }
        enter()
        let query = app.buttons["checkDailyCacheHealth"].firstMatch
        reveal(query)
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: query)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
        query.tap()
        let progress = app.descendants(matching: .any).matching(identifier: "dailyCacheProgress").firstMatch
        func phase(_ value: String) {
            let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: progress)
            XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 20), .completed)
        }
        phase("sdk-held-18"); snap("daily-query-held")
        phase("sdk-observed-18")
        let began = Date()
        if leaving { app.navigationBars.buttons.element(boundBy: 0).tap() }
        else { let cancel = app.buttons["cancelDailyCache"].firstMatch; reveal(cancel); cancel.tap() }
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 3), .completed)
        let elapsed = Date().timeIntervalSince(began)
        XCTAssertLessThan(elapsed, 3)
        if leaving { XCTAssertTrue(app.buttons["manageDailyCache"].waitForExistence(timeout: 5)) }
        else {
            let issue = app.staticTexts["dailyCacheIssue"].firstMatch
            XCTAssertTrue(issue.waitForExistence(timeout: 5)); XCTAssertEqual(issue.label, "Cancelled. Saved readings haven't changed.")
        }
        snap("daily-query-stopped")
        let confirm = app.buttons["confirmRebuildDailyCache"].firstMatch
        let late = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: confirm); late.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 4), .completed)
        snap("daily-query-late-idle")
        if leaving { enter() }
        reveal(query); XCTAssertTrue(query.isEnabled); query.tap()
        XCTAssertTrue(confirm.waitForExistence(timeout: 35)); snap("daily-query-fresh-review")
        let consequence = app.staticTexts["dailyCacheConsequence"].firstMatch
        reveal(consequence, towardsTop: true)
        XCTAssertEqual(consequence.label, "These Apple Health results will replace the saved daily snapshot.")
        let notNow = app.buttons["Not now"].firstMatch
        reveal(notNow); notNow.tap()
        XCTAssertTrue(query.waitForExistence(timeout: 10))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["manageDailyCache"].waitForExistence(timeout: 10)); snap("daily-query-final-parent")
        let finalLate = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: confirm); finalLate.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [finalLate], timeout: 4), .completed)
        let report: [String: Any] = ["action": leaving ? "Back" : "Cancel", "stoppedSeconds": elapsed,
            "firstResultNeverReviewed": true, "idleAfterLateCallbacksSeconds": 4, "freshReviewReached": true,
            "retryNotNow": true, "finalParent": app.buttons["manageDailyCache"].exists, "finalIdleSeconds": 4]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "daily-query-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testDailyCacheClearCorruptBack() throws { try dailyCacheInterruptedClear(leaving: true) }
    private func dailyCacheInterruptedClear(leaving: Bool) throws {
        executionTimeAllowance = 180
        func enter() {
            let manage = app.buttons["manageDailyCache"].firstMatch
            reveal(manage); XCTAssertTrue(manage.waitForExistence(timeout: 10)); manage.tap()
            let state = app.staticTexts["dailyCacheFileState"].firstMatch
            XCTAssertTrue(state.waitForExistence(timeout: 10)); XCTAssertEqual(state.label, "Saved snapshot couldn't be opened")
        }
        func start() {
            let review = app.buttons["reviewClearDailyCache"].firstMatch
            reveal(review); XCTAssertTrue(review.isEnabled); review.tap()
            let confirm = app.buttons["confirmClearDailyCache"].firstMatch
            XCTAssertTrue(confirm.waitForExistence(timeout: 10)); reveal(confirm); confirm.tap()
            let alert = app.alerts["Clear saved readings?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Clear readings"].tap()
        }
        let progress = app.descendants(matching: .any).matching(identifier: "dailyCacheProgress").firstMatch
        func waitPhase(_ phase: String) {
            XCTAssertTrue(progress.waitForExistence(timeout: 5))
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", phase), object: progress)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: 10), .completed)
        }
        enter(); start(); waitPhase("held-1"); snap("daily-cache-interrupt-held")
        // Host acknowledgement means the actual stage and original files have
        // been observed. It does not release the first worker's barrier.
        waitPhase("observed-1")
        let began = Date()
        if leaving { app.navigationBars.buttons.element(boundBy: 0).tap() }
        else { let cancel = app.buttons["cancelDailyCache"].firstMatch; reveal(cancel); XCTAssertTrue(cancel.isHittable); cancel.tap() }
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: progress)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 3), .completed)
        let stopSeconds = Date().timeIntervalSince(began)
        XCTAssertLessThan(stopSeconds, 3)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "dailyCacheSaved").firstMatch.exists)
        if leaving { XCTAssertTrue(app.buttons["manageDailyCache"].waitForExistence(timeout: 5)) }
        else {
            let issue = app.staticTexts["dailyCacheIssue"].firstMatch
            XCTAssertTrue(issue.waitForExistence(timeout: 5)); XCTAssertEqual(issue.label, "Cancelled. Saved readings haven't changed.")
        }
        snap("daily-cache-interrupt-stopped")
        let late = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: progress)
        late.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [late], timeout: 4), .completed)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "dailyCacheSaved").firstMatch.exists)
        snap("daily-cache-interrupt-idle")
        if leaving { enter() }
        start(); waitPhase("held-2"); snap("daily-cache-interrupt-retry-held")
        let saved = app.descendants(matching: .any).matching(identifier: "dailyCacheSaved").firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 35)); XCTAssertEqual(saved.label, "Saved snapshot cleared")
        let retrySavedLabel = saved.label
        snap("daily-cache-interrupt-retry-saved")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["manageDailyCache"].waitForExistence(timeout: 10)); snap("daily-cache-interrupt-final-parent")
        let finalLate = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: progress)
        finalLate.isInverted = true
        XCTAssertEqual(XCTWaiter.wait(for: [finalLate], timeout: 4), .completed)
        let readback: [String: Any] = ["scope": "native-corrupt-cache-interrupted-clear", "action": leaving ? "Back" : "Cancel",
            "hostObservedFirstStage": true, "stoppedSeconds": stopSeconds, "firstAttemptSaved": false,
            "idleBeforeRetrySeconds": 4, "retrySavedLabel": retrySavedLabel,
            "finalRecoveryParentVisible": app.buttons["manageDailyCache"].exists, "finalIdleSeconds": 4]
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: readback, options: [.prettyPrinted, .sortedKeys]), uniformTypeIdentifier: "public.json")
        attachment.name = "daily-cache-interrupt-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHealthRecoveryReadRetainedRecords() throws {
        executionTimeAllowance = 300
        let copy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(copy); XCTAssertTrue(copy.waitForExistence(timeout: 10)); copy.tap()
        let records = app.buttons["reviewHealth-water"].firstMatch
        reveal(records); XCTAssertTrue(records.isEnabled); records.tap()
        let loading = app.descendants(matching: .any).matching(identifier: "recoveryRecordsLoading").firstMatch
        func phase(_ value: String, object: XCUIElement, timeout: TimeInterval) {
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: object)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
        }
        XCTAssertTrue(loading.waitForExistence(timeout: 10)); phase("held-1", object: loading, timeout: 10)
        snap("retained-record-read-held")
        phase("observed-1", object: loading, timeout: 10)
        let backStarted = Date()
        app.navigationBars["Water history"].buttons.element(boundBy: 0).tap()
        let state = app.descendants(matching: .any).matching(identifier: "healthReadControlState").firstMatch
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            app.navigationBars["Review recovery"].exists && state.exists && state.value as? String == "closed-1"
        }, object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 3), .completed)
        let backElapsed = Date().timeIntervalSince(backStarted)
        XCTAssertLessThan(backElapsed, 3, "Back must close the held reader promptly without host release")
        snap("retained-record-read-cancelled-closed")
        reveal(records, towardsTop: true); records.tap()
        XCTAssertTrue(loading.waitForExistence(timeout: 5)); phase("held-2", object: loading, timeout: 10)
        snap("retained-record-read-retry-held")
        let record = app.buttons["recoveryRecord-0"].firstMatch
        XCTAssertTrue(record.waitForExistence(timeout: 30)); record.tap()
        let amount = app.descendants(matching: .any).matching(identifier: "recoveryField-0").firstMatch
        XCTAssertTrue(amount.waitForExistence(timeout: 10)); XCTAssertTrue(amount.label.contains("137 mL"))
        XCTAssertFalse(app.staticTexts["This copy changed or couldn't be opened. Return to check copies again."].exists)
        snap("retained-record-read-retry-detail")
        let readback = try JSONSerialization.data(withJSONObject: ["scope": "retained-record", "backToClosedSeconds": backElapsed, "retryAmount": amount.label], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: readback, uniformTypeIdentifier: "public.json")
        attachment.name = "held-read-ui-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHealthRecoveryReadRetainedPhoto() throws {
        executionTimeAllowance = 300
        let copy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(copy); XCTAssertTrue(copy.waitForExistence(timeout: 10)); copy.tap()
        let records = app.buttons["reviewHealth-meals"].firstMatch; reveal(records); records.tap()
        let meal = app.buttons["recoveryRecord-0"].firstMatch; reveal(meal); XCTAssertTrue(meal.exists); meal.tap()
        let parentTitle = app.navigationBars.firstMatch.identifier
        let photoLink = app.buttons["recoveryChild-2"].firstMatch; reveal(photoLink); XCTAssertTrue(photoLink.exists); photoLink.tap()
        let loading = app.descendants(matching: .any).matching(identifier: "recoveryPhotoLoading").firstMatch
        func phase(_ value: String, object: XCUIElement, timeout: TimeInterval) {
            let expected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: object)
            XCTAssertEqual(XCTWaiter.wait(for: [expected], timeout: timeout), .completed)
        }
        XCTAssertTrue(loading.waitForExistence(timeout: 10)); phase("held-1", object: loading, timeout: 10)
        snap("retained-photo-read-held"); phase("observed-1", object: loading, timeout: 10)
        let backStarted = Date()
        app.navigationBars["Meal photo"].buttons.element(boundBy: 0).tap()
        let state = app.descendants(matching: .any).matching(identifier: "healthReadControlState").firstMatch
        let stopped = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            app.navigationBars[parentTitle].exists && state.exists && state.value as? String == "closed-1"
        }, object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [stopped], timeout: 3), .completed)
        let elapsed = Date().timeIntervalSince(backStarted)
        XCTAssertLessThan(elapsed, 3, "Back must close the held JPEG reader without host release")
        snap("retained-photo-read-cancelled-closed")
        reveal(photoLink, towardsTop: true); photoLink.tap()
        XCTAssertTrue(loading.waitForExistence(timeout: 5)); phase("held-2", object: loading, timeout: 10)
        snap("retained-photo-read-retry-held")
        let photo = app.images["recoveryMealPhoto"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 30)); reveal(photo); alignHealthRecordPhoto(photo)
        XCTAssertTrue(photo.frame.width > 0 && photo.frame.height > photo.frame.width)
        XCTAssertTrue(app.frame.contains(photo.frame))
        XCTAssertFalse(app.staticTexts["This photo changed or couldn't be opened. Return to check copies again."].exists)
        snap("retained-photo-read-retry-image")
        let readback = try JSONSerialization.data(withJSONObject: ["scope": "retained-photo", "backToClosedSeconds": elapsed, "retryPhotoLabel": photo.label, "x": photo.frame.minX, "y": photo.frame.minY, "width": photo.frame.width, "height": photo.frame.height], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: readback, uniformTypeIdentifier: "public.json")
        attachment.name = "held-read-ui-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHealthRecoveryReadRetainedPhotoMutation() throws { try retainedPhotoChangedDuringRead(mode: "in-place") }
    func testHealthRecoveryReadRetainedPhotoReplacement() throws { try retainedPhotoChangedDuringRead(mode: "replacement") }
    func testHealthRecoveryReadRetainedPhotoPayloadMutation() throws { try retainedPhotoChangedDuringRead(mode: "in-place", payload: true) }
    func testHealthRecoveryReadRetainedPhotoPayloadReplacement() throws { try retainedPhotoChangedDuringRead(mode: "replacement", payload: true) }
    private func retainedPhotoChangedDuringRead(mode: String, payload: Bool = false) throws {
        executionTimeAllowance = 300
        let copy = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(copy); XCTAssertTrue(copy.waitForExistence(timeout: 10)); copy.tap()
        let records = app.buttons["reviewHealth-meals"].firstMatch; reveal(records); records.tap()
        let meal = app.buttons["recoveryRecord-0"].firstMatch; reveal(meal); XCTAssertTrue(meal.exists); meal.tap()
        let parentTitle = app.navigationBars.firstMatch.identifier
        let photoLink = app.buttons["recoveryChild-2"].firstMatch; reveal(photoLink); XCTAssertTrue(photoLink.exists); photoLink.tap()
        let loading = app.descendants(matching: .any).matching(identifier: "recoveryPhotoLoading").firstMatch
        XCTAssertTrue(loading.waitForExistence(timeout: 10))
        let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "held-1"), object: loading)
        XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 10), .completed)
        let prefix = "retained-photo-" + (payload ? "payload-" : "") + mode
        snap(prefix + "-held")
        let error = app.staticTexts["This photo changed or couldn't be opened. Return to check copies again."].firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 30))
        let state = app.descendants(matching: .any).matching(identifier: "healthReadControlState").firstMatch
        let closed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "closed-1"), object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
        XCTAssertFalse(app.images["recoveryMealPhoto"].exists)
        XCTAssertFalse(loading.exists)
        snap(prefix + "-rejected")
        let readback = try JSONSerialization.data(withJSONObject: ["scope": "retained-photo", "mutation": mode, "error": error.label, "imageExists": app.images["recoveryMealPhoto"].exists, "readerState": state.value as? String ?? "missing"], options: [.prettyPrinted, .sortedKeys])
        let attachment = XCTAttachment(data: readback, uniformTypeIdentifier: "public.json")
        attachment.name = "held-photo-source-change-readback"; attachment.lifetime = .keepAlways; add(attachment)
        if payload {
            // The host restores only after the original rejection attachment.
            // Actual navigation must then start a new reader of restored bytes.
            app.navigationBars["Meal photo"].buttons.element(boundBy: 0).tap()
            XCTAssertTrue(app.navigationBars[parentTitle].waitForExistence(timeout: 5))
            reveal(photoLink, towardsTop: true); photoLink.tap()
            XCTAssertTrue(loading.waitForExistence(timeout: 5))
            let retry = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "held-2"), object: loading)
            XCTAssertEqual(XCTWaiter.wait(for: [retry], timeout: 10), .completed)
            snap(prefix + "-restored-retry-held")
            let photo = app.images["recoveryMealPhoto"].firstMatch
            XCTAssertTrue(photo.waitForExistence(timeout: 30)); reveal(photo); alignHealthRecordPhoto(photo)
            XCTAssertFalse(error.exists)
            XCTAssertTrue(photo.frame.width > 0 && photo.frame.height > photo.frame.width)
            XCTAssertTrue(app.frame.contains(photo.frame))
            snap(prefix + "-restored-retry-image")
            let frame = XCTAttachment(data: try JSONSerialization.data(withJSONObject: ["scope": "retained-photo-payload", "mutation": mode, "x": photo.frame.minX, "y": photo.frame.minY, "width": photo.frame.width, "height": photo.frame.height, "photoLabel": photo.label]), uniformTypeIdentifier: "public.json")
            frame.name = "held-photo-restored-frame"; frame.lifetime = .keepAlways; add(frame)
        }
    }
    func testHealthRecoveryScreenDark() throws { try healthRecoveryScreen() }
    func testHealthRecoveryScreenLargest() throws { try healthRecoveryScreen() }
    func testHealthRecoveryScreenCancel() throws { try healthRecoveryCancelScreen() }
    func testHealthRecoveryScreenCancelDark() throws { try healthRecoveryCancelScreen() }
    func testHealthRecoveryScreenCancelLargest() throws { try healthRecoveryCancelScreen() }
    func testHealthRecoveryScreenCancelBack() throws { try healthRecoveryCancelScreen() }
    func testHealthRecoveryScreenCancelBackDark() throws { try healthRecoveryCancelScreen() }
    func testHealthRecoveryScreenCancelBackLargest() throws { try healthRecoveryCancelScreen() }
    private func healthRecoveryCancelScreen() throws {
        executionTimeAllowance = 180
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(first); XCTAssertTrue(first.waitForExistence(timeout: 10)); let identity = first.identifier; first.tap()
        let choice = app.switches["recoverHealth-water"].firstMatch
        reveal(choice); XCTAssertEqual(choice.value as? String, "0"); nativeSwitch("recoverHealth-water", enabled: true)
        XCTAssertEqual(choice.value as? String, "1")
        let confirm = app.buttons["confirmHealthRecovery"].firstMatch
        func start() {
            reveal(confirm); XCTAssertTrue(confirm.isEnabled); confirm.tap()
            let alert = app.alerts["Replace selected data?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5)); alert.buttons["Recover"].tap()
        }
        start()
        let busy = app.descendants(matching: .any).matching(identifier: "healthRecoveryBusy").firstMatch
        XCTAssertTrue(busy.waitForExistence(timeout: 5))
        let held = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "held-1"), object: busy)
        XCTAssertEqual(XCTWaiter.wait(for: [held], timeout: 10), .completed)
        let leaving = name.contains("CancelBack")
        let cancel = app.buttons["Cancel"].firstMatch; reveal(cancel)
        XCTAssertTrue(cancel.isHittable); snap("health-recovery-cancel-held")
        let stopped: Bool
        if leaving {
            app.navigationBars.buttons.element(boundBy: 0).tap()
            let checked = app.buttons["checkHealthCopies"].firstMatch; reveal(checked)
            let ended = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "cancelled-1"), object: checked)
            stopped = XCTWaiter.wait(for: [ended], timeout: 3) == .completed
        } else { cancel.tap(); stopped = confirm.waitForExistence(timeout: 3) }
        continueAfterFailure = true
        XCTAssertTrue(stopped, "Cancel must reach held transaction preparation without waiting for host release")
        continueAfterFailure = false
        if !stopped {
            // Preserve the expected baseline failure, then let the host release
            // the real worker so its ordinary cancellation guard/cleanup runs.
            XCTAssertTrue(confirm.waitForExistence(timeout: 30))
            snap("health-recovery-cancel-late-stop")
            return
        }
        if leaving {
            snap("health-recovery-back-cancelled-destination")
            let same = app.buttons[identity].firstMatch; reveal(same, towardsTop: true)
            XCTAssertTrue(same.waitForExistence(timeout: 10)); same.tap()
            reveal(choice); XCTAssertEqual(choice.value as? String, "0")
            snap("health-recovery-back-reopened-unselected")
            nativeSwitch("recoverHealth-water", enabled: true)
        }
        reveal(choice, towardsTop: true); XCTAssertEqual(choice.value as? String, "1")
        snap(leaving ? "health-recovery-back-explicitly-reselected" : "health-recovery-cancel-retained-water-choice")
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); XCTAssertFalse(busy.exists)
        XCTAssertFalse(app.staticTexts["Recovery couldn't finish. Your current files haven't been replaced. Check the copy and try again."].exists)
        snap("health-recovery-cancel-retained-selection")
        start()
        let retry = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "held-2"), object: busy)
        XCTAssertEqual(XCTWaiter.wait(for: [retry], timeout: 10), .completed)
        reveal(cancel); snap("health-recovery-cancel-retry-held")
        let success = app.descendants(matching: .any).matching(identifier: "healthDataRecovered").firstMatch
        reveal(success, towardsTop: true); XCTAssertTrue(success.waitForExistence(timeout: 30))
        snap("health-recovery-cancel-retry-success")
        app.terminate(); app.launchArguments = app.launchArguments.filter { $0 != "-resetForUITests" }; app.launch()
        let same = app.buttons[identity].firstMatch; reveal(same)
        XCTAssertTrue(same.waitForExistence(timeout: 10)); same.tap()
        let healthy = app.staticTexts["Current data opens"].firstMatch; reveal(healthy)
        XCTAssertTrue(healthy.exists); XCTAssertFalse(app.switches["recoverHealth-water"].exists)
        snap("health-recovery-cancel-retry-relaunch")
    }
    func testHealthRecordReviewBaseline() throws {
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(first); XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        let records = app.buttons["reviewHealth-workouts"].firstMatch; reveal(records); records.tap()
        XCTAssertTrue(app.staticTexts["Synthetic unknown energy"].waitForExistence(timeout: 5))
        snap("health-review-baseline-unknown-energy")
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'Energy not provided'")).firstMatch.waitForExistence(timeout: 5))
    }
    func testHealthRecordReviewEmpty() throws {
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(first); XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        let records = app.buttons["reviewHealth-water"].firstMatch; reveal(records); records.tap()
        XCTAssertTrue(app.staticTexts["No records in this copy."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["recoveryRecord-0"].exists); snap("health-record-empty-history")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let choice = app.switches["recoverHealth-water"].firstMatch; reveal(choice)
        XCTAssertEqual(choice.value as? String, "0")
    }
    func testHealthRecordReviewScreen() throws { try healthRecordReviewScreen() }
    func testHealthRecordReviewScreenDark() throws { try healthRecordReviewScreen() }
    func testHealthRecordReviewScreenLargest() throws { try healthRecordReviewScreen() }
    func testHealthRecordReviewPhotoUnavailable() throws { try healthRecordReviewPhotoUnavailable() }
    func testHealthRecordReviewPhotoUnavailableDark() throws { try healthRecordReviewPhotoUnavailable() }
    func testHealthRecordReviewPhotoUnavailableLargest() throws { try healthRecordReviewPhotoUnavailable() }
    func testHealthRecordReviewConfidence() throws { try healthRecordReviewConfidence() }
    func testHealthRecordReviewConfidenceDark() throws { try healthRecordReviewConfidence() }
    func testHealthRecordReviewConfidenceLargest() throws { try healthRecordReviewConfidence() }
    private func healthRecordReviewConfidence() throws {
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(first); XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        let records = app.buttons["reviewHealth-meals"].firstMatch; reveal(records); records.tap()
        let meal = app.buttons["recoveryRecord-0"].firstMatch; reveal(meal); XCTAssertTrue(meal.exists); meal.tap()
        let food = app.buttons["recoveryChild-0"].firstMatch; reveal(food); XCTAssertTrue(food.exists); food.tap()
        let score = app.descendants(matching: .any).matching(identifier: "recoveryField-7").firstMatch
        reveal(score); XCTAssertTrue(score.waitForExistence(timeout: 5))
        XCTAssertEqual(score.label, "Saved confidence score, " + "0.84".replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? "."))
        let observedScore = score.label
        capturePreferenceDisclosure("recoveryField-7", prefix: "health-record-confidence-score")
        let message = "This is a saved estimate score, not a measure of accuracy."
        capturePreferenceDisclosure(message, prefix: "health-record-confidence-footer")
        let footer = app.staticTexts[message].firstMatch; XCTAssertEqual(footer.label, message)
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: ["score": observedScore, "footer": footer.label]), uniformTypeIdentifier: "public.json")
        attachment.name = "health-record-confidence-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    func testHealthRecordReviewPhotoOriented() throws {
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(first); XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        let records = app.buttons["reviewHealth-meals"].firstMatch; reveal(records); records.tap()
        let meal = app.buttons["recoveryRecord-0"].firstMatch; reveal(meal); XCTAssertTrue(meal.exists); meal.tap()
        let photoLink = app.buttons["recoveryChild-2"].firstMatch; reveal(photoLink); XCTAssertTrue(photoLink.exists); photoLink.tap()
        let photo = app.images["recoveryMealPhoto"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10)); reveal(photo)
        alignHealthRecordPhoto(photo)
        snap("health-record-oriented-jpeg")
        let frame = XCTAttachment(data: try JSONSerialization.data(withJSONObject: ["x": photo.frame.minX, "y": photo.frame.minY, "width": photo.frame.width, "height": photo.frame.height]), uniformTypeIdentifier: "public.json")
        frame.name = "health-record-oriented-frame"; frame.lifetime = .keepAlways; add(frame)
        // AX reports the padded Form row. Independent original-pixel checks
        // compare exact rendered aspect/colour order with the EXIF JPEG.
        XCTAssertTrue(photo.frame.width > 0 && photo.frame.height > photo.frame.width)
        XCTAssertTrue(app.frame.contains(photo.frame))
    }
    private func alignHealthRecordPhoto(_ photo: XCUIElement) {
        for _ in 0..<8 {
            let top = app.navigationBars.firstMatch.frame.maxY + 12, bottom = app.frame.maxY - 28
            let rect = photo.frame
            if rect.minY >= top && rect.maxY <= bottom { break }
            let delta = rect.maxY > bottom ? min(150, rect.maxY - bottom + 8) : max(-150, rect.minY - top - 8)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: app.frame.maxY - 120))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: app.frame.maxY - 120 - delta))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
    }
    private func healthRecordReviewPhotoUnavailable() throws {
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(first); XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        let records = app.buttons["reviewHealth-meals"].firstMatch; reveal(records); records.tap()
        let meal = app.buttons["recoveryRecord-0"].firstMatch; reveal(meal); XCTAssertTrue(meal.exists); meal.tap()
        let photo = app.buttons["recoveryChild-2"].firstMatch; reveal(photo); XCTAssertTrue(photo.exists); photo.tap()
        let message = "This photo changed or couldn't be opened. Return to check copies again."
        XCTAssertTrue(app.staticTexts[message].waitForExistence(timeout: 10))
        XCTAssertFalse(app.images["recoveryMealPhoto"].exists)
        capturePreferenceDisclosure(message, prefix: "health-record-photo-unavailable")
    }
    private func healthRecordReviewScreen() throws {
        executionTimeAllowance = 900
        var observed: [String: String] = [:]
        observed["context-locale"] = Locale.current.identifier
        observed["context-timeZone"] = TimeZone.current.identifier
        var previousDomain = 0
        func back() { app.navigationBars.buttons.element(boundBy: 0).tap() }
        func decimal(_ value: String) -> String { value.replacingOccurrences(of: ".", with: Locale.current.decimalSeparator ?? ".") }
        func domain(_ value: String) {
            let button = app.buttons["reviewHealth-" + value].firstMatch
            let nextDomain = ["water","meals","workouts","goals","today"].firstIndex(of: value)!
            reveal(button, towardsTop: nextDomain < previousDomain)
            XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
            previousDomain = nextDomain
        }
        func record(_ index: Int) {
            let button = app.buttons["recoveryRecord-\(index)"].firstMatch
            reveal(button); XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        }
        func child(_ index: Int, towardsTop: Bool = false) {
            let button = app.buttons["recoveryChild-\(index)"].firstMatch
            reveal(button, towardsTop: towardsTop); XCTAssertTrue(button.waitForExistence(timeout: 5)); button.tap()
        }
        func field(_ index: Int, contains value: String, capture: String) {
            let row = app.descendants(matching: .any).matching(identifier: "recoveryField-\(index)").firstMatch
            reveal(row); XCTAssertTrue(row.waitForExistence(timeout: 5))
            XCTAssertTrue(row.label.contains(value), row.debugDescription)
            observed[capture] = row.label; snap("health-record-" + capture)
            if name.contains("Largest") {
                capturePreferenceDisclosure("recoveryField-\(index)", prefix: "health-record-" + capture + "-full")
            }
        }
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(first); XCTAssertTrue(first.waitForExistence(timeout: 10)); first.tap()
        domain("water")
        XCTAssertTrue(app.buttons["recoveryRecord-1"].waitForExistence(timeout: 5)); snap("health-record-two-water")
        record(0); field(0, contains: "137 mL", capture: "water-amount")
        let note = app.buttons["recoveryText-2"].firstMatch; reveal(note); XCTAssertTrue(note.exists); note.tap()
        var parts: [String] = []
        for part in 0..<8 {
            let text = app.staticTexts["recoveryFullText"].firstMatch
            XCTAssertTrue(text.waitForExistence(timeout: 5)); parts.append(text.label)
            if part == 0 { snap("health-record-long-first") }
            let next = app.buttons["Next part"].firstMatch
            XCTAssertTrue(next.exists); XCTAssertTrue(app.frame.contains(next.frame))
            if !next.isEnabled {
                XCTAssertTrue(text.label.contains("Exact final marker.")); XCTAssertTrue(app.frame.contains(text.frame))
                snap("health-record-long-final"); break
            }
            next.tap(); XCTAssertTrue(app.staticTexts["Part \(part + 2)"].waitForExistence(timeout: 5))
        }
        XCTAssertEqual(parts.count, 3); XCTAssertTrue(parts.joined().count > 4000)
        observed["longNote"] = parts.joined()
        back(); child(0)
        field(1, contains: "I drank 137 ml of water.", capture: "water-statement")
        field(3, contains: "synthetic-review-conversation", capture: "water-source-id")
        back(); back(); back()
        domain("workouts"); record(0)
        field(4, contains: "Energy not provided", capture: "workout-unknown")
        back(); record(1)
        field(4, contains: "0 kcal", capture: "workout-known-zero")
        field(6, contains: decimal("94.5 bpm"), capture: "workout-heart-rate")
        child(0); field(3, contains: "synthetic-health-export.zip", capture: "workout-import")
        child(0); field(0, contains: "Synthetic import warning.", capture: "workout-warning")
        back(); back(); back(); back()
        domain("meals"); record(0); child(0)
        field(3, contains: decimal("20.25 g"), capture: "food-protein")
        field(7, contains: decimal("0.84"), capture: "food-score")
        capturePreferenceDisclosure("This is a saved estimate score, not a measure of accuracy.", prefix: "health-record-food-confidence")
        back(); child(2)
        let photo = app.images["recoveryMealPhoto"].firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 10)); reveal(photo)
        snap("health-record-square-before-alignment")
        let frame = XCTAttachment(data: try JSONSerialization.data(withJSONObject: ["x": photo.frame.minX, "y": photo.frame.minY, "width": photo.frame.width, "height": photo.frame.height, "viewportWidth": app.frame.width, "viewportHeight": app.frame.height]), uniformTypeIdentifier: "public.json")
        frame.name = "health-record-square-before-frame"; frame.lifetime = .keepAlways; add(frame)
        alignHealthRecordPhoto(photo)
        XCTAssertTrue(photo.frame.width > 0 && photo.frame.height > 0); XCTAssertTrue(app.frame.contains(photo.frame))
        snap("health-record-real-jpeg")
        back(); back(); back()
        domain("goals"); record(0)
        for index in [4,5,6] { field(index, contains: "Not provided", capture: "target-missing-\(index)") }
        back(); back()
        domain("today"); record(0); child(19)
        field(0, contains: "No reading", capture: "day-water-unknown")
        child(0); field(0, contains: "No samples returned", capture: "day-water-query")
        back(); back(); child(1, towardsTop: true)
        field(0, contains: "0 steps", capture: "day-recorded-zero")
        back(); child(2)
        field(0, contains: decimal("About 123.5 kcal"), capture: "day-estimate")
        child(0); field(3, contains: "Reported day", capture: "day-aggregation")
        field(8, contains: "Yes", capture: "day-estimate-flag")
        back(); child(1); field(0, contains: "Samples found", capture: "day-query")
        let checked = DateFormatter(); checked.dateStyle = .medium; checked.timeStyle = .long
        field(3, contains: checked.string(from: Date(timeIntervalSince1970: 1_793_620_800 + 86500)), capture: "day-query-checked")
        back(); back(); child(20)
        field(12, contains: decimal("72.6 kg"), capture: "day-cache-weight")
        capturePreferenceDisclosure("Stored zeros can mean no reading. The daily readings show which values were recorded.", prefix: "health-record-cache-presence")
        let attachment = XCTAttachment(data: try JSONSerialization.data(withJSONObject: observed, options: [.sortedKeys,.prettyPrinted]), uniformTypeIdentifier: "public.json")
        attachment.name = "health-record-ui-readback"; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func healthRecoveryScreen() throws {
        func captureLowerChoice(_ prefix: String) {
            guard name.contains("Largest") else { return }
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: app.frame.maxY - 100))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: app.frame.maxY - 240))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            snap(prefix + "-lower")
        }
        capturePreferenceDisclosure("Water history couldn't be opened. Changes to this data are paused. Lumen hasn't replaced the saved data.", prefix: "health-recovery-unavailable")
        let first = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'healthRecoveryCopy-'")).firstMatch
        reveal(first); XCTAssertTrue(first.waitForExistence(timeout: 10)); let identity = first.identifier
        snap("health-recovery-copy-list")
        capturePreferenceDisclosure("Review a copy before replacing unavailable data. Healthy data can't be replaced here.", prefix: "health-recovery-healthy-footer")
        reveal(first, towardsTop: true); first.tap()
        let water = app.switches["recoverHealth-water"].firstMatch
        reveal(water); XCTAssertTrue(water.waitForExistence(timeout: 5)); XCTAssertEqual(water.value as? String, "0"); snap("health-recovery-initial-choice")
        captureLowerChoice("health-recovery-initial-choice")
        let records = app.buttons["reviewHealth-water"].firstMatch; reveal(records, towardsTop: true); records.tap()
        XCTAssertTrue(app.staticTexts["137 mL"].waitForExistence(timeout: 5)); snap("health-recovery-reviewed-water")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        nativeSwitch("recoverHealth-water", enabled: true)
        XCTAssertEqual(water.value as? String, "1"); snap("health-recovery-selected-choice")
        captureLowerChoice("health-recovery-selected-choice")
        capturePreferenceDisclosure("Replaced files stay in a private copy on this iPhone. For meal recovery, this includes any old photos.", prefix: "health-recovery-retained-originals")
        capturePreferenceDisclosure("Recovered entries won't be added to Apple Health. Earlier pending Health saves won't restart; pending removals can finish.", prefix: "health-recovery-health-work")
        let confirm = app.buttons["confirmHealthRecovery"].firstMatch
        reveal(confirm); XCTAssertTrue(confirm.isEnabled); snap("health-recovery-selection")
        confirm.tap(); let alert = app.alerts["Replace selected data?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        if name.contains("Largest") { capturePreferenceAlert(alert, prefix: "health-recovery-confirmation") }
        else { snap("health-recovery-confirmation") }
        alert.buttons["Not now"].tap()
        XCTAssertTrue(confirm.isEnabled); confirm.tap(); alert.buttons["Recover"].tap()
        snap("health-recovery-after-request")
        let success = app.descendants(matching: .any).matching(identifier: "healthDataRecovered").firstMatch
        reveal(success, towardsTop: true); snap("health-recovery-request-top")
        XCTAssertTrue(success.waitForExistence(timeout: 10), app.debugDescription); snap("health-recovery-success")
        app.terminate(); app.launchArguments = app.launchArguments.filter { $0 != "-resetForUITests" }; app.launch()
        let sameCopy = app.buttons[identity].firstMatch
        reveal(sameCopy); XCTAssertTrue(sameCopy.waitForExistence(timeout: 10)); sameCopy.tap()
        let healthy = app.staticTexts["Current data opens"].firstMatch; reveal(healthy)
        XCTAssertTrue(healthy.waitForExistence(timeout: 5))
        XCTAssertFalse(app.switches["recoverHealth-water"].exists); snap("health-recovery-relaunch-healthy")
    }
    func testHealthLegacyRootAcquisitionNoPrior() throws { try legacyRootAcquisitionObserved() }
    func testHealthLegacyRootAcquisitionWithPrior() throws { try legacyRootAcquisitionObserved() }
    func testHealthLegacyRootAcquisitionOrdinary() throws { try legacyRootAcquisitionObserved() }
    private func legacyRootAcquisitionObserved() throws {
        let status = app.staticTexts["healthWriteProbeStatus"].firstMatch
        let terminal = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH %@ OR label BEGINSWITH %@", "Legacy root probe observed:", "Legacy root probe failed:"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [terminal], timeout: 300), .completed)
        XCTAssertTrue(status.label.hasPrefix("Legacy root probe observed:"), status.label)
        snap("legacy-root-acquisition-observed")
    }
    func testHealthLocalSemanticRecovery() throws { try healthLocalDataRecovery("semantic-fixture") }
    func testHealthLocalMealsRecovery() throws { try healthLocalDataRecovery("meals") }
    func testHealthLocalWorkoutsRecovery() throws { try healthLocalDataRecovery("workouts") }
    func testHealthLocalGoalsRecovery() throws { try healthLocalDataRecovery("goals") }
    func testHealthLocalTodayRecovery() throws { try healthLocalDataRecovery("today") }
    func testHealthLocalUnreadableRecovery() throws { try healthLocalDataRecovery("unreadable-water") }
    func testHealthLocalWaterAfterOpen() throws { try healthLocalDataRecovery("water", afterOpen: true) }
    func testHealthLocalMealsAfterOpen() throws { try healthLocalDataRecovery("meals", afterOpen: true) }
    func testHealthLocalWorkoutsAfterOpen() throws { try healthLocalDataRecovery("workouts", afterOpen: true) }
    func testHealthLocalGoalsAfterOpen() throws { try healthLocalDataRecovery("goals", afterOpen: true) }
    func testHealthLocalTodayAfterOpen() throws { try healthLocalDataRecovery("today", afterOpen: true) }
    private func healthLocalDataRecovery(_ domain: String, afterOpen: Bool = false) throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-health-write-native-probe", "-health-local-repair", domain]
        if name.contains("testHealthPreviousCopyTaskCancellation") { app.launchArguments.append("-health-recovery-task-cancel-probe") }
        if afterOpen { app.launchArguments.append("-health-local-after-open") }
        app.launch()
        let status = app.staticTexts["healthWriteProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Saved-data checks passed' OR label BEGINSWITH 'Saved-data checks failed'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 120), .completed)
        XCTAssertEqual(status.label, "Saved-data checks passed")
        snap("local-data-recovery-" + domain + (afterOpen ? "-after-open" : "-startup"))
    }
    func testHealthLocalCorruptMealsBaseline() throws { try healthLocalDataBaseline("meals") }
    func testHealthLocalCorruptGoalsBaseline() throws { try healthLocalDataBaseline("goals") }
    func testHealthLocalUnreadableWaterBaseline() throws { try healthLocalDataBaseline("unreadable-water") }
    private func healthLocalDataBaseline(_ domain: String) throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-health-write-native-probe", "-health-local-baseline", domain]
        app.launch()
        let status = app.staticTexts["healthWriteProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Local data baseline recorded' OR label BEGINSWITH 'Local data baseline failed'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 60), .completed)
        XCTAssertEqual(status.label, "Local data baseline recorded")
        snap("local-data-baseline-" + domain)
    }

    func testDurableHealthRestartBeforeWorkerPrepare() throws { try durableHealthLifecycle(resume: false) }
    func testDurableHealthRestartBeforeWorkerResume() throws { try durableHealthLifecycle(resume: true) }
    func testDurableHealthRestartBeforeReceiptPrepare() throws { try durableHealthLifecycle(resume: false) }
    func testDurableHealthRestartBeforeReceiptResume() throws { try durableHealthLifecycle(resume: true) }
    func testDurableHealthRestartUndoPrepare() throws { try durableHealthLifecycle(resume: false) }
    func testDurableHealthRestartUndoResume() throws { try durableHealthLifecycle(resume: true) }
    private func durableHealthLifecycle(resume: Bool) throws {
        if !resume { approveSyntheticHealthAccess(until: app.staticTexts["healthLifecycleAccessReady"].firstMatch) }
        let status = app.staticTexts["healthLifecycleStatus"].firstMatch
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Health restart ready to stop' OR label BEGINSWITH 'Health restart checks passed' OR label BEGINSWITH 'Health restart checks failed'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 90), .completed)
        XCTAssertEqual(status.label, resume ? "Health restart checks passed" : "Health restart ready to stop")
        snap(name.replacingOccurrences(of: " ", with: "-"))
        app.terminate()
        XCTAssertEqual(app.state, .notRunning, "The prepared/resumed native app process must actually terminate")
    }
    func testDurableHealthNativeReceiptFailure() throws {
        try durableHealthNativeProbe(receipt: true)
    }
    func testDurableHealthKitReplayAndRemoval() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-health-write-healthkit-probe"]
        app.launch()
        let access = app.staticTexts["healthKitProbeAccessReturned"].firstMatch
        approveSyntheticHealthAccess(until: access)
        let status = app.staticTexts["healthKitWriteProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'HealthKit replay checks passed' OR label BEGINSWITH 'HealthKit replay checks failed'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        XCTAssertEqual(status.label, "HealthKit replay checks passed")
        snap("durable-healthkit-replay-report")
    }
    private func durableHealthNativeProbe(receipt: Bool) throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-health-write-native-probe", "-quick-save-fault", receipt ? "health-receipt:1" : "water.json:1"]
        if receipt { app.launchArguments.append("-health-write-receipt-trial") }
        app.launch()
        let status = app.staticTexts["healthWriteProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Health recovery checks passed' OR label BEGINSWITH 'Health recovery checks failed'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        XCTAssertEqual(status.label, "Health recovery checks passed")
        snap(receipt ? "durable-health-receipt-failure-report" : "durable-health-combined-failure-report")
    }

    func testConversationNativeBackendProbe() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-conversation-native-probe", "-quick-save-fault", "conversations.json:3,5,8"]
        app.launch()
        let status = app.staticTexts["conversationProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Conversation checks passed' OR label BEGINSWITH 'Conversation checks failed'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        XCTAssertEqual(status.label, "Conversation checks passed")
        snap("1033-conversation-native-report")
    }

    /// Bounded positioning avoids whole-viewport oscillation around a tall
    /// Dynamic Type switch row. Operates the actual native thumb after settling.
    func librarySharingSwitch(enabled: Bool) {
        let toggle = app.switches["Use in assistant"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        let top = max(app.navigationBars.firstMatch.frame.maxY + 16, scroll.frame.minY + 16)
        let bottom = min(app.tabBars.firstMatch.frame.minY - 20, scroll.frame.maxY - 20)
        let middle = (top + bottom) / 2
        for _ in 0..<24 {
            let frame = toggle.frame
            print("LIBRARY SHARING POSITION", frame, "viewport", top, bottom)
            if frame.minY >= top && frame.maxY <= bottom && toggle.isHittable { break }
            let distance = min(180, max(-180, frame.midY - middle))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle - distance))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        settleLabFrame(toggle)
        XCTAssertGreaterThanOrEqual(toggle.frame.minY, top); XCTAssertLessThanOrEqual(toggle.frame.maxY, bottom)
        if (toggle.value as? String) != (enabled ? "1" : "0") {
            let thumb = toggle.switches.firstMatch
            XCTAssertTrue(thumb.exists && thumb.isHittable)
            thumb.coordinate(withNormalizedOffset: CGVector(dx: enabled ? 0.25 : 0.75, dy: 0.5)).tap()
        }
        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", enabled ? "1" : "0"), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
    }

    func positionLibraryPlanStep(_ element: XCUIElement) {
        let top = app.navigationBars.firstMatch.frame.maxY + 16
        let bottom = app.tabBars.firstMatch.frame.minY - 20
        let middle = (top + bottom) / 2
        XCTAssertTrue(element.exists); XCTAssertLessThan(element.frame.height, bottom - top)
        for _ in 0..<24 {
            let frame = element.frame
            print("LIBRARY COMPLETE STEP POSITION", frame, "viewport", top, bottom)
            if frame.minY >= top && frame.maxY <= bottom && element.isHittable { break }
            let distance = min(160, max(-160, frame.midY - middle))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle - distance))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        settleLabFrame(element, pixelTolerance: 1)
        XCTAssertGreaterThanOrEqual(element.frame.minY, top - 1)
        XCTAssertLessThanOrEqual(element.frame.maxY, bottom + 1)
        XCTAssertTrue(element.isHittable)
    }

    func captureLibraryConversationNotice(text: String, action: String) {
        let scroll = app.scrollViews.firstMatch
        let notice = scroll.descendants(matching: .any).matching(NSPredicate(format: "identifier == 'coachMessage' AND label == %@", text)).firstMatch
        let save = app.buttons[action].firstMatch
        XCTAssertTrue(notice.exists && save.exists); XCTAssertEqual(notice.label, text)
        let navigation = app.navigationBars["Assistant"].firstMatch
        settleLabFrame(navigation, pixelTolerance: 1)
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        let top = max(navigation.frame.maxY + 16, scroll.frame.minY + 16)
        let bottom = min(scroll.frame.maxY - 12, input.frame.minY - 20)
        XCTAssertGreaterThan(bottom - top, 180)
        let middle = (top + bottom) / 2
        let stride = min(140, (bottom - top) / 2)
        func pan(_ distance: CGFloat) {
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle - distance))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        for _ in 0..<24 {
            if notice.frame.minY >= top && (notice.frame.maxY <= bottom || notice.frame.minY <= top + 48) { break }
            pan(min(stride, max(-stride, notice.frame.minY - (top + 16))))
        }
        settleLabFrame(notice, pixelTolerance: 1)
        XCTAssertGreaterThanOrEqual(notice.frame.minY, top - 1)
        if notice.frame.height <= bottom - top {
            XCTAssertLessThanOrEqual(notice.frame.maxY, bottom + 1)
        } else { XCTAssertLessThanOrEqual(notice.frame.minY, top + 48) }
        for step in 0..<24 {
            print("LIBRARY NOTICE COVERAGE", notice.frame, save.frame, "viewport", top, bottom)
            snap("1111-complete-library-notice-\(step)")
            if save.frame.minY >= top && save.frame.maxY <= bottom && save.isHittable { return }
            pan(min(stride, max(32, save.frame.maxY - bottom)))
        }
        XCTFail("Complete Library notice and manual save action were not reached")
    }

    func captureSavedNoticeTitleAndBody(title: String, text: String) {
        let scroll = app.scrollViews.firstMatch
        let heading = scroll.staticTexts.matching(NSPredicate(format: "label == %@", title)).firstMatch
        let body = scroll.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5)); XCTAssertTrue(body.exists)
        XCTAssertEqual(heading.label, title); XCTAssertEqual(body.label, text)
        let top = app.navigationBars.firstMatch.frame.maxY + 16
        let bottom = app.tabBars.firstMatch.frame.minY - 20
        let middle = (top + bottom) / 2
        func pan(_ distance: CGFloat) {
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle - distance))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        for _ in 0..<24 {
            if heading.frame.minY >= top && heading.frame.minY <= top + 48 { break }
            pan(min(160, max(-160, heading.frame.minY - (top + 16))))
        }
        settleLabFrame(heading, pixelTolerance: 1)
        XCTAssertGreaterThanOrEqual(heading.frame.minY, top - 1)
        XCTAssertLessThanOrEqual(heading.frame.minY, top + 48)
        for step in 0..<30 {
            print("SAVED NOTICE TITLE BODY COVERAGE", heading.frame, body.frame, "viewport", top, bottom)
            snap("1110-saved-notice-title-body-\(step)")
            if body.frame.maxY <= bottom && body.frame.maxY > top { return }
            pan(min(160, max(32, body.frame.maxY - bottom)))
        }
        XCTFail("Complete saved-note title and body ending were not reached")
    }

    func captureLibrarySharingFooter(_ prefix: String) {
        let text = "When enabled, matching text can be sent with your questions to the AI provider selected in Settings. Turning this off stops future retrieval. Earlier replies and saved copies keep their excerpts."
        let footer = app.staticTexts.matching(NSPredicate(format: "label == %@", text)).firstMatch
        XCTAssertTrue(footer.exists)
        let top = app.navigationBars.firstMatch.frame.maxY + 16
        let bottom = app.tabBars.firstMatch.frame.minY - 20
        for step in 0..<20 {
            snap(prefix + "-footer-\(step)")
            print("LIBRARY FOOTER COVERAGE", footer.frame, "viewport", top, bottom)
            if footer.frame.maxY <= bottom && footer.frame.maxY > top { return }
            let middle = (top + bottom) / 2
            let distance = min(160, max(32, footer.frame.maxY - bottom))
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle + 60))
            let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: middle + 60 - distance))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
        }
        XCTFail("Complete sharing disclosure ending was not reached")
    }

    func testLibraryNoticePlanUI() throws { try libraryNoticePlanUI(large: false) }
    func testLibraryNoticePlanUILarge() throws { try libraryNoticePlanUI(large: true) }
    func testLibrarySearchChangeUI() throws { try libraryNoticePlanUI(large: false, preSearch: true) }
    func testLibrarySearchChangeUILarge() throws { try libraryNoticePlanUI(large: true, preSearch: true) }
    func libraryNoticePlanUI(large: Bool, preSearch: Bool = false) throws {
        app.terminate()
        app.launchEnvironment["LUMEN_PERSONAL_TEST_NONCE"] = UUID().uuidString
        app.launchArguments = ["-resetForUITests", "-personal-provenance-ui"] + (preSearch ? ["-library-search-hold-ui"] : [])
            + (large ? ["-lumen.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : ["-lumen.appearance", "light"])
        app.launch(); finishOnboarding()
        createSemanticNote(title: "Shared routine", body: "SYNTHETIC-LIBRARY-CONTEXT-41. A synthetic flexible routine.", shared: false)
        let shared = app.buttons["Shared routine"].firstMatch; reveal(shared); shared.tap()
        librarySharingSwitch(enabled: true)
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        let before = try personalRequestAudit().count
        let preparedBefore = try conversationRouteCounts("prepared-stage")["requests"] ?? 0
        let release = preSearch ? "/release-prepared" : "/release-personal"
        _ = try conversationControl(preSearch ? "/arm-prepared" : "/arm-personal")
        defer { _ = try? conversationControl(release) }
        tab("Assistant")
        enterConversationQuestion("Make a plan using SYNTHETIC-LIBRARY-CONTEXT-41" + (preSearch ? "" : " SYNTHETIC-PERSONAL-HELD-40"))
        if preSearch {
            let deadline = Date().addingTimeInterval(15)
            var held = false
            while Date() < deadline {
                let counts = try XCTUnwrap(JSONSerialization.jsonObject(with: conversationControl("/counts")) as? [String: [String: Int]])
                if (counts["prepared-stage"]?["requests"] ?? 0) > preparedBefore { held = true; break }
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            XCTAssertTrue(held)
            XCTAssertEqual(try personalRequestAudit().count, before)
        } else { try waitPersonalRequest(before + 1) }
        tab("Library"); let source = app.buttons["Shared routine"].firstMatch; reveal(source); source.tap()
        librarySharingSwitch(enabled: false)
        snap("1102-library-withdrawn-during-reply")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        _ = try conversationControl(release)
        tab("Assistant")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 20))
        let notice = "Library records or search settings changed during this " + (preSearch ? "request" : "reply") + ". Send your question again to use the current settings."
        XCTAssertEqual(coachMessages.firstMatch.label, notice)
        let save = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'saveReplyToLibrary-' ")).firstMatch
        reveal(save); XCTAssertTrue(save.isHittable)
        let saveID = save.identifier
        captureLibraryConversationNotice(text: notice, action: saveID)
        tab("Library")
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).count, 0)
        snap("1104-library-no-automatic-notice-plan")
        tab("Assistant"); reveal(app.buttons[saveID]); app.buttons[saveID].tap()
        let saved = app.buttons["View saved document"].firstMatch; reveal(saved); saved.tap()
        XCTAssertTrue(app.navigationBars["Document"].waitForExistence(timeout: 5))
        let expectedTitle = "Library records or search settings changed during this " + (preSearch ? "request" : "reply") + ". Send your…"
        captureSavedNoticeTitleAndBody(title: expectedTitle, text: notice)
        XCTAssertEqual(app.switches["Use in assistant"].firstMatch.value as? String, "0")
        librarySharingSwitch(enabled: false)
        snap("1105-explicitly-saved-notice")
        captureLibrarySharingFooter("1105-explicitly-saved-notice")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        app.terminate()
        app.launchArguments = ["-personal-provenance-ui"]
            + (large ? ["-lumen.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : ["-lumen.appearance", "light"])
        app.launch(); tab("Assistant")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(coachMessages.firstMatch.label, notice)
        tab("Library"); XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).count, 0)
        tab("Assistant")
        askLibrary("Make a flexible plan SYNTHETIC-PLAN-41", replies: 2)
        let plan = app.buttons["View saved plan"].firstMatch; reveal(plan); plan.tap()
        for text in ["Incomplete: Check how you feel.", "Incomplete: Take a comfortable break.", "Incomplete: Review tomorrow."] {
            let action = app.buttons[text].firstMatch; positionLibraryPlanStep(action); snap("1106-genuine-plan-step-" + text)
        }
        XCTAssertEqual(app.switches["Use in assistant"].firstMatch.value as? String, "0")
        librarySharingSwitch(enabled: false)
        snap("1106-genuine-plan-sharing-off")
        captureLibrarySharingFooter("1106-genuine-plan-sharing")
        app.navigationBars["Document"].buttons.element(boundBy: 0).tap()
        tab("Library"); XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).count, 1)
        snap("1107-only-genuine-plan-in-library")
        let audit = try personalRequestAudit()
        XCTAssertEqual(audit.count, before + (preSearch ? 1 : 2))
        if !preSearch { XCTAssertGreaterThan(try personalCanary(audit[before], "library41", role: "system"), 0) }
        let latest = try XCTUnwrap(audit.last)
        XCTAssertEqual(try personalCanary(latest, "library41", role: "system"), 0)
        XCTAssertEqual(try personalCanary(latest, "library41", role: "assistant"), 0)
    }

    func testLibraryAuthorizationChecks() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-library-authorization-checks"]
        app.launch()
        let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Request authorization checks'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 60), .completed)
        XCTAssertEqual(status.label, "Request authorization checks passed")
        snap("1101-library-authorization-native-checks")
    }

    func testProviderAuthorizationChecks() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-provider-authorization-checks"]
        app.launch()
        let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Provider authorization checks'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        XCTAssertEqual(status.label, "Provider authorization checks passed")
        snap("1203-provider-authorization-native-checks")
    }

    func testProviderCredentialStorage() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-provider-credential-checks"]
        app.launch()
        let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Credential storage checks'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 60), .completed)
        XCTAssertEqual(status.label, "Credential storage checks passed")
        snap("1202-provider-credential-storage-checks")
    }

    func providerUIReadback(_ checkpoint: String, nonce: String) throws -> [String: Any] {
        let ready = expectation(description: "Actual connection UI read-back")
        var received: Data?, status: Int?, failure: Error?
        let session = URLSession(configuration: .ephemeral)
        session.dataTask(with: URL(string: "http://127.0.0.1:48733/ui-state?checkpoint=" + checkpoint)!) { data, response, error in
            received = data; status = (response as? HTTPURLResponse)?.statusCode; failure = error; ready.fulfill()
        }.resume()
        wait(for: [ready], timeout: 10); session.invalidateAndCancel()
        if let failure { throw failure }
        XCTAssertEqual(status, 200)
        let data = try XCTUnwrap(received), object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["nonce"] as? String, nonce)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json"); attachment.name = "provider-ui-" + checkpoint; attachment.lifetime = .keepAlways; add(attachment)
        return object
    }

    func testProviderConnectionDraftUI() throws { try runProviderConnectionDraftUI() }
    func testProviderConnectionDraftUILargest() throws { try runProviderConnectionDraftUI(large: true) }
    func testProviderConnectionDraftUIDark() throws { try runProviderConnectionDraftUI(dark: true) }
    func testProviderConnectionKeyboardUI() throws { try runProviderConnectionKeyboardUI() }
    func testProviderConnectionKeyboardUILargest() throws { try runProviderConnectionKeyboardUI(large: true) }
    func testProviderConnectionKeyboardUIDark() throws { try runProviderConnectionKeyboardUI(dark: true) }
    func testProviderConnectionModelKeyboardUI() throws { try runProviderConnectionKeyboardUI(secure: false) }
    func testProviderConnectionModelKeyboardUILargest() throws { try runProviderConnectionKeyboardUI(large: true, secure: false) }
    func testProviderConnectionModelKeyboardUIDark() throws { try runProviderConnectionKeyboardUI(dark: true, secure: false) }

    func testProviderConnectionScopeEditingDiagnostic() throws {
        app.terminate()
        let nonce = UUID().uuidString
        app.launchArguments = ["-resetForUITests", "-provider-connection-ui", "-provider-ui-nonce", nonce]
        app.launch(); tap("openAIConnectionFixture")
        let original = try providerUIReadback("scope-diagnostic-opened", nonce: nonce)
        let mode = app.buttons["aiConnectionMode"].firstMatch; reveal(mode, towardsTop: true); mode.tap(); tap("Google OAuth")
        replaceConnectionText("aiGoogleScopes", with: "openid email")
        snap("1254-ai-scope-exact-edit")
        let edited = try providerUIReadback("scope-diagnostic-edited", nonce: nonce)
        XCTAssertEqual(edited["recordSHA256"] as? String, original["recordSHA256"] as? String)
        XCTAssertEqual(edited["dirty"] as? Bool, true); XCTAssertEqual(edited["oauthScopeClass"] as? String, "fixture-a")
        tap("closeAIConnection"); tap("Discard"); tap("openAIConnectionFixture")
        XCTAssertEqual(try providerUIReadback("scope-diagnostic-discarded", nonce: nonce)["recordSHA256"] as? String, original["recordSHA256"] as? String)
        let remove = app.buttons["removeAICredentials"].firstMatch; reveal(remove); remove.tap(); tap("Remove")
        let cleaned = try providerUIReadback("scope-diagnostic-cleaned", nonce: nonce)
        XCTAssertEqual(cleaned["apiKeyClass"] as? String, "missing"); XCTAssertEqual(cleaned["oauthAccountPresent"] as? Bool, false)
    }

    func testProviderConnectionEndpointEditingDiagnosticLargest() throws {
        app.terminate()
        let nonce = UUID().uuidString
        app.launchArguments = ["-resetForUITests", "-provider-connection-ui", "-provider-ui-nonce", nonce,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); tap("openAIConnectionFixture")
        let original = try providerUIReadback("endpoint-diagnostic-opened", nonce: nonce)
        let mode = app.buttons["aiConnectionMode"].firstMatch; reveal(mode); mode.tap(); tap("Google OAuth")
        replaceConnectionText("aiOAuthEndpoint", with: "http://127.0.0.1:48733/chat-b")
        snap("1255-ai-endpoint-exact-edit")
        let edited = try providerUIReadback("endpoint-diagnostic-edited", nonce: nonce)
        XCTAssertEqual(edited["recordSHA256"] as? String, original["recordSHA256"] as? String)
        XCTAssertEqual(edited["dirty"] as? Bool, true); XCTAssertEqual(edited["oauthEndpointClass"] as? String, "fixture-a")
        tap("closeAIConnection"); tap("Discard"); tap("openAIConnectionFixture")
        XCTAssertEqual(try providerUIReadback("endpoint-diagnostic-discarded", nonce: nonce)["recordSHA256"] as? String, original["recordSHA256"] as? String)
        let remove = app.buttons["removeAICredentials"].firstMatch; reveal(remove); remove.tap(); tap("Remove")
        let cleaned = try providerUIReadback("endpoint-diagnostic-cleaned", nonce: nonce)
        XCTAssertEqual(cleaned["apiKeyClass"] as? String, "missing"); XCTAssertEqual(cleaned["oauthAccountPresent"] as? Bool, false)
    }

    func runProviderConnectionKeyboardUI(large: Bool = false, dark: Bool = false, secure: Bool = true) throws {
        app.terminate()
        let nonce = UUID().uuidString
        app.launchArguments = ["-resetForUITests", "-provider-connection-ui", "-provider-ui-nonce", nonce]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if dark { app.launchArguments.append("-provider-ui-dark") }
        app.launch(); tap("openAIConnectionFixture")
        let original = try providerUIReadback("keyboard-opened", nonce: nonce)
        let key = secure ? app.secureTextFields["aiAPIKey"].firstMatch : connectionField("aiModel")
        reveal(key); key.tap()
        _ = try providerUIReadback("keyboard-focused", nonce: nonce)
        let q = app.keys["q"].firstMatch
        let visible = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hittable == true"), object: q)
        let result = XCTWaiter.wait(for: [visible], timeout: 60)
        let structure = XCTAttachment(string: app.debugDescription); structure.name = "provider-visible-keyboard-structure"; structure.lifetime = .keepAlways; add(structure)
        XCTAssertEqual(result, .completed)
        guard result == .completed else { return }
        XCTAssertTrue(app.frame.contains(q.frame)); XCTAssertGreaterThan(q.frame.width, 20); XCTAssertGreaterThan(q.frame.height, 20)
        q.tap()
        let delete = app.keyboards.keys["delete"].firstMatch
        XCTAssertTrue(delete.isHittable); delete.tap(); XCTAssertTrue(q.isHittable); q.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertGreaterThan(keyboard.frame.height, 100); XCTAssertTrue(app.frame.insetBy(dx: -0.5, dy: -0.5).contains(keyboard.frame))
        snap("1260-ai-visible-software-keyboard")
        let typed = try providerUIReadback("keyboard-touched-key", nonce: nonce)
        XCTAssertEqual(typed["recordSHA256"] as? String, original["recordSHA256"] as? String)
        XCTAssertEqual(typed["dirty"] as? Bool, true)
        let done = app.buttons["Done"].firstMatch; XCTAssertTrue(done.isHittable); done.tap()
        XCTAssertFalse(q.isHittable); snap("1261-ai-software-keyboard-done")
        let after = try providerUIReadback("keyboard-done", nonce: nonce)
        XCTAssertEqual(after["recordSHA256"] as? String, original["recordSHA256"] as? String)
        tap("closeAIConnection"); tap("Discard"); tap("openAIConnectionFixture")
        XCTAssertEqual(try providerUIReadback("keyboard-discard-reopened", nonce: nonce)["recordSHA256"] as? String, original["recordSHA256"] as? String)
        let remove = app.buttons["removeAICredentials"].firstMatch; reveal(remove); remove.tap(); tap("Remove")
        let cleaned = try providerUIReadback("keyboard-cleaned", nonce: nonce)
        XCTAssertEqual(cleaned["apiKeyClass"] as? String, "missing"); XCTAssertEqual(cleaned["oauthAccountPresent"] as? Bool, false)
    }

    func testProviderConnectionModesUI() throws { try runProviderConnectionModesUI() }
    func testProviderConnectionModesUILargest() throws { try runProviderConnectionModesUI(large: true) }
    func testProviderConnectionModesUIDark() throws { try runProviderConnectionModesUI(dark: true) }

    func testProviderConnectionChoiceMenuLargest() throws {
        app.terminate()
        let nonce = UUID().uuidString
        app.launchArguments = ["-resetForUITests", "-provider-connection-ui", "-provider-ui-nonce", nonce,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); tap("openAIConnectionFixture")
        let opened = try providerUIReadback("choice-menu-opened", nonce: nonce)
        let mode = app.buttons["aiConnectionMode"].firstMatch; reveal(mode); mode.tap()
        snap("1270-ai-choice-menu-start")
        captureConnectionChoicesEnd(large: true)
        tap("Google OAuth")
        let edited = try providerUIReadback("choice-menu-edited", nonce: nonce)
        XCTAssertEqual(edited["recordSHA256"] as? String, opened["recordSHA256"] as? String)
        XCTAssertEqual(edited["dirty"] as? Bool, true)
        tap("closeAIConnection"); tap("Discard"); tap("openAIConnectionFixture")
        XCTAssertEqual(try providerUIReadback("choice-menu-discarded", nonce: nonce)["recordSHA256"] as? String, opened["recordSHA256"] as? String)
        let remove = app.buttons["removeAICredentials"].firstMatch; reveal(remove); remove.tap(); tap("Remove")
        let cleaned = try providerUIReadback("choice-menu-cleaned", nonce: nonce)
        XCTAssertEqual(cleaned["apiKeyClass"] as? String, "missing"); XCTAssertEqual(cleaned["oauthAccountPresent"] as? Bool, false)
    }

    func captureConnectionChoicesEnd(large: Bool) {
        guard large else { return }
        let menu = app.collectionViews.containing(.button, identifier: "Google OAuth").firstMatch
        XCTAssertTrue(menu.exists)
        // Drag inside the visible middle option. The menu collection's AX
        // frame can extend beyond its actual clipped popup on a small phone.
        let middle = menu.buttons["API key"].firstMatch
        XCTAssertTrue(middle.isHittable)
        middle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            .press(forDuration: 0.1, thenDragTo: middle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)), withVelocity: .slow, thenHoldForDuration: 0)
        snap("1264-ai-connection-choices-end")
        let structure = XCTAttachment(string: app.debugDescription)
        structure.name = "provider-connection-choices-large-structure"; structure.lifetime = .keepAlways; add(structure)
    }

    func testProviderConnectionLongIdentifierEndLargest() throws {
        app.terminate()
        let nonce = UUID().uuidString
        app.launchArguments = ["-resetForUITests", "-provider-connection-ui", "-provider-ui-nonce", nonce,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); tap("openAIConnectionFixture")
        let original = try providerUIReadback("long-identifiers-opened", nonce: nonce)
        replaceConnectionText("aiEndpoint", with: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions", captureEditingEnd: true)
        replaceConnectionText("aiModel", with: "organizations/synthetic-organization-42/models/synthetic-context-generation-v42-large", captureEditingEnd: true)
        let mode = app.buttons["aiConnectionMode"].firstMatch; reveal(mode, towardsTop: true); mode.tap(); tap("Google OAuth")
        replaceConnectionText("aiGoogleClient", with: "123456789012345678901234567890-synthetic42.apps.googleusercontent.com", captureEditingEnd: true)
        let edited = try providerUIReadback("long-identifiers-edited", nonce: nonce)
        XCTAssertEqual(edited["recordSHA256"] as? String, original["recordSHA256"] as? String)
        XCTAssertEqual(edited["dirty"] as? Bool, true)
        tap("closeAIConnection"); tap("Discard"); tap("openAIConnectionFixture")
        XCTAssertEqual(try providerUIReadback("long-identifiers-discarded", nonce: nonce)["recordSHA256"] as? String, original["recordSHA256"] as? String)
        let remove = app.buttons["removeAICredentials"].firstMatch; reveal(remove); remove.tap(); tap("Remove")
        let cleaned = try providerUIReadback("long-identifiers-cleaned", nonce: nonce)
        XCTAssertEqual(cleaned["apiKeyClass"] as? String, "missing"); XCTAssertEqual(cleaned["oauthAccountPresent"] as? Bool, false)
    }

    func connectionField(_ identifier: String) -> XCUIElement {
        if app.textFields[identifier].exists { return app.textFields[identifier].firstMatch }
        if app.textViews[identifier].exists { return app.textViews[identifier].firstMatch }
        return app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    func replaceConnectionText(_ identifier: String, with value: String, captureEditingEnd: Bool = false) {
        let field = connectionField(identifier); reveal(field); field.tap()
        let selectAll = app.buttons["selectAllConnectionText"].firstMatch
        guard selectAll.waitForExistence(timeout: 8) else {
            let structure = XCTAttachment(string: app.debugDescription)
            structure.name = "provider-selection-action-missing-" + identifier
            structure.lifetime = .keepAlways; add(structure)
            snap("1257-ai-selection-action-missing-" + identifier)
            XCTFail("Keyboard Select all action did not appear for " + identifier)
            return
        }
        if let original = field.value as? String, !original.isEmpty {
            XCTAssertTrue(selectAll.isEnabled)
            selectAll.tap()
            snap("1254-ai-keyboard-select-all-" + identifier)
        }
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
        if captureEditingEnd {
            snap("1255-ai-typed-long-end-" + identifier)
            captureConnectionContent(field, name: "1256-ai-long-field-" + identifier, large: true)
            XCTAssertTrue(app.keyboards.firstMatch.exists)
            XCTAssertTrue(app.buttons["Done"].firstMatch.isHittable)
        }
        tap("Done")
    }

    /// Capture literal content through real overlapping gutter pans. This does
    /// not resize text, change the field value or manufacture an ending frame.
    func captureConnectionContent(_ element: XCUIElement, name: String, large: Bool) {
        guard large else { return }
        reveal(element)
        let top = app.navigationBars.firstMatch.frame.maxY + 4
        var bottom = app.frame.maxY - 20
        if app.keyboards.firstMatch.exists {
            bottom = min(bottom, app.keyboards.firstMatch.frame.minY - 8)
            let done = app.buttons["Done"].firstMatch
            if done.exists { bottom = min(bottom, done.frame.minY - 8) }
        }
        XCTAssertGreaterThan(bottom - top, 80)
        func pan(_ offset: CGFloat) {
            let distance = min(max(abs(offset), 40), (bottom - top) * 0.45)
            let start = offset > 0 ? bottom - 12 : top + 12
            let finish = offset > 0 ? start - distance : start + distance
            app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: start))
                .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: finish)), withVelocity: .slow, thenHoldForDuration: 0)
        }
        for _ in 0..<24 {
            let previous = element.frame
            let offset = previous.minY - top
            if abs(offset) < 8 { break }
            pan(offset)
            if abs(element.frame.minY - previous.minY) < 1 { break }
        }
        snap(name + "-start")
        for part in 1...24 {
            let previous = element.frame
            if previous.maxY <= bottom { break }
            pan(previous.maxY - bottom + 8)
            snap(name + "-part-" + String(part))
            if abs(element.frame.minY - previous.minY) < 1 { break }
        }
        XCTAssertLessThanOrEqual(element.frame.maxY, bottom + 2, "Literal content ending must be above fixed controls")
        snap(name + "-end")
    }

    func captureConnectionAlertEnd(_ title: String, name: String, large: Bool) {
        guard large else { return }
        let alert = app.alerts[title].firstMatch
        XCTContext.runActivity(named: "Native large-text alert structure") { activity in
            let attachment = XCTAttachment(string: alert.debugDescription); attachment.name = name + "-structure"; attachment.lifetime = .keepAlways; activity.add(attachment)
        }
        let body = alert.scrollViews.firstMatch
        if body.exists && !body.frame.isEmpty {
            let message = body.staticTexts.firstMatch
            for part in 1...12 {
                let previous = message.exists ? message.frame : .null
                body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8))
                    .press(forDuration: 0.1, thenDragTo: body.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)), withVelocity: .slow, thenHoldForDuration: 0)
                let next = message.exists ? message.frame : .null
                if next == previous { break }
                snap(name + "-message-part-" + String(part))
            }
            body.swipeUp(velocity: .slow); snap(name + "-message-end")
        }
    }

    func runProviderConnectionModesUI(large: Bool = false, dark: Bool = false) throws {
        app.terminate()
        let nonce = UUID().uuidString
        app.launchArguments = ["-resetForUITests", "-provider-connection-ui", "-provider-ui-nonce", nonce]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if dark { app.launchArguments.append("-provider-ui-dark") }
        app.launch(); tap("openAIConnectionFixture")
        let opened = try providerUIReadback("modes-opened", nonce: nonce)
        let original = try XCTUnwrap(opened["recordSHA256"] as? String), account = try XCTUnwrap(opened["oauthAccountSHA256"] as? String)
        let preset = app.buttons["aiConnectionPreset"].firstMatch
        reveal(preset); preset.tap(); settleLabFrame(app.buttons["OpenAI"].firstMatch, pixelTolerance: 1); snap("1230-ai-provider-choices"); tap("OpenAI")
        let endpoint = connectionField("aiEndpoint"); reveal(endpoint)
        XCTAssertEqual(endpoint.value as? String, "https://api.openai.com/v1/chat/completions")
        let model = connectionField("aiModel"); reveal(model)
        XCTAssertTrue(["", "Model"].contains(model.value as? String ?? ""))
        XCTAssertEqual(try providerUIReadback("preset-openai-draft", nonce: nonce)["recordSHA256"] as? String, original)
        reveal(preset, towardsTop: true); preset.tap(); tap("Google AI Studio")
        reveal(endpoint); XCTAssertEqual(endpoint.value as? String, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        reveal(model); XCTAssertEqual(model.value as? String, "gemini-3.8-flash"); snap("1231-ai-google-api-preset-draft")
        let googlePreset = try providerUIReadback("preset-google-draft", nonce: nonce)
        XCTAssertEqual(googlePreset["recordSHA256"] as? String, original)
        XCTAssertEqual(googlePreset["authorizationRevision"] as? String, opened["authorizationRevision"] as? String)
        reveal(preset, towardsTop: true); preset.tap(); tap("Custom")
        replaceConnectionText("aiEndpoint", with: "http://127.0.0.1:48733/chat-b")
        replaceConnectionText("aiModel", with: "synthetic-provider-42-b")
        snap("1232-ai-edited-api-fields")
        let preference = app.switches["preferAIConnection"].firstMatch; reveal(preference, towardsTop: true)
        snap("1250-ai-preference-before-toggle")
        preference.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let preferenceChanged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == '0'"), object: preference)
        let preferenceResult = XCTWaiter.wait(for: [preferenceChanged], timeout: 5)
        snap("1251-ai-preference-after-toggle")
        XCTAssertEqual(preferenceResult, .completed); XCTAssertEqual(preference.value as? String, "0")
        let apiDraft = try providerUIReadback("api-settings-draft", nonce: nonce)
        XCTAssertEqual(apiDraft["recordSHA256"] as? String, original)
        XCTAssertEqual(apiDraft["authorizationRevision"] as? String, opened["authorizationRevision"] as? String)
        XCTAssertEqual(apiDraft["preferExternal"] as? Bool, true); XCTAssertEqual(apiDraft["dirty"] as? Bool, true)
        tap("saveAIConnection")
        let apiSaved = try providerUIReadback("api-settings-saved", nonce: nonce)
        XCTAssertEqual(apiSaved["apiEndpointClass"] as? String, "fixture-b"); XCTAssertEqual(apiSaved["modelClass"] as? String, "fixture-b")
        XCTAssertEqual(apiSaved["preferExternal"] as? Bool, false); XCTAssertEqual(apiSaved["apiKeyClass"] as? String, "fixture-a")
        XCTAssertEqual(apiSaved["oauthAccountSHA256"] as? String, account)
        snap("1233-ai-api-settings-saved")
        captureConnectionContent(app.staticTexts["The key stays in Keychain. Requests go to the saved endpoint."].firstMatch,
                                 name: "1262-ai-key-storage-footer", large: large)
        captureConnectionContent(app.staticTexts.matching(NSPredicate(format: "label == %@", "Requests can include health summaries, selected messages, shared notes and Library excerpts, depending on the feature. Photo requests also depend on your provider and model.")).firstMatch,
                                 name: "1263-ai-content-disclosure", large: large)
        tap("closeAIConnection"); tap("openAIConnectionFixture")
        XCTAssertEqual(try providerUIReadback("api-settings-reopened", nonce: nonce)["recordSHA256"] as? String, apiSaved["recordSHA256"] as? String)
        let mode = app.buttons["aiConnectionMode"].firstMatch; reveal(mode); mode.tap(); settleLabFrame(app.buttons["Google OAuth"].firstMatch, pixelTolerance: 1); snap("1234-ai-connection-choices")
        captureConnectionChoicesEnd(large: large)
        tap("Google OAuth")
        let oauthDraft = try providerUIReadback("oauth-mode-draft", nonce: nonce)
        XCTAssertEqual(oauthDraft["recordSHA256"] as? String, apiSaved["recordSHA256"] as? String); XCTAssertEqual(oauthDraft["mode"] as? String, "key")
        let client = connectionField("aiGoogleClient"); reveal(client); XCTAssertEqual(client.value as? String, "123456789-synthetic42.apps.googleusercontent.com")
        snap("1235-ai-google-draft-fields")
        replaceConnectionText("aiGoogleClient", with: "123456789-synthetic43.apps.googleusercontent.com")
        replaceConnectionText("aiGoogleScopes", with: "openid email")
        replaceConnectionText("aiOAuthEndpoint", with: "http://127.0.0.1:48733/chat-b")
        replaceConnectionText("aiOAuthModel", with: "synthetic-provider-42-b")
        let connect = app.buttons["connectGoogleAI"].firstMatch; reveal(connect)
        XCTAssertFalse(connect.isEnabled); snap("1236-ai-google-unsaved-signin-disabled")
        let oauthFieldsDraft = try providerUIReadback("oauth-settings-draft", nonce: nonce)
        XCTAssertEqual(oauthFieldsDraft["recordSHA256"] as? String, apiSaved["recordSHA256"] as? String)
        XCTAssertEqual(oauthFieldsDraft["dirty"] as? Bool, true)
        for key in ["oauthClientClass", "oauthScopeClass", "oauthEndpointClass", "oauthModelClass"] { XCTAssertEqual(oauthFieldsDraft[key] as? String, "fixture-a") }
        tap("saveAIConnection")
        let oauthSaved = try providerUIReadback("oauth-settings-saved", nonce: nonce)
        XCTAssertEqual(oauthSaved["mode"] as? String, "oauth")
        for key in ["oauthClientClass", "oauthScopeClass", "oauthEndpointClass", "oauthModelClass"] { XCTAssertEqual(oauthSaved[key] as? String, "fixture-b") }
        XCTAssertEqual(oauthSaved["oauthAccountSHA256"] as? String, account)
        XCTAssertEqual(oauthSaved["configured"] as? Bool, false)
        reveal(connect); XCTAssertTrue(connect.isEnabled); snap("1237-ai-google-saved-signin-available")
        captureConnectionContent(app.staticTexts.matching(NSPredicate(format: "label == %@", "Use an iOS client configured for this app. The endpoint must accept that client's tokens and requested scopes. Google sign-in alone doesn't grant access to every AI service.")).firstMatch,
                                 name: "1265-ai-google-configuration-footer", large: large)
        tap("closeAIConnection"); tap("openAIConnectionFixture")
        let oauthReopened = try providerUIReadback("oauth-settings-reopened", nonce: nonce)
        XCTAssertEqual(oauthReopened["recordSHA256"] as? String, oauthSaved["recordSHA256"] as? String)
        for (identifier, value) in [("aiGoogleClient", "123456789-synthetic43.apps.googleusercontent.com"), ("aiGoogleScopes", "openid email"), ("aiOAuthEndpoint", "http://127.0.0.1:48733/chat-b"), ("aiOAuthModel", "synthetic-provider-42-b")] {
            let field = connectionField(identifier); reveal(field); XCTAssertEqual(field.value as? String, value)
        }
        snap("1238-ai-google-reopened-fields")
        reveal(mode, towardsTop: true); mode.tap(); tap("Apple or built-in")
        XCTAssertEqual(try providerUIReadback("builtin-mode-draft", nonce: nonce)["recordSHA256"] as? String, oauthSaved["recordSHA256"] as? String)
        snap("1239-ai-builtin-unsaved")
        tap("saveAIConnection")
        let builtIn = try providerUIReadback("builtin-mode-saved", nonce: nonce)
        XCTAssertEqual(builtIn["mode"] as? String, "onDevice"); XCTAssertEqual(builtIn["configured"] as? Bool, false)
        XCTAssertEqual(builtIn["apiKeyClass"] as? String, "fixture-a"); XCTAssertEqual(builtIn["oauthAccountSHA256"] as? String, account)
        let detail = app.staticTexts["Uses built-in coaching. Apple Intelligence isn't available right now."].firstMatch
        reveal(detail); XCTAssertTrue(detail.exists); snap("1240-ai-builtin-available-assistant")
        captureConnectionContent(detail, name: "1266-ai-builtin-detail", large: large)
        captureConnectionContent(app.staticTexts["Photo recognition, Not available"].firstMatch,
                                 name: "1267-ai-photo-capability", large: large)
        tap("closeAIConnection"); tap("openAIConnectionFixture")
        XCTAssertEqual(try providerUIReadback("builtin-reopened", nonce: nonce)["recordSHA256"] as? String, builtIn["recordSHA256"] as? String)
        reveal(mode, towardsTop: true); mode.tap(); tap("API key")
        let restoredEndpoint = connectionField("aiEndpoint"); reveal(restoredEndpoint); XCTAssertEqual(restoredEndpoint.value as? String, "http://127.0.0.1:48733/chat-b")
        let restoredModel = connectionField("aiModel"); reveal(restoredModel); XCTAssertEqual(restoredModel.value as? String, "synthetic-provider-42-b")
        snap("1241-ai-api-draft-restored"); tap("saveAIConnection")
        let restored = try providerUIReadback("api-mode-restored", nonce: nonce)
        XCTAssertEqual(restored["mode"] as? String, "key"); XCTAssertEqual(restored["apiKeyClass"] as? String, "fixture-a")
        XCTAssertEqual(restored["apiEndpointClass"] as? String, "fixture-b"); XCTAssertEqual(restored["modelClass"] as? String, "fixture-b")
        XCTAssertEqual(restored["preferExternal"] as? Bool, false); XCTAssertEqual(restored["oauthAccountSHA256"] as? String, account)
        let remove = app.buttons["removeAICredentials"].firstMatch; reveal(remove); remove.tap(); tap("Remove")
        let removed = try providerUIReadback("modes-cleaned", nonce: nonce)
        XCTAssertEqual(removed["apiKeyClass"] as? String, "missing"); XCTAssertEqual(removed["oauthAccountPresent"] as? Bool, false)
        XCTAssertEqual(removed["configured"] as? Bool, false)
    }

    func runProviderConnectionDraftUI(large: Bool = false, dark: Bool = false) throws {
        app.terminate()
        let nonce = UUID().uuidString
        app.launchArguments = ["-resetForUITests", "-provider-connection-ui", "-provider-ui-nonce", nonce, "-provider-ui-fail-save"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if dark { app.launchArguments.append("-provider-ui-dark") }
        app.launch()
        XCTAssertTrue(app.buttons["openAIConnectionFixture"].waitForExistence(timeout: 10))
        let beforeOpen = try providerUIReadback("before-open", nonce: nonce)
        tap("openAIConnectionFixture")
        XCTAssertTrue(app.staticTexts["savedAIOrigin"].waitForExistence(timeout: 10))
        let opened = try providerUIReadback("opened", nonce: nonce)
        XCTAssertEqual(opened["apiKeyClass"] as? String, "fixture-a")
        XCTAssertEqual(opened["endpoint"] as? String, "fixed-loopback")
        XCTAssertEqual(opened["preset"] as? String, "custom")
        XCTAssertEqual(opened["dirty"] as? Bool, false)
        let original = try XCTUnwrap(opened["recordSHA256"] as? String)
        XCTAssertEqual(opened["authorizationRevision"] as? String, beforeOpen["authorizationRevision"] as? String)
        XCTAssertEqual(original, beforeOpen["recordSHA256"] as? String)
        snap("1208-ai-connection-opened")
        let key = app.secureTextFields["aiAPIKey"].firstMatch
        reveal(key); key.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        key.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 100)); key.typeText("synthetic-key-42-b")
        snap("1209-ai-connection-keyboard-draft")
        tap("Done")
        let typed = try providerUIReadback("typed", nonce: nonce)
        XCTAssertEqual(typed["recordSHA256"] as? String, original)
        XCTAssertEqual(typed["apiKeyClass"] as? String, "fixture-a")
        XCTAssertEqual(typed["dirty"] as? Bool, true)
        XCTAssertEqual(typed["authorizationRevision"] as? String, opened["authorizationRevision"] as? String)
        tap("closeAIConnection")
        XCTAssertTrue(app.alerts["Discard connection edits?"].waitForExistence(timeout: 5))
        snap("1210-ai-connection-discard-confirmation")
        captureConnectionAlertEnd("Discard connection edits?", name: "1246-ai-discard", large: large); tap("Keep draft")
        let kept = try providerUIReadback("kept-draft", nonce: nonce)
        XCTAssertEqual(kept["recordSHA256"] as? String, original)
        XCTAssertEqual(kept["dirty"] as? Bool, true)
        tap("saveAIConnection")
        let issue = app.staticTexts["aiConnectionIssue"].firstMatch
        reveal(issue, towardsTop: true); XCTAssertTrue(issue.waitForExistence(timeout: 5))
        snap("1211-ai-connection-failed-save")
        let retainedModel = app.descendants(matching: .any).matching(identifier: "aiModel").firstMatch
        reveal(retainedModel); snap("1229-ai-failed-save-retained-fields")
        let failed = try providerUIReadback("failed-save", nonce: nonce)
        XCTAssertEqual(failed["recordSHA256"] as? String, original)
        XCTAssertEqual(failed["apiKeyClass"] as? String, "fixture-a")
        XCTAssertEqual(failed["dirty"] as? Bool, true)
        tap("saveAIConnection")
        XCTAssertFalse(app.staticTexts["aiConnectionIssue"].exists)
        let saved = try providerUIReadback("saved", nonce: nonce)
        XCTAssertEqual(saved["apiKeyClass"] as? String, "fixture-b")
        XCTAssertNotEqual(saved["recordSHA256"] as? String, original)
        XCTAssertEqual(saved["dirty"] as? Bool, false)
        XCTAssertEqual(saved["configured"] as? Bool, true)
        snap("1212-ai-connection-saved")
        let testSaved = app.buttons["testSavedAIConnection"].firstMatch; reveal(testSaved); testSaved.tap()
        let testResult = app.staticTexts["aiConnectionTestResult"].firstMatch
        XCTAssertTrue(testResult.waitForExistence(timeout: 15)); XCTAssertEqual(testResult.label, "Lumen AI link OK")
        let tested = try providerUIReadback("tested-saved", nonce: nonce)
        XCTAssertEqual(tested["recordSHA256"] as? String, saved["recordSHA256"] as? String)
        XCTAssertEqual(tested["testResultClass"] as? String, "success")
        snap("1216-ai-saved-connection-tested")
        tap("closeAIConnection"); tap("openAIConnectionFixture")
        let reopened = try providerUIReadback("reopened", nonce: nonce)
        XCTAssertEqual(reopened["recordSHA256"] as? String, saved["recordSHA256"] as? String)
        app.terminate(); app.launchArguments.append("-provider-connection-ui-resume"); app.launch(); tap("openAIConnectionFixture")
        let relaunched = try providerUIReadback("relaunched", nonce: nonce)
        XCTAssertEqual(relaunched["recordSHA256"] as? String, saved["recordSHA256"] as? String)
        XCTAssertNotEqual(relaunched["pid"] as? Int, opened["pid"] as? Int)
        snap("1213-ai-connection-relaunched")
        let remove = app.buttons["removeAICredentials"].firstMatch; reveal(remove); remove.tap()
        XCTAssertTrue(app.alerts["Remove AI credentials?"].waitForExistence(timeout: 5)); snap("1214-ai-credential-removal-confirmation")
        captureConnectionAlertEnd("Remove AI credentials?", name: "1247-ai-remove", large: large); tap("Remove")
        let removed = try providerUIReadback("removed", nonce: nonce)
        XCTAssertEqual(removed["apiKeyClass"] as? String, "missing")
        XCTAssertEqual(removed["oauthAccountPresent"] as? Bool, false)
        XCTAssertEqual(removed["legacyAPIKeyPresent"] as? Bool, false)
        XCTAssertEqual(removed["mode"] as? String, "onDevice")
        XCTAssertEqual(removed["configured"] as? Bool, false)
        snap("1215-ai-credentials-removed")
    }

    func editSyntheticConnectionKey() {
        let key = app.secureTextFields["aiAPIKey"].firstMatch
        reveal(key); key.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        key.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 100)); key.typeText("synthetic-key-42-b"); tap("Done")
    }

    func testProviderConnectionRecoveryUI() throws { try runProviderConnectionRecoveryUI() }
    func testProviderConnectionRecoveryUILargest() throws { try runProviderConnectionRecoveryUI(large: true) }
    func testProviderConnectionRecoveryUIDark() throws { try runProviderConnectionRecoveryUI(dark: true) }

    func runProviderConnectionRecoveryUI(large: Bool = false, dark: Bool = false) throws {
        for mode in ["cleanup", "remove", "stale", "discard"] {
            app.terminate()
            let nonce = UUID().uuidString
            app.launchArguments = ["-resetForUITests", "-provider-connection-ui", "-provider-ui-nonce", nonce]
            if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
            if dark { app.launchArguments.append("-provider-ui-dark") }
            if mode != "discard" { app.launchArguments.append(mode == "stale" ? "-provider-ui-stale-save" : "-provider-ui-fail-" + mode) }
            app.launch(); tap("openAIConnectionFixture")
            XCTAssertTrue(app.staticTexts["savedAIOrigin"].waitForExistence(timeout: 10))
            let before = try providerUIReadback(mode + "-opened", nonce: nonce)
            if mode == "remove" {
                let remove = app.buttons["removeAICredentials"].firstMatch; reveal(remove); remove.tap(); tap("Remove")
                let retry = app.buttons["retryAICredentialRemoval"].firstMatch; reveal(retry, towardsTop: true); XCTAssertTrue(retry.waitForExistence(timeout: 5))
            } else {
                editSyntheticConnectionKey()
                if mode == "discard" {
                    tap("closeAIConnection"); tap("Discard"); tap("openAIConnectionFixture")
                    let after = try providerUIReadback("discard-reopened", nonce: nonce)
                    XCTAssertEqual(after["recordSHA256"] as? String, before["recordSHA256"] as? String); XCTAssertEqual(after["dirty"] as? Bool, false)
                    snap("1224-ai-draft-discarded")
                } else {
                    if mode == "stale" {
                        let savedStatus = app.staticTexts["savedAIStatus"].firstMatch; reveal(savedStatus, towardsTop: true)
                        let changed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS 'synthetic-provider-42-b'"), object: savedStatus)
                        XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 10), .completed)
                    }
                    tap("saveAIConnection")
                    let issue = app.staticTexts["aiConnectionIssue"].firstMatch; reveal(issue, towardsTop: true); XCTAssertTrue(issue.waitForExistence(timeout: 5))
                }
            }
            if mode == "cleanup" || mode == "remove" {
                let pending = try providerUIReadback(mode + "-pending", nonce: nonce)
                XCTAssertEqual(pending[mode == "cleanup" ? "legacyCleanupPending" : "keyRemovalPending"] as? Bool, true)
                XCTAssertEqual(pending["configured"] as? Bool, false)
                XCTAssertEqual(pending["apiKeyClass"] as? String, mode == "cleanup" ? "fixture-b" : "fixture-a")
                snap(mode == "cleanup" ? "1217-ai-cleanup-pending" : "1220-ai-removal-pending")
                captureConnectionContent(app.staticTexts["aiConnectionIssue"].firstMatch,
                                         name: "1271-ai-" + mode + "-issue", large: large)
                app.terminate(); app.launchArguments.append("-provider-connection-ui-resume"); app.launch(); tap("openAIConnectionFixture")
                let resumed = try providerUIReadback(mode + "-resumed", nonce: nonce)
                XCTAssertEqual(resumed["recordSHA256"] as? String, pending["recordSHA256"] as? String)
                XCTAssertNotEqual(resumed["pid"] as? Int, pending["pid"] as? Int)
                XCTAssertEqual(resumed["configured"] as? Bool, false)
                let retry = app.buttons[mode == "cleanup" ? "retryAIConnectionCleanup" : "retryAICredentialRemoval"].firstMatch
                reveal(retry); snap(mode == "cleanup" ? "1218-ai-cleanup-after-restart" : "1221-ai-removal-after-restart"); retry.tap()
                let recovered = try providerUIReadback(mode + "-retried", nonce: nonce)
                XCTAssertEqual(recovered["legacyCleanupPending"] as? Bool, false); XCTAssertEqual(recovered["keyRemovalPending"] as? Bool, false)
                XCTAssertEqual(recovered["legacyAPIKeyPresent"] as? Bool, false)
                XCTAssertEqual(recovered["apiKeyClass"] as? String, mode == "cleanup" ? "fixture-b" : "missing")
                XCTAssertEqual(recovered["configured"] as? Bool, mode == "cleanup")
                snap(mode == "cleanup" ? "1219-ai-cleanup-retried" : "1222-ai-removal-retried")
            }
            if mode == "stale" {
                let stale = try providerUIReadback("stale-rejected", nonce: nonce)
                XCTAssertEqual(stale["modelClass"] as? String, "fixture-b"); XCTAssertEqual(stale["apiKeyClass"] as? String, "fixture-a")
                XCTAssertEqual(stale["dirty"] as? Bool, true)
                snap("1243-ai-stale-save-rejected")
                captureConnectionContent(app.staticTexts["aiConnectionIssue"].firstMatch,
                                         name: "1272-ai-stale-issue", large: large)
                let reload = app.buttons["reloadAIConnection"].firstMatch; reveal(reload); reload.tap(); tap("Keep draft")
                XCTAssertEqual(try providerUIReadback("stale-kept", nonce: nonce)["dirty"] as? Bool, true)
                XCTAssertFalse(app.buttons["saveAIConnection"].isEnabled)
                snap("1244-ai-stale-draft-kept")
                reload.tap(); snap("1223-ai-stale-reload-confirmation")
                captureConnectionAlertEnd("Reload saved connection?", name: "1248-ai-reload", large: large); tap("Reload")
                let reloaded = try providerUIReadback("stale-reloaded", nonce: nonce)
                XCTAssertEqual(reloaded["recordSHA256"] as? String, stale["recordSHA256"] as? String); XCTAssertEqual(reloaded["dirty"] as? Bool, false)
                snap("1245-ai-stale-reloaded")
            }
            let remove = app.buttons["removeAICredentials"].firstMatch; reveal(remove); remove.tap(); tap("Remove")
            let cleaned = try providerUIReadback(mode + "-cleaned", nonce: nonce)
            XCTAssertEqual(cleaned["apiKeyClass"] as? String, "missing"); XCTAssertEqual(cleaned["oauthAccountPresent"] as? Bool, false)
        }
    }

    func testProviderConnectionStorage() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-provider-authorization-checks", "-provider-connection-checks"]
        app.launch()
        let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Connection storage checks'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 60), .completed)
        XCTAssertEqual(status.label, "Connection storage checks passed")
        snap("1207-provider-connection-storage-checks")
    }

    func testProviderCallerChecks() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-provider-authorization-checks", "-provider-caller-checks"]
        app.launch()
        let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Provider caller checks'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 120), .completed)
        XCTAssertEqual(status.label, "Provider caller checks passed")
        snap("1206-provider-caller-checks")
    }

    func testProviderTokenTransportChecks() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-provider-authorization-checks", "-provider-token-transport-checks"]
        app.launch()
        let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Token transport checks'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 120), .completed)
        XCTAssertEqual(status.label, "Token transport checks passed")
        snap("1228-provider-token-transport-checks")
    }

    func testProviderRemovalRelaunch() throws {
        for mode in ["oauth", "all", "key"] {
            for phase in ["prepare", "resume"] {
                app.terminate()
                app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-provider-authorization-checks", "-provider-removal-relaunch", "-provider-removal-" + mode]
                if phase == "resume" { app.launchArguments.append("-provider-removal-resume") }
                app.launch()
                let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
                let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Credential removal relaunch checks'"), object: status)
                XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 30), .completed)
                XCTAssertEqual(status.label, "Credential removal relaunch checks passed: " + mode + " " + phase)
            }
        }
        snap("1205-provider-removal-relaunch-checks")
    }

    func testProviderAccountResetRelaunch() throws {
        for mode in ["failure", "after-secrets"] {
            for phase in ["prepare", "resume"] {
                app.terminate()
                app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-provider-authorization-checks", "-provider-reset-checks", "-provider-reset-" + mode]
                if phase == "resume" { app.launchArguments.append("-provider-reset-resume") }
                app.launch()
                let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
                let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Account reset checks'"), object: status)
                XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 45), .completed)
                XCTAssertEqual(status.label, "Account reset checks passed: " + mode + " " + phase)
                snap("1225-reset-" + mode + "-" + phase)
            }
        }
    }

    func testProviderAccountResetUI() throws { try runProviderAccountResetUI() }
    func testProviderAccountResetUILargest() throws { try runProviderAccountResetUI(large: true) }
    func testProviderAccountResetUIDark() throws { try runProviderAccountResetUI(dark: true) }

    func runProviderAccountResetUI(large: Bool = false, dark: Bool = false) throws {
        app.terminate()
        let nonce = UUID().uuidString
        app.launchArguments = ["-resetForUITests", "-provider-connection-ui", "-provider-ui-nonce", nonce, "-provider-ui-fail-reset"]
        if large { app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] }
        if dark { app.launchArguments.append("-provider-ui-dark") }
        app.launch(); tap("openAIConnectionFixture")
        let before = try providerUIReadback("reset-before", nonce: nonce)
        let erase = app.buttons["eraseAllLumenData"].firstMatch; reveal(erase); erase.tap(); tap("Erase everything")
        XCTAssertTrue(app.alerts["Couldn't erase Lumen"].waitForExistence(timeout: 10))
        snap("1226-reset-credential-failure")
        captureConnectionAlertEnd("Couldn't erase Lumen", name: "1249-reset-failure", large: large)
        let failed = try providerUIReadback("reset-failed", nonce: nonce)
        XCTAssertEqual(failed["profileSHA256"] as? String, before["profileSHA256"] as? String)
        XCTAssertEqual(failed["recordSHA256"] as? String, before["recordSHA256"] as? String)
        XCTAssertEqual(failed["globalRemovalPending"] as? Bool, true)
        XCTAssertEqual(failed["configured"] as? Bool, false)
        tap("Not now"); app.terminate(); app.launchArguments.append("-provider-connection-ui-resume"); app.launch(); tap("openAIConnectionFixture")
        let resumed = try providerUIReadback("reset-resumed", nonce: nonce)
        XCTAssertNotEqual(resumed["pid"] as? Int, failed["pid"] as? Int)
        XCTAssertEqual(resumed["profileContentSHA256"] as? String, failed["profileContentSHA256"] as? String)
        XCTAssertEqual(resumed["recordSHA256"] as? String, failed["recordSHA256"] as? String)
        XCTAssertEqual(resumed["globalRemovalPending"] as? Bool, true)
        let retryErase = app.buttons["eraseAllLumenData"].firstMatch; reveal(retryErase); retryErase.tap(); tap("Erase everything")
        XCTAssertTrue(app.buttons["openAIConnectionFixture"].waitForExistence(timeout: 10))
        let done = try providerUIReadback("reset-complete", nonce: nonce)
        XCTAssertNotEqual(done["profileSHA256"] as? String, before["profileSHA256"] as? String)
        XCTAssertEqual(done["apiKeyClass"] as? String, "missing")
        XCTAssertEqual(done["oauthAccountPresent"] as? Bool, false)
        XCTAssertEqual(done["globalRemovalPending"] as? Bool, false)
        XCTAssertEqual(done["configured"] as? Bool, false)
        snap("1227-reset-retry-complete")
    }

    func testProviderSignInChecks() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-provider-authorization-checks", "-provider-signin-checks"]
        app.launch()
        let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Provider sign-in checks'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        XCTAssertEqual(status.label, "Provider sign-in checks passed")
        snap("1204-provider-signin-checks")
    }

    func testPersonalContextNativeProvenance() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-personal-provenance-probe", "-quick-save-fault", "conversations.json:3"]
        app.launch()
        let status = app.staticTexts["personalProvenanceProbeStatus"].firstMatch
        let completed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label BEGINSWITH 'Personal context checks passed' OR label BEGINSWITH 'Personal context checks failed'"), object: status)
        XCTAssertEqual(XCTWaiter.wait(for: [completed], timeout: 90), .completed)
        XCTAssertEqual(status.label, "Personal context checks passed")
        snap("1080-personal-context-native-provenance")
    }

    func personalRequestAudit() throws -> [[String: Any]] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: conversationControl("/personal-audit")) as? [[String: Any]])
    }
    func waitPersonalRequest(_ count: Int) throws {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if try personalRequestAudit().count >= count { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTFail("The actual synthetic personal request did not arrive")
        throw URLError(.timedOut)
    }
    func personalCanary(_ packet: [String: Any], _ name: String, role: String) throws -> Int {
        let canaries = try XCTUnwrap(packet["canaries"] as? [String: [String: Int]])
        return try XCTUnwrap(canaries[name]?[role])
    }
    func savedPersonalNote() -> XCUIElement {
        app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'savedPersonalContext-' ")).firstMatch
    }
    func saveSyntheticPersonalNotes() {
        openPersonalPreferences()
        let field = app.descendants(matching: .any).matching(identifier: "personalFocus").firstMatch
        reveal(field); field.tap(); field.typeText("SYNTHETIC-PERSONAL-NOTE-40-A")
        finishContextInput(); nativeSwitch("personalContextSharing", enabled: true); tap("savePersonalContext")
        XCTAssertTrue(app.navigationBars["Personal context"].waitForNonExistence(timeout: 5)); tap("Done"); tab("Assistant")
    }
    func openPersonalNotesFromAssistant() {
        tab("Today"); openPersonalPreferences()
    }
    func withdrawSyntheticPersonalNotes() {
        openPersonalNotesFromAssistant()
        nativeSwitch("personalContextSharing", enabled: false); tap("savePersonalContext")
        XCTAssertTrue(app.navigationBars["Personal context"].waitForNonExistence(timeout: 5)); tap("Done"); tab("Assistant")
    }
    func testPersonalContextPendingRetryUI() throws { try personalContextPendingRetryUI(large: false) }
    func testPersonalContextPendingRetryUILarge() throws { try personalContextPendingRetryUI(large: true) }
    func personalContextPendingRetryUI(large: Bool) throws {
        app.launchEnvironment["LUMEN_PERSONAL_TEST_NONCE"] = UUID().uuidString
        quickFault("conversations.json:3", large: large, extra: ["-personal-provenance-ui"])
        let before = try personalRequestAudit().count
        saveSyntheticPersonalNotes()
        enterConversationQuestion("SYNTHETIC-PERSONAL-COMPLETE-40")
        let alert = app.alerts["Couldn’t save reply"]
        XCTAssertTrue(alert.waitForExistence(timeout: 20)); alert.buttons["OK"].tap()
        let pending = app.staticTexts["unsavedConversationReply"].firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 5))
        let note = app.descendants(matching: .any).matching(identifier: "pendingPersonalContext").firstMatch
        XCTAssertEqual(note.label, "Used your shared personal notes.")
        let exactReply = coachMessages.firstMatch.label
        capturePendingConversationReply("1081-pending-current-personal-notes")
        withdrawSyntheticPersonalNotes()
        XCTAssertEqual(note.label, "Used earlier personal notes. This reply isn’t included with new questions. Retry saves this same reply.")
        capturePendingConversationReply("1082-pending-earlier-personal-notes")
        let retry = app.buttons["retryConversationReply"].firstMatch; reveal(retry); retry.tap()
        XCTAssertTrue(pending.waitForNonExistence(timeout: 10)); XCTAssertEqual(coachMessages.firstMatch.label, exactReply)
        let saved = savedPersonalNote()
        XCTAssertTrue(saved.waitForExistence(timeout: 10))
        XCTAssertEqual(saved.label, "Used earlier personal notes. This reply isn’t included with new questions.")
        let saveID = "saveReplyToLibrary-" + String(saved.identifier.dropFirst("savedPersonalContext-".count))
        captureConversationSection(heading: saved.identifier, action: saveID, prefix: "1083-saved-earlier-personal-notes")
        XCTAssertEqual(try personalRequestAudit().count, before + 1, "Storage retry must not send a second provider request")
        tap("Quote in new question")
        let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
        XCTAssertTrue((input.value as? String)?.contains(exactReply) == true)
        XCTAssertTrue((input.value as? String)?.hasSuffix("My question: ") == true)
        XCTAssertEqual(try personalRequestAudit().count, before + 1, "Quoting prepares an editable draft without sending")
        snap("1084-earlier-personal-reply-unsent-quote")
        relaunchPersonalConversations(large: large); tab("Assistant")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(coachMessages.firstMatch.label, exactReply)
        XCTAssertEqual(savedPersonalNote().label, "Used earlier personal notes. This reply isn’t included with new questions.")
        captureConversationSection(heading: savedPersonalNote().identifier, action: saveID, prefix: "1085-earlier-personal-reply-relaunch")
        let audit = try personalRequestAudit()
        XCTAssertEqual(try personalCanary(audit[before], "noteA", role: "system"), 1)
        enterConversationQuestion("SYNTHETIC-PERSONAL-COMPLETE-40")
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.coachMessages.count == 2 }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 20), .completed)
        let afterRelaunch = try personalRequestAudit()
        XCTAssertEqual(afterRelaunch.count, before + 2)
        XCTAssertEqual(try personalCanary(afterRelaunch[before + 1], "noteA", role: "system"), 0)
        XCTAssertEqual(try personalCanary(afterRelaunch[before + 1], "returned", role: "assistant"), 0)
        snap("1093-actual-outgoing-after-personal-note-relaunch")
    }

    func relaunchPersonalConversations(large: Bool) {
        app.terminate()
        app.launchArguments = ["-personal-provenance-ui", "-lumen.appearance", large ? "dark" : "light"]
            + (large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
        app.launch()
    }

    func testPersonalContextHeldEditorUI() throws { try personalContextHeldEditorUI(large: false) }
    func testPersonalContextHeldEditorUILarge() throws { try personalContextHeldEditorUI(large: true) }
    func personalContextHeldEditorUI(large: Bool) throws {
        app.launchEnvironment["LUMEN_PERSONAL_TEST_NONCE"] = UUID().uuidString
        quickFault("none:0", large: large, extra: ["-personal-provenance-ui"])
        var holding = false
        defer { if holding { _ = try? conversationControl("/release-personal") } }
        let before = try personalRequestAudit().count
        saveSyntheticPersonalNotes()
        _ = try conversationControl("/arm-personal")
        holding = true
        enterConversationQuestion("SYNTHETIC-PERSONAL-HELD-40")
        try waitPersonalRequest(before + 1)
        XCTAssertTrue(app.buttons["Stop response"].exists)
        openPersonalNotesFromAssistant()
        let field = app.descendants(matching: .any).matching(identifier: "personalFocus").firstMatch
        reveal(field); field.tap(); field.typeText(" SYNTHETIC-PERSONAL-UNSAVED-40")
        snap("1086-held-response-editor-actual-focus-draft")
        finishContextInput()
        XCTAssertTrue((field.value as? String)?.contains("SYNTHETIC-PERSONAL-UNSAVED-40") == true)
        XCTAssertTrue(app.buttons["savePersonalContext"].isEnabled)
        let unsaved = app.staticTexts["personalContextUnsaved"].firstMatch; reveal(unsaved); XCTAssertTrue(unsaved.exists)
        XCTAssertEqual(app.staticTexts["personalContextSavedSharing"].label, "Saved sharing: On")
        snap("1086-held-response-editor-unsaved-notes")
        _ = try conversationControl("/release-personal")
        holding = false
        capturePreferenceDisclosure("personalContextSavedSharing", prefix: "1086-held-editor-saved-sharing")
        capturePreferenceDisclosure("personalContextHistoryDisclosure", prefix: "1086-held-editor-full-history-disclosure")
        tap("Cancel"); let discard = app.alerts["Discard context changes?"]
        XCTAssertTrue(discard.waitForExistence(timeout: 5)); discard.buttons["Discard"].tap()
        XCTAssertTrue(app.navigationBars["Personal context"].waitForNonExistence(timeout: 5)); tap("Done"); tab("Assistant")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 15))
        XCTAssertEqual(coachMessages.firstMatch.label, "SYNTHETIC-PERSONAL-REPLY-40")
        XCTAssertEqual(savedPersonalNote().label, "Used your shared personal notes.")
        captureConversationSection(heading: savedPersonalNote().identifier, action: "Save to Library", prefix: "1087-unsaved-editor-does-not-change-reply")
        _ = try conversationControl("/arm-personal")
        holding = true
        enterConversationQuestion("Make a plan SYNTHETIC-PERSONAL-HELD-40")
        try waitPersonalRequest(before + 2)
        withdrawSyntheticPersonalNotes()
        _ = try conversationControl("/release-personal")
        holding = false
        let notice = coachMessages.matching(NSPredicate(format: "label CONTAINS %@", "This reply wasn't kept")).firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 15))
        XCTAssertEqual(coachMessages.count, 2)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'savedReplyProvider-' AND label == 'Lumen notice' ")).firstMatch.exists)
        let noticeText = coachMessages.element(boundBy: 1)
        XCTAssertEqual(noticeText.label, notice.label)
        captureIdentifierText(noticeText, prefix: "1088-complete-changed-note-notice", contentGestures: true)
        snap("1088-saved-withdrawal-discards-held-plan-reply")
        tab("Library")
        XCTAssertTrue(app.staticTexts["Keep what matters"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).count, 0)
        snap("1089-changed-note-notice-has-no-plan-copy"); tab("Assistant")
        enterConversationQuestion("SYNTHETIC-PERSONAL-COMPLETE-40")
        let complete = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in self.coachMessages.count == 3 }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [complete], timeout: 15), .completed)
        let noNotes = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'savedPersonalContext-' AND label == 'No personal notes used.' ")).firstMatch
        XCTAssertTrue(noNotes.waitForExistence(timeout: 15)); snap("1090-withdrawn-notes-next-question")
        let audit = try personalRequestAudit()
        XCTAssertEqual(audit.count, before + 3)
        XCTAssertEqual(try personalCanary(audit[before], "noteA", role: "system"), 1)
        XCTAssertEqual(try personalCanary(audit[before], "unsaved", role: "system"), 0)
        XCTAssertEqual(try personalCanary(audit[before + 2], "noteA", role: "system"), 0)
        XCTAssertEqual(try personalCanary(audit[before + 2], "returned", role: "assistant"), 0)
        relaunchPersonalConversations(large: large); tab("Assistant")
        XCTAssertTrue(coachMessages.firstMatch.waitForExistence(timeout: 10)); XCTAssertEqual(coachMessages.count, 3)
        XCTAssertEqual(savedPersonalNote().label, "Used earlier personal notes. This reply isn’t included with new questions.")
        snap("1091-note-provenance-history-relaunch")
    }

    func testPersonalContextUnknownHistoryUI() throws { try personalContextUnknownHistoryUI(large: false) }
    func testPersonalContextUnknownHistoryUILarge() throws { try personalContextUnknownHistoryUI(large: true) }
    func personalContextUnknownHistoryUI(large: Bool) throws {
        for mode in ["legacy", "invalid", "unknownSources"] {
            app.terminate()
            app.launchEnvironment["LUMEN_PERSONAL_TEST_NONCE"] = UUID().uuidString
            app.launchArguments = ["-resetForUITests", "-personal-provenance-ui", "-personal-provenance-history-fixture", mode,
                "-lumen.appearance", large ? "dark" : "light"]
                + (large ? ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : [])
            app.launch(); tab("Assistant")
            let before = try personalRequestAudit().count
            let note = app.descendants(matching: .any).matching(identifier: "savedPersonalContext-synthetic-personal-history-reply-40").firstMatch
            XCTAssertTrue(note.waitForExistence(timeout: 10))
            XCTAssertEqual(note.label, mode == "unknownSources" ? "No personal notes used." : "Whether this reply used personal notes isn’t recorded. It isn’t included with new questions.")
            let quoteID = "quoteReply-synthetic-personal-history-reply-40"
            captureConversationSection(heading: note.identifier, action: "saveReplyToLibrary-synthetic-personal-history-reply-40", prefix: "1094-unknown-personal-provenance-" + mode)
            if mode == "unknownSources" { XCTAssertTrue(app.staticTexts["Sources weren’t recorded for this reply. It isn’t included with new questions."].exists) }
            tap(quoteID)
            let input = app.descendants(matching: .any).matching(identifier: "coachInput").firstMatch
            XCTAssertTrue((input.value as? String)?.contains("Synthetic earlier reply with \(mode) provenance.") == true)
            XCTAssertTrue((input.value as? String)?.hasSuffix("My question: ") == true)
            XCTAssertEqual(try personalRequestAudit().count, before, "Unknown provenance never automatically sends an explicit quote")
            snap("1095-unknown-personal-provenance-unsent-quote-" + mode)
        }
    }

    func testPersonalContextPlanRevisionUI() throws { try personalContextPlanRevisionUI(large: false) }
    func testPersonalContextPlanRevisionUILarge() throws { try personalContextPlanRevisionUI(large: true) }
    func testPersonalContextRetainedPlanEditorUILarge() throws { try personalContextPlanRevisionUI(large: true, captureEditor: true) }
    func personalContextPlanRevisionUI(large: Bool, captureEditor: Bool = false) throws {
        for mode in ["context-change", "context-revert"] {
            quickFault("none:0", large: large, extra: ["-scheduledPlanUITestFixture", mode])
            saveSyntheticPersonalNotes()
            let before = try personalRequestAudit().count
            openScheduledPlan()
            let goal = "Keep a flexible synthetic routine."
            enterPlanGoal(goal)
            let duration = app.buttons["scheduledPlanWeeks"].firstMatch
            reveal(duration); duration.tap(); tap("4 weeks")
            let end = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Through '")).firstMatch
            reveal(end); let originalEnd = end.label
            XCTAssertTrue(originalEnd.hasPrefix("Through "))
            reveal(app.buttons["prepareScheduledPlan"].firstMatch); tap("prepareScheduledPlan")
            let error = app.staticTexts["scheduledPlanError"].firstMatch
            // At the largest type size on the compact phone, the provider
            // disclosure fills the viewport before this lazy Form row.
            // Bring the warning into view before querying its exact wording.
            reveal(error)
            XCTAssertTrue(error.waitForExistence(timeout: 10))
            XCTAssertEqual(error.label, "Your personal context changed while preparing. Prepare again to use your current sharing choice and text. Input already sent to a provider can't be recalled.")
            if !captureEditor {
                capturePreferenceDisclosure("scheduledPlanError", prefix: "1096-delayed-plan-context-" + mode, navigationTitle: "Make a plan")
            }
            XCTAssertFalse(app.staticTexts["scheduledPlanCount"].exists)
            reveal(end, towardsTop: true); XCTAssertEqual(end.label, originalEnd)
            reveal(app.staticTexts["scheduledPlanGoalPreview"].firstMatch, towardsTop: true)
            XCTAssertEqual(app.staticTexts["scheduledPlanGoalPreview"].label, goal)
            tap("editScheduledPlanGoal")
            XCTAssertEqual(app.textViews["scheduledPlanGoal"].value as? String, goal)
            if captureEditor { captureRetainedPlanEditor(goal: goal, mode: mode) }
            else { snap("1097-delayed-plan-retained-goal-" + mode) }
            tap("finishPlanText")
            if captureEditor {
                XCTAssertTrue(app.navigationBars["Make a plan"].waitForExistence(timeout: 5))
                let preview = app.staticTexts["scheduledPlanGoalPreview"].firstMatch
                reveal(preview, towardsTop: true); settleLabFrame(preview)
                XCTAssertEqual(preview.label, goal)
                snap("1099-retained-plan-after-done-goal-" + mode)
                reveal(end); XCTAssertEqual(end.label, originalEnd); settleLabFrame(end)
                snap("1099-retained-plan-after-done-timeframe-" + mode)
                XCTAssertEqual(try personalRequestAudit().count, before)
                // Other privacy/Library/footer checks already passed at app6.
                // This repeat supplies only the remaining editor/Done evidence.
                continue
            }
            tap("closeScheduledPlan"); tap("Discard draft"); tab("Library")
            XCTAssertEqual(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'library-plan-' ")).count, 0)
            XCTAssertEqual(try personalRequestAudit().count, before, "Synthetic planning never calls a provider")
            openPersonalNotesFromAssistant()
            let saved = app.staticTexts["personalContextSavedSharing"].firstMatch; reveal(saved)
            XCTAssertEqual(saved.label, mode == "context-revert" ? "Saved sharing: On" : "Saved sharing: Off")
            capturePreferenceDisclosure("personalContextHistoryDisclosure", prefix: "1098-plan-context-history-disclosure-" + mode)
        }
    }

    func captureRetainedPlanEditor(goal: String, mode: String) {
        let editor = app.textViews["scheduledPlanGoal"].firstMatch
        let keyboard = app.keyboards.firstMatch
        let done = app.buttons["finishPlanText"].firstMatch
        let visibleKey = app.keyboards.keys.matching(NSPredicate(format: "label ==[c] %@", "q")).firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        settleLabFrame(editor); settleLabFrame(keyboard)
        XCTAssertTrue(visibleKey.isHittable, "Actual on-screen keys must be visible")
        XCTAssertEqual(editor.value as? String, goal)
        editor.swipeDown(velocity: .slow); settleLabFrame(editor)
        XCTAssertTrue(visibleKey.isHittable && done.isHittable)
        snap("1099-retained-plan-editor-start-keyboard-" + mode)
        // Reuse the native-key pattern from calendar editing and rename: text
        // injection can hide the software keyboard, so tap actual visible keys.
        let letter = app.keyboards.keys.matching(NSPredicate(format: "label ==[c] %@", "x")).firstMatch
        XCTAssertTrue(letter.exists && letter.isHittable)
        let literal = letter.label; letter.tap()
        XCTAssertEqual(editor.value as? String, goal + literal)
        settleLabFrame(editor); settleLabFrame(keyboard)
        XCTAssertTrue(visibleKey.isHittable && done.isHittable)
        XCTAssertLessThanOrEqual(done.frame.maxY, keyboard.frame.minY + 1)
        let erase = app.keyboards.keys["delete"].firstMatch
        XCTAssertTrue(erase.exists && erase.isHittable); erase.tap()
        snap("1099-retained-plan-end-caret-keyboard-" + mode)
        XCTAssertEqual(editor.value as? String, goal)
        XCTAssertTrue(visibleKey.isHittable && done.isHittable)
    }
    func testPersonalContextStaleReload() throws {
        quickFault("none:0", large: true, extra: ["-preference-context-change"]); openPersonalPreferences()
        let focus = app.descendants(matching: .any).matching(identifier: "personalFocus").firstMatch
        reveal(focus); focus.tap(); focus.typeText("Synthetic older draft"); finishContextInput()
        nativeSwitch("personalContextSharing", enabled: true); tap("savePersonalContext")
        let alert = app.alerts["Saved context changed"]; XCTAssertTrue(alert.waitForExistence(timeout: 5)); capturePreferenceAlert(alert, prefix: "1001-context-stale-choice")
        alert.buttons["Keep draft"].tap(); reveal(focus, towardsTop: true); XCTAssertEqual(focus.value as? String, "Synthetic older draft")
        snap("1001-context-kept-stale-draft")
        tap("savePersonalContext"); XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap("1001-context-reload-reopened")
        alert.buttons["Reload"].tap()
        reveal(focus, towardsTop: true); XCTAssertEqual(focus.value as? String, "Synthetic newer notes")
        XCTAssertFalse(app.buttons["savePersonalContext"].isEnabled)
        let saved = app.staticTexts["personalContextSavedSharing"]; reveal(saved); XCTAssertEqual(saved.label, "Saved sharing: Off"); XCTAssertFalse(app.staticTexts["personalContextUnsaved"].exists); snap("1001-context-reloaded")
    }
    func testPreferenceSchedulingFailurePresentation() throws {
        quickFault("none:0", large: true, extra: ["-preference-schedule-failure"]); openHealthConnections()
        preferenceSwitch("contextualCheckIns").tap(); approveReminderAccess()
        let issue = app.staticTexts["Your settings were saved, but the check-in couldn’t be scheduled. Try again."].firstMatch
        reveal(issue); XCTAssertTrue(issue.waitForExistence(timeout: 10)); snap("1003-reminder-schedule-failed")
        capturePreferenceDisclosure("reminderSchedulingIssue", prefix: "1003-reminder-schedule-message")
        let retry = app.buttons["Retry check-in"].firstMatch; reveal(retry); XCTAssertTrue(retry.isHittable); snap("1003-reminder-schedule-retry")
        retry.tap(); XCTAssertTrue(issue.waitForNonExistence(timeout: 10))
        let enabled = app.switches["contextualCheckIns"].firstMatch; reveal(enabled, towardsTop: true); XCTAssertEqual(enabled.value as? String, "1"); snap("1003-reminder-saved-choice")
    }
    func testPreferenceAccessPendingPresentation() throws {
        quickFault("none:0", large: true, extra: ["-preference-access-hold"]); openHealthConnections()
        let started = Date(); preferenceSwitch("contextualCheckIns").tap(); approveReminderAccess()
        let pending = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Requesting notification access…'")).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 5)); reveal(pending); snap("1002-reminder-requesting-access")
        app.navigationBars["Connections"].buttons.element(boundBy: 0).tap()
        let remaining = 18 - Date().timeIntervalSince(started)
        if remaining > 0 { Thread.sleep(forTimeInterval: remaining) }
        let link = app.buttons["Health imports & contextual reminders"].firstMatch; reveal(link); link.tap()
        let enabled = app.switches["contextualCheckIns"].firstMatch; reveal(enabled); XCTAssertEqual(enabled.value as? String, "0"); snap("1002-reminder-departed-owner-off")
    }
    func testSettingsNameLargeDiskFailures() throws { settingsNameRepeatedDiskFailures(large: true) }

    func settingsNameRepeatedDiskFailures(large: Bool) {
        quickFault("profile:1,2", large: large)
        tap("Settings")
        let name = app.textFields["settingsNameDraft"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        name.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 40)); name.typeText("Alex Rivera")
        XCTAssertEqual(name.value as? String, "Alex Rivera")
        reveal(app.buttons["Save name"]); snap(large ? "951-name-large-draft-actions" : "951-name-draft-actions"); tap("Save name")
        let alert = app.alerts["Couldn’t save name"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap("940-name-first-failure")
        alert.buttons["Try again"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap("941-name-repeated-failure")
        alert.buttons["Not now"].tap()
        XCTAssertEqual(name.value as? String, "Alex Rivera")
        XCTAssertTrue(app.staticTexts["Name not saved"].exists); snap("942-name-retained-edit")
        tap("Save name")
        XCTAssertTrue(app.staticTexts["Name not saved"].waitForNonExistence(timeout: 5))
        tap("Done"); reopenSettings(large: large)
        XCTAssertEqual(name.value as? String, "Alex Rivera"); snap("943-name-relaunch")
        if large {
            name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap(); name.typeText(" draft")
            let discard = app.buttons["Discard"].firstMatch
            // Drag inside the form, above the keyboard. The generic left-edge
            // gesture can land outside this compact sheet's scrolling content.
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            snap("971-large-name-before-discard-scroll")
            func keyboardTop() -> CGFloat {
                let keyboard = app.keyboards.firstMatch
                guard keyboard.exists else { return app.frame.maxY - 40 }
                var top = keyboard.frame.minY
                // Keyboard excludes the prediction/accessory strip in this
                // native hierarchy. Start above that strip, not on its keys.
                for identifier in ["SystemInputAssistantView", "inputView"] {
                    let accessory = app.otherElements[identifier].firstMatch
                    if accessory.exists && !accessory.frame.isEmpty { top = min(top, accessory.frame.minY) }
                }
                return top
            }
            for attempt in 0..<8 {
                let top = app.navigationBars["Settings"].frame.maxY + 16
                let bottom = keyboardTop() - 12
                if discard.exists && discard.isHittable && discard.frame.minY > top && discard.frame.maxY < bottom { break }
                let moveUp = !discard.exists || discard.frame.maxY >= bottom
                let gap = moveUp ? discard.frame.maxY - bottom : top - discard.frame.minY
                let distance = min(100, max(40, gap + 16))
                let startY = moveUp ? bottom - 8 : top + 8
                let endY = startY + (moveUp ? -distance : distance)
                let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: startY))
                let end = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: app.frame.midX, dy: endY))
                start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.3)
                snap("972-large-name-discard-scroll-step-\(attempt + 1)")
            }
            print("SETTINGS DISCARD AFTER SCROLL", app.debugDescription)
            XCTAssertTrue(discard.isHittable)
            XCTAssertGreaterThan(discard.frame.minY, app.navigationBars.firstMatch.frame.maxY)
            XCTAssertLessThan(discard.frame.maxY, keyboardTop())
            snap("969-large-name-discard-reachable")
            discard.tap(); XCTAssertEqual(name.value as? String, "Alex Rivera")
            XCTAssertFalse(app.staticTexts["Name not saved"].exists); snap("970-large-name-discarded")
        }
    }

    func testSettingsNameDoneFailureAndDiscard() throws {
        quickFault("profile:1"); tap("Settings")
        let name = app.textFields["settingsNameDraft"]
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap(); name.typeText(" Taylor")
        tap("Done")
        let alert = app.alerts["Couldn’t save name"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap("952-name-done-failed")
        alert.buttons["Not now"].tap()
        XCTAssertEqual(name.value as? String, "Alex Taylor")
        reveal(app.buttons["Discard"]); tap("Discard")
        XCTAssertEqual(name.value as? String, "Alex")
        XCTAssertFalse(app.staticTexts["Name not saved"].exists); snap("953-name-discarded")
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap(); name.typeText(" Taylor"); tap("Done")
        XCTAssertTrue(app.navigationBars["Settings"].waitForNonExistence(timeout: 5))
        app.terminate(); app.launchArguments = []; app.launch(); tap("Settings")
        XCTAssertEqual(name.value as? String, "Alex Taylor"); snap("954-name-done-relaunch")
        name.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap(); name.typeText(" Reed\n")
        XCTAssertTrue(app.staticTexts["Name not saved"].waitForNonExistence(timeout: 5))
        snap("959-name-return-saved")
        app.terminate(); app.launchArguments = []; app.launch(); tap("Settings")
        XCTAssertEqual(name.value as? String, "Alex Taylor Reed"); snap("959-name-return-relaunch")
    }

    func testSettingsGoalsAndSleepDiskFailures() throws { settingsGoalsAndSleepDiskFailures(large: false) }
    func testSettingsGoalsAndSleepLargeDiskFailures() throws { settingsGoalsAndSleepDiskFailures(large: true) }

    func settingsGoalsAndSleepDiskFailures(large: Bool) {
        for profile in [false, true] {
            quickFault(profile ? "profile:1" : "goals:1", large: large)
            tap("Settings")
            let control = app.steppers[profile ? "settingsSleepNeed" : "settingsMoveGoal"].firstMatch
            reveal(control)
            print("SETTINGS STEPPER " + control.debugDescription)
            snap(profile ? "944-sleep-need-before" : "944-move-goal-before")
            let before = control.label + (control.value as? String ?? "")
            let increment = control.buttons[control.identifier + "-Increment"].firstMatch
            XCTAssertTrue(increment.exists); increment.tap()
            let alert = app.alerts[profile ? "Couldn’t save sleep need" : "Couldn’t save move goal"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap(profile ? "944-sleep-need-failed" : "944-move-goal-failed")
            captureSettingsAlertBody(alert, prefix: profile ? "968-sleep-error-body" : "968-move-error-body")
            alert.buttons["Not now"].tap(); XCTAssertEqual(control.label + (control.value as? String ?? ""), before)
            snap(profile ? "958-sleep-need-unchanged" : "958-move-goal-unchanged")
            increment.tap(); XCTAssertNotEqual(control.label + (control.value as? String ?? ""), before)
            let saved = control.label + (control.value as? String ?? ""); snap(profile ? "945-sleep-need-retried" : "945-move-goal-retried")
            tap("Done"); reopenSettings(large: large); reveal(control)
            XCTAssertEqual(control.label + (control.value as? String ?? ""), saved)
            let explanation = app.staticTexts["Targets are estimates from your settings. Missing values use defaults."].firstMatch
            reveal(explanation, towardsTop: profile); fullyRevealSettingsDisclosure(explanation)
            snap(profile ? "957-sleep-target-disclosure" : "957-goal-target-disclosure")
        }
    }

    func testSettingsLargeDisclosure() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-lumen.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); finishOnboarding(); tap("Settings")
        let explanation = app.staticTexts["Targets are estimates from your settings. Missing values use defaults."].firstMatch
        reveal(explanation); fullyRevealSettingsDisclosure(explanation); snap("960-large-complete-target-disclosure")
    }

    func fullyRevealSettingsDisclosure(_ text: XCUIElement) {
        let top = app.navigationBars["Settings"].frame.maxY + 16
        let bottom = app.frame.maxY - 40
        for _ in 0..<6 {
            let frame = text.frame
            if frame.minY >= top && frame.maxY <= bottom { return }
            let distance = frame.minY < top ? min(220, top - frame.minY + 8) : -min(220, frame.maxY - bottom + 8)
            let start = app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 10, dy: (top + bottom) / 2))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: distance)))
        }
        XCTAssertGreaterThanOrEqual(text.frame.minY, top)
        XCTAssertLessThanOrEqual(text.frame.maxY, bottom)
    }

    func testSettingsBirthYearPairedDiskFailure() throws { settingsBirthYearPairedDiskFailure(large: false) }
    func testSettingsBirthYearLargeDiskFailure() throws { settingsBirthYearPairedDiskFailure(large: true) }

    func testSettingsSexMenuDiskFailure() throws {
        quickFault("goals:1", large: true); tap("Settings")
        let sex = app.buttons["settingsSex"].firstMatch
        reveal(sex)
        let previous = sex.label + (sex.value as? String ?? "")
        XCTAssertTrue(previous.contains("Not specified")); snap("961-large-sex-not-specified")
        sex.tap(); tap("Female")
        let alert = app.alerts["Couldn’t save sex"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap("962-large-sex-menu-failure")
        captureSettingsAlertBody(alert, prefix: "968-sex-error-body")
        XCTAssertEqual(sex.label + (sex.value as? String ?? ""), previous)
        alert.buttons["Try again"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 5))
        XCTAssertTrue((sex.label + (sex.value as? String ?? "")).contains("Female")); snap("963-large-sex-menu-retry")
        tap("Done"); reopenSettings(large: true); reveal(sex)
        XCTAssertTrue((sex.label + (sex.value as? String ?? "")).contains("Female")); snap("964-large-sex-menu-relaunch")
    }

    func settingsBirthYearPairedDiskFailure(large: Bool) {
        quickFault("profile.json:2", large: large)
        tap("Settings")
        let row = app.buttons["settingsBirthYear"].firstMatch
        reveal(row)
        let previous = row.label + (row.value as? String ?? "")
        row.tap()
        let year = String(Calendar.current.component(.year, from: Date()) - 31)
        print("BIRTH YEAR MENU " + app.debugDescription); snap("946-birth-year-menu")
        selectBirthYearOption(year)
        let alert = app.alerts["Couldn’t save birth year"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap("946-birth-year-paired-failure")
        captureSettingsAlertBody(alert, prefix: "968-birth-year-error-body")
        XCTAssertEqual(row.label + (row.value as? String ?? ""), previous)
        alert.buttons["Try again"].tap()
        XCTAssertTrue(alert.waitForNonExistence(timeout: 8))
        if !app.navigationBars["Settings"].exists { app.navigationBars.buttons.element(boundBy: 0).tap() }
        reveal(row); XCTAssertTrue((row.label + (row.value as? String ?? "")).contains(year)); snap("947-birth-year-paired-retried")
        tap("Done"); reopenSettings(large: large); reveal(row)
        XCTAssertTrue((row.label + (row.value as? String ?? "")).contains(year))
        let calories = app.descendants(matching: .any).matching(identifier: "settingsCalorieTarget").firstMatch
        reveal(calories); XCTAssertTrue((calories.label + (calories.value as? String ?? "")).contains("2421")); snap("948-birth-year-age-relaunch")
        reveal(row, towardsTop: true); row.tap()
        selectBirthYearOption("Not recorded", capture: "955-birth-year-not-recorded-choice")
        reveal(row, towardsTop: true)
        XCTAssertTrue((row.label + (row.value as? String ?? "")).contains("Not recorded")); snap("955-birth-year-cleared")
        tap("Done"); reopenSettings(large: large); reveal(row)
        XCTAssertTrue((row.label + (row.value as? String ?? "")).contains("Not recorded")); snap("956-birth-year-cleared-relaunch")
    }

    func reopenSettings(large: Bool) {
        app.terminate()
        app.launchArguments = large ? ["-lumen.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : ["-lumen.appearance", "light"]
        app.launch(); tap("Settings")
    }

    func captureSettingsAlertBody(_ alert: XCUIElement, prefix: String) {
        print("SETTINGS ALERT BEFORE SCROLL " + alert.debugDescription)
        let scroll = alert.scrollViews.firstMatch
        print("SETTINGS ALERT SCROLL COUNT \(alert.scrollViews.count)")
        for index in 1...2 {
            if scroll.exists {
                scroll.swipeUp(velocity: .slow)
            } else {
                let message = alert.staticTexts["This change wasn’t applied. Try again."].firstMatch
                let action = alert.buttons["Try again"].firstMatch
                let startY = action.frame.minY - 20
                let endY = max(alert.frame.minY + 36, message.frame.minY + 8)
                let origin = app.coordinate(withNormalizedOffset: .zero)
                let lower = origin.withOffset(CGVector(dx: alert.frame.midX, dy: startY))
                let upper = origin.withOffset(CGVector(dx: alert.frame.midX, dy: endY))
                lower.press(forDuration: 0.05, thenDragTo: upper)
            }
            snap(prefix + "-scroll-\(index)")
        }
        print("SETTINGS ALERT AFTER SCROLL " + alert.debugDescription)
    }

    func selectBirthYearOption(_ label: String, capture: String? = nil) {
        let option = app.buttons[label].firstMatch
        let screen = app.frame
        // Native menus expose only their current rows. Scroll inside the year
        // menu rather than swiping the form's gutter and dismissing it.
        for _ in 0..<32 {
            if option.exists && option.isHittable { if let capture { snap(capture) }; option.tap(); return }
            let years = app.buttons.matching(NSPredicate(format: "label MATCHES '[0-9]{4}'")).allElementsBoundByIndex.filter { $0.isHittable }
            guard let first = years.first else { break }
            let menu = app.collectionViews.containing(.button, identifier: first.label).firstMatch
            guard menu.exists else { break }
            // Menu rows may extend above/below their actual clipping surface,
            // even when XCTest calls them hittable. Use the enclosing popup's
            // bounds so the pan cannot start on and scroll the background form.
            var popup = menu.frame
            let containers = app.otherElements.containing(.button, identifier: first.label).allElementsBoundByIndex
            for container in containers {
                let rectangle = container.frame
                if rectangle.width > 100 && rectangle.width < screen.width && rectangle.height > 60 {
                    if rectangle.width * rectangle.height < popup.width * popup.height { popup = rectangle }
                }
            }
            let top = max(screen.minY + 24, popup.minY + 24)
            let bottom = min(screen.maxY - 24, popup.maxY - 24)
            guard bottom - top > 60 else { break }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let upper = origin.withOffset(CGVector(dx: popup.midX, dy: top))
            let lower = origin.withOffset(CGVector(dx: popup.midX, dy: bottom))
            let towardBeginning = Int(label).map { $0 > (Int(first.label) ?? $0) } ?? true
            if towardBeginning { upper.press(forDuration: 0.05, thenDragTo: lower) }
            else { lower.press(forDuration: 0.05, thenDragTo: upper) }
        }
        snap("unreachable-birth-year-option"); print(app.debugDescription)
        XCTFail("Birth-year option must be reachable within the native menu: " + label)
    }

    func testOnboardingPairedDiskFailures() throws {
        for domain in ["goals.json", "profile.json"] {
            quickFault(domain + ":1")
            let alert = app.alerts["Couldn’t save setup"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5)); snap("949-setup-failed-" + domain)
            XCTAssertFalse(app.buttons["currentReadingsShortcut"].exists)
            alert.buttons["OK"].tap()
            tap("Start using Lumen")
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 10))
            app.terminate(); app.launchArguments = []; app.launch(); tap("Settings")
            XCTAssertEqual(app.textFields["settingsNameDraft"].value as? String, "Alex"); snap("950-setup-retry-relaunch-" + domain)
        }
    }

    func quickFault(_ specification: String, photo: Bool = false, large: Bool = false, extra: [String] = []) {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-quick-save-fault", specification]
            + (photo ? ["-quick-meal-photo"] : []) + extra
            + (large ? ["-lumen.appearance", "dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"] : ["-lumen.appearance", "light"])
        app.launch(); finishOnboarding()
    }

    func assertQuickFailure(_ title: String, capture: String) {
        let alert = app.alerts[title]
        XCTAssertTrue(alert.waitForExistence(timeout: 8)); snap(capture)
        alert.buttons["OK"].tap()
    }

    func testQuickWaterDiskFailures() throws {
        for index in 1...2 {
            quickFault("water:\(index)")
            scrollAndTap("Food")
            let value = app.staticTexts["foodWaterValue"]; reveal(value)
            XCTAssertEqual(value.label, "Not recorded")
            tap("+ 250 ml")
            if index == 1 {
                assertQuickFailure("Couldn’t save water", capture: "910-water-save-failed")
                XCTAssertEqual(value.label, "Not recorded")
                tap("+ 250 ml"); XCTAssertEqual(value.label, "250 ml")
            } else {
                XCTAssertEqual(value.label, "250 ml"); tap("undoQuickWater")
                assertQuickFailure("Couldn’t remove water", capture: "911-water-undo-failed")
                XCTAssertEqual(value.label, "250 ml"); tap("undoQuickWater")
                XCTAssertEqual(value.label, "Not recorded")
            }
            app.terminate(); app.launchArguments = []; app.launch()
            scrollAndTap("Food"); reveal(value)
            XCTAssertEqual(value.label, index == 1 ? "250 ml" : "Not recorded")
            snap("912-water-retry-relaunch-\(index)")
        }
    }

    func testQuickWaterTodayAndSheetDiskFailures() throws {
        for inSheet in [false, true] {
            quickFault("water:1")
            if inSheet { tap("Log"); scrollAndTap("Water") }
            else { let action = app.buttons["Add 250 millilitres of water"].firstMatch; reveal(action); action.tap() }
            assertQuickFailure("Couldn’t save water", capture: inSheet ? "930-water-log-sheet-failed" : "930-water-today-failed")
            if inSheet {
                XCTAssertTrue(app.navigationBars["Log"].exists); snap("931-water-log-sheet-retained")
                scrollAndTap("Water")
                XCTAssertTrue(app.navigationBars["Log"].waitForNonExistence(timeout: 5))
            } else {
                tap("currentReadingsShortcut"); tap("current-reading-water")
                XCTAssertEqual(app.staticTexts["currentReadingValue"].label, "Not recorded")
                app.navigationBars.buttons.element(boundBy: 0).tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
                let action = app.buttons["Add 250 millilitres of water"].firstMatch; reveal(action); action.tap()
            }
            app.terminate(); app.launchArguments = []; app.launch()
            tap("currentReadingsShortcut"); tap("current-reading-water")
            XCTAssertEqual(app.staticTexts["currentReadingValue"].label, "250 ml")
            snap(inSheet ? "932-water-log-sheet-retry-relaunch" : "932-water-today-retry-relaunch")
        }
    }

    func testQuickFoodSearchDiskFailure() throws {
        quickFault("meals:1")
        scrollAndTap("Food"); tap("Search foods")
        let espresso = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Espresso")).firstMatch
        XCTAssertTrue(espresso.waitForExistence(timeout: 5)); espresso.tap()
        assertQuickFailure("Couldn’t save food", capture: "913-food-search-save-failed")
        XCTAssertTrue(app.navigationBars["Add food"].exists)
        espresso.tap()
        XCTAssertTrue(app.navigationBars["Add food"].waitForNonExistence(timeout: 5))
        let meal = app.staticTexts["Espresso"].firstMatch; reveal(meal); XCTAssertTrue(meal.exists)
        snap("914-food-search-retried")
        app.terminate(); app.launchArguments = []; app.launch(); scrollAndTap("Food")
        reveal(meal); XCTAssertTrue(meal.exists)
    }

    func testQuickMealPhotoDiskFailures() throws {
        for specification in ["photo:1", "meals:1", "meals:2"] {
            quickFault(specification, photo: true)
            tap("Log"); scrollAndTap("Meal")
            let search = app.buttons["mealSearch"].firstMatch
            if search.waitForExistence(timeout: 5) { reveal(search); search.tap() }
            else { scrollAndTap("Search foods") }
            let espresso = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Espresso")).firstMatch
            XCTAssertTrue(espresso.waitForExistence(timeout: 5)); espresso.tap()
            scrollAndTap("Add 2 kcal")
            if specification != "meals:2" {
                assertQuickFailure("Couldn’t save meal", capture: "915-meal-draft-failed-" + specification.replacingOccurrences(of: ":", with: "-"))
                XCTAssertTrue(app.navigationBars["Review meal"].exists)
                scrollAndTap("Add 2 kcal")
            }
            XCTAssertTrue(app.navigationBars["Review meal"].waitForNonExistence(timeout: 5))
            scrollAndTap("Food")
            let meal = app.staticTexts["Espresso"].firstMatch; reveal(meal); XCTAssertTrue(meal.exists)
            XCTAssertTrue(app.images["savedMealPhoto"].exists)
            snap("916-meal-photo-saved-" + specification.replacingOccurrences(of: ":", with: "-"))
            if specification == "meals:2" {
                meal.press(forDuration: 1.2); tap("Delete")
                assertQuickFailure("Couldn’t remove meal", capture: "917-meal-photo-delete-failed")
                XCTAssertTrue(meal.exists && app.images["savedMealPhoto"].exists)
                app.terminate(); app.launchArguments = []; app.launch(); scrollAndTap("Food")
                reveal(meal); XCTAssertTrue(meal.exists && app.images["savedMealPhoto"].exists)
                snap("929-meal-photo-delete-failure-relaunch")
                meal.press(forDuration: 1.2); tap("Delete")
                XCTAssertTrue(meal.waitForNonExistence(timeout: 5))
            }
            app.terminate(); app.launchArguments = []; app.launch(); scrollAndTap("Food")
            if specification == "meals:2" { XCTAssertEqual(app.staticTexts["foodEnergyValue"].label, "Not recorded") }
            else { reveal(meal); XCTAssertTrue(meal.exists && app.images["savedMealPhoto"].exists) }
        }
    }

    func testQuickWorkoutDiskFailure() throws {
        for index in 1...2 {
            quickFault("workouts:\(index)")
            tap("Log"); scrollAndTap("Workout"); tap("Save walk")
            if index == 1 {
                assertQuickFailure("Couldn’t save workout", capture: "918-workout-save-failed")
                XCTAssertTrue(app.navigationBars["Log a workout"].exists)
                XCTAssertTrue(app.staticTexts["30 min"].exists); tap("Save walk")
            }
            XCTAssertTrue(app.navigationBars["Log a workout"].waitForNonExistence(timeout: 5))
            scrollAndTap("Activity")
            let workout = app.staticTexts["Walk"].firstMatch; reveal(workout); XCTAssertTrue(workout.exists)
            if index == 2 {
                workout.press(forDuration: 1.2); tap("Delete")
                assertQuickFailure("Couldn’t remove workout", capture: "919-workout-delete-failed")
                XCTAssertTrue(workout.exists); workout.press(forDuration: 1.2); tap("Delete")
                XCTAssertTrue(workout.waitForNonExistence(timeout: 5))
            }
            snap("919-workout-retried-\(index)")
            app.terminate(); app.launchArguments = []; app.launch(); scrollAndTap("Activity")
            if index == 1 { reveal(workout); XCTAssertTrue(workout.exists) }
            else { XCTAssertTrue(app.staticTexts["No workouts yet"].exists) }
        }
    }

    func testQuickWeightDiskFailure() throws { try weightDiskFailure(large: false) }
    func testQuickWeightDiskFailureLargeDark() throws { try weightDiskFailure(large: true) }
    func testQuickWeightBusySync() throws {
        app.terminate()
        app.launchArguments = ["-resetForUITests", "-quick-weight-busy", "-lumen.appearance", "dark"]
        app.launch(); finishOnboarding()
        tap("Log"); scrollAndTap("Weight")
        let value = app.staticTexts["weightDraftValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5)); tap("increaseWeight")
        let draft = value.label; tap("Save weight")
        let alert = app.alerts["Couldn’t save weight"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertTrue(alert.staticTexts["Your weight is still here. Health is syncing. Wait for it to finish, then try saving again."].exists)
        snap("925-weight-busy-sync"); alert.buttons["OK"].tap()
        XCTAssertEqual(value.label, draft); snap("926-weight-busy-retained-draft")
        let ready = NSPredicate(format: "value == %@", "Ready to save")
        expectation(for: ready, evaluatedWith: app.buttons["Save weight"])
        waitForExpectations(timeout: 30)
        tap("Save weight"); XCTAssertTrue(app.navigationBars["Log weight"].waitForNonExistence(timeout: 8))
        app.terminate(); app.launchArguments = []; app.launch()
        tap("currentReadingsShortcut"); tap("current-reading-weight")
        XCTAssertEqual(app.staticTexts["currentReadingValue"].label, draft); snap("927-weight-busy-retry-relaunch")
    }
    func weightDiskFailure(large: Bool) throws {
        quickFault("today.json:1", large: large)
        tap("Log"); scrollAndTap("Weight")
        let value = app.staticTexts["weightDraftValue"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        let original = value.label
        let increase = app.buttons["increaseWeight"]; reveal(increase); increase.tap()
        let draft = value.label; XCTAssertNotEqual(draft, original)
        snap(large ? "920-weight-large-draft" : "920-weight-draft")
        if large {
            let copy = app.staticTexts["Save on this iPhone."]
            let scroll = app.scrollViews.containing(.staticText, identifier: "weightDraftValue").firstMatch
            let action = app.buttons["Save weight"]
            for _ in 0..<5 {
                if copy.exists && copy.frame.maxY < action.frame.minY - 4 && copy.frame.minY > app.navigationBars["Log weight"].frame.maxY { break }
                scroll.swipeUp(velocity: .slow)
            }
            XCTAssertTrue(copy.exists && copy.frame.maxY < action.frame.minY - 4 && copy.frame.minY > app.navigationBars["Log weight"].frame.maxY)
            snap("924-weight-large-local-save-disclosure")
        }
        tap("Save weight")
        assertQuickFailure("Couldn’t save weight", capture: large ? "921-weight-large-failed" : "921-weight-failed")
        XCTAssertEqual(value.label, draft)
        if large { app.scrollViews.containing(.staticText, identifier: "weightDraftValue").firstMatch.swipeDown(velocity: .slow) }
        snap(large ? "928-weight-large-retained-draft" : "928-weight-retained-draft")
        tap("Save weight")
        XCTAssertTrue(app.navigationBars["Log weight"].waitForNonExistence(timeout: 8))
        app.terminate(); app.launchArguments = []; app.launch()
        tap("Log"); scrollAndTap("Weight")
        XCTAssertTrue(value.waitForExistence(timeout: 5)); XCTAssertEqual(value.label, draft)
        snap("922-weight-retry-relaunch-" + (large ? "large" : "normal"))
        tap("Cancel"); tap("currentReadingsShortcut"); tap("current-reading-weight")
        XCTAssertEqual(app.staticTexts["currentReadingValue"].label, draft)
        snap("923-weight-reading-relaunch-" + (large ? "large" : "normal"))
    }

    func testQuickWaterAndMealMutationLifecycle() throws {
        finishOnboarding()
        scrollAndTap("Food")
        let water = app.staticTexts["foodWaterValue"]
        reveal(water); XCTAssertEqual(water.label, "Not recorded")
        tap("+ 250 ml"); tap("+ 250 ml")
        XCTAssertEqual(water.label, "500 ml")
        tap("undoQuickWater")
        XCTAssertEqual(water.label, "250 ml")
        let status = app.staticTexts["waterUndoStatus"]
        let noHealthRemoval = NSPredicate(format: "label CONTAINS %@", "No Apple Health removal was attempted")
        expectation(for: noHealthRemoval, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        snap("900-ordered-water-first-undo")

        app.terminate(); app.launchArguments = []; app.launch()
        scrollAndTap("Food"); reveal(water)
        XCTAssertEqual(water.label, "250 ml")
        tap("undoQuickWater")
        XCTAssertEqual(water.label, "Not recorded")
        expectation(for: noHealthRemoval, evaluatedWith: status)
        waitForExpectations(timeout: 10)
        XCTAssertFalse(app.buttons["undoQuickWater"].isEnabled)
        snap("901-ordered-water-persisted-undo")

        let search = app.buttons["Search foods"].firstMatch
        reveal(search, towardsTop: true); search.tap()
        let espresso = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Espresso")).firstMatch
        XCTAssertTrue(espresso.waitForExistence(timeout: 5)); espresso.tap()
        let meal = app.staticTexts["Espresso"].firstMatch
        reveal(meal); XCTAssertTrue(meal.exists)
        snap("902-ordered-meal-added")
        meal.press(forDuration: 1.2); tap("Delete")
        XCTAssertTrue(meal.waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["foodEnergyValue"].label, "Not recorded")
        snap("903-ordered-meal-deleted")
        app.terminate(); app.launchArguments = []; app.launch()
        scrollAndTap("Food")
        XCTAssertEqual(app.staticTexts["foodEnergyValue"].label, "Not recorded")
        reveal(water); XCTAssertEqual(water.label, "Not recorded")
        XCTAssertFalse(app.buttons["undoQuickWater"].isEnabled)
        snap("904-ordered-mutations-after-relaunch")
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
