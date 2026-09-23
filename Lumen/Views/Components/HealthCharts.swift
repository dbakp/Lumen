import SwiftUI
import Charts

// MARK: - Health charts: rings, macros, HR, weekly load.

public struct TripleRingView: View {
    let move: Double; let exercise: Double; let stand: Double // 0-1 each
    public init(move: Double, exercise: Double, stand: Double) {
        self.move = move; self.exercise = exercise; self.stand = stand
    }
    public var body: some View {
        ZStack {
            Circle().stroke(.pink.opacity(0.22), lineWidth: 12).frame(width: 150, height: 150)
            Circle().trim(from: 0, to: max(0.02, min(1, move)))
                .stroke(.pink, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90)).frame(width: 150, height: 150)
            Circle().stroke(.green.opacity(0.22), lineWidth: 12).frame(width: 118, height: 118)
            Circle().trim(from: 0, to: max(0.02, min(1, exercise)))
                .stroke(.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90)).frame(width: 118, height: 118)
            Circle().stroke(.cyan.opacity(0.22), lineWidth: 12).frame(width: 86, height: 86)
            Circle().trim(from: 0, to: max(0.02, min(1, stand)))
                .stroke(.cyan, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90)).frame(width: 86, height: 86)
        }
        .animation(.spring(response: 0.9, dampingFraction: 0.8), value: move + exercise + stand)
        .frame(width: 170, height: 170)
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
            GlowRing(progress: target > 0 ? eaten/target : 0, colors: [.orange, .pink])
            VStack(spacing: 1) {
                AnimatedNumber(eaten).font(.system(size: 34, weight: .bold, design: .rounded)).foregroundStyle(.white)
                Text("of \(Int(target)) kcal").font(.caption).foregroundStyle(.white.opacity(0.6))
                Text("Protein \(Int(protein))/\(Int(proteinTarget))g")
                    .font(.caption2.weight(.bold)).foregroundStyle(protein >= proteinTarget ? .green : .orange)
                    .padding(.horizontal, 10).padding(.vertical, 3)
                    .background(.white.opacity(0.08), in: Capsule()).padding(.top, 4)
            }
        }.frame(width: 190, height: 190)
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
                Text(label).font(.caption.weight(.bold)).foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("\(Int(grams))g / \(Int(target))g").font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule().fill(LinearGradient(colors: [color, color.opacity(0.6)], startPoint: .leading, endPoint: .trailing))
                        .frame(width: geo.size.width * min(1, target > 0 ? grams/target : 0))
                        .shadow(color: color.opacity(0.5), radius: 6)
                        .animation(.spring(response: 0.8), value: grams)
                }
            }.frame(height: 8)
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
                .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .bottom, endPoint: .top))
                .cornerRadius(6)
        }
        .chartXAxis { AxisMarks(values: .stride(by: .day, count: 2)) { _ in
            AxisValueLabel(format: .dateTime.weekday(.narrow)).font(.caption2).foregroundStyle(.white.opacity(0.55)) } }
        .chartYAxis { AxisMarks { _ in
            AxisValueLabel().font(.caption2).foregroundStyle(.white.opacity(0.5))
            AxisGridLine().foregroundStyle(.white.opacity(0.07)) } }
        .frame(height: 150)
    }
}

public struct WorkoutRow: View {
    let workout: Workout
    public init(_ workout: Workout) { self.workout = workout }
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: workout.kind.icon).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white).frame(width: 40, height: 40)
                .background(LinearGradient(colors: [.cyan.opacity(0.7), .purple.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(workout.title).font(.subheadline.weight(.bold)).foregroundStyle(.white)
                Text("\(workout.kind.label) · \(Int(workout.duration/60)) min\(workout.distanceM.map { " · " + String(format: "%.1f km", $0/1000) } ?? "") · \(workout.source.label)")
                    .font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(workout.activeCalories))").font(.headline.weight(.bold).monospacedDigit()).foregroundStyle(.white)
                Text("kcal").font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.vertical, 6)
    }
}
