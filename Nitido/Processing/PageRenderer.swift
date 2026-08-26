import CoreImage
import CoreGraphics

enum PageRendererError: Error {
    case filterUnavailable(String)
    case renderingFailed
}

/// Pipeline no destructivo común para la miniatura de edición y la exportación
/// persistida. El único resultado que se guarda es una derivada del original.
enum PageRenderer {
    static let previewMaxPixelSize: CGFloat = 1_600

    static func preview(
        _ image: CGImage,
        configuration: PageEditConfiguration
    ) throws -> CGImage {
        try render(image, configuration: configuration, maximumPixelSize: previewMaxPixelSize)
    }

    static func fullResolution(
        _ image: CGImage,
        configuration: PageEditConfiguration
    ) throws -> CGImage {
        try render(image, configuration: configuration, maximumPixelSize: nil)
    }

    private static func render(
        _ image: CGImage,
        configuration: PageEditConfiguration,
        maximumPixelSize: CGFloat?
    ) throws -> CGImage {
        var output = CIImage(cgImage: image)
        output = scaled(output, maximumPixelSize: maximumPixelSize)
        output = rotated(output, degrees: configuration.rotation)

        if !configuration.quad.isFullImage {
            output = try perspectiveCorrected(output, quad: configuration.quad)
        }

        output = try applyingFilter(
            configuration.filter,
            intensity: configuration.documentEnhancementIntensity,
            to: output
        )

        guard let rendered = ImageProcessor.ciContext.createCGImage(output, from: output.extent.integral) else {
            throw PageRendererError.renderingFailed
        }
        return rendered
    }

    private static func scaled(_ image: CIImage, maximumPixelSize: CGFloat?) -> CIImage {
        guard let maximumPixelSize else { return image }
        let longestSide = max(image.extent.width, image.extent.height)
        guard longestSide > maximumPixelSize else { return image }

        let scale = maximumPixelSize / longestSide
        return image.transformed(by: .init(scaleX: scale, y: scale))
    }

    private static func rotated(_ image: CIImage, degrees: Int) -> CIImage {
        let orientation: CGImagePropertyOrientation
        switch PageEditConfiguration.normalizedRotation(degrees) {
        case 90: orientation = .right
        case 180: orientation = .down
        case 270: orientation = .left
        default: orientation = .up
        }

        let oriented = image.oriented(orientation)
        return oriented.transformed(by: .init(
            translationX: -oriented.extent.origin.x,
            y: -oriented.extent.origin.y
        ))
    }

    private static func perspectiveCorrected(_ image: CIImage, quad: QuadPoints) throws -> CIImage {
        guard let filter = CIFilter(name: "CIPerspectiveCorrection") else {
            throw PageRendererError.filterUnavailable("CIPerspectiveCorrection")
        }

        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(ciVector(quad.topLeft, in: image.extent), forKey: "inputTopLeft")
        filter.setValue(ciVector(quad.topRight, in: image.extent), forKey: "inputTopRight")
        filter.setValue(ciVector(quad.bottomRight, in: image.extent), forKey: "inputBottomRight")
        filter.setValue(ciVector(quad.bottomLeft, in: image.extent), forKey: "inputBottomLeft")
        guard let output = filter.outputImage else {
            throw PageRendererError.renderingFailed
        }
        return output
    }

    private static func applyingFilter(
        _ filter: PageFilter,
        intensity: Double,
        to image: CIImage
    ) throws -> CIImage {
        switch filter {
        case .original:
            return image
        case .enhancedColor:
            return try applying("CIColorControls", to: image, parameters: [
                kCIInputSaturationKey: 1.08,
                kCIInputContrastKey: 1.14
            ])
        case .grayscale:
            return try applying("CIColorControls", to: image, parameters: [
                kCIInputSaturationKey: 0
            ])
        case .document:
            return try applying("CIDocumentEnhancer", to: image, parameters: [
                kCIInputAmountKey: intensity
            ])
        case .blackAndWhite:
            let gray = try applying("CIColorControls", to: image, parameters: [
                kCIInputSaturationKey: 0,
                kCIInputContrastKey: 1.25
            ])
            return try applying("CIColorThreshold", to: gray, parameters: [
                "inputThreshold": 0.55
            ])
        }
    }

    private static func applying(
        _ name: String,
        to image: CIImage,
        parameters: [String: Any]
    ) throws -> CIImage {
        guard let filter = CIFilter(name: name) else {
            throw PageRendererError.filterUnavailable(name)
        }
        filter.setValue(image, forKey: kCIInputImageKey)
        for (key, value) in parameters {
            filter.setValue(value, forKey: key)
        }
        guard let output = filter.outputImage else {
            throw PageRendererError.renderingFailed
        }
        return output
    }

    /// La UI almacena coordenadas normalizadas con Y hacia abajo; Core Image
    /// mide desde abajo, por lo que la conversión debe vivir en un único lugar.
    private static func ciVector(_ point: QuadPoints.Point, in extent: CGRect) -> CIVector {
        CIVector(
            x: extent.minX + (point.x * extent.width),
            y: extent.minY + ((1 - point.y) * extent.height)
        )
    }
}
