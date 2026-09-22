import SwiftUI

// MARK: - Onboarding (day-one personalization like Rise)

public struct OnboardingView: View {
    @EnvironmentObject var store: SleepStore
    @State private var step = 0
    @State private var name = ""
    @State private var age = 30.0
    @State private var chronotype: Chronotype = .intermediate
    @State private var needHours: Double = 8.15
    @State private var wake = Calendar.current.date(from: DateComponents(hour: 7, minute: 0)) ?? Date()
    @State private var usualSlept: Double = 6.75

    public init() {}

    public var body: some View {
        ZStack {
            AuroraBackground()
            VStack {
                // Progress
                HStack(spacing: 6) {
                    ForEach(0..<5) { i in
                        Capsule().fill(i <= step ? Color.cyan : .white.opacity(0.2))
                            .frame(height: 4)
                    }
                }
                .padding(.horizontal, 24).padding(.top, 16)

                TabView(selection: $step) {
                    welcome.tag(0)
                    who.tag(1)
                    chronotypeStep.tag(2)
                    sleepStep.tag(3)
                    wakeStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.spring(response: 0.5), value: step)

                // Nav buttons
                HStack(spacing: 12) {
                    if step > 0 {
                        Button("Back") { withAnimation { step -= 1 } }
                            .buttonStyle(.bordered).tint(.white)
                    }
                    Button(step == 4 ? "Build my plan" : "Continue") {
                        haptic(.medium)
                        if step < 4 {
                            withAnimation { step += 1 }
                        } else {
                            finish()
                        }
                    }
                    .buttonStyle(.borderedProminent).tint(.cyan)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 24).padding(.bottom, 28)
            }
        }
    }

    var welcome: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("LUMEN").font(.caption.weight(.bold)).foregroundStyle(.cyan).tracking(3)
            Text("Know your sleep.\nOwn your energy.").font(.largeTitle.weight(.bold)).foregroundStyle(.white).multilineTextAlignment(.center)
            Text("Personal sleep need · 14-night debt · circadian predictions — powered by 100 years of sleep science.")
                .font(.subheadline).foregroundStyle(.white.opacity(0.7)).multilineTextAlignment(.center).padding(.horizontal, 24)
            Image(systemName: "moon.stars.fill").font(.system(size: 64)).foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .top, endPoint: .bottom))
                .padding(.top, 8)
            Spacer()
        }
    }

    var who: some View {
        onboardCard(title: "About you", subtitle: "Used to estimate your sleep need") {
            TextField("First name", text: $name).textFieldStyle(.roundedBorder).colorScheme(.dark)
            VStack(alignment: .leading) {
                Text("Age: \(Int(age))").font(.headline).foregroundStyle(.white)
                Slider(value: $age, in: 13...80, step: 1).tint(.cyan)
            }
        }
    }

    var chronotypeStep: some View {
        onboardCard(title: "Are you a lark or an owl?", subtitle: "Your clock shifts peaks + melatonin") {
            ForEach([Chronotype.morning, .intermediate, .evening], id: \.self) { c in
                Button {
                    chronotype = c; haptic(.light)
                    // Auto-suggest need shift: owls often carry more debt; keep same.
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(c.label).font(.headline).foregroundStyle(.white)
                            Text(c.description).font(.caption).foregroundStyle(.white.opacity(0.6))
                        }
                        Spacer()
                        Image(systemName: chronotype == c ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(chronotype == c ? .cyan : .white.opacity(0.4)).font(.title2)
                    }
                    .padding(14)
                    .liquidGlass(cornerRadius: 18, tintOpacity: chronotype == c ? 0.25 : 0.1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    var sleepStep: some View {
        onboardCard(title: "How much do you usually sleep?", subtitle: "We'll combine this with your need guess") {
            Text("\(SleepFormat.durationHM(usualSlept*3600)) / night").font(.title2.weight(.bold)).foregroundStyle(.white)
            Slider(value: $usualSlept, in: 4...11, step: 0.25).tint(.cyan)
            Divider().background(.white.opacity(0.12))
            Text("How much do you think you NEED?").font(.subheadline.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
            Text("\(SleepFormat.durationHM(needHours*3600))").font(.title2.weight(.bold)).foregroundStyle(.cyan)
            Slider(value: $needHours, in: 5...11.5, step: 0.0833).tint(.purple)
            Text("Median is ~8h. Almost half need 8h+. Your history will refine this automatically.")
                .font(.caption).foregroundStyle(.white.opacity(0.6))
        }
    }

    var wakeStep: some View {
        onboardCard(title: "Usual wake time?", subtitle: "We anchor everything to a consistent wake") {
            DatePicker("Wake up", selection: $wake, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel).colorScheme(.dark).labelsHidden()
            let debt0 = max(0, (needHours - usualSlept) * 5)
            GlassCard {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PREVIEW").font(.caption2.weight(.bold)).foregroundStyle(.white.opacity(0.55)).tracking(1)
                    Text("Likely debt ~\(String(format: "%.1f hr", debt0)) · Energy ~\(CircadianModel.energyPotential(debt: debt0*3600))")
                        .font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    Text("Lumen will confirm this from your first week of nights.").font(.caption).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }

    func onboardCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack {
            Spacer()
            VStack(alignment: .leading, spacing: 14) {
                Text(title).font(.title.weight(.bold)).foregroundStyle(.white)
                Text(subtitle).font(.subheadline).foregroundStyle(.white.opacity(0.65))
                content()
            }
            .padding(22)
            .liquidGlass()
            .padding(.horizontal, 20)
            Spacer()
        }
    }

    func finish() {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: wake)
        // Blend user's need guess with age default + usual shortfall hint.
        let blended = needHours * 3600 * 0.7 + SleepNeedEstimator.defaultNeed(age: Int(age)) * 0.3
        store.completeOnboarding(
            need: (blended / 300).rounded() * 300,
            chronotype: chronotype,
            wakeHour: comps.hour ?? 7,
            wakeMinute: comps.minute ?? 0,
            name: name
        )
        haptic(.heavy)
    }
}
