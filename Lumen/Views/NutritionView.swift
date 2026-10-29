import SwiftUI

// MARK: - Food: available records, estimated targets, water and meals

public struct NutritionView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @State private var showSearch = false
    @Environment(\.dynamicTypeSize) private var typeSize
    var router: AppRouter { .shared }

    public init() {}

    var units: UnitSystem { sleep.profile.unitSystem }
    var target: Double { Double(health.goals.calorieTarget()) }
    var proteinTarget: Double { Double(health.goals.proteinTarget()) }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                hero
                actions
                water
                meals
                week
            }
            .padding(.horizontal, Theme.gutter).padding(.bottom, 40)
        }
        .lumenScreen(Theme.food)
        .navigationTitle("Food")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.show(.meal(camera: true)) } label: { Image(systemName: "camera") }.accessibilityLabel("Snap a meal")
            }
        }
        .sheet(isPresented: $showSearch) {
            FoodSearchSheet { food in
                health.addMeal(Meal(type: MealType.forHour(Calendar.current.component(.hour, from: Date())), items: [food]))
                router.confirm("\(food.name) added")
            }
        }
    }

    // MARK: Hero

    var hero: some View {
        let energy = health.metrics.reading("calories")
        return VStack(alignment: .leading, spacing: 16) {
            Text("Recorded food energy").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
            Text(HealthMetricCatalog.display(energy.value, key: "calories"))
                .font(.largeTitle.bold()).fontWidth(.expanded).monospacedDigit().accessibilityIdentifier("foodEnergyValue")
            Text("Estimated target: \(HealthMetricCatalog.number((target / 10).rounded() * 10)) kcal").font(.subheadline).foregroundStyle(Theme.secondary)
            if energy.isEstimate { Text("Includes food estimates").font(.footnote).foregroundStyle(Theme.secondary) }
            Text("Available records may cover only part of your intake.").font(.footnote).foregroundStyle(Theme.secondary)
            if let value = energy.value { Bar(value / max(1, target), color: Theme.food, height: 8).accessibilityHidden(true) }
            if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 20) { macros } }
            else { HStack(alignment: .top, spacing: 16) { macros } }
            NavigationLink { CurrentReadingsView() } label: {
                HStack { Text("Review source details"); Spacer(); Image(systemName: "chevron.right").font(.footnote.weight(.semibold)) }
            }.foregroundStyle(Theme.accent).frame(minHeight: 44)
        }.padding(.top, 8)
    }
    @ViewBuilder var macros: some View {
        macro("Protein", key: "protein", target: proteinTarget, color: Theme.steps)
        macro("Carbohydrates", key: "carbs", target: target * 0.45 / 4, color: Theme.water)
        macro("Fat", key: "fat", target: target * 0.3 / 9, color: Theme.food)
    }
    func macro(_ name: String, key: String, target: Double, color: Color) -> some View {
        let value = health.metrics.reading(key).value
        return VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.footnote).foregroundStyle(Theme.secondary)
            Text(HealthMetricCatalog.display(value, key: key)).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.text).accessibilityIdentifier("food-" + key)
            Text("Est. target \(HealthMetricCatalog.number(target.rounded())) g").font(.caption).foregroundStyle(Theme.secondary)
            if let value { Bar(value / max(1, target), color: color, height: 4).accessibilityHidden(true) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    var actions: some View {
        HStack(spacing: 12) {
            Button { router.show(.meal(camera: true)) } label: { Label("Snap a meal", systemImage: "camera.fill") }
                .buttonStyle(LumenPrimaryButtonStyle())
            Button { showSearch = true } label: { Image(systemName: "magnifyingglass").font(.headline) }
                .frame(width: 56, height: 56)
                .background(Theme.surfaceRaised, in: Circle())
                .foregroundStyle(Theme.text)
                .accessibilityLabel("Search foods")
        }
    }

    // MARK: Water

    var water: some View {
        let target = Double(health.plan?.waterTargetML ?? 2500)
        let value = health.metrics.reading("water").value
        return VStack(alignment: .leading, spacing: 12) {
            GroupLabel("Water")
            VStack(alignment: .leading, spacing: 14) {
                Text(value.map { Units.water($0, units) } ?? "Not recorded").font(.title2.weight(.semibold)).monospacedDigit().accessibilityIdentifier("foodWaterValue")
                Text("Estimated target: \((units == .metric ? (target / 1000).formatted(.number.precision(.fractionLength(1))) + " L" : (target / 29.5735).formatted(.number.precision(.fractionLength(0))) + " fl oz"))").font(.footnote).foregroundStyle(Theme.secondary)
                HStack(spacing: 12) {
                    Button("Undo quick log", systemImage: "arrow.uturn.backward") { health.undoLastWater() }
                        .disabled(!health.canUndoQuickWater).frame(minHeight: 44).accessibilityIdentifier("undoQuickWater")
                    Spacer(minLength: 8)
                    Button("+ 250 ml") { health.addWater(ml: 250); haptic(.light) }.frame(minHeight: 44)
                }.font(.subheadline.weight(.semibold))
                if let value { Bar(value / max(1, target), color: Theme.water, height: 6).accessibilityHidden(true) }
                Text("Undo removes the latest quick log from Lumen. Confirmed entries can be changed in Journal.").font(.footnote).foregroundStyle(Theme.secondary)
                if let status = health.waterUndoStatus { Text(status).font(.footnote).foregroundStyle(Theme.secondary).accessibilityIdentifier("waterUndoStatus") }
            }.padding(16).surface()
        }
    }

    // MARK: Meals

    @ViewBuilder var meals: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel("Today's meals")
            if health.mealsToday.isEmpty {
                EmptyStateCard(icon: "fork.knife", title: "Nothing logged yet",
                               message: "Meals you add in Lumen appear here. Source totals can be available without individual meal entries.",
                               actionTitle: "Snap a meal") { router.show(.meal(camera: true)) }
            } else {
                RowGroup {
                    ForEach(Array(health.mealsToday.reversed().enumerated()), id: \.element.id) { i, meal in
                        if i > 0 { RowDivider() }
                        MealRow(meal: meal)
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { withAnimation { health.deleteMeal(meal.id) } }
                            }
                    }
                }
                Text("Touch and hold a meal to delete it.").font(.footnote).foregroundStyle(Theme.tertiary)
            }
        }
    }

    // MARK: Week

    var pastDays: [Date] {
        let cal = Calendar.current
        return (1...7).compactMap { cal.date(byAdding: .day, value: -$0, to: cal.startOfDay(for: Date())) }
            .filter { !health.meals(on: $0).isEmpty }
    }

    @ViewBuilder var week: some View {
        if !pastDays.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                GroupLabel("Past week")
                RowGroup {
                    ForEach(Array(pastDays.enumerated()), id: \.element) { i, day in
                        if i > 0 { RowDivider() }
                        let m = health.meals(on: day)
                        LumenRow(day.formatted(.dateTime.weekday(.wide)),
                                 subtitle: "\(Int(m.reduce(0) { $0 + $1.protein })) g protein",
                                 value: "\(Int(m.reduce(0) { $0 + $1.calories })) kcal", chevron: false)
                    }
                }
            }
        }
    }
}

// MARK: - Meal row (with photo thumbnail)

struct MealRow: View {
    let meal: Meal
    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let img = PhotoStore.load(meal.photoID) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else {
                    Image(systemName: "fork.knife").font(.subheadline).foregroundStyle(Theme.food)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.surfaceRaised)
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.note ?? meal.items.map(\.name).joined(separator: ", ")).font(.body).foregroundStyle(Theme.text).lineLimit(1)
                Text("\(meal.type.label) · \(SleepFormat.time(meal.date)) · \(Int(meal.protein)) g protein").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text("\(Int(meal.calories))").font(.body.monospacedDigit()).foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 10)
    }
}
