import SwiftUI
import ImageIO
#if DEBUG && targetEnvironment(simulator)
import HealthKit
#endif

@MainActor
struct HealthRecoveryView: View {
    let scope: HealthRetainedRecoveryReviewScope
    @EnvironmentObject private var health: HealthStore
    @State private var copies: [HealthRecoveryCopies.Preview] = []
    @State private var loading = false
    @State private var issue: String?
    @State private var control: BackupOperationControl?
    @State private var copiesRoot: URL?
    @State private var reviewSession: HealthRetainedRecoveryReviewSession?
    @State private var reviewingCopy = false
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var cancelVerification = HealthRecoveryCancelUIState.shared
    #endif

    var body: some View {
        Form {
            if let message = health.localHealthStorageIssue {
                Section {
                    Text(message)
                    Button("Retry opening data") {
                        do { try health.retryLocalHealthDataChecked(); issue = nil }
                        catch { issue = error.localizedDescription }
                    }.accessibilityIdentifier("retryLocalHealthData")
                }
            }
            if loading { Section { ProgressView("Checking recovery copies…") } }
            if let issue { Section { Text(issue).foregroundStyle(.secondary) } }
            Section {
                NavigationLink("Manage daily readings") { HealthDailyCacheView() }
                    .disabled(loading).accessibilityIdentifier("manageDailyCache")
            } footer: { Text("Rebuild daily readings from Apple Health, or review clearing the saved snapshot.") }
            Section {
                if copies.isEmpty && !loading && issue == nil { Text("No retained copies on this iPhone.").foregroundStyle(.secondary) }
                ForEach(copies, id: \.id) { copy in
                    Button {
                        guard let copiesRoot else { return }
                        reviewSession?.close()
                        do { reviewSession = try scope.review(copy, in: copiesRoot) }
                        catch { issue = "This review ended. Open recovery again."; return }
                        reviewingCopy = true
                    } label: {
                        HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(copy.complete ? "Retained copy" : "Incomplete copy")
                            if let date = copy.createdAt { Text(date.formatted(date: .abbreviated, time: .standard)).font(.footnote).foregroundStyle(.secondary) }
                            Text(copy.domains.filter { $0.state == .readable }.isEmpty
                                 ? copy.domains.filter { $0.state != .notIncluded }.map { recoveryLabel($0.domain) }.joined(separator: ", ")
                                 : copy.domains.filter { $0.state == .readable }.map { recoveryLabel($0.domain) }.joined(separator: ", "))
                                .font(.footnote).foregroundStyle(.secondary)
                            if !copy.domains.contains(where: { $0.state == .readable }) {
                                Text("Contents couldn't be opened").font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(.secondary)
                        }
                        .foregroundStyle(.primary).contentShape(Rectangle())
                    }.disabled(!copy.complete || loading).accessibilityIdentifier("healthRecoveryCopy-" + copy.id)
                }
                #if DEBUG && targetEnvironment(simulator)
                if HealthRecoveryCancelUIFixture.requested {
                    checkCopiesButton.accessibilityValue(cancelVerification.phase)
                } else { checkCopiesButton }
                #else
                checkCopiesButton
                #endif
            } header: { Text("Retained copies") } footer: {
                Text("Review a copy before replacing unavailable data. Healthy data can't be replaced here.")
            }
        }
        .navigationTitle("Recover health data").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $reviewingCopy) {
            if let reviewSession { HealthRecoveryReviewView(session: reviewSession).id(reviewSession.id) }
        }
        .task { await load() }
        .onChange(of: reviewingCopy) { _, active in
            if !active { reviewSession?.close(); reviewSession = nil }
        }
        .onDisappear {
            control?.cancel()
            if !reviewingCopy { reviewSession?.close(); reviewSession = nil }
        }
    }

    private var checkCopiesButton: some View {
        Button("Check copies again") { Task { await load() } }.disabled(loading)
            .accessibilityIdentifier("checkHealthCopies")
    }

    private func load() async {
        guard !loading else { return }
        loading = true; issue = nil
        let operation = BackupOperationControl(); control = operation
        defer { loading = false; control = nil }
        do {
            let root = try LocalStore.checkedDirectory()
            let observed = try await Task.detached { try HealthRecoveryCopies.discover(in: root, control: operation) }.value
            try Task.checkCancellation(); try operation.checkCancellation()
            copies = observed; copiesRoot = root
        } catch is CancellationError { }
        catch { issue = "Recovery copies couldn't be opened. Check again to retry. Your saved files haven't been replaced." }
    }
}

@MainActor
private struct HealthRecoveryReviewView: View {
    let session: HealthRetainedRecoveryReviewSession
    @EnvironmentObject private var health: HealthStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected: Set<HealthLocalFiles.Domain> = []
    @State private var omitPhotos = false
    @State private var confirmation = false
    @State private var busy = false
    @State private var recovered = false
    @State private var issue: String?
    @State private var originMetadata: HealthLegacyRecoveryOrigin.ReviewMetadata?
    @State private var captureControl: BackupOperationControl?
    @State private var captureWork: Task<Void, Never>?
    @State private var captureIssue = false
    @State private var captureID = UUID()
    @State private var reviewActive = false
    @State private var appearanceID = UUID()
    @State private var recordsDomain: HealthLocalFiles.Domain?
    @State private var reviewingRecords = false
    private struct ConfirmationSelection: Sendable {
        let sessionID: UUID
        let appearanceID: UUID
        let domains: Set<HealthLocalFiles.Domain>
        let legacyDomains: Set<HealthLocalFiles.Domain>
        let omitPhotos: Bool
    }
    @State private var confirmationSelection: ConfirmationSelection?
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var readVerification = HealthReadUIState.shared
    #endif
    @State private var operation: BackupOperationControl?
    @State private var work: Task<Void, Never>?
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var cancelVerification = HealthRecoveryCancelUIState.shared
    #endif
    private var photoIDs: Set<String> { Set(session.summary.domains.first { $0.domain == .meals }?.photos.map(\.id) ?? []) }
    private var missingPhotos: Int { session.summary.domains.first { $0.domain == .meals }?.photos.filter { $0.state != .readable }.count ?? 0 }
    private var eligibleDomains: Set<HealthLocalFiles.Domain> {
        Set((originMetadata?.recoverableDomains ?? []).filter {
            session.summary.readableDomains.contains($0) && !health.localHealthAvailable($0)
        })
    }
    private var selectedLegacyDomains: Set<HealthLocalFiles.Domain> {
        selected.intersection(originMetadata?.legacyDomains ?? [])
    }
    private var canRecover: Bool {
        reviewActive && !session.isClosed && session.originState == .ready && originMetadata != nil
        && !busy && !recovered && !health.isSyncing && !selected.isEmpty
        && selected.isSubset(of: eligibleDomains)
        && (!selected.contains(.meals) || missingPhotos == 0 || omitPhotos)
    }

