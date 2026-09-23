import SwiftUI

// MARK: - Nutrition: calorie budget + macros + photo-first logging.

public struct NutritionView: View {
    @EnvironmentObject var health: HealthStore
    @State private var showCapture = false
    @State private var showQuickAdd = false

    public init() {}

    var todayMeals: [Meal] { health.meals.filter { Calendar.current.isDateInToday($0.date) }.sorted { $0.date < $1.date } }

    public var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            MacroRingView(eaten: health.caloriesEaten, target: Double(health.goals.calorieTarget()), protein: health.proteinEaten, proteinTarget: Double(health.goals.proteinTarget()))
                            VStack(alignment: .leading, spacing: 6) {
                                Text("BUDGET").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)).tracking(1.2)
                                Text("\(health.caloriesRemaining) left").font(.title2.weight(.bold)).foregroundStyle(.white)
                                    .lineLimit(1).minimumScaleFactor(0.85)
                                Text(health.goals.goal.label + " · TDEE \(Int(health.goals.tdee()))").font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                        }
                        HStack(spacing: 10) {
                            Button { showCapture = true } label: {
                                Label("Snap a meal", systemImage: "camera.fill").font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                            }.buttonStyle(.borderedProminent).tint(.orange).pressable()
                            Button { showQuickAdd = true } label: {
                                Label("Quick add", systemImage: "plus").font(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity).padding(.vertical, 11)
                            }.buttonStyle(.bordered).tint(.white).pressable()
                        }
                    }
                }
                GlassCard {
                    VStack(spacing: 10) {
                        SectionHeader("Macros", subtitle: "Protein-first · fiber matters", systemImage: "chart.pie.fill")
                        MacroBar(label: "Protein", grams: health.proteinEaten, target: Double(health.goals.proteinTarget()), color: .green)
                        MacroBar(label: "Carbs", grams: health.carbsEaten, target: Double(health.goals.calorieTarget()) * 0.45 / 4, color: .cyan)
                        MacroBar(label: "Fat", grams: health.fatEaten, target: Double(health.goals.calorieTarget()) * 0.3 / 9, color: .yellow)
                    }
                }
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            SectionHeader("Hydration", subtitle: "\(Int(health.waterTodayML)) of \(health.plan?.waterTargetML ?? 2500) ml", systemImage: "drop.fill")
                            Spacer()
                            Button("+250 ml") { health.addWater(ml: 250); haptic(.light) }.font(.caption.weight(.bold))
                                .padding(.horizontal, 12).padding(.vertical, 7).background(.cyan.opacity(0.2), in: Capsule()).foregroundStyle(.cyan)
                            Button("+500") { health.addWater(ml: 500); haptic(.light) }.font(.caption.weight(.bold))
                                .padding(.horizontal, 12).padding(.vertical, 7).background(.cyan.opacity(0.2), in: Capsule()).foregroundStyle(.cyan)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.1))
                                Capsule().fill(LinearGradient(colors: [.cyan, .blue], startPoint: .leading, endPoint: .trailing))
                                    .frame(width: geo.size.width * min(1, health.waterTodayML / Double(health.plan?.waterTargetML ?? 2500)))
                            }
                        }.frame(height: 10)
                    }
                }
                ForEach(todayMeals) { meal in MealCard(meal: meal) }
                if todayMeals.isEmpty {
                    Text("No meals yet — snap your first plate.").font(.caption).foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 16).padding(.bottom, 110)
        }
        .background(AuroraBackground())
        .navigationTitle("Nutrition").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showCapture) { MealCaptureView() }
        .sheet(isPresented: $showQuickAdd) { QuickAddSheet() }
    }
}

struct MealCard: View {
    @EnvironmentObject var health: HealthStore
    let meal: Meal
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(meal.type.label).font(.caption.weight(.bold)).foregroundStyle(.orange)
                        .padding(.horizontal, 9).padding(.vertical, 4).background(.orange.opacity(0.15), in: Capsule())
                    Spacer()
                    Text(SleepFormat.time(meal.date)).font(.caption).foregroundStyle(.white.opacity(0.55))
                    Button { health.deleteMeal(meal.id) } label: { Image(systemName: "trash").font(.caption).foregroundStyle(.white.opacity(0.4)) }
                }
                ForEach(meal.items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                            Text("\(Int(item.grams))g · P\(Int(item.proteinG)) C\(Int(item.carbsG)) F\(Int(item.fatG))")
                                .font(.caption2).foregroundStyle(.white.opacity(0.55))
                        }
                        Spacer()
                        Text("\(Int(item.calories))").font(.subheadline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                    }.padding(.vertical, 2)
                }
                HStack {
                    Text("Total").font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.6))
                    Spacer()
                    Text("\(Int(meal.calories)) kcal · \(Int(meal.protein))g protein").font(.caption.weight(.bold)).foregroundStyle(.white)
                }
            }
        }
    }
}

struct QuickAddSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    var results: [FoodItem] { NutritionEngine.shared.search(query) }
    var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                List {
                    ForEach(results) { item in
                        Button {
                            let type = MealType.forHour(Calendar.current.component(.hour, from: Date()))
                            health.addMeal(Meal(type: type, items: [item]))
                            haptic(.light); dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name).foregroundStyle(.white).font(.subheadline.weight(.semibold))
                                    Text("\(Int(item.calories)) kcal · \(Int(item.proteinG))g protein").font(.caption).foregroundStyle(.white.opacity(0.6))
                                }
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(.cyan)
                            }
                        }.listRowBackground(Color.clear)
                    }
                }.scrollContentBackground(.hidden)
                .searchable(text: $query, prompt: "Search foods")
            }
            .navigationTitle("Quick add").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
