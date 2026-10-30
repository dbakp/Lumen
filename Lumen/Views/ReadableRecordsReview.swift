import SwiftUI

/// Read-only views of the converted values, before any local storage changes.
struct ReadableRecordsReview: View {
    let conversion: ReadableExport.Conversion
    let domain: ReadableExport.Domain
    @Environment(\.dismiss) private var dismiss
    @State private var offset = 0
    private var count: Int { conversion.count(domain) }
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Saved values only. Recovery doesn't verify medical accuracy.").font(.footnote).foregroundStyle(Theme.secondary)
                    if count == 0 { Text("No saved entries in this section.").foregroundStyle(Theme.secondary) }
                    ForEach(Array(offset..<min(count, offset + 100)), id: \.self) { index in
                        NavigationLink {
                            ReadableEntryReview(snapshot: conversion.snapshot, domain: domain, index: index)
                        } label: {
                            let summary = ReadableRecordSummary(snapshot: conversion.snapshot, domain: domain, index: index)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(verbatim: summary.title).font(.headline)
                                Text(verbatim: summary.detail).font(.subheadline).foregroundStyle(Theme.secondary).lineLimit(3)
                            }.padding(.vertical, 6)
                        }.accessibilityIdentifier("readableEntry-\(index)")
                    }
                }
            }.id(offset).scrollContentBackground(.hidden).background(Theme.bg)
                .navigationTitle(domain.title).navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if count > 100 {
                        ReadablePageControls(summary: "\(offset + 1)–\(min(count, offset + 100)) of \(count.formatted()) entries", previous: "Previous entries", next: "Next entries", first: offset == 0, last: offset + 100 >= count,
                                             back: { offset = max(0, offset - 100) }, forward: { offset += 100 })
                    }
                }
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }.tint(Theme.accent)
    }
}

private struct ReadableEntryReview: View {
    let snapshot: BackupSnapshot
    let domain: ReadableExport.Domain
    let index: Int
    @State private var messageIndex = 0
    var body: some View {
        if domain == .conversations {
            let conversation = snapshot.conversations[index]
            List {
                Section {
                    Text(verbatim: conversation.title).font(.title2.bold())
                    Text("\(conversation.messages.count.formatted()) saved messages").foregroundStyle(Theme.secondary)
                    ForEach(Array(messageIndex..<min(conversation.messages.count, messageIndex + 50)), id: \.self) { i in
                        let message = conversation.messages[i]
                        NavigationLink(message.role == .user ? "Your message · \(ReadableRecordSummary.date(message.date))" : "Assistant · \(ReadableRecordSummary.date(message.date))") {
                            ReadableTextReview(title: message.role == .user ? "Your message" : "Assistant reply", text: message.text + (message.recordContext?.markdownReferences ?? ""), subtitle: message.role == .user ? ReadableRecordSummary.date(message.date) : message.provider ?? "Provider not recorded")
                        }.accessibilityIdentifier("readableMessage-\(i)")
                    }
                }
            }.id(messageIndex).scrollContentBackground(.hidden).background(Theme.bg).navigationTitle("Saved conversation").navigationBarTitleDisplayMode(.inline)
                .safeAreaInset(edge: .bottom) {
                    if conversation.messages.count > 50 {
                        ReadablePageControls(summary: "\(messageIndex + 1)–\(min(conversation.messages.count, messageIndex + 50)) of \(conversation.messages.count.formatted()) messages", previous: "Previous messages", next: "Next messages", first: messageIndex == 0, last: messageIndex + 50 >= conversation.messages.count,
                                             back: { messageIndex = max(0, messageIndex - 50) }, forward: { messageIndex += 50 })
                    }
                }
        } else {
            let record = ReadableRecordSummary(snapshot: snapshot, domain: domain, index: index)
            ReadableTextReview(title: record.title, text: record.text, subtitle: record.detail)
        }
    }
}

private struct ReadableTextReview: View {
    let title: String
    let subtitle: String
    private let sections: [Substring]
    @State private var page = 0
    private var pages: Int { sections.count }
    init(title: String, text: String, subtitle: String) {
        self.title = title; self.subtitle = subtitle
        sections = ReadableExport.reviewSections(text)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(verbatim: title).font(.title.bold()).fontWidth(.expanded)
                if !subtitle.isEmpty { Text(verbatim: subtitle).font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("readableEntryMetadata") }
                Text(verbatim: String(sections[page])).font(.body).textSelection(.enabled).accessibilityIdentifier("readableEntryText")
            }.padding(Theme.gutter).padding(.bottom, 24)
        }.id(page).lumenScreen().navigationTitle("Saved entry").navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if pages > 1 {
                    ReadablePageControls(summary: "Text section \(page + 1) of \(pages)", previous: "Previous", next: "Next", first: page == 0, last: page + 1 >= pages,
                                         back: { page -= 1 }, forward: { page += 1 })
                }
            }
    }
}

