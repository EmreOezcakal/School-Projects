import PhotosUI
import SwiftUI

struct CameraScreen: View {
    @ObservedObject var camera: CameraModel
    @ObservedObject var coach: CoachModel
    @StateObject private var level = LevelMonitor()

    @AppStorage("aspect") private var aspectRaw = AspectRatio.portrait9x16.rawValue
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("showLevel") private var showLevel = true
    @AppStorage("smartScan") private var smartScan = false
    @AppStorage("autoSave") private var autoSave = true
    @AppStorage("claudeModel") private var claudeModel = ClaudeCoach.defaultModel

    @State private var drawMode = false
    @State private var drawRect: CGRect?
    @State private var pinchStartZoom: CGFloat?
    @State private var focusPoint: CGPoint?
    @State private var shutterFlash = false
    @State private var showSettings = false
    @State private var editing: EditableImage?
    @State private var pickerItem: PhotosPickerItem?
    @Environment(\.scenePhase) private var scenePhase

    init(camera: CameraModel, coach: CoachModel) {
        self.camera = camera
        self.coach = coach
    }

    private var aspect: AspectRatio { AspectRatio(rawValue: aspectRaw) ?? .portrait9x16 }

    var body: some View {
        VStack(spacing: 0) {
            topBar
                .padding(.horizontal, 20)
                .frame(height: 52)
            viewfinder
            Spacer(minLength: 6)
            hintLine
                .frame(minHeight: 44)
            zoomBar
                .padding(.vertical, 10)
            bottomBar
                .padding(.horizontal, 32)
                .padding(.bottom, 8)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            coach.aspect = aspect
            camera.start()
            level.start()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                camera.start()
                level.start()
            } else if phase == .background {
                camera.stop()
                level.stop()
            }
        }
        .onChange(of: aspectRaw) { coach.aspectChanged(aspect) }
        .onReceive(camera.$zoomPresets) { presets in coach.zoomPresets = presets.map(\.display) }
        .onReceive(camera.$activeZoom) { zoom in coach.currentZoom = zoom }
        .onChange(of: pickerItem) { loadPickedPhoto() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fullScreenCover(item: $editing) { item in EditorView(image: item.image) }
        .overlay {
            if !camera.isAuthorized { permissionHint }
        }
    }

    // MARK: Oben

    private var topBar: some View {
        HStack(spacing: 20) {
            Menu {
                Picker("Format", selection: $aspectRaw) {
                    ForEach(AspectRatio.allCases) { ratio in
                        Text(ratio.rawValue).tag(ratio.rawValue)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "rectangle.portrait")
                    Text(aspect.rawValue).font(.headline)
                    Image(systemName: "chevron.down").font(.caption)
                }
            }
            Spacer()
            Button {
                camera.flashOn.toggle()
            } label: {
                Image(systemName: camera.flashOn ? "bolt.fill" : "bolt.slash")
            }
            .accessibilityLabel("Blitz")
            Button {
                drawMode.toggle()
                if drawMode { coach.clearTarget() }
            } label: {
                Image(systemName: "scribble.variable")
                    .foregroundStyle(drawMode ? Color.yellow : Color.white)
            }
            .accessibilityLabel("Rahmen zeichnen")
            if coach.target != nil {
                Button {
                    coach.clearTarget()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .accessibilityLabel("Rahmen entfernen")
            }
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo.on.rectangle")
            }
            .accessibilityLabel("Foto bearbeiten")
            Button {
                showSettings = true
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .accessibilityLabel("Einstellungen")
        }
        .font(.title3)
        .foregroundStyle(.white)
    }

    // MARK: Sucher

    private var viewfinder: some View {
        GeometryReader { geo in
            let size = geo.size
            let crop = aspect.unitCrop(imageAspect: CoachModel.imageAspect).scaled(to: size)
            ZStack {
                CameraPreview(session: camera.session)
                CropMask(crop: crop)
                    .fill(Color.black.opacity(0.55), style: FillStyle(eoFill: true))
                    .allowsHitTesting(false)
                if showGrid {
                    GridLines(area: crop)
                        .stroke(Color.white.opacity(0.35), lineWidth: 0.6)
                        .allowsHitTesting(false)
                }
                if showLevel, level.isUsable, coach.target == nil {
                    LevelLine(roll: level.rollDegrees, isLevel: level.isLevel, width: crop.width)
                        .position(x: crop.midX, y: crop.midY)
                }
                if let target = coach.target {
                    TargetBox(rect: target.scaled(to: size), aligned: coach.guidance?.aligned == true, label: coach.subject)
                }
                if let drawRect {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .frame(width: drawRect.width, height: drawRect.height)
                        .position(x: drawRect.midX, y: drawRect.midY)
                        .allowsHitTesting(false)
                }
                if let focusPoint {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.yellow, lineWidth: 1.5)
                        .frame(width: 70, height: 70)
                        .position(focusPoint)
                        .allowsHitTesting(false)
                }
                gestureLayer(size: size)
                if shutterFlash {
                    Color.black.allowsHitTesting(false)
                }
            }
            .clipped()
        }
        .aspectRatio(CoachModel.imageAspect, contentMode: .fit)
    }

