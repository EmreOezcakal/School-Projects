import CoreImage
import SwiftUI

final class EditorModel: ObservableObject {
    @Published var settings = EditSettings() {
        didSet { scheduleRender() }
    }
    @Published var presetName = "Original"
    @Published private(set) var preview: UIImage?
    @Published private(set) var thumbnails: [String: UIImage] = [:]

    let original: UIImage
    private let previewSource: CIImage
    private let queue = DispatchQueue(label: "motiv.editor", qos: .userInitiated)
    private var generation = 0

    init(image: UIImage) {
        original = image.normalizedUp()
        let full = CIImage(image: original) ?? CIImage()
        let scale = min(1, 1600 / max(full.extent.width, full.extent.height, 1))
        previewSource = full.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        scheduleRender()
        makeThumbnails()
    }

    func apply(_ preset: FilmPreset) {
        presetName = preset.name
        settings = preset.settings
    }

    func binding(for adjustment: Adjustment) -> Binding<Double> {
        Binding(
            get: { self.settings[keyPath: adjustment.keyPath] },
            set: { value in
                self.settings[keyPath: adjustment.keyPath] = value
                self.presetName = "Eigene"
            }
        )
    }

    /// Rechnet das Bild in voller Auflösung. `completion` läuft auf dem Main-Thread.
    func exportFullResolution(completion: @escaping (UIImage?) -> Void) {
        let settings = self.settings
        let image = original
        queue.async {
            let output = CIImage(image: image).flatMap { FilterEngine.render(settings, source: $0) }
            DispatchQueue.main.async { completion(output) }
        }
    }

    private func scheduleRender() {
        generation += 1
        let round = generation
        let settings = self.settings
        let source = previewSource
        queue.async { [weak self] in
            let image = FilterEngine.render(settings, source: source)
            DispatchQueue.main.async {
                guard let self, self.generation == round else { return }
                self.preview = image
            }
        }
    }

    private func makeThumbnails() {
        let scale = 220 / max(previewSource.extent.width, previewSource.extent.height, 1)
        let small = previewSource.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        queue.async { [weak self] in
            var result: [String: UIImage] = [:]
            for preset in FilmPreset.all {
                result[preset.name] = FilterEngine.render(preset.settings, source: small)
            }
            DispatchQueue.main.async { self?.thumbnails = result }
        }
    }
}

struct EditorView: View {
    @StateObject private var model: EditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var mode = Mode.looks
    @State private var selected = Adjustment.exposure
    @State private var showOriginal = false
    @State private var isSaving = false
    @State private var message: String?

    enum Mode { case looks, adjust }

    init(image: UIImage) {
        _model = StateObject(wrappedValue: EditorModel(image: image))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(uiImage: showOriginal ? model.original : (model.preview ?? model.original))
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onLongPressGesture(minimumDuration: 0.15, perform: {}, onPressingChanged: { showOriginal = $0 })
                    .overlay(alignment: .top) {
                        if let message {
                            Text(message)
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial, in: Capsule())
                                .padding(.top, 8)
                        }
                    }

                Text(showOriginal ? "Original" : "Gedrückt halten zeigt das Original")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Modus", selection: $mode) {
                    Text("Looks").tag(Mode.looks)
                    Text("Anpassen").tag(Mode.adjust)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                Group {
                    if mode == .looks { presetStrip } else { adjustPanel }
                }
                .frame(height: 120)
            }
            .padding(.bottom, 8)
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(model.presetName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Schließen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Sichern") { save() }
                    }
                }
            }
        }
    }

    private var presetStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(FilmPreset.all) { preset in
                    Button {
                        model.apply(preset)
                        Haptics.tick()
                    } label: {
                        VStack(spacing: 6) {
                            Group {
                                if let thumb = model.thumbnails[preset.name] {
                                    Image(uiImage: thumb).resizable().scaledToFill()
                                } else {
                                    Color.white.opacity(0.1)
                                }
                            }
                            .frame(width: 66, height: 82)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.yellow, lineWidth: model.presetName == preset.name ? 2 : 0)
                            )
                            Text(preset.name)
                                .font(.caption2)
                                .foregroundStyle(model.presetName == preset.name ? Color.yellow : Color.white)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
        }
    }

    private var adjustPanel: some View {
        VStack(spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Adjustment.allCases) { adjustment in
                        Button {
                            selected = adjustment
                        } label: {
                            Label(adjustment.title, systemImage: adjustment.symbol)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(
                                    Capsule().fill(selected == adjustment ? Color.yellow : Color.white.opacity(0.12))
                                )
                                .foregroundStyle(selected == adjustment ? Color.black : Color.white)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)
            }
            HStack {
                Slider(value: model.binding(for: selected), in: selected.range)
                    .tint(.yellow)
                Text(String(format: "%+.0f", model.settings[keyPath: selected.keyPath] * 100))
                    .font(.caption.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
                Button {
                    model.binding(for: selected).wrappedValue = 0
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                }
                .accessibilityLabel("Zurücksetzen")
            }
            .padding(.horizontal)
        }
    }

    private func save() {
        isSaving = true
        model.exportFullResolution { image in
            guard let image else {
                isSaving = false
                show("Bearbeiten fehlgeschlagen")
                return
            }
            PhotoSaver.save(image) { ok in
                isSaving = false
                show(ok ? "In Fotos gesichert ✓" : "Kein Zugriff auf Fotos")
            }
        }
    }

    private func show(_ text: String) {
        withAnimation { message = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation { if message == text { message = nil } }
        }
    }
}
