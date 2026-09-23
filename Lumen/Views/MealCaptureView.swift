import SwiftUI
import PhotosUI
import UIKit

// MARK: - MealCapture: photo → analysis → confirm in <10 seconds.
// Delight: staged shimmer analysis, editable portions, one-tap save.

public struct MealCaptureView: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    @StateObject private var engine = NutritionEngine.shared

    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var image: Image?
    @State private var analysis: MealAnalysis?
    @State private var mealType: MealType = MealType.forHour(Calendar.current.component(.hour, from: Date()))
    @State private var stage = "Ready"

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                AuroraBackground()
                ScrollView {
                    VStack(spacing: 16) {
                        // Photo well
                        ZStack {
                            RoundedRectangle(cornerRadius: 26, style: .continuous)
                                .fill(.white.opacity(0.06))
                                .frame(height: 260)
                                .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(.white.opacity(0.15), lineWidth: 1))
                            if let image {
                                image.resizable().scaledToFill().frame(height: 260)
                                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                            } else {
                                VStack(spacing: 10) {
                                    Image(systemName: "camera.viewfinder").font(.system(size: 44)).foregroundStyle(.white.opacity(0.7))
                                    Text("Snap your plate").font(.headline).foregroundStyle(.white)
                                    Text("One photo → calories + protein, reviewed by you.").font(.caption).foregroundStyle(.white.opacity(0.6))
                                    PhotosPicker(selection: $pickerItem, matching: .images) {
                                        Text("Choose photo").font(.subheadline.weight(.bold))
                                            .padding(.horizontal, 18).padding(.vertical, 10)
                                            .background(.cyan, in: Capsule()).foregroundStyle(.black)
                                    }
                                }
                            }
                            if engine.isAnalyzing {
                                RoundedRectangle(cornerRadius: 26, style: .continuous).fill(.black.opacity(0.45)).frame(height: 260)
                                VStack(spacing: 8) {
                                    ProgressView().tint(.white)
                                    Text(stage).font(.caption.weight(.bold)).foregroundStyle(.white)
                                }
                            }
                        }

                        Picker("Meal", selection: $mealType) {
                            ForEach(MealType.allCases, id: \.self) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented)

                        if let analysis {
                            GlassCard {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text("AI ESTIMATE").font(.caption2.weight(.bold)).foregroundStyle(.orange).tracking(1.2)
                                        Spacer()
                                        Text("Review portions, then save").font(.caption2).foregroundStyle(.white.opacity(0.55))
                                    }
                                    Text(analysis.headline).font(.headline).foregroundStyle(.white)
                                    ForEach(editableItems.indices, id: \.self) { i in
                                        HStack {
                                            VStack(alignment: .leading) {
                                                Text(editableItems[i].name).font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                                                Text("\(Int(editableItems[i].calories)) kcal · \(Int(editableItems[i].proteinG))g protein").font(.caption2).foregroundStyle(.white.opacity(0.6))
                                            }
                                            Spacer()
                                            Stepper("\(Int(editableItems[i].grams))g", value: $editableItems[i].grams, in: 20...1000, step: 10)
                                                .font(.caption2).foregroundStyle(.white.opacity(0.7))
                                                .onChange(of: editableItems[i].grams) { _, g in scaleItem(id: editableItems[i].id, grams: g) }
                                        }.padding(.vertical, 2)
                                    }
                                    Text(analysis.coachingNote).font(.caption).foregroundStyle(.cyan).lineSpacing(2)
                                    Button {
                                        health.addMeal(Meal(type: mealType, items: editableItems, note: analysis.headline))
                                        haptic(.medium); dismiss()
                                    } label: {
                                        Label("Save \(Int(totalKcal)) kcal", systemImage: "checkmark.circle.fill")
                                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 12)
                                    }.buttonStyle(.borderedProminent).tint(.orange)
                                }
                            }
                        } else if imageData != nil && !engine.isAnalyzing {
                            Button("Analyze photo") { Task { await analyze() } }
                                .buttonStyle(.borderedProminent).tint(.cyan).font(.headline)
                        }
                        Spacer(minLength: 20)
                    }.padding(18)
                }
            }
            .navigationTitle("Log meal").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        imageData = data
                        if let ui = UIImage(data: data) { image = Image(uiImage: ui) }
                        await analyze()
                    }
                }
            }
        }
    }

    @State private var editableItems: [FoodItem] = []
    private var totalKcal: Double { editableItems.reduce(0) { $0 + $1.calories } }

    private func scaleItem(id: String, grams: Double) {
        guard let i = editableItems.firstIndex(where: { $0.id == id }) else { return }
        let base = analysis?.items.first(where: { $0.name == editableItems[i].name })
        let ratio = grams / max(1, (base?.grams ?? editableItems[i].grams))
        // Scale macros linearly from the analyzed base.
        if let b = base {
            editableItems[i].calories = b.calories * ratio
            editableItems[i].proteinG = b.proteinG * ratio
            editableItems[i].carbsG = b.carbsG * ratio
            editableItems[i].fatG = b.fatG * ratio
        }
    }

    private func analyze() async {
        guard let data = imageData else { return }
        stage = "Seeing your plate…"
        try? await Task.sleep(nanoseconds: 300_000_000)
        stage = "Estimating portions…"
        let result = await engine.estimateFromPhoto(imageData: data, mealType: mealType)
        stage = "Checking protein…"
        analysis = result
        editableItems = result.items
    }
}