    private func gestureLayer(size: CGSize) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in focus(at: value.location, size: size) }
            )
            .simultaneousGesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStartZoom ?? camera.activeZoom
                        pinchStartZoom = start
                        camera.setZoom(start * value.magnification, animated: false)
                    }
                    .onEnded { _ in pinchStartZoom = nil }
            )
            .highPriorityGesture(drawGesture(size: size), including: drawMode ? .all : .none)
    }

    private func drawGesture(size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                drawRect = CGRect(x: min(value.startLocation.x, value.location.x),
                                  y: min(value.startLocation.y, value.location.y),
                                  width: abs(value.location.x - value.startLocation.x),
                                  height: abs(value.location.y - value.startLocation.y))
            }
            .onEnded { _ in
                if let rect = drawRect, rect.width > 20, rect.height > 20 {
                    coach.setUserFrame(CGRect(x: rect.minX / size.width, y: rect.minY / size.height,
                                              width: rect.width / size.width, height: rect.height / size.height))
                    Haptics.tick()
                }
                drawRect = nil
                drawMode = false
            }
    }

    private func focus(at point: CGPoint, size: CGSize) {
        guard !drawMode else { return }
        // Hochformat-Punkt → Sensorkoordinaten (Querformat)
        let u = point.x / size.width
        let v = point.y / size.height
        camera.focus(at: CGPoint(x: v, y: 1 - u))
        focusPoint = point
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if focusPoint == point { focusPoint = nil }
        }
    }

    // MARK: Unten

    private var hintText: String {
        if let status = coach.status { return status }
        if coach.isScanning { return "Halte still – ich suche das beste Motiv …" }
        if drawMode { return "Zieh einen Rahmen um das, was du fotografieren willst" }
        if let guidance = coach.guidance { return guidance.text }
        return "Richte die Kamera aus und tippe auf ✦"
    }

    private var hintLine: some View {
        VStack(spacing: 3) {
            Text(hintText)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(coach.guidance?.aligned == true ? Color.yellow : Color.white.opacity(0.85))
            if let tip = coach.tip {
                Text(tip)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .animation(.easeInOut(duration: 0.2), value: hintText)
    }

    private var zoomBar: some View {
        HStack(spacing: 14) {
            ForEach(camera.zoomPresets) { preset in
                let active = isActive(preset)
                Button {
                    selectZoom(preset.display)
                } label: {
                    Text(active ? ZoomPreset.label(camera.activeZoom) : preset.label)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(active ? Color.yellow : Color.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Color.white.opacity(active ? 0.18 : 0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var bottomBar: some View {
        HStack {
            Button {
                if let photo = camera.lastPhoto { editing = EditableImage(image: photo) }
            } label: {
                Group {
                    if let photo = camera.lastPhoto {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Color.white.opacity(0.12)
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.3), lineWidth: 1))
            }
            .disabled(camera.lastPhoto == nil)
            .accessibilityLabel("Letztes Foto bearbeiten")
            Spacer()
            ShutterButton(highlighted: coach.guidance?.aligned == true) { shoot() }
            Spacer()
            ScanButton(isScanning: coach.isScanning,
                       tap: { scan(alternate: false) },
                       longPress: { scan(alternate: true) })
                .frame(width: 56, height: 56)
        }
    }

    private var permissionHint: some View {
        VStack(spacing: 14) {
            Text("Motiv braucht Zugriff auf die Kamera.")
                .font(.headline)
            Button("Einstellungen öffnen") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Aktionen

    /// Die Stufe, in deren Bereich der aktuelle Zoom liegt, wird gelb markiert.
    private func isActive(_ preset: ZoomPreset) -> Bool {
        camera.zoomPresets.last(where: { $0.display <= camera.activeZoom * 1.02 })?.id == preset.id
    }

    private func selectZoom(_ display: CGFloat) {
        let old = camera.activeZoom
        camera.setZoom(display, animated: false)
        coach.zoomChanged(from: old, to: camera.activeZoom)
        Haptics.tick()
    }

    private func scan(alternate: Bool) {
        drawMode = false
        let key = Keychain.read(Keychain.apiKeyAccount) ?? ""
        var useClaude = smartScan
        if alternate { useClaude.toggle() }
        Haptics.tick()
        if useClaude {
            guard !key.isEmpty else {
                coach.flash("Für den Smart-Scan brauchst du einen API-Schlüssel (Einstellungen)")
                return
            }
            coach.scanWithClaude(apiKey: key, model: claudeModel)
        } else {
            coach.scanOnDevice()
        }
    }

    private func shoot() {
        Haptics.shutter()
        shutterFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeIn(duration: 0.2)) { shutterFlash = false }
        }
        let crop = aspect.unitCrop(imageAspect: CoachModel.imageAspect)
        let save = autoSave
        camera.capturePhoto { image in
            guard let image else {
                coach.flash("Foto konnte nicht aufgenommen werden")
                return
            }
            DispatchQueue.global(qos: .userInitiated).async {
                let photo = image.cropped(toUnit: crop)
                DispatchQueue.main.async {
                    camera.lastPhoto = photo
                    coach.clearTarget()
                    if save {
                        PhotoSaver.save(photo) { ok in
                            if !ok { coach.flash("Kein Zugriff auf Fotos – in den iOS-Einstellungen erlauben") }
                        }
                    }
                }
            }
        }
    }

    private func loadPickedPhoto() {
        guard let item = pickerItem else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                editing = EditableImage(image: image)
            }
            pickerItem = nil
        }
    }
}