    var body: some View {
        Form {
            if let date = session.summary.createdAt { Section { LabeledContent("Copy saved", value: date.formatted(date: .abbreviated, time: .standard)) } }
            if recovered { Section { Label("Selected data recovered", systemImage: "checkmark.circle").accessibilityIdentifier("healthDataRecovered") } }
            if let issue { Section { Text(issue).foregroundStyle(.secondary) } }
            if originMetadata == nil && !captureIssue { Section { ProgressView("Checking current data…") } }
            if captureIssue {
                Section { Text("Current data couldn't be checked. Go back and review this copy again.").foregroundStyle(.secondary) }
            }
            ForEach(session.summary.domains, id: \.domain) { item in
                Section {
                    if item.state == .readable {
                        Text(item.domain == .goals || item.domain == .today ? "Saved snapshot" : item.recordCount == 1 ? "1 record" : "\(item.recordCount ?? 0) records")
                        Button("Review records") { recordsDomain = item.domain; reviewingRecords = true }
                            .accessibilityIdentifier("reviewHealth-" + item.domain.rawValue)
                        if health.localHealthAvailable(item.domain) {
                            Text("Current data opens").foregroundStyle(.secondary)
                        }
                        else if originMetadata?.ineligibleDomains.contains(item.domain) == true {
                            Text("Current data can't be replaced here.").foregroundStyle(.secondary)
                        }
                        else {
                            Toggle("Recover \(recoveryLabel(item.domain).lowercased())", isOn: Binding(
                                get: { selected.contains(item.domain) },
                                set: { if $0 { selected.insert(item.domain) } else { selected.remove(item.domain) } }
                            )).disabled(!eligibleDomains.contains(item.domain))
                                .accessibilityIdentifier("recoverHealth-" + item.domain.rawValue)
                        }
                    } else { Text(item.state == .notIncluded ? "Not included" : "Couldn't open this copy").foregroundStyle(.secondary) }
                    if item.domain == .meals && !photoIDs.isEmpty {
                        if missingPhotos > 0 { Text("\(missingPhotos) photo files unavailable").foregroundStyle(.secondary) }
                        Toggle("Recover without meal photos", isOn: $omitPhotos)
                            .disabled(!eligibleDomains.contains(.meals))
                        Text("Photo files stay in this copy. Photos kept for recovery receive a final image check.").font(.footnote).foregroundStyle(.secondary)
                    }
                } header: { Text(recoveryLabel(item.domain)) }.disabled(busy || recovered)
            }
            Section {
                Text("Replaced files stay in a private copy on this iPhone. For meal recovery, this includes any old photos.")
                Text("Recovered entries won't be added to Apple Health. Earlier pending Health saves won't restart; pending removals can finish.")
                if busy {
                    recoveryProgress
                    Button("Cancel") { operation?.cancel(); work?.cancel() }
                } else if recovered { Button("Done") { dismiss() } }
                else {
                    Button("Recover selected data") {
                        guard canRecover else { return }
                        confirmationSelection = ConfirmationSelection(sessionID: session.id, appearanceID: appearanceID,
                            domains: selected, legacyDomains: selectedLegacyDomains, omitPhotos: omitPhotos)
                        confirmation = true
                    }.disabled(!canRecover).accessibilityIdentifier("confirmHealthRecovery")
                }
            }
        }
        .navigationTitle("Review recovery").navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $reviewingRecords) {
            if let recordsDomain { HealthRecoveryRecordsView(session: session, domain: recordsDomain) }
        }
        #if DEBUG && targetEnvironment(simulator)
        .toolbar {
            if HealthRetainedReviewUIFixture.mode != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Review check").accessibilityIdentifier("retainedReviewOwnerState")
                        .accessibilityValue("session=\(session.id.uuidString);capture=\(captureID.uuidString);phase=\(originMetadata == nil ? "pending" : "ready");selected=\(selected.map(\.rawValue).sorted().joined(separator: ","))")
                }
            }
            if HealthReadUIFixture.requested {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Read check").accessibilityIdentifier("healthReadControlState").accessibilityValue(readVerification.phase)
                }
            }
        }
        #endif
        .alert("Replace selected data?", isPresented: $confirmation) {
            Button("Recover") { if let confirmationSelection { recover(confirmationSelection) } }
            Button("Not now", role: .cancel) { confirmationSelection = nil }
        } message: { Text("Selected data will be replaced by records from this copy. Damaged originals will stay on this iPhone.") }
        .onAppear { reviewActive = true; appearanceID = UUID(); startOriginCapture() }
        .onChange(of: eligibleDomains) { _, eligible in
            selected.formIntersection(eligible)
            if !eligible.contains(.meals) { omitPhotos = false }
        }
        .onDisappear {
            reviewActive = false; confirmation = false; confirmationSelection = nil
            if let captureControl { session.suspendOriginCapture(control: captureControl) }
            captureControl?.cancel(); captureWork?.cancel(); captureControl = nil; captureWork = nil
            operation?.cancel(); work?.cancel()
            if !reviewingRecords { session.close() }
        }
    }

    private func startOriginCapture() {
        guard !session.isClosed else { captureIssue = true; return }
        if let ready = session.originMetadata { originMetadata = ready; return }
        guard captureControl == nil else { return }
        captureIssue = false; captureID = UUID()
        let control = BackupOperationControl(); captureControl = control
        captureWork = Task { @MainActor in
            defer { if captureControl === control { captureControl = nil; captureWork = nil } }
            do {
                try await withTaskCancellationHandler {
                    try await Task.detached { [session] in
                        try session.captureOrigins(control: control) { domains, control in
                            try LocalStore.captureLegacyRecoveryReview(domains, control: control)
                        }
                    }.value
                } onCancel: { control.cancel() }
                try Task.checkCancellation(); try session.checkOpen(control: control)
                guard reviewActive, captureControl === control, let ready = session.originMetadata else { return }
                originMetadata = ready
            } catch is CancellationError { }
            catch {
                guard reviewActive, captureControl === control, !Task.isCancelled else { return }
                captureIssue = true
            }
        }
    }

    private func recover(_ selection: ConfirmationSelection) {
        guard canRecover, selection.sessionID == session.id, selection.appearanceID == appearanceID,
              selection.domains == selected, selection.legacyDomains == selectedLegacyDomains,
              selection.omitPhotos == omitPhotos else { return }
        busy = true; issue = nil
        #if DEBUG && targetEnvironment(simulator)
        let control = HealthRecoveryCancelUIFixture.makeControl()
        #else
        let control = BackupOperationControl()
        #endif
        let registration: UUID
        do { registration = try session.beginOperation(control: control) }
        catch { busy = false; return }
        operation = control
        let domains = selected, omissions = omitPhotos && selected.contains(.meals) ? photoIDs : []
        work = Task { @MainActor in
            defer { session.endOperation(registration); busy = false; operation = nil; work = nil }
            do {
                let payload = try await Task.detached { [session] in
                    try session.payload(domains: domains, legacyDomains: selection.legacyDomains,
                        omittingPhotos: omissions, control: control, validPhoto: BackupService.validPhoto)
                }.value
                try session.checkOpen(control: control); try Task.checkCancellation()
                try await health.recoverUnavailableHealth(payload, control: control)
                recovered = true; selected = []
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, operation === control, !session.isClosed else { return }
                do { try control.checkCancellation() } catch { return }
                issue = "Recovery couldn't finish. Your current files haven't been replaced. Check the copy and try again."
            }
        }
    }

    @ViewBuilder private var recoveryProgress: some View {
        #if DEBUG && targetEnvironment(simulator)
        if HealthRecoveryCancelUIFixture.requested {
            ProgressView("Recovering selected data…").accessibilityIdentifier("healthRecoveryBusy")
                .accessibilityValue(cancelVerification.phase)
        } else { ProgressView("Recovering selected data…").accessibilityIdentifier("healthRecoveryBusy") }
        #else
        ProgressView("Recovering selected data…").accessibilityIdentifier("healthRecoveryBusy")
        #endif
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Only the dedicated synthetic UI launch uses this root. Product views and
/// the real checked replacement APIs are unchanged. Only the explicit daily
/// rebuild fixture requests actual Health access; other launches queue no SDK work.
enum HealthRecoveryUIFixture {
    static var dailyRebuildRequested: Bool {
        let args = ProcessInfo.processInfo.arguments
        return requested && args.contains("-resetForUITests") && args.contains("-health-daily-cache-rebuild-ui")
    }
    static var recordsRequested: Bool { ProcessInfo.processInfo.arguments.contains("-health-review-records-fixture") }
    static var backupRequested: Bool { ProcessInfo.processInfo.arguments.contains("-health-backup-ui-fixture") }
    static var requested: Bool { recordsRequested || ProcessInfo.processInfo.arguments.contains("-health-recovery-ui-fixture") }
    @MainActor static func prepareIfRequested() throws {
        guard requested || backupRequested else { return }
        let root = try LocalStore.checkedDirectory(), encoder = BackupArchive.encoder()
        var files = try ConversationFiles.encoded([], activeID: nil)
        files["water.json"] = try encoder.encode([HydrationLog(id: "synthetic-review-water", date: Date(timeIntervalSince1970: 1_793_620_800), ml: 137)])
        files["meals.json"] = Data("[]".utf8); files["workouts.json"] = Data("[]".utf8)
        if ProcessInfo.processInfo.arguments.contains("-health-backup-healthy-merge-ui") {
            let date = Date(timeIntervalSince1970: 1_793_620_800)
            files["meals.json"] = try encoder.encode([Meal(id: "synthetic-current-meal", date: date, type: .breakfast, items: [], note: "Keep this current meal.", source: .manual)])
            var workout = Workout(id: "synthetic-multi-zero", kind: .strength, title: "Current edited workout", start: date, duration: 900, activeCalories: 35, source: .manual)
            workout.energyKnown = true
            files["workouts.json"] = try encoder.encode([workout])
        }
        files["goals.json"] = try encoder.encode(HealthGoals()); files["today.json"] = try encoder.encode(DayMetrics.empty)
        files[HealthWriteFiles.name] = try HealthWriteJournal(owner: HealthWriteDeviceOwner.current()).encoded()
        if ProcessInfo.processInfo.arguments.contains("-health-backup-empty-ui") {
            var goals = HealthGoals(); goals.stepGoal = 6543; goals.weightKg = 88.5; goals.heightCm = 181; goals.age = 42
            files["goals.json"] = try encoder.encode(goals)
        }
        if ProcessInfo.processInfo.arguments.contains("-health-daily-cache-ui-fixture") {
            var journal = HealthWriteJournal(owner: try HealthWriteDeviceOwner.current())
            try journal.append(domain: .water, localID: "synthetic-review-water",
                               components: [.init(metric: .water, value: 137, date: Date(timeIntervalSince1970: 1_793_620_800))])
            try journal.requestDeletion(domain: .water, localID: "synthetic-removed-water")
            files[HealthWriteFiles.name] = try journal.encoded()
        }
        if backupRequested {
            var profile = UserProfile.default
            profile.name = "Synthetic backup baseline"; profile.onboardingDone = true
            if ProcessInfo.processInfo.arguments.contains("-health-backup-preferences-ui") {
                profile.isSubscribed = true; profile.appLock = false; profile.units = .imperial; profile.birthYear = 1985
                var context = PersonalHealthContext(); context.notes = "Synthetic current notes to replace explicitly."; context.includeInAssistant = true
                files["personal-context.json"] = try encoder.encode(context)
                files["habits.json"] = try encoder.encode(Array(SleepHabit.defaults().prefix(1)))
            }
            files["profile.json"] = try encoder.encode(profile)
        }
        if recordsRequested {
            let date = Date(timeIntervalSince1970: 1_793_620_800)
            let origin = HealthLogOrigin(conversationID: "synthetic-review-conversation", messageID: "synthetic-review-message", statement: "I drank 137 ml of water.", preparedBy: "Local draft", confirmedAt: date.addingTimeInterval(30))
            var water = HydrationLog(id: "synthetic-detailed-water", date: date, ml: 137)
            water.note = String(String(repeating: "Synthetic record note 🧭.\n", count: 200).prefix(4000)) + "\nExact final marker."; water.lastEditedAt = date.addingTimeInterval(60); water.logOrigin = origin
            files["water.json"] = try encoder.encode([water, HydrationLog(id: "synthetic-second-water", date: date.addingTimeInterval(3600), ml: 286)])
            let tofu = FoodItem(id: "synthetic-tofu", name: "Synthetic tofu", grams: 125, calories: 190, proteinG: 20.25, carbsG: 3.5, fatG: 10.75, fiberG: 1.5, confidence: 0.84)
            let rice = FoodItem(id: "synthetic-rice", name: "Synthetic rice", grams: 150, calories: 195, proteinG: 4.05, carbsG: 42.3, fatG: 0.45, fiberG: 0.6, confidence: 0.75)
            files["meals.json"] = try encoder.encode([
                Meal(id: "synthetic-first-meal", date: date, type: .lunch, items: [tofu, rice], photoID: "synthetic-review-photo", note: "Synthetic meal note.", source: .manual),
                Meal(id: "synthetic-second-meal", date: date.addingTimeInterval(3600), type: .snack, items: [tofu], photoID: "synthetic-review-photo", source: .manual)
            ])
            var unknown = Workout(id: "synthetic-unknown-energy", kind: .walk, title: "Synthetic unknown energy", start: date, duration: 1200, activeCalories: 0, source: .manual)
            unknown.energyKnown = false; unknown.note = "Synthetic workout with no supplied energy."; unknown.logOrigin = origin
            var zero = Workout(id: "synthetic-known-zero", kind: .strength, title: "Synthetic recorded zero", start: date.addingTimeInterval(3600), duration: 1800, activeCalories: 0, distanceM: 0, avgHR: 94.5, source: .healthKit, stravaID: 123456, polyline: "synthetic-route-data")
            zero.energyKnown = true; zero.energyIsEstimate = false; zero.lastEditedAt = date.addingTimeInterval(5401)
            zero.importOrigin = .init(sourceName: "Synthetic export source", activityType: "Traditional strength training", end: date.addingTimeInterval(5400), filename: "synthetic-health-export.zip", durationWasReported: true, warnings: ["Synthetic import warning."])
            files["workouts.json"] = try encoder.encode([unknown, zero])
            var goals = HealthGoals(); goals.weightKg = nil; goals.heightCm = nil; goals.age = nil
            files["goals.json"] = try encoder.encode(goals)
            var day = DayMetrics.empty; day.date = date
            let query = HealthMetricQuery(start: date, end: date.addingTimeInterval(86400), checkedAt: date.addingTimeInterval(86500), outcome: .recorded)
            day.setReading(.init(components: [.init(value: 0, origin: .healthKit, source: "Synthetic Health source", start: date, end: query.end, lastSampleAt: date, checkedAt: query.checkedAt, aggregation: .total)], healthQuery: query), for: "steps")
            day.setReading(.init(components: [.init(value: 123.5, origin: .healthImport, source: "Synthetic estimate source", start: date, end: query.end, checkedAt: query.checkedAt, aggregation: .reportedDay, isEstimate: true)], healthQuery: query, overlapKeptSeparate: true), for: "activeEnergy")
            var noData = query; noData.outcome = .noData
            day.readings?["water"] = .init(components: [], healthQuery: noData)
            day.restingHR = 58.5; day.weightKg = 72.6; day.sleepSeconds = 25200
            files["today.json"] = try encoder.encode(day)
            if ProcessInfo.processInfo.arguments.contains("-health-review-empty-fixture") { files["water.json"] = Data("[]".utf8) }
        }
        for (name, bytes) in files { try bytes.write(to: root.appendingPathComponent(name), options: .atomic) }
        if recordsRequested {
            let photos = root.appendingPathComponent("photos")
            try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
            let oriented = ProcessInfo.processInfo.arguments.contains("-health-review-oriented-photo")
            let height: CGFloat = oriented ? 16 : 24
            let image = UIGraphicsImageRenderer(size: CGSize(width: 24, height: height)).image { context in
                UIColor.systemTeal.setFill(); context.fill(CGRect(x: 0, y: 0, width: 24, height: height))
                UIColor.systemOrange.setFill(); context.fill(CGRect(x: 12, y: 0, width: 12, height: height))
            }
            guard var jpeg = image.jpegData(compressionQuality: 0.9) else { throw BackupError.invalid }
            if oriented {
                let encoded = NSMutableData()
                guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
                      let destination = CGImageDestinationCreateWithData(encoded, "public.jpeg" as CFString, 1, nil) else { throw BackupError.invalid }
                CGImageDestinationAddImageFromSource(destination, source, 0, [kCGImagePropertyOrientation: 6] as CFDictionary)
                guard CGImageDestinationFinalize(destination) else { throw BackupError.invalid }
                jpeg = encoded as Data
            }
            try jpeg.write(to: photos.appendingPathComponent("synthetic-review-photo.jpg"), options: .atomic)
            if ProcessInfo.processInfo.arguments.contains("-health-review-invalid-photo") {
                try Data("synthetic-not-a-jpeg".utf8).write(to: photos.appendingPathComponent("synthetic-review-photo.jpg"), options: .atomic)
            }
        }
        let previous = root.appendingPathExtension("previous")
        try FileManager.default.copyItem(at: root, to: previous)
        if !ProcessInfo.processInfo.arguments.contains("-health-backup-healthy-merge-ui") {
            try Data("{\"syntheticUnavailableWater\":".utf8).write(to: root.appendingPathComponent("water.json"), options: .atomic)
        }
        if ProcessInfo.processInfo.arguments.contains("-health-backup-multi-ui") {
            for domain in ["meals", "workouts", "goals"] {
                try Data(("{\"syntheticUnavailable" + domain + "\":").utf8).write(to: root.appendingPathComponent(domain + ".json"), options: .atomic)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-health-backup-empty-ui") {
            for domain in ["meals", "workouts"] {
                try Data(("{\"syntheticUnavailable" + domain + "\":").utf8).write(to: root.appendingPathComponent(domain + ".json"), options: .atomic)
            }
        }
        if ProcessInfo.processInfo.arguments.contains("-health-daily-cache-ui-fixture") && !ProcessInfo.processInfo.arguments.contains("-health-daily-cache-healthy-ui") {
            try Data("{\"syntheticUnavailableToday\":".utf8).write(to: root.appendingPathComponent("today.json"), options: .atomic)
            if ProcessInfo.processInfo.arguments.contains("-health-daily-cache-missing-ui") {
                try FileManager.default.removeItem(at: root.appendingPathComponent("today.json"))
            }
            if ProcessInfo.processInfo.arguments.contains("-health-daily-cache-link-ui") {
                let target = root.deletingLastPathComponent().appendingPathComponent("Lumen-ui-daily-cache-link-target.bin")
                try Data("Synthetic external snapshot target; must remain unchanged.\n".utf8).write(to: target, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                try FileManager.default.removeItem(at: root.appendingPathComponent("today.json"))
                try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("today.json").path, withDestinationPath: target.path)
            }
            if ProcessInfo.processInfo.arguments.contains("-health-daily-cache-directory-ui") {
                let directory = root.appendingPathComponent("today.json")
                try FileManager.default.removeItem(at: directory)
                try FileManager.default.createDirectory(at: directory.appendingPathComponent("nested"), withIntermediateDirectories: true)
                try Data([0, 17, 255, 42]).write(to: directory.appendingPathComponent("nested/raw-a.bin"))
                try Data("Synthetic damaged directory snapshot.\n".utf8).write(to: directory.appendingPathComponent("raw-b.txt"))
                for path in [directory, directory.appendingPathComponent("nested")] {
                    try FileManager.default.setAttributes([.posixPermissions: 0o750], ofItemAtPath: path.path)
                }
                try FileManager.default.setAttributes([.posixPermissions: 0o640], ofItemAtPath: directory.appendingPathComponent("nested/raw-a.bin").path)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: directory.appendingPathComponent("raw-b.txt").path)
            }
        }
        if recordsRequested {
            for domain in HealthLocalFiles.Domain.allCases where domain != .water {
                try Data("{".utf8).write(to: root.appendingPathComponent(domain.rawValue + ".json"), options: .atomic)
            }
        }
        try HealthLegacyResetUIFixture.prepare(in: root)
        try HealthLegacyOriginUIFixture.prepare(in: root)
        try HealthRetainedReviewUIFixture.prepare(in: root)
        // Leave .previous unarchived: the real product discovery path must
        // expose it without an unrelated write or fixture-only retirement.
        try HealthRecoveryCancelUIFixture.reset(in: root)
        try HealthReadUIFixture.reset(in: root)
        if backupRequested {
            let arguments = ProcessInfo.processInfo.arguments
            guard let index = arguments.firstIndex(of: "-health-backup-case"),
                  arguments.indices.contains(index + 1),
                  ["legacy", "encrypted", "readable"].contains(arguments[index + 1]) else { throw BackupError.invalid }
            // Establish the real startup store before freezing byte-exact input.
            // Its normal recompute persists the synthetic profile once.
            _ = SleepStore.shared
            var originals: [String: String] = [:]
            for name in HealthLocalFiles.Domain.allCases.map({ $0.rawValue + ".json" }) + [HealthWriteFiles.name, "profile.json"] {
                if HealthLegacyOriginUIFixture.kind != nil, ["meals.json", "workouts.json"].contains(name) { continue }
                originals[name] = try HealthLocalFiles.readRegularData(root.appendingPathComponent(name), limit: 256 * 1024).base64EncodedString()
            }
            var checkpoint: [String: Any] = ["case": arguments[index + 1], "originals": originals,
                "scope": "Dedicated small fixture before real normal-Settings Files selection; no HealthKit/background delivery claim"]
            if HealthLegacyOriginUIFixture.kind != nil {
                checkpoint["missing"] = ["meals.json", "workouts.json"]
                checkpoint["legacyOrigins"] = try HealthLegacyOriginUIFixture.provenance(in: root)
            }
            let bytes = try JSONSerialization.data(withJSONObject: checkpoint, options: [.prettyPrinted, .sortedKeys])
            try bytes.write(to: root.deletingLastPathComponent().appendingPathComponent("Lumen-health-backup-baseline.json"), options: .atomic)
        }
    }
}
#endif

func recoveryLabel(_ domain: HealthLocalFiles.Domain) -> String {
    switch domain {
    case .water: return "Water history"
    case .meals: return "Meal history"
    case .workouts: return "Workout history"
    case .goals: return "Targets"
    case .today: return "Daily readings"
    }
}

@MainActor
private struct HealthRecoveryRecordsView: View {
    let session: HealthRetainedRecoveryReviewSession
    let domain: HealthLocalFiles.Domain
    @State private var document: HealthRecoveryRecordReview.Document?
    @State private var issue: String?
    @State private var operation: BackupOperationControl?
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var readVerification = HealthReadUIState.shared
    #endif
    var body: some View {
        List {
            if let issue { Text(issue).foregroundStyle(.secondary) }
            else if let document {
                if document.count == 0 { Text("No records in this copy.").foregroundStyle(.secondary) }
                ForEach(0..<document.count, id: \.self) { index in
                    if let page = document.page(at: index) {
                        NavigationLink { HealthRecoveryRecordPageView(session: session, page: page) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(page.title).lineLimit(2)
                                if !page.subtitle.isEmpty { Text(page.subtitle).font(.footnote).foregroundStyle(.secondary) }
                            }
                        }.accessibilityIdentifier("recoveryRecord-\(index)")
                    }
                }
            } else { readProgress }
        }.navigationTitle(recoveryLabel(domain)).navigationBarTitleDisplayMode(.inline)
        .task {
            let control = BackupOperationControl(); operation = control
            #if DEBUG && targetEnvironment(simulator)
            HealthReadUIFixture.register(control, scope: "retained-record")
            #endif
            defer { if operation === control { operation = nil } }
            do {
                let session = session, domain = domain
                let result = try await withTaskCancellationHandler {
                    try await Task.detached {
                        let data = try session.records(domain: domain, control: control)
                        return try HealthRecoveryRecordReview.Document.decode(data, domain: domain, control: control)
                    }.value
                } onCancel: { control.cancel() }
                try Task.checkCancellation(); try session.checkOpen(control: control)
                guard operation === control else { return }
                document = result
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, operation === control else { return }
                do { try control.checkCancellation() } catch { return }
                issue = "This copy changed or couldn't be opened. Return to check copies again."
            }
        }
        .onDisappear { operation?.cancel() }
    }
    @ViewBuilder private var readProgress: some View {
        #if DEBUG && targetEnvironment(simulator)
        if HealthReadUIFixture.requested {
            ProgressView("Opening records…").accessibilityIdentifier("recoveryRecordsLoading").accessibilityValue(readVerification.phase)
        } else { ProgressView("Opening records…") }
        #else
        ProgressView("Opening records…")
        #endif
    }
}

