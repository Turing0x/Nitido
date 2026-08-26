# Nítido — estado del proyecto

## Sprint 0 — Esqueleto y cimientos ✅

Generado con **XcodeGen** (`project.yml` es la fuente de verdad; `Nitido.xcodeproj`
se regenera con `xcodegen generate` y está en `.gitignore`).

- Target y módulo `Nitido`, bundle `com.threedotsdev.nitido`, iOS 18, Swift 6 con
  `SWIFT_STRICT_CONCURRENCY: complete`. Compila **sin warnings**.
- `Info.plist` con los dos textos de permiso acordados. `NSPhotoLibraryUsageDescription`
  no se declara (la importación irá por `PhotosPicker`).
- `PrivacyInfo.xcprivacy`: tracking `false`, dominios y datos recogidos vacíos, y una
  única API declarada — `NSPrivacyAccessedAPICategoryUserDefaults` con razón `CA92.1`,
  que es la que se usa de verdad (`@AppStorage` de la presentación de la biblioteca).
  `FileTimestamp` (`C617.1`) **no** está declarado porque todavía no se leen fechas de
  fichero; se añadirá el día que se lea alguna.
- Sin capacidades especiales, sin dependencias externas, sin `URLSession`.
- String Catalog `Nitido/Resources/Localizable.xcstrings`, base español + inglés,
  46 claves. Ninguna cadena escrita a fuego en las vistas.
- Estructura de carpetas de la sección 7 creada entera.
- Modelos SwiftData: `ScanDocument`, `ScanPage`, `ScanFolder`, más `PageFilter`,
  `OCRBox` y `QuadPoints`. Solo nombres de fichero relativos; ninguna imagen como `Data`.
- `FileStore`: protocolo `FileStoring` + `LocalFileStore`. Único sitio que toca
  `FileManager`. Protección de datos `.completeUnlessOpen` en la raíz y en los
  directorios de documento; las miniaturas se marcan `isExcludedFromBackupKey`
  (fichero a fichero, para conservar el layout `thumb-*.jpg` dentro del directorio
  del documento y aun así dejarlas fuera de la copia).
- `ModelContainer.nitido(storeDirectory:)` guarda el store dentro de
  `Application Support/Nitido`, junto a las imágenes.
- Navegación esbozada: `TabView` (Documentos · Carpetas · Ajustes), cada una en su
  `NavigationStack`, con pantallas vacías conectadas y `ContentUnavailableView` en todas.
- `DesignTokens.swift` integrado en todas las vistas: color semántico según
  `colorScheme`, tipografía, spacing, radios y `dsEyebrow`. Cero valores de diseño
  inventados; ningún color ni tamaño escrito a fuego fuera del fichero de tokens.
- **11 tests, todos en verde** (`FileStoreTests`, `ModelTests`), incluido el de
  reconstrucción de ruta tras un cambio de contenedor.

Comprobado en el simulador (iPhone 17 Pro): arranca, biblioteca vacía en español,
pestañas navegables.

