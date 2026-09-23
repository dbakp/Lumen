import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

// MARK: - Log a meal: camera first, then review and save.
// Paths: take a photo · choose a photo · describe it · search foods.
// Without an AI that can see, we never guess a photo — you pick what's on the plate.

public struct MealCaptureView: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    @ObservedObject private var ai = AIService.shared

    var openCamera: Bool

    @State private var showCamera = false
    @State private var cameraDenied = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var photo: UIImage?
    @State private var items: [FoodItem] = []
    @State private var baseItems: [String: FoodItem] = [:]
    @State private var title = ""
    @State private var note = ""
    @State private var mealType: MealType = MealType.forHour(Calendar.current.component(.hour, from: Date()))
    @State private var analyzing = false
    @State private var analysisFailed = false
    @State private var describing = false
    @State private var descriptionText = ""
    @State private var showSearch = false
    @FocusState private var describeFocused: Bool

    public init(openCamera: Bool = false) { self.openCamera = openCamera }

    var total: Double { items.reduce(0) { $0 + $1.calories } }
    var protein: Double { items.reduce(0) { $0 + $1.proteinG } }
    var hasContent: Bool { photo != nil || !items.isEmpty }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if hasContent { review } else { start }
                }
                .padding(.horizontal, Theme.gutter).padding(.top, 8).padding(.bottom, 120)
            }
            .scrollDismissesKeyboard(.interactively)
            .lumenScreen(Theme.food)
            .safeAreaInset(edge: .bottom) {
                if !items.isEmpty {
                    Button { save() } label: {
                        Text("Add \(Int(total)) kcal to \(mealType.label.lowercased())")
                    }
                    .buttonStyle(LumenPrimaryButtonStyle())
                    .padding(.horizontal, Theme.gutter).padding(.bottom, 8)
                    .background(Theme.bg.opacity(0.001))
                }
            }
            .navigationTitle(hasContent ? "Review meal" : "Log a meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if hasContent {
                    ToolbarItem(placement: .primaryAction) { Button("Start over") { reset() } }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image { use(image) }
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showSearch) {
                FoodSearchSheet { food in add(food) }
            }
            .alert("Camera access is off", isPresented: $cameraDenied) {
                Button("Open Settings") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                Button("Not now", role: .cancel) {}
            } message: {
                Text("To snap meals, allow Lumen to use the camera in Settings.")
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self), let ui = UIImage(data: data) { use(ui) }
                }
            }
            .task { if openCamera && !hasContent { await startCamera() } }
        }
        .tint(.white)
    }

    // MARK: Start

    var start: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("What did you eat?").font(.largeTitle.weight(.bold)).foregroundStyle(Theme.text).padding(.top, 12)
            Text(ai.canSeePhotos ? "Snap your plate and Lumen works out the calories and protein. You can adjust anything before saving."
                                 : "Snap your plate, then pick what's on it — or search. You can adjust portions before saving.")
                .font(.body).foregroundStyle(Theme.secondary).padding(.bottom, 8)

            Button { Task { await startCamera() } } label: {
                Label("Take a photo", systemImage: "camera.fill")
            }
            .buttonStyle(LumenPrimaryButtonStyle())

            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label("Choose from Photos", systemImage: "photo.on.rectangle")
                    .font(.headline).foregroundStyle(.white)
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .background(Theme.surfaceRaised, in: Capsule())
            }

            HStack(spacing: 12) {
                if ai.canReadDescriptions {
                    Button { withAnimation { describing = true }; describeFocused = true } label: {
                        Label("Describe it", systemImage: "text.bubble")
                    }
                    .buttonStyle(LumenTonalButtonStyle())
                }
                Button { showSearch = true } label: { Label("Search foods", systemImage: "magnifyingglass") }
                    .buttonStyle(LumenTonalButtonStyle())
                    .accessibilityIdentifier("mealSearch")
            }

            if describing {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("", text: $descriptionText, prompt: Text("e.g. chicken salad with avocado and bread").foregroundStyle(Theme.tertiary), axis: .vertical)
                        .lineLimit(2...4).focused($describeFocused)
                        .padding(14).surface(16)
                    Button {
                        Task { await describe() }
                    } label: {
                        HStack { if analyzing { ProgressView().tint(.black) }; Text(analyzing ? "Estimating…" : "Estimate") }
                    }
                    .buttonStyle(LumenPrimaryButtonStyle())
                    .disabled(descriptionText.trimmingCharacters(in: .whitespaces).isEmpty || analyzing)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !ai.brain.isAI {
                Label("Turn on Apple Intelligence in iOS Settings and Lumen can recognise meals from photos.", systemImage: "sparkles")
                    .font(.footnote).foregroundStyle(Theme.tertiary).padding(.top, 8)
            }
        }
    }

    // MARK: Review

    var review: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let photo {
                Image(uiImage: photo).resizable().scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: 240).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
                    .overlay {
                        if analyzing {
                            ZStack {
                                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).fill(.black.opacity(0.45))
                                VStack(spacing: 10) {
                                    ProgressView().tint(.white)
                                    Text("Looking at your plate…").font(.subheadline.weight(.medium)).foregroundStyle(.white)
                                }
                            }
                        }
                    }
            }

            Picker("Meal", selection: $mealType) {
                ForEach(MealType.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    if !title.isEmpty { Text(title).font(.title2.weight(.semibold)).foregroundStyle(Theme.text) }
                    Text("\(Int(total)) kcal · \(Int(protein)) g protein").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                RowGroup {
                    ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 { RowDivider() }
                        FoodEditRow(item: item) { grams in scale(item.id, grams) } onDelete: {
                            withAnimation { items.removeAll { $0.id == item.id } }
                        }
                    }
                }
                Button { showSearch = true } label: { Label("Add another food", systemImage: "plus") }
                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.text)
                if !note.isEmpty {
                    Label(note, systemImage: "sparkles").font(.footnote).foregroundStyle(Theme.secondary)
                }
                Text("Estimates — adjust portions if they look off.").font(.footnote).foregroundStyle(Theme.tertiary)
            } else if !analyzing {
                VStack(alignment: .leading, spacing: 12) {
                    Text(analysisFailed ? "Couldn't recognise this one" : "What's on the plate?")
                        .font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                    Text("Search and add each food — Lumen fills in the nutrition.").font(.subheadline).foregroundStyle(Theme.secondary)
                    Button { showSearch = true } label: { Label("Search foods", systemImage: "magnifyingglass") }
                        .buttonStyle(LumenPrimaryButtonStyle())
                }
            }
        }
    }

    // MARK: Actions

    func startCamera() async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: showCamera = true
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) { showCamera = true } else { cameraDenied = true }
        default: cameraDenied = true
        }
    }

    func use(_ image: UIImage) {
        photo = image
        items = []
        Task { await analyze(image) }
    }

    func analyze(_ image: UIImage) async {
        guard ai.canSeePhotos else { return }
        analyzing = true; analysisFailed = false
        defer { analyzing = false }
        if let result = await ai.analyzeMeal(image: image) {
            apply(result)
            haptic(.medium)
        } else {
            analysisFailed = true
        }
    }

    func describe() async {
        analyzing = true; defer { analyzing = false }
        describeFocused = false
        if let result = await ai.estimateMeal(description: descriptionText) {
            apply(result)
            if title.isEmpty { title = descriptionText.capitalizedFirst }
        } else {
            analysisFailed = true
            showSearch = true
        }
    }

    func apply(_ a: MealAnalysis) {
        withAnimation(.spring) {
            items = a.items
            title = a.headline
            note = a.coachingNote
            baseItems = Dictionary(uniqueKeysWithValues: a.items.map { ($0.id, $0) })
        }
    }

    func add(_ food: FoodItem) {
        var copy = food
        copy.id = UUID().uuidString
        baseItems[copy.id] = copy
        withAnimation { items.append(copy) }
    }

    func scale(_ id: String, _ grams: Double) {
        guard let i = items.firstIndex(where: { $0.id == id }), let base = baseItems[id], base.grams > 0 else { return }
        let r = grams / base.grams
        items[i].grams = grams
        items[i].calories = base.calories * r
        items[i].proteinG = base.proteinG * r
        items[i].carbsG = base.carbsG * r
        items[i].fatG = base.fatG * r
        items[i].fiberG = base.fiberG * r
    }

    func save() {
        let meal = Meal(type: mealType, items: items, photoID: nil, note: title.isEmpty ? nil : title)
        var saved = meal
        if let photo { PhotoStore.save(photo, id: meal.id); saved.photoID = meal.id }
        health.addMeal(saved)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }

    func reset() {
        withAnimation { photo = nil; items = []; title = ""; note = ""; analysisFailed = false; describing = false; descriptionText = "" }
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Editable food row

struct FoodEditRow: View {
    let item: FoodItem
    let onGrams: (Double) -> Void
    let onDelete: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(item.name).font(.body).foregroundStyle(Theme.text).lineLimit(2)
                Text("\(Int(item.calories)) kcal · \(Int(item.proteinG)) g protein").font(.footnote).foregroundStyle(Theme.secondary)
            }
            Spacer()
            HStack(spacing: 0) {
                Button { onGrams(max(10, item.grams - step)) } label: { Image(systemName: "minus").frame(width: 34, height: 34) }
                Text("\(Int(item.grams)) g").font(.subheadline.monospacedDigit()).frame(minWidth: 52)
                Button { onGrams(item.grams + step) } label: { Image(systemName: "plus").frame(width: 34, height: 34) }
            }
            .foregroundStyle(Theme.text)
            .background(Theme.surfaceRaised, in: Capsule())
            .buttonStyle(.plain)
        }
        .padding(.vertical, 10)
        .contextMenu { Button("Remove", systemImage: "trash", role: .destructive, action: onDelete) }
        .swipeActions { Button("Remove", role: .destructive, action: onDelete) }
    }
    var step: Double { item.grams >= 200 ? 25 : 10 }
}