@MainActor
struct HealthRecoveryRecordPageView: View {
    let page: HealthRecoveryRecordReview.Page
    let loadPhoto: @Sendable (String, BackupOperationControl) throws -> Data
    let photoLabel: String
    let photoFailure: String
    @State private var photo: UIImage?
    @State private var photoIssue: String?
    @State private var photoOperation: BackupOperationControl?
    #if DEBUG && targetEnvironment(simulator)
    @ObservedObject private var readVerification = HealthReadUIState.shared
    #endif
    init(session: HealthRetainedRecoveryReviewSession, page: HealthRecoveryRecordReview.Page) {
        self.page = page; photoLabel = "Meal photo from this copy"
        photoFailure = "This photo changed or couldn't be opened. Return to check copies again."
        loadPhoto = { id, control in
            try session.photoData(id, control: control)
        }
    }
    init(session: BackupRecoveryReviewSession, page: HealthRecoveryRecordReview.Page) {
        self.page = page; photoLabel = "Meal photo from this file"
        photoFailure = "This photo changed or couldn't be opened. Return to choose the file again."
        loadPhoto = { try session.photoData($0, control: $1) }
    }
    private init(page: HealthRecoveryRecordReview.Page, loadPhoto: @escaping @Sendable (String, BackupOperationControl) throws -> Data, photoLabel: String, photoFailure: String) {
        self.page = page; self.loadPhoto = loadPhoto; self.photoLabel = photoLabel; self.photoFailure = photoFailure
    }
    var body: some View {
        Form {
            Section {
                ForEach(Array(page.fields.enumerated()), id: \.offset) { index, field in
                    if field.value.utf8.count > 1000 {
                        NavigationLink { HealthRecoveryLongTextView(title: field.label, value: field.value) } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(field.label).font(.footnote).foregroundStyle(.secondary)
                                Text(String(field.value.prefix(160))).lineLimit(3)
                            }
                        }.accessibilityIdentifier("recoveryText-\(index)")
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.label).font(.footnote).foregroundStyle(.secondary)
                            Text(field.value).textSelection(.enabled)
                        }.accessibilityElement(children: .combine).accessibilityIdentifier("recoveryField-\(index)")
                    }
                }
            } footer: { if let footer = page.footer { Text(footer) } }
            if page.childCount > 0 {
                Section {
                    ForEach(0..<page.childCount, id: \.self) { index in
                        if let child = page.child(at: index) {
                            NavigationLink { HealthRecoveryRecordPageView(page: child, loadPhoto: loadPhoto, photoLabel: photoLabel, photoFailure: photoFailure) } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(child.title).lineLimit(2)
                                    if !child.subtitle.isEmpty { Text(child.subtitle).font(.footnote).foregroundStyle(.secondary) }
                                }
                            }.accessibilityIdentifier("recoveryChild-\(index)")
                        }
                    }
                }
            }
            if case .photo = page {
                Section {
                    if let photo { Image(uiImage: photo).resizable().scaledToFit().accessibilityLabel(photoLabel).accessibilityIdentifier("recoveryMealPhoto") }
                    else if let photoIssue { Text(photoIssue).foregroundStyle(.secondary) }
                    else { photoProgress }
                }
            }
        }.navigationTitle(page.title).navigationBarTitleDisplayMode(.inline)
        #if DEBUG && targetEnvironment(simulator)
        .toolbar {
            if HealthReadUIFixture.requested {
                ToolbarItem(placement: .topBarTrailing) {
                    Text("Read check").accessibilityIdentifier("healthReadControlState").accessibilityValue(readVerification.phase)
                }
            }
        }
        #endif
        .task {
            guard case .photo(let id) = page else { return }
            let control = BackupOperationControl(); photoOperation = control
            #if DEBUG && targetEnvironment(simulator)
            HealthReadUIFixture.register(control, scope: photoLabel == "Meal photo from this copy" ? "retained-photo" : "selected-photo")
            #endif
            defer { if photoOperation === control { photoOperation = nil } }
            do {
                let loadPhoto = loadPhoto
                let result = try await withTaskCancellationHandler {
                  try await Task.detached {
                    let data = try loadPhoto(id, control)
                    try control.checkCancellation()
                    guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                          CGImageSourceGetType(source) as String? == "public.jpeg", CGImageSourceGetCount(source) == 1,
                          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                          let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                          width > 0, height > 0, width <= 4096, height <= 4096,
                          CGImageSourceGetStatus(source) == .statusComplete,
                          let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
                          CGImageSourceGetStatusAtIndex(source, 0) == .statusComplete else { throw BackupError.missingPhoto }
                    try control.checkCancellation()
                    return ReviewedImage(image: image)
                  }.value
                } onCancel: { control.cancel() }
                try Task.checkCancellation(); try control.checkCancellation()
                guard photoOperation === control else { return }
                photo = UIImage(cgImage: result.image)
            } catch is CancellationError { }
            catch {
                guard !Task.isCancelled, photoOperation === control else { return }
                do { try control.checkCancellation() } catch { return }
                photoIssue = photoFailure
            }
        }
        .onDisappear { photoOperation?.cancel() }
    }
    @ViewBuilder private var photoProgress: some View {
        #if DEBUG && targetEnvironment(simulator)
        if HealthReadUIFixture.requested {
            ProgressView("Opening photo…").accessibilityIdentifier("recoveryPhotoLoading").accessibilityValue(readVerification.phase)
        } else { ProgressView("Opening photo…") }
        #else
        ProgressView("Opening photo…")
        #endif
    }
    private struct ReviewedImage: @unchecked Sendable { let image: CGImage }
}

