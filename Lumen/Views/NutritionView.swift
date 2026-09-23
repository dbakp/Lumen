import SwiftUI

// MARK: - Food: what's left today → snap → water → meals → week

public struct NutritionView: View {
    @EnvironmentObject var health: HealthStore
    @EnvironmentObject var sleep: SleepStore
    @State private var showSearch = false
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
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Left today").font(.subheadline.weight(.medium)).foregroundStyle(Theme.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(health.caloriesRemaining)").font(.system(size: 56, weight: .semibold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(Theme.text).contentTransition(.numericText())
                    Text("kcal").font(.title3).foregroundStyle(Theme.secondary)
                }
                Text("\(Int(health.caloriesEaten)) eaten of \(Int(target))").font(.subheadline).foregroundStyle(Theme.secondary)
            }
            Bar(health.caloriesEaten / max(1, target), color: Theme.food, height: 8)
            HStack(spacing: 16) {
                macro("Protein", health.proteinEaten, proteinTarget, Theme.steps)
                macro("Carbs", health.carbsEaten, target * 0.45 / 4, Theme.water)
                macro("Fat", health.fatEaten, target * 0.3 / 9, Theme.food)
            }
        }
        .padding(.top, 8)
    }

    func macro(_ name: String, _ g: Double, _ t: Double, _ c: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.footnote).foregroundStyle(Theme.secondary)
            Text("\(Int(g)) / \(Int(t)) g").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.text)
            Bar(g / max(1, t), color: c, height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Actions

    var actions: some View {
        HStack(spacing: 12) {
            Button { router.show(.meal(camera: true)) } label: { Label("Snap a meal", systemImage: "camera.fill") }
                .buttonStyle(LumenPrimaryButtonStyle())
            Button { showSearch = true } label: { Image(systemName: "magnifyingglass").font(.headline) }
                .frame(width: 56, height: 56)
                .background(Theme.surfaceRaised, in: Circle())
                .foregroundStyle(.white)
                .accessibilityLabel("Search foods")
        }
    }

    // MARK: Water

    var water: some View {
        let target = Double(health.plan?.waterTargetML ?? 2500)
        let glasses = Int(health.waterTodayML / 250)
        return VStack(alignment: .leading, spacing: 12) {
            GroupLabel("Water")
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Units.water(health.waterTodayML, units)).font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Theme.text)
                        Text("of \(Units.water(target, units)) · \(glasses) glass\(glasses == 1 ? "" : "es")").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button { health.undoLastWater() } label: {
                        Image(systemName: "minus").font(.headline).frame(width: 44, height: 44).background(Theme.surfaceRaised, in: Circle())
                    }
                    .accessibilityLabel("Remove last glass")
                    .disabled(health.waterTodayML == 0)
                    Button { health.addWater(ml: 250); haptic(.light) } label: {
                        Image(systemName: "plus").font(.headline).foregroundStyle(.black).frame(width: 44, height: 44).background(Theme.water, in: Circle())
                    }
                    .accessibilityLabel("Add a glass of water")
                }
                .foregroundStyle(.white)
                Bar(health.waterTodayML / target, color: Theme.water, height: 6)
            }
            .padding(16).surface()
        }
    }

    // MARK: Meals

    @ViewBuilder var meals: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupLabel("Today's meals")
            if health.mealsToday.isEmpty {
                EmptyStateCard(icon: "fork.knife", title: "Nothing logged yet",
                               message: "Take a photo of your plate — it only takes a few seconds.",
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