// MARK: - Food search

struct FoodSearchSheet: View {
    @EnvironmentObject var health: HealthStore
    @Environment(\.dismiss) var dismiss
    @State private var query = ""
    let onPick: (FoodItem) -> Void

    var recent: [FoodItem] { health.meals.suffix(30).flatMap(\.items).reversed() }
    var results: [FoodItem] { NutritionEngine.shared.search(query, recent: recent) }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty && !recent.isEmpty {
                    Section("Recent and common") { rows }
                } else {
                    Section { rows }
                }
            }
            .scrollContentBackground(.hidden)
            .background(AuroraBackground(Theme.food))
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search foods")
            .navigationTitle("Add food").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .overlay {
                if results.isEmpty {
                    ContentUnavailableView("No match", systemImage: "magnifyingglass", description: Text("Try a simpler word, like “rice” or “chicken”."))
                }
            }
        }
        .tint(.white)
    }

    var rows: some View {
        ForEach(results) { item in
            Button {
                onPick(item); haptic(.light); dismiss()
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).foregroundStyle(Theme.text)
                        Text("\(Int(item.grams)) g · \(Int(item.calories)) kcal · \(Int(item.proteinG)) g protein").font(.footnote).foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Image(systemName: "plus.circle.fill").font(.title3).foregroundStyle(Theme.food)
                }
            }
            .listRowBackground(Theme.surface)
        }
    }
}

// MARK: - Camera (system camera UI; asks for permission on first use)

struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = .camera
        p.cameraCaptureMode = .photo
        p.delegate = context.coordinator
        return p
    }
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { onFinish(nil) }
    }
}