@MainActor
private struct HealthRecoveryLongTextView: View {
    let title: String
    let value: String
    @State private var starts: [String.Index] = []
    var body: some View {
        let start = starts.last ?? value.startIndex
        let end = value.index(start, offsetBy: 2000, limitedBy: value.endIndex) ?? value.endIndex
        Form { Section { Text(String(value[start..<end])).textSelection(.enabled).accessibilityIdentifier("recoveryFullText") } header: { Text("Part \(starts.count + 1)") } }.id(starts.count)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .bottomBar) {
                    Button("Previous part") { starts.removeLast() }.disabled(starts.isEmpty)
                    Spacer()
                    Button("Next part") { starts.append(end) }.disabled(end == value.endIndex)
                }
            }
    }
}

#if DEBUG && targetEnvironment(simulator)
/// Observes actual SDK permission completion and production query results. It
/// supplies no readings, authorizations or replacement data to the product.
@MainActor
enum HealthDailyCacheHealthUIFixture {
    private static var accessCompleted = false
    static func connect() async {
        guard HealthRecoveryUIFixture.dailyRebuildRequested else { return }
        HealthDailyCacheSDKCallbackObservation.reset()
        if let root = try? LocalStore.checkedDirectory() {
            HealthDailyCacheSDKInterruptionFixture.configure(root.deletingLastPathComponent())
        }
        let hk = HealthKitService.shared
        let completed = await hk.requestAuthorization()
        accessCompleted = completed
        HealthBackgroundSync.shared.stop()
        if HealthDailyCacheRecordedFixture.requested {
            await HealthDailyCacheRecordedFixture.seed()
        }
        struct Access: Encodable {
            let requestCompleted: Bool; let available: Bool; let connected: Bool
            let readPermissionInferred: Bool; let checkedAt: Date
        }
        if let root = try? LocalStore.checkedDirectory() {
            let report = Access(requestCompleted: completed, available: hk.isAvailable, connected: hk.isAuthorized,
                                readPermissionInferred: false, checkedAt: Date())
            try? BackupArchive.encoder().encode(report).write(to: root.deletingLastPathComponent().appendingPathComponent("Lumen-daily-cache-health-access.json"), options: .atomic)
        }
    }
    static func record(_ result: HealthTodayReadCoordinator.Readings) throws {
        guard HealthRecoveryUIFixture.dailyRebuildRequested else { return }
        struct Query: Encodable {
            let requestCompleted: Bool; let requestID: UUID; let sourceGeneration: UUID
            let start: Date; let end: Date; let calendar: String; let timeZone: String
            let metrics: DayMetrics; let scope: String
            let callbacks: [HealthDailyCacheSDKCallbackObservation.Callback]
            let normalizationChecks: [NormalizationCheck]
        }
        let root = try LocalStore.checkedDirectory()
        let report = Query(requestCompleted: accessCompleted, requestID: result.request.id, sourceGeneration: result.request.source,
                           start: result.raw.start, end: result.raw.end, calendar: result.request.calendar, timeZone: result.request.timeZone,
                           metrics: result.raw.metrics, scope: "Actual production HealthKit query callbacks; no injected observations or inferred read permission.",
                           callbacks: HealthDailyCacheSDKCallbackObservation.snapshot(), normalizationChecks: normalizationChecks())
        try BackupArchive.encoder().encode(report).write(to: root.deletingLastPathComponent().appendingPathComponent("Lumen-daily-cache-health-query.json"), options: .atomic)
    }
    struct NormalizationCheck: Encodable {
        let name: String; let inputValue: Double?; let errorDomain: String?; let errorCode: Int?
        let outcome: HealthMetricQuery.Outcome?; let value: Double?
    }
    private static func normalizationChecks() -> [NormalizationCheck] {
        let noData = NSError(domain: HKErrorDomain, code: HKError.Code.errorNoData.rawValue)
        let cases: [(String, Double?, NSError?)] = [
            ("empty-success", nil, nil), ("SDK-no-data", nil, noData), ("no-data-with-quantity", 137, noData),
            ("database-locked", 0, NSError(domain: HKErrorDomain, code: HKError.Code.errorDatabaseInaccessible.rawValue)),
            ("authorization-denied", 137, NSError(domain: HKErrorDomain, code: HKError.Code.errorAuthorizationDenied.rawValue)),
            ("other-domain-same-code", nil, NSError(domain: "synthetic-other-domain", code: HKError.Code.errorNoData.rawValue)),
            ("transport-cancelled", nil, NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)),
            ("recorded-zero", 0, nil), ("recorded-value", 137.25, nil)]
        return cases.map { name, value, error in
            let reading = HealthKitService.quantityResult(value, source: "Synthetic normalization control", error: error,
                                                         multiplier: 1, aggregation: .total,
                                                         start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 60))
            return NormalizationCheck(name: name, inputValue: value, errorDomain: error?.domain, errorCode: error?.code,
                                      outcome: reading.healthQuery?.outcome, value: reading.value)
        }
    }
}

