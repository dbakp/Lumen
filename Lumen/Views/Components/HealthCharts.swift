import SwiftUI
import Charts

// MARK: - Health charts: rings, macros, HR, weekly load.

public struct TripleRingView: View {
    let move: Double; let exercise: Double; let stand: Double // 0-1 each
    public init(move: Double, exercise: Double, stand: Double) {
        self.move = move; self.exercise = exercise; self.stand = stand
    }
    public var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            let w = d * 0.085
            ZStack {
                ThinRing(progress: move, color: Theme.move, width: w).frame(width: d - w, height: d - w)
                ThinRing(progress: exercise, color: Theme.steps, width: w).frame(width: d - w * 3.4, height: d - w * 3.4)
                ThinRing(progress: stand, color: Theme.calm, width: w).frame(width: d - w * 5.8, height: d - w * 5.8)
            }
            .frame(width: g.size.width, height: g.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Move \(Int(move * 100)) percent, exercise \(Int(exercise * 100)) percent, stand \(Int(stand * 100)) percent")
    }
}

public struct MacroRingView: View {
    let eaten: Double; let target: Double
    let protein: Double; let proteinTarget: Double
    public init(eaten: Double, target: Double, protein: Double, proteinTarget: Double) {
        self.eaten = eaten; self.target = target; self.protein = protein; self.proteinTarget = proteinTarget
    }
    public var body: some View {
        ZStack {
            ThinRing(progress: target > 0 ? eaten/target : 0, color: Theme.food, width: 10)
            VStack(spacing: 1) {
                AnimatedNumber(eaten).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text("of \(Int(target)) kcal").font(.caption).foregroundStyle(.white.opacity(0.6)).lineLimit(1).minimumScaleFactor(0.8)
                Text("Protein \(Int(protein))/\(Int(proteinTarget))g")
                    .font(.caption2.weight(.bold)).foregroundStyle(protein >= proteinTarget ? .green : .orange)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .background(.white.opacity(0.08), in: Capsule()).padding(.top, 4)
            }
            .padding(18)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

public struct MacroBar: View {
    let label: String; let grams: Double; let target: Double; let color: Color
    public init(label: String, grams: Double, target: Double, color: Color) {
        self.label = label; self.grams = grams; self.target = target; self.color = color
    }
    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label).font(.subheadline).foregroundStyle(Theme.secondary)
                Spacer()
                Text("\(Int(grams)) / \(Int(target)) g").font(.subheadline.monospacedDigit()).foregroundStyle(Theme.text)
            }
            Bar(target > 0 ? grams / target : 0, color: color, height: 6)
        }
    }
}

public struct WeeklyLoadChart: View {
    let workouts: [Workout]
    public init(workouts: [Workout]) { self.workouts = workouts }
    struct Day: Identifiable { var id: Date { date }; var date: Date; var kcal: Double }
    var days: [Day] {
        let cal = Calendar.current
        return (0..<7).map { i in
            let d = cal.date(byAdding: .day, value: i-6, to: Date()) ?? Date()
            let sod = cal.startOfDay(for: d)
            let kcal = workouts.filter { cal.isDate($0.start, inSameDayAs: d) }.reduce(0) { $0 + $1.activeCalories }
            return Day(date: sod, kcal: kcal)
        }
    }
    public var body: some View {
        Chart(days) { d in
            BarMark(x: .value("Day", d.date, unit: .day), y: .value("kcal", d.kcal))
                .foregroundStyle(d.kcal > 0 ? Theme.move : Theme.move.opacity(0.2))
                .cornerRadius(5)
        }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 1)) { _ in
            AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(Theme.tertiary) } }
        .chartYAxis(.hidden)
        .frame(height: 150)
    }
}

public struct WorkoutRow: View {
    let workout: Workout
    let units: UnitSystem
    public init(_ workout: Workout, units: UnitSystem = .metric) { self.workout = workout; self.units = units }
    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: workout.kind.icon).font(.body.weight(.medium)).foregroundStyle(Theme.move).frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title).font(.body).foregroundStyle(Theme.text)
                Text(([ "\(Int(workout.duration / 60)) min" ] + [workout.distanceM.map { Units.distance($0, units) }, workout.avgHR.map { "\(Int($0)) bpm" }].compactMap { $0 })
                        .joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            Text("\(Int(workout.activeCalories)) kcal").font(.body.monospacedDigit()).foregroundStyle(Theme.secondary)
        }
        .padding(.vertical, 12)
    }
}
