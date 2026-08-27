import SwiftData
import SwiftUI
import UIKit

struct PageEditorView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case crop
        case improve

        var id: String { rawValue }
        var title: String {
            switch self {
            case .crop: String(localized: "pageEditor.crop", defaultValue: "Recorte")
            case .improve: String(localized: "pageEditor.improve", defaultValue: "Mejora")
            }
        }
    }

    let documentID: UUID
    let pageID: UUID

    @Environment(ScanCoordinator.self) private var coordinator
    @Environment(\.fileStore) private var fileStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Query private var pages: [ScanPage]

    @State private var source: SendableImage?
    @State private var previewImage: UIImage?
    @State private var draft = PageEditConfiguration()
    @State private var mode: Mode = .crop
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var previewTask: Task<Void, Never>?

    init(documentID: UUID, pageID: UUID) {
        self.documentID = documentID
        self.pageID = pageID
        _pages = Query(filter: #Predicate<ScanPage> { $0.id == pageID })
    }

    private var page: ScanPage? { pages.first }

    /// El recorte se pinta encima de la imagen sin reaplicar perspectiva en
    /// cada gesto; la previsualización solo se recalcula al girar, filtrar o
    /// cambiar de modo.
    private var previewSignature: String {
        if mode == .crop {
            "crop-\(draft.rotation)"
        } else {
            "\(draft.rotation)-\(draft.filter.rawValue)-\(draft.documentEnhancementIntensity)"
        }
    }

    var body: some View {
        Group {
            if let page {
                editor(for: page)
            } else {
                ContentUnavailableView(
                    String(localized: "pageEditor.missing.title", defaultValue: "Página no disponible"),
                    systemImage: "doc.questionmark"
                )
            }
        }
        .dsScreenBackground()
        .navigationTitle(String(localized: "pageEditor.title", defaultValue: "Editar página"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar { toolbar }
        .task(id: page?.id) {
            guard let page else { return }
            await load(page)
        }
        .onChange(of: previewSignature) { _, _ in schedulePreview() }
        .onDisappear { previewTask?.cancel() }
        .errorAlert(coordinator: coordinator)
    }

    @ViewBuilder
    private func editor(for page: ScanPage) -> some View {
        if isLoading {
            ProgressView(String(localized: "pageEditor.loading", defaultValue: "Preparando página…"))
        } else if let previewImage {
            VStack(spacing: DS.Spacing.x4) {
                Picker(String(localized: "pageEditor.mode", defaultValue: "Herramienta"), selection: $mode) {
                    ForEach(Mode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DS.Spacing.screenGutter)

                Group {
                    if mode == .crop {
                        CropEditorCanvas(image: previewImage, quad: $draft.quad)
                    } else {
                        Image(uiImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                            .padding(.horizontal, DS.Spacing.screenGutter)
                    }
                }
                .frame(maxHeight: 440)

                if mode == .crop { cropControls } else { filterControls }
                Spacer(minLength: 0)
            }
            .padding(.top, DS.Spacing.x2)
            // Mientras se guarda, el draft ya está capturado: no se admiten más
            // cambios que se perderían al cerrar la vista.
            .disabled(isSaving)
        } else {
            ContentUnavailableView(
                String(localized: "pageEditor.imageUnavailable.title", defaultValue: "No se pudo abrir la imagen"),
                systemImage: "photo.badge.exclamationmark"
            )
        }
    }

    private var cropControls: some View {
        HStack(spacing: DS.Spacing.x3) {
            Button {
                draft.quad = .full
            } label: {
                Label(String(localized: "pageEditor.resetCrop", defaultValue: "Restablecer"), systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.bordered)

            Button {
                draft.rotateClockwise()
            } label: {
                Label(String(localized: "pageEditor.rotate", defaultValue: "Girar"), systemImage: "rotate.right")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, DS.Spacing.screenGutter)
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x3) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Spacing.x2) {
                    ForEach(PageFilter.allCases) { filter in
                        filterButton(filter)
                    }
                }
                .padding(.horizontal, DS.Spacing.screenGutter)
            }

            if draft.filter == .document {
                VStack(alignment: .leading, spacing: DS.Spacing.x1) {
                    Text(String(localized: "pageEditor.documentIntensity", defaultValue: "Intensidad"))
                        .font(DS.Typography.captionText)
                    Slider(value: $draft.documentEnhancementIntensity, in: 0...1)
                        .accessibilityLabel(String(localized: "pageEditor.documentIntensity", defaultValue: "Intensidad"))
                }
                .padding(.horizontal, DS.Spacing.screenGutter)
            }
        }
    }

    private func filterButton(_ filter: PageFilter) -> some View {
        let isSelected = draft.filter == filter
        let background = isSelected ? DS.ColorToken.primary(scheme) : DS.ColorToken.muted(scheme)
        let foreground = isSelected ? Color.black : DS.ColorToken.foreground(scheme)

        return Button { draft.filter = filter } label: {
            Text(filter.displayName)
                .font(DS.Typography.captionText)
                .padding(.horizontal, DS.Spacing.x3)
                .padding(.vertical, DS.Spacing.x2)
                .background(Capsule().fill(background))
                .foregroundStyle(foreground)
        }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(String(localized: "common.cancel", defaultValue: "Cancelar")) { dismiss() }
        }
        ToolbarItem(placement: .topBarTrailing) {
            NavigationLink {
                RecognizedTextView(documentID: documentID, pageID: pageID)
            } label: {
                Label(
                    String(localized: "pageEditor.recognizedText", defaultValue: "Texto reconocido"),
                    systemImage: "doc.text.magnifyingglass"
                )
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button(String(localized: "common.save", defaultValue: "Guardar")) { save() }
                .disabled(source == nil || isSaving)
        }
    }

    private func load(_ page: ScanPage) async {
        isLoading = true
        draft = PageEditConfiguration(
            rotation: page.rotation,
            filter: page.filter,
            documentEnhancementIntensity: page.documentEnhancementIntensity,
            quad: page.quad ?? .full
        )

        let fileStore = fileStore
        let fileName = page.originalFileName
        let documentID = documentID
        source = await Task.detached(priority: .userInitiated) {
            guard let data = try? fileStore.read(fileName: fileName, documentID: documentID),
                  let image = Downsampler.fullImage(from: data)
            else { return nil }
            return image
        }.value
        isLoading = false
        schedulePreview(immediately: true)
    }

    private func schedulePreview(immediately: Bool = false) {
        previewTask?.cancel()
        guard let source else { return }
        let configuration = mode == .crop
            ? PageEditConfiguration(rotation: draft.rotation, quad: .full)
            : draft

        previewTask = Task {
            if !immediately { try? await Task.sleep(for: .milliseconds(110)) }
            guard !Task.isCancelled else { return }
            let image = await Task.detached(priority: .userInitiated) {
                try? PageRenderer.preview(source.cgImage, configuration: configuration)
            }.value
            guard !Task.isCancelled, let image else { return }
            previewImage = UIImage(cgImage: image)
        }
    }

    private func save() {
        isSaving = true
        let draft = draft
        Task {
            let didSave = await coordinator.savePageEdit(draft, pageID: pageID, documentID: documentID)
            isSaving = false
            if didSave { dismiss() }
        }
    }
}

private struct CropEditorCanvas: View {
    let image: UIImage
    @Binding var quad: QuadPoints
    @State private var draggedCorner: QuadPoints.Corner?

    var body: some View {
        GeometryReader { proxy in
            let imageRect = fittedRect(in: proxy.size)
            let points = points(in: imageRect)

            ZStack(alignment: .topLeading) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: imageRect.width, height: imageRect.height)
                    .position(x: imageRect.midX, y: imageRect.midY)

                cropPath(points).stroke(DS.ColorToken.primary(.dark), lineWidth: 2)
                    .background { cropPath(points).fill(DS.ColorToken.primary(.dark).opacity(0.16)) }

                ForEach(QuadPoints.Corner.allCases, id: \.self) { corner in
                    handle(corner, at: points[corner]!, in: imageRect)
                }

                if let corner = draggedCorner, let point = points[corner] {
                    magnifier(at: point, imageRect: imageRect)
                }
            }
            .coordinateSpace(.named("crop"))
        }
        .aspectRatio(CGFloat(image.size.width / max(image.size.height, 1)), contentMode: .fit)
        .padding(.horizontal, DS.Spacing.screenGutter)
        .accessibilityElement(children: .contain)
    }

    private func cropPath(_ points: [QuadPoints.Corner: CGPoint]) -> Path {
        Path { path in
            path.move(to: points[.topLeft]!)
            path.addLine(to: points[.topRight]!)
            path.addLine(to: points[.bottomRight]!)
            path.addLine(to: points[.bottomLeft]!)
            path.closeSubpath()
        }
    }

    private func handle(_ corner: QuadPoints.Corner, at position: CGPoint, in imageRect: CGRect) -> some View {
        Circle()
            .fill(.white)
            .overlay { Circle().stroke(DS.ColorToken.primary(.dark), lineWidth: 3) }
            .frame(width: 28, height: 28)
            .contentShape(Rectangle().inset(by: -16))
            .position(position)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("crop"))
                    .onChanged { value in
                        draggedCorner = corner
                        let candidate = QuadPoints.Point(
                            x: min(max((value.location.x - imageRect.minX) / imageRect.width, 0), 1),
                            y: min(max((value.location.y - imageRect.minY) / imageRect.height, 0), 1)
                        )
                        let updated = quad.replacing(corner, with: candidate)
                        if updated.isValidForEditing { quad = updated }
                    }
                    .onEnded { _ in draggedCorner = nil }
            )
            .accessibilityLabel(accessibilityLabel(for: corner))
            .accessibilityHint(String(localized: "pageEditor.dragHandleHint", defaultValue: "Arrastra para ajustar el recorte"))
    }

    private func magnifier(at point: CGPoint, imageRect: CGRect) -> some View {
        let size: CGFloat = 96
        let zoom: CGFloat = 2.2
        let localX = point.x - imageRect.minX
        let localY = point.y - imageRect.minY
        let lensX = min(max(point.x + (point.x < imageRect.midX ? 64 : -64), size / 2), imageRect.maxX - size / 2)
        let lensY = min(max(point.y + (point.y < imageRect.midY ? 70 : -70), size / 2), imageRect.maxY - size / 2)

        return ZStack {
            Image(uiImage: image)
                .resizable()
                .frame(width: imageRect.width * zoom, height: imageRect.height * zoom)
                .position(
                    x: size / 2 + (imageRect.width / 2 - localX) * zoom,
                    y: size / 2 + (imageRect.height / 2 - localY) * zoom
                )
            Rectangle().fill(.white).frame(width: 1, height: size)
            Rectangle().fill(.white).frame(width: size, height: 1)
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay { Circle().stroke(.white, lineWidth: 3).shadow(radius: 3) }
        .position(x: lensX, y: lensY)
        .accessibilityHidden(true)
    }

    private func points(in rect: CGRect) -> [QuadPoints.Corner: CGPoint] {
        [
            .topLeft: point(quad.topLeft, in: rect),
            .topRight: point(quad.topRight, in: rect),
            .bottomRight: point(quad.bottomRight, in: rect),
            .bottomLeft: point(quad.bottomLeft, in: rect)
        ]
    }

    private func point(_ point: QuadPoints.Point, in rect: CGRect) -> CGPoint {
        .init(x: rect.minX + point.x * rect.width, y: rect.minY + point.y * rect.height)
    }

    private func fittedRect(in size: CGSize) -> CGRect {
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let width = image.size.width * scale
        let height = image.size.height * scale
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func accessibilityLabel(for corner: QuadPoints.Corner) -> String {
        switch corner {
        case .topLeft: String(localized: "pageEditor.handle.topLeft", defaultValue: "Esquina superior izquierda")
        case .topRight: String(localized: "pageEditor.handle.topRight", defaultValue: "Esquina superior derecha")
        case .bottomRight: String(localized: "pageEditor.handle.bottomRight", defaultValue: "Esquina inferior derecha")
        case .bottomLeft: String(localized: "pageEditor.handle.bottomLeft", defaultValue: "Esquina inferior izquierda")
        }
    }
}