/// Seeds only freshly tagged, source-owned synthetic simulator samples. The
/// product still obtains their values through its ordinary actual SDK queries.
@MainActor
enum HealthDailyCacheRecordedFixture {
    static var requested: Bool {
        HealthRecoveryUIFixture.dailyRebuildRequested
            && ProcessInfo.processInfo.arguments.contains("-health-daily-cache-recorded-ui")
    }
    private static let tag = "LumenSyntheticDailyCache-" + UUID().uuidString
    private static var samples: [HKQuantitySample] = []
    private static var seedFacts: [[String: Any]] = []
    private static var cleaned = false
    private static func matching(_ type: HKQuantityType, tag: String? = nil) async throws -> [HKQuantitySample] {
        let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
            HKQuery.predicateForObjects(from: HKSource.default()),
            HKQuery.predicateForObjects(withMetadataKey: "LumenSyntheticDailyCache", allowedValues: [tag ?? Self.tag])])
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 16, sortDescriptors: nil) { _, values, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (values as? [HKQuantitySample]) ?? []) }
            }
            HealthKitService.shared.store.execute(query)
        }
    }
    static func seed() async {
        guard requested, samples.isEmpty else { return }
        let definitions: [(HKQuantityTypeIdentifier, HKUnit, Double)] = [
            (.stepCount, .count(), 0), (.bodyMass, .gramUnit(with: .kilo), 76.25),
            (.heartRate, HKUnit(from: "count/min"), 64), (.heartRate, HKUnit(from: "count/min"), 80)]
        do {
            try await cleanupInterruptedFixture()
            let date = Date().addingTimeInterval(-60)
            for (index, definition) in definitions.enumerated() {
                let (identifier, unit, value) = definition
                let type = HKQuantityType(identifier)
                guard HealthKitService.shared.store.authorizationStatus(for: type) == .sharingAuthorized else {
                    throw HealthTodayReadCoordinator.Failure.unavailable
                }
                let instant = date.addingTimeInterval(Double(index))
                let sample = HKQuantitySample(type: type, quantity: HKQuantity(unit: unit, doubleValue: value),
                    start: instant, end: instant, metadata: ["LumenSyntheticDailyCache": tag])
                // Keep the exact UUID before saving so partial failures can be cleaned.
                samples.append(sample)
                try await HealthKitService.shared.store.save(sample)
                let matches = try await matching(type)
                guard let actual = matches.first(where: { $0.uuid == sample.uuid }),
                      actual.quantity.doubleValue(for: unit) == value,
                      actual.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    throw HealthTodayReadCoordinator.Failure.changed
                }
                seedFacts.append(["identifier": identifier.rawValue, "uuid": actual.uuid.uuidString,
                    "value": actual.quantity.doubleValue(for: unit), "unit": unit.unitString,
                    "sourceBundle": actual.sourceRevision.source.bundleIdentifier,
                    "start": actual.startDate.timeIntervalSince1970, "end": actual.endDate.timeIntervalSince1970])
            }
            write(status: "seeded", remaining: samples.count)
            HealthRecoveryCancelUIState.shared.phase = "sdk-seed-ready"
        } catch {
            write(status: "seed-failed", remaining: samples.count, error: String(describing: error))
            await cleanup()
            HealthRecoveryCancelUIState.shared.phase = "sdk-seed-failed"
        }
    }
    private static func cleanupInterruptedFixture() async throws {
        let root = try LocalStore.checkedDirectory().deletingLastPathComponent()
        let reportURL = root.appendingPathComponent("Lumen-daily-cache-recorded-fixture.json")
        guard let data = try? Data(contentsOf: reportURL) else { return }
        guard var report = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = report["status"] as? String else { throw HealthTodayReadCoordinator.Failure.changed }
        if status == "cleaned" || status == "cleaned-after-interrupted-test" { return }
        try data.write(to: root.appendingPathComponent("Lumen-daily-cache-previous-fixture-before-cleanup.json"), options: .atomic)
        guard let oldTag = report["tag"] as? String, oldTag.hasPrefix("LumenSyntheticDailyCache-"),
              UUID(uuidString: String(oldTag.dropFirst("LumenSyntheticDailyCache-".count))) != nil,
              let rows = report["samples"] as? [[String: Any]], rows.count == 4 else {
            throw HealthTodayReadCoordinator.Failure.changed
        }
        let expected: [(String, Double)] = [(HKQuantityTypeIdentifier.stepCount.rawValue, 0), (HKQuantityTypeIdentifier.bodyMass.rawValue, 76.25),
                                           (HKQuantityTypeIdentifier.heartRate.rawValue, 64), (HKQuantityTypeIdentifier.heartRate.rawValue, 80)]
        var ids: Set<UUID> = []
        for (row, fact) in zip(rows, expected) {
            guard row["identifier"] as? String == fact.0, row["value"] as? Double == fact.1,
                  row["sourceBundle"] as? String == Bundle.main.bundleIdentifier,
                  let rawID = row["uuid"] as? String, let id = UUID(uuidString: rawID), ids.insert(id).inserted else {
                throw HealthTodayReadCoordinator.Failure.changed
            }
        }
        let identifiers: [HKQuantityTypeIdentifier] = [.stepCount, .bodyMass, .heartRate]
        for identifier in identifiers {
            let type = HKQuantityType(identifier), existing = try await matching(type, tag: oldTag)
            guard existing.allSatisfy({ ids.contains($0.uuid) && $0.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier }) else {
                throw HealthTodayReadCoordinator.Failure.changed
            }
            if !existing.isEmpty { try await HealthKitService.shared.store.delete(existing) }
            guard try await matching(type, tag: oldTag).isEmpty else { throw HealthTodayReadCoordinator.Failure.changed }
        }
        report["status"] = "cleaned-after-interrupted-test"; report["remaining"] = 0
        let cleaned = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        try cleaned.write(to: reportURL, options: .atomic)
        try cleaned.write(to: root.appendingPathComponent("Lumen-daily-cache-previous-fixture-cleanup.json"), options: .atomic)
    }
    static func cleanup() async {
        guard requested, !cleaned else { return }
        do {
            let ids = Set(samples.map(\.uuid))
            let identifiers: [HKQuantityTypeIdentifier] = [.stepCount, .bodyMass, .heartRate]
            for identifier in identifiers {
                let type = HKQuantityType(identifier), existing = try await matching(type)
                guard existing.allSatisfy({ ids.contains($0.uuid) && $0.sourceRevision.source.bundleIdentifier == Bundle.main.bundleIdentifier }) else {
                    throw HealthTodayReadCoordinator.Failure.changed
                }
                if !existing.isEmpty { try await HealthKitService.shared.store.delete(existing) }
                guard try await matching(type).isEmpty else { throw HealthTodayReadCoordinator.Failure.changed }
            }
            cleaned = true; write(status: "cleaned", remaining: 0)
        } catch { write(status: "cleanup-failed", remaining: samples.count, error: String(describing: error)) }
    }
    private static func write(status: String, remaining: Int, error: String? = nil) {
        guard let root = try? LocalStore.checkedDirectory() else { return }
        var report: [String: Any] = ["status": status, "tag": tag, "samples": seedFacts, "remaining": remaining,
            "scope": "Actual synthetic samples on dedicated simulator only; own source and exact fresh metadata/UUID cleanup."]
        if let error { report["error"] = error }
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: root.deletingLastPathComponent().appendingPathComponent("Lumen-daily-cache-recorded-fixture.json"), options: .atomic)
        }
    }
}

