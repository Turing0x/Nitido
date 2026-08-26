import SwiftUI

/// Marco de proporción fija para una página.
///
/// El contenido se recorta al marco en lugar de empujarlo: sin esto, una foto
/// apaisada dentro de una celda vertical se sale de la cuadrícula y desplaza a
/// las de al lado. `Color.clear` fija la proporción y el contenido va encima.
struct PageCard<Content: View>: View {
    var ratio: CGFloat = 3.0 / 4.0
    var dashed = false
    @ViewBuilder var content: () -> Content

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Color.clear
            .aspectRatio(ratio, contentMode: .fit)
            .overlay { content() }
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .strokeBorder(
                        DS.ColorToken.border(scheme),
                        style: StrokeStyle(
                            lineWidth: DS.Border.hairline,
                            dash: dashed ? [6, 4] : []
                        )
                    )
            }
    }
}

/// Celda de la cuadrícula: miniatura de la primera página, número de páginas,
/// título y fecha.
struct DocumentGridCell: View {
    let document: ScanDocument

    @Environment(\.colorScheme) private var scheme

    private var firstPage: ScanPage? { document.orderedPages.first }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.x2) {
            ZStack(alignment: .topTrailing) {
                PageCard {
                    if let firstPage {
                        PageThumbnail(
                            documentID: document.id,
                            thumbnailFileName: firstPage.thumbnailFileName,
                            processedFileName: firstPage.processedFileName,
                            revision: document.updatedAt.timeIntervalSinceReferenceDate
                        )
                    } else {
                        DS.ColorToken.muted(scheme)
                    }
                }

                PageCountBadge(count: document.pages.count)
                    .padding(DS.Spacing.x2)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.x1) {
                Text(document.title)
                    .font(DS.Typography.rowTitle)
                    .foregroundStyle(DS.ColorToken.foreground(scheme))
                    .lineLimit(2)
                Text(document.createdAt, format: .dateTime.day().month().hour().minute())
                    .font(DS.Typography.captionText)
                    .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(accessibilityLabel))
    }

    private var accessibilityLabel: String {
        let pages = String(
            localized: "document.pageCount",
            defaultValue: "\(document.pages.count) páginas"
        )
        return "\(document.title), \(pages)"
    }
}

/// Fila de la lista.
struct DocumentRow: View {
    let document: ScanDocument

    @Environment(\.colorScheme) private var scheme

    private var firstPage: ScanPage? { document.orderedPages.first }

    var body: some View {
        HStack(spacing: DS.Spacing.x3) {
            Group {
                if let firstPage {
                    PageThumbnail(
                        documentID: document.id,
                        thumbnailFileName: firstPage.thumbnailFileName,
                        processedFileName: firstPage.processedFileName,
                        revision: document.updatedAt.timeIntervalSinceReferenceDate
                    )
                } else {
                    DS.ColorToken.muted(scheme)
                }
            }
            .frame(width: 44, height: 58)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.ColorToken.border(scheme), lineWidth: DS.Border.hairline)
            )

            VStack(alignment: .leading, spacing: DS.Spacing.x1) {
                Text(document.title)
                    .font(DS.Typography.rowTitle)
                    .foregroundStyle(DS.ColorToken.foreground(scheme))
                    .lineLimit(1)
                Text(String(
                    localized: "document.pageCount",
                    defaultValue: "\(document.pages.count) páginas"
                ))
                .font(DS.Typography.captionText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
            }

            Spacer(minLength: 0)

            Text(document.createdAt, format: .dateTime.day().month())
                .font(DS.Typography.captionText)
                .foregroundStyle(DS.ColorToken.mutedForeground(scheme))
        }
        .padding(.vertical, DS.Spacing.x1)
    }
}

struct PageCountBadge: View {
    let count: Int

    var body: some View {
        Text(String(localized: "document.pageCountShort", defaultValue: "\(count) pág."))
            .font(DS.Typography.captionText)
            .foregroundStyle(.white)
            .padding(.horizontal, DS.Spacing.x2)
            .padding(.vertical, DS.Spacing.x1)
            .background(.black.opacity(0.65), in: Capsule())
            .accessibilityHidden(true)
    }
}