```bash
xcodegen generate && xcodebuild -project Nitido.xcodeproj -scheme Nitido -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

## Sprint 1 — Captura y biblioteca ✅

Build sin warnings, **25 tests en verde**, probado en el simulador de punta a punta.

**Captura.** `DocumentCameraView` envuelve `VNDocumentCameraViewController` con su
coordinador y los tres callbacks del delegado. Interfaz nativa de Apple, sin
personalizar: detección de bordes, disparo automático y multipágina vienen de serie.
`DocumentCameraView.isSupported` decide si el origen «cámara» aparece en el menú.

**Pipeline de una página** (`PageIngestor`, fuera del hilo principal, una página por
`autoreleasepool`):

1. Original en HEIC, **comprobando el resultado** y cayendo a JPEG 0.95 si el
   dispositivo no lo acepta.
2. Procesado en JPEG 0.9. En esta sprint es el original recodificado —el recorte y la
   perspectiva ya vienen de VisionKit—; los filtros entran aquí en la Sprint 2, siempre
   sobre el original, que no se toca.
3. Miniatura de lado mayor 400 px con `CGImageSourceCreateThumbnailAtIndex`.

La orientación EXIF se resuelve **una sola vez, al importar**, para que el resto del
pipeline (recorte, OCR, PDF) trabaje siempre con píxeles rectos.

**Concurrencia.** `DocumentStore` es un `@ModelActor`: todas las escrituras de
SwiftData salen del hilo principal y lo único que cruza la frontera son tipos
`Sendable` planos (`PageRecord`, `UUID`, `String`). Nunca un modelo. `SendableImage`
envuelve `CGImage` con un `@unchecked` razonado en el propio fichero. `CIContext`
único y compartido.

**Importación.** Fotos con `PhotosPicker` (sin pedir permiso de fototeca, verificado
en el simulador) y Archivos con `fileImporter`, aceptando imágenes y PDF. Un PDF se
rasteriza página a página con PDFKit, con tope de 3000 px de lado mayor y fondo
blanco.

**Biblioteca.** Cuadrícula y lista conmutables, orden por fecha o por nombre,
miniatura de la primera página, número de páginas y fecha, estado vacío y estado «sin
resultados». Botón flotante de escaneo con los tres orígenes. Al terminar una captura
se navega al documento nuevo.

**Detalle.** Cuadrícula de páginas, renombrar, favorito, mover a la papelera (borrado
lógico) y añadir páginas escaneando o importando.

Título por defecto: `Escaneo` + fecha corta localizada, editable.

### Verificado en el simulador

- Importar dos fotos → documento creado, navegación automática, miniaturas correctas.
- Cerrar y reabrir la app → todo sigue ahí.
- Renombrar → persiste.
- Cámara denegada → VisionKit enseña su propia alerta con enlace a Ajustes y la app
  vuelve a la biblioteca sin romperse.

### Dos fallos encontrados y corregidos

1. **Las miniaturas se salían de la celda.** `aspectRatio(_:contentMode: .fill)` sobre
   el contenido empuja el marco en vez de recortarlo, así que una foto apaisada
   desplazaba la columna de al lado. Se ha añadido `PageCard`, que fija la proporción
   con un `Color.clear` y pone el contenido encima, recortado.
2. **La cámara denegada enseñaba el `NSError` crudo** («Error de
   AVFoundationErrorDomain -11852»). Ahora `ScanCoordinator.reportCameraError`
   consulta `AVCaptureDevice.authorizationStatus` —más fiable que el código— y explica
   qué hacer y qué alternativas quedan.

### Pendiente de la Sprint 1

- **La captura real solo se puede validar en dispositivo.** El simulador de iOS 26 sí
  abre `VNDocumentCameraViewController` (al contrario de lo que decía el HANDOFF), pero
  sin cámara real no hay detección de bordes que probar. El criterio de aceptación
  —cinco páginas, añadir una sexta desde Fotos, cerrar y reabrir— hay que ejecutarlo en
  tu iPhone.
- **Importar un PDF desde Archivos** está cubierto por tests (tres páginas A4, tope de
  tamaño, orientación), pero no se ha podido ejercitar en el simulador porque no hay
  forma cómoda de meter un PDF en Archivos.
- **Renombrar**: el campo llega relleno con el título actual y hay que borrarlo a mano
  antes de escribir. Funciona, pero es incómodo con los títulos automáticos, que son
  largos. Candidato claro a la Sprint 5.

## Decisiones cerradas (26/08/2026)

- **Cámara: VisionKit, sin discusión.** `VNDocumentCameraViewController` con su
  interfaz nativa, que ya trae detección de bordes, disparo automático y
  multipágina. El mockup de la pantalla 2 del diseño (modos
  Documento/Tarjeta/Libro/Texto, rejilla, flash manual) queda **descartado**: es
  una cámara propia con AVFoundation y no se construye en la v1. La bandeja de
  lote y la revisión tras captura sí son nuestras y van en el editor de página
  (Sprint 2), donde no hay restricción de VisionKit.
- **Fuera de la v1**, por la sección 2 del HANDOFF: sincronización e icono de nube,
  avatar de cuenta, «Traducir a inglés», «Exportar tabla a CSV» y firmar. Nada de
  esto llegó a implementarse.
- **Pestaña «Herramientas» eliminada**, junto con su vista y sus cuatro cadenas.
- **Nombres de filtro**: manda el HANDOFF (Original · Color mejorado · Escala de
  grises · Documento · Blanco y negro).
- **Claro y oscuro**: la app sigue la apariencia del sistema y los tokens resuelven
  ambas paletas. Comprobado en el simulador en los dos modos.

## Cambios hechos en `DesignTokens.swift`

El fichero **no compilaba** con concurrencia estricta de Swift 6. Dos arreglos
mínimos, ningún valor de diseño tocado:

1. Líneas 192–197, los estilos listos para usar (`title`, `heading`, `body`,
   `callout`, `caption`, `eyebrow`) eran `public static var` y nunca se mutan:
   bajo Swift 6 eso es estado global mutable compartido. Pasados a
   `public static let`.
2. `public struct Shadow` no era `Sendable`, así que sus constantes estáticas
   (`xs`…`xl`, `emeraldGlow`) también fallaban. Añadido `: Sendable`.

Conviene arreglarlo en el generador para que la próxima regeneración no lo pise.

La rama `NSFont` no se ha añadido: el target es iOS-only, sería código muerto.

## Pendiente

- **Ni Geist ni Inter están en el bundle**, así que `DS.Typography.font(_:weight:)`
  cae siempre a la rama del sistema y la tipografía de marca no se ve. Intenté sacar
  el `Inter-VariableFont_opsz_wght.ttf` del proyecto de diseño, pero la lectura de
  ficheros está capada a 256 KiB y llega truncado. **Hacen falta los ficheros de
  fuente** (Geist, y/o Inter como fallback) para dejarlos caer en
  `Nitido/Resources/Fonts/` y declararlos en `UIAppFonts`.
- **Dynamic Type**: `.system(size:)` con tamaño fijo no escala. Se ha añadido
  `Nitido/DesignTokens+DynamicType.swift` — que **no** toca el fichero de tokens —
  con `DS.Typography.scaled(_:weight:relativeTo:)` y los estilos de pantalla ya
  escalables. Los tamaños siguen saliendo de los tokens; solo cambia cómo se aplican.
  La verificación seria con tamaños de accesibilidad es de la Sprint 5.
- **Prueba en dispositivo.** Solo simulador de momento.
- Requisitos de la sección 4 sin confirmar: Apple Developer Program de pago y el
  banco de documentos de prueba (DNI, factura con tabla, folio manuscrito,
  documento de varias páginas).