/// Delays the first eighteen actual SDK callbacks before gate delivery; native
/// cancellation still reaches store.stop before replaying the late deliveries.
enum HealthDailyCacheSDKInterruptionFixture {
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var root: URL?
        var executed: Set<String> = []
        var stopped: Set<String> = []
        var held: [String: @Sendable () -> Void] = [:]
        var released = false
        var lateDelivered = 0
        var observed = false
    }
    private static let state = State()
    static var requested: Bool {
        HealthRecoveryUIFixture.dailyRebuildRequested
            && ProcessInfo.processInfo.arguments.contains("-health-daily-cache-query-interrupt-ui")
    }
    static func configure(_ root: URL) {
        guard requested else { return }
        state.lock.lock(); defer { state.lock.unlock() }
        state.root = root
        try? FileManager.default.removeItem(at: root.appendingPathComponent("Lumen-daily-query-observed.json"))
        writeLocked()
    }
    static func executed(_ query: HKQuery) {
        guard requested else { return }
        state.lock.lock(); defer { state.lock.unlock() }
        guard !state.released else { return }
        state.executed.insert(String(describing: ObjectIdentifier(query))); writeLocked()
    }
    static func hold(query: HKQuery, delivery: @escaping @Sendable () -> Void) -> Bool {
        guard requested else { return false }
        state.lock.lock()
        let id = String(describing: ObjectIdentifier(query))
        guard !state.released, state.executed.contains(id) else { state.lock.unlock(); return false }
        state.held[id] = delivery; writeLocked()
        let ready = state.held.count == 18
        let root = state.root
        state.lock.unlock()
        if ready, let root {
            Task { @MainActor in HealthRecoveryCancelUIState.shared.phase = "sdk-held-18" }
            Task.detached {
                let deadline = Date().addingTimeInterval(25)
                while Date() < deadline {
                    if let data = try? Data(contentsOf: root.appendingPathComponent("Lumen-daily-query-observed.json")),
                       let report = try? JSONSerialization.jsonObject(with: data) as? [String: Bool], report["observed"] == true {
                        markObserved()
                        await MainActor.run { HealthRecoveryCancelUIState.shared.phase = "sdk-observed-18" }
                        return
                    }
                    try? await Task.sleep(for: .milliseconds(100))
                }
            }
        }
        return true
    }
    private static func markObserved() {
        state.lock.lock(); defer { state.lock.unlock() }
        state.observed = true; writeLocked()
    }
    static func stopped(_ query: HKQuery) {
        guard requested else { return }
        state.lock.lock()
        let id = String(describing: ObjectIdentifier(query))
        guard state.executed.contains(id), !state.released else { state.lock.unlock(); return }
        state.stopped.insert(id)
        let deliveries = state.stopped.count == 18 ? Array(state.held.values) : []
        if state.stopped.count == 18 { state.released = true; state.held = [:] }
        writeLocked(); state.lock.unlock()
        deliveries.forEach { $0() }
        if !deliveries.isEmpty {
            state.lock.lock(); state.lateDelivered = deliveries.count; writeLocked(); state.lock.unlock()
        }
    }
    private static func writeLocked() {
        guard let root = state.root else { return }
        let report: [String: Any] = ["executed": state.executed.sorted(), "stopped": state.stopped.sorted(),
            "held": state.held.keys.sorted(), "released": state.released, "lateDelivered": state.lateDelivered,
            "hostObserved": state.observed, "scope": "Actual SDK callbacks held before gate delivery; SDK may already have completed its query."]
        if let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: root.appendingPathComponent("Lumen-daily-query-interruption.json"), options: .atomic)
        }
    }
}

enum HealthDailyCacheSDKCallbackObservation {
    struct Callback: Encodable {
        let identifier: String; let kind: String; let errorDomain: String?; let errorCode: Int?
    }
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var values: [String: Callback] = [:]
    }
    private static let state = State()
    static func reset() { state.lock.lock(); defer { state.lock.unlock() }; state.values = [:] }
    static func record(identifier: String, kind: String, error: Error?) {
        guard HealthRecoveryUIFixture.dailyRebuildRequested else { return }
        let error = error.map { $0 as NSError }
        state.lock.lock(); defer { state.lock.unlock() }
        state.values[identifier] = Callback(identifier: identifier, kind: kind, errorDomain: error?.domain, errorCode: error?.code)
    }
    static func snapshot() -> [Callback] {
        state.lock.lock(); defer { state.lock.unlock() }
        return state.values.values.sorted { $0.identifier < $1.identifier }
    }
}
#endif