private struct ReadablePageControls: View {
    let summary: String
    let previous: String
    let next: String
    let first: Bool
    let last: Bool
    let back: () -> Void
    let forward: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(spacing: 10) {
            Text(summary).font(.footnote).foregroundStyle(Theme.secondary)
            if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 8) { actions } }
            else { HStack { actions } }
        }.padding(.horizontal, Theme.gutter).padding(.vertical, 8).background(.regularMaterial)
    }
    @ViewBuilder private var actions: some View {
        Button(previous, action: back).disabled(first).frame(minHeight: 44)
        if !typeSize.isAccessibilitySize { Spacer() }
        Button(next, action: forward).disabled(last).frame(minHeight: 44)
    }
}

private struct ReadableRecordSummary {
    var title: String
    var detail: String
    var text: String
    static func date(_ date: Date) -> String { date.formatted(date: .abbreviated, time: .shortened) + " · " + (TimeZone.current.abbreviation(for: date) ?? TimeZone.current.identifier) }
    private static func number(_ value: Double) -> String { HealthMetricCatalog.number(value) }
    private static func origin(_ value: HealthLogOrigin?) -> String {
        guard let value else { return "" }
        return "\n\nOriginal statement\n" + value.statement + "\nPrepared with: " + value.preparedBy + "\nConfirmed: " + date(value.confirmedAt)
    }
    init(snapshot s: BackupSnapshot, domain: ReadableExport.Domain, index i: Int) {
        title = domain.title; detail = ""; text = ""
        switch domain {
        case .sleep:
            let x = s.sleep[i]; title = "Sleep · " + Self.date(x.wakeTime); detail = x.source.label
            text = "Bedtime: \(Self.date(x.bedtime))\nWake time: \(Self.date(x.wakeTime))\nTime in bed: \(Self.number(x.timeInBed / 3600)) h\n" + (x.asleepSeconds.map { "Saved time asleep: \(Self.number($0 / 3600)) h" } ?? "Time asleep not provided")
            if let q = x.quality { text += "\nSaved quality: \(q)/5" }
            for (label, seconds) in [("Deep", x.deepSeconds), ("REM", x.remSeconds), ("Core", x.coreSeconds), ("Awake", x.awakeSeconds)] { if let seconds { text += "\n\(label): \(Self.number(seconds / 60)) min" } }
            if let note = x.note { text += "\n\n" + note }
        case .meals:
            let x = s.meals[i]; title = x.type.label; detail = Self.date(x.date) + " · " + x.source.label
            text = x.items.map { "\($0.name)\n\(Self.number($0.grams)) g · \(Self.number($0.calories)) kcal\nProtein \(Self.number($0.proteinG)) g · Carbohydrates \(Self.number($0.carbsG)) g · Fat \(Self.number($0.fatG)) g · Fibre \(Self.number($0.fiberG)) g" }.joined(separator: "\n\n")
            if let note = x.note { text += "\n\n" + note }
            text += "\n\nThese are saved food values, which may be estimates. Photo files aren't included."
        case .workouts:
            let x = s.workouts[i]; title = x.title; detail = Self.date(x.start) + " · " + x.sourceDescription
            text = "\(x.kind.label) · \(Self.number(x.duration / 60)) min\n\(x.energyDescription)"
            if let distance = x.distanceM { text += "\nDistance: \(Self.number(distance)) m" }
            if let hr = x.avgHR { text += "\nAverage heart rate: \(Self.number(hr)) bpm" }
            if let warnings = x.importOrigin?.warnings { text += "\n" + warnings.joined(separator: "\n") }
            if let note = x.note { text += "\n\n" + note }; text += Self.origin(x.logOrigin)
        case .water:
            let x = s.water[i]; title = "\(Self.number(x.ml)) ml water"; detail = Self.date(x.date); text = title + Self.origin(x.logOrigin)
            if let changed = x.lastEditedAt { text += "\nLast edited: " + Self.date(changed) }
        case .conversations:
            let x = s.conversations[i]; title = x.title; detail = "\(x.messages.count.formatted()) messages · " + Self.date(x.updatedAt)
        case .symptoms:
            let x = s.symptoms[i]; title = x.name; detail = Self.date(x.date)
            text = "Location: \(x.location)\nSeverity: \(x.severity)/10\n" + (x.durationMinutes.map { "Duration: \($0) min" } ?? "Duration not provided") + "\n" + (x.resolvedAt.map { "Resolved: " + Self.date($0) } ?? "Marked ongoing") + "\n\n" + x.note
            if !x.triggers.isEmpty { text += "\n\nSaved possible triggers: " + x.triggers.joined(separator: ", ") }; text += Self.origin(x.logOrigin)
        case .checkIns:
            let x = s.checkIns[i]; title = "Check-in"; detail = Self.date(x.date)
            text = "Energy: \(x.energy)/5\nMood: \(x.mood)/5\nStress: \(x.stress)/5\n\n" + x.note + Self.origin(x.logOrigin)
        case .documents:
            let x = s.documents[i]; title = x.title; detail = x.kind.rawValue.capitalized + " · " + x.source + "\nUpdated " + Self.date(x.updatedAt)
            text = x.body
            if x.kind == .plan { text += "\n\nPlan status: " + x.status.label }
            for step in x.steps {
                let date = step.plannedDay.flatMap { PlanDay.date($0) == nil ? nil : $0 }
                let dateText = date.map { "\nPlanned calendar day: " + $0 } ?? step.dueDate.map { "\nDue: " + Self.date($0) } ?? "\nNo due date"
                text += "\n\n[\(step.isDone ? "done" : "pending")] " + step.title + dateText
            }
            if let extraction = x.extraction { text += "\n\nReviewed import: \(Self.date(extraction.reviewedAt))\n\(extraction.pages.count) source pages. The original file isn't in this export." }
            text += (x.recordContext?.markdownReferences ?? "") + "\n\nAssistant sharing starts off if this document is added."
        case .importedDays:
            let x = s.importedDays[i]; title = x.date.formatted(date: .abbreviated, time: .omitted); detail = "\(x.values.count) saved daily values · " + Self.date(x.date)
            text = x.values.keys.sorted().map { key in
                (HealthMetricCatalog.labels[key] ?? key) + ": " + Self.number(x.values[key]!) + " " + (HealthMetricCatalog.units[key] ?? "(unit not provided)") + "\nSource: " + (x.sources[key] ?? "Not provided")
            }.joined(separator: "\n\n") + "\n\nThis timestamp is shown in this iPhone’s time zone. The original daily time zone was not saved."
        case .imports:
            let x = s.imports[i]; title = x.filename; detail = Self.date(x.date)
            text = "\(x.days) days · \(x.samples) samples · \(x.skipped) skipped" + (x.workouts.map { "\n\($0) workouts" } ?? "") + "\n\nAn import receipt describes an earlier import. It doesn't contain the measurements themselves."
        case .profile:
            let x = s.profile; title = "Name & sleep settings"
            text = "Name: \(x.name)\nSleep need setting: \(Self.number(x.sleepNeed / 3600)) h\nChronotype: \(x.chronotype.label)\nWake goal: \(x.wakeGoal.hour.flatMap { hour in x.wakeGoal.minute.map { String(format: "%02d:%02d", hour, $0) } } ?? "Not provided")\nUnits: \(x.unitSystem.label)" + (x.birthYear.map { "\nBirth year: \($0)" } ?? "") + "\n\nDevice lock, subscription and onboarding aren't replaced."
        case .goals:
            let x = s.goals; title = "Body & activity goals"
            text = "Step goal: \(Self.number(x.stepGoal))\nActive energy goal: \(Self.number(x.activeCalGoal)) kcal\nExercise goal: \(Self.number(x.exerciseGoalMin)) min\nStand or roll goal: \(x.standGoal) h\nWeight setting: \(x.weightKg.map { Self.number($0) + " kg" } ?? "Not provided")\nHeight setting: \(x.heightCm.map { Self.number($0) + " cm" } ?? "Not provided")\nAge setting: \(x.age.map(String.init) ?? "Not provided")\nSex setting: \(x.sex.rawValue)\nActivity setting: \(x.activityLevel.label)\nGoal: \(x.goal.label)\n\nThese are saved settings, not current measurements."
        case .habits:
            let x = s.habits[i]; title = x.title; detail = x.isEnabled ? "Enabled" : "Off"
            let timing = x.anchor == .wakePlus ? "after waking" : x.anchor == .bedtimeMinus ? "before bedtime" : "after midnight"
            text = x.detail + "\n\nSaved timing: \(Self.number(x.offset / 60)) min \(timing)\nToday's checkmark resets on recovery."
        case .personalContext:
            let x = s.personalContext; title = "Personal notes"
            text = "Focus\n\(x.focus)\n\nFood preferences\n\(x.foodPreferences)\n\nAllergies\n\(x.allergies)\n\nLimitations\n\(x.limitations)\n\nSchedule\n\(x.schedule)\n\nNotes\n\(x.notes)\n\nAssistant sharing starts off if these notes replace your current ones."
        }
    }
}
