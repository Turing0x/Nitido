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

## Sprint 2 — Editor de página ✅

`PageRenderer`, pipeline único y no destructivo para la miniatura de edición y
para la derivada que se persiste: escala → rotación → corrección de
perspectiva → filtro. El original nunca se toca; `preview()` limita a 1600 px
de lado mayor, `fullResolution()` renderiza sin tope solo al confirmar.

**Recorte y perspectiva.** Cuatro puntos (`QuadPoints`) normalizados con Y
hacia abajo en la UI; `PageRenderer` los convierte al sistema de Core Image
(origen abajo) en un único sitio (`ciVector`) antes de `CIPerspectiveCorrection`.
Si el cuadrilátero es la imagen completa (`isFullImage`), se salta la
corrección de perspectiva.

**Detección automática en importadas.** `DocumentQuadDetector` usa
`DetectDocumentSegmentationRequest` (API moderna de Vision), convierte a la
convención de Y de la app y descarta observaciones no usables: cuadrilátero
degenerado, franja estrecha o área (fórmula de Shoelace) menor al 12 % —
umbral para no proponer un recorte inútil. Si Vision falla o no encuentra
nada, la imagen entra igualmente sin recorte sugerido.

**Filtros**, todos en `PageRenderer.applyingFilter`, con `PageFilter` como
enum persistido (`filterRaw`, no renombrable sin migración):

- Original: sin cambios.
- Color mejorado: `CIColorControls` (saturación 1.08, contraste 1.14).
- Escala de grises: `CIColorControls` con saturación 0.
- Documento: `CIDocumentEnhancer` con intensidad expuesta (`documentEnhancementIntensity`,
  0–1), sugerido por defecto (`PageFilter.recommendedDefault`).
- Blanco y negro: gris con contraste 1.25 + `CIColorThreshold` a 0.55.

**Rotación** en pasos de 90°, guardada en `PageEditConfiguration.rotation` y
normalizada antes de mapear a `CGImagePropertyOrientation`.

**Editor** (`PageEditorView`, 364 líneas): tiradores arrastrables sobre los
cuatro puntos, con lupa (zoom 2.2×) que sigue al dedo mientras se arrastra un
tirador, para no tapar el punto que se está ajustando. Previsualización sobre
la versión reducida (1600 px), renderizado a resolución completa solo al
confirmar. Reordenar páginas arrastrando y eliminar página, integrados con
`DocumentStore`.

### Pendiente de la Sprint 2

- Criterio de aceptación (factura torcida, a mano, con sombra → recta y
  legible en menos de cinco toques) sin ejecutar en iPhone físico.

## Sprint 3 — OCR y búsqueda ✅

`TextRecognizer` sobre `RecognizeTextRequest` (API moderna de Vision), nivel
preciso, corrección lingüística y detección automática de idioma
(español/inglés prioritarios). Corre sobre `processedFileName` —el
procesado, no el original— porque el contraste del modo Documento mejora la
tasa de acierto.

Se guardan `ocrText` (texto plano, ya en orden de lectura humano vía
`inReadingOrder()`) y `ocrBoxesData` (`[OCRBox]`, normalizadas, **origen
abajo-izquierda tal como las devuelve Vision, sin convertir** — la conversión
de eje se deja para el punto de dibujo, que es Sprint 4).

OCR en segundo plano tras guardar un documento, página a página, con
indicador discreto en la ficha (`ocrProgress`). Búsqueda global con
resaltado, indexación en Core Spotlight con deep link, pantalla de texto
reconocido con copiar y exportar `.txt`.

## Sprint 4 — Exportación a PDF ✅

**`PDFExporter`**, con `UIGraphicsPDFRenderer`: por página, dibuja la imagen
procesada y encima el texto reconocido en modo invisible
(`setTextDrawingMode(.invisible)`), colocado sobre sus cajas de OCR. La
conversión de eje Y (Vision origen abajo-izquierda → UIKit/PDF origen
arriba-izquierda) vive en un único sitio, `pdfRect(for:in:)`
(`PDFCoordinateMapping.swift`), verificado tanto con tests (caja arriba/abajo/
ancho completo) como generando un PDF real y comprobando con
`PDFDocument.findString` que el texto se encuentra donde se dibujó. El
tamaño de fuente se ajusta midiendo la cadena a un tamaño de referencia
(100 pt) y escalando para que coincida con el ancho de la caja
(`PDFExporter.fittedFontSize`), no un tamaño fijo.

Tres tamaños de página (ajustar a la imagen / A4 / Carta con márgenes), tres
niveles de compresión (`PDFCompression`, 3000/2000/1400 px ·
0.85/0.6/0.4 JPEG) con peso estimado antes de exportar, protección con
contraseña (`PDFPasswordProtector`, un solo campo como owner+user password de
`PDFDocument`), exportación a JPG/PNG página suelta o todas
(`ImageExporter`, varios ficheros en un único `ShareLink`, sin zip).

**Trampa encontrada y corregida en el simulador, no solo en tests:** dibujar
un `CGImage` ya decodificado con `UIImage.draw(in:)` dentro de un contexto
`UIGraphicsPDFRenderer` **no conserva la compresión JPEG** — Core Graphics lo
reincrusta como bitmap, y un documento con un peso estimado de 4,5 MB salía
con 28,3 MB reales. Se arregla construyendo el `CGImage` directamente desde
los bytes JPEG con `CGImage(jpegDataProviderSource:)`, que sí hace que Core
Graphics empotre el mismo flujo comprimido. Con eso, peso estimado y peso
real coinciden exactamente. Comprobado exportando de verdad en el
simulador (PDF y JPG), no solo con la suite de tests.

`ScanCoordinator.savePageEdit` ahora relanza el OCR de la página tras
guardar una edición (rotar/recortar/filtro), para que las cajas de texto no
queden desincronizadas de los píxeles del procesado tras un reajuste
posterior al reconocimiento inicial.

**33 tests nuevos** (coordenadas, ajuste de fuente, compresión, saneado de
nombre, `DocumentStore.exportInfo`, PDF real con búsqueda de texto,
protección con contraseña), **59 en total, todos en verde**.

### Pendiente de la Sprint 4

- Criterio de aceptación real —abrir en Preview de macOS y Adobe Reader,
  Cmd+F— sin ejecutar todavía: solo verificado que Preview de iOS (Vista
  Previa) abre el PDF y genera miniatura correctamente, y que `PDFKit`
  encuentra el texto invisible en su sitio (test automatizado). Falta la
  verificación cruzada en un visor de terceros que el HANDOFF pide
  explícitamente.
- La estimación de peso para JPG/PNG usa como aproximación el mismo cálculo
  JPEG aunque el formato elegido sea PNG (sin pérdida, más pesado); es una
  aproximación deliberada, documentada en el código.

## Sprint 5 — Organización y calidad de vida (en curso, sin accesibilidad)

Carpetas: crear/renombrar/borrar (`FoldersView`), mover documento
(`FolderMoveMenu`) y vista de carpeta (`FolderDetailView`) — hecho en un
commit anterior a esta sesión.

**Papelera con purga automática.** `DocumentStore.expiredTrash(before:)` +
`permanentlyDelete(_:)`; `ScanCoordinator.purgeExpiredTrash()` se llama una
vez al arrancar desde `RootView.task`, sin bloquear el primer frame, y borra
del todo (registro y ficheros) lo que lleve más de 30 días en la papelera.
`TrashView` nueva (`Views/Library/TrashView.swift`), accesible desde Ajustes,
con restaurar y "eliminar definitivamente" con confirmación.

**Selección múltiple** en `LibraryView`: botón "Seleccionar" en la cuadrícula
y en la lista, barra de acciones inferior con mover a carpeta
(`BatchFolderMoveMenu`), papelera en lote y exportación en lote a PDF (varios
ficheros en un único `ShareLink`, mismo patrón que la exportación de imágenes
de la Sprint 4). `DocumentStore.moveToTrash(_ ids:)` y
`moveDocuments(_ ids:toFolder:)` hacen el cambio en un único `save`.

**Favoritos**: ya estaban completos desde antes (toggle + filtro "Solo
favoritos" en `LibraryView`); no hizo falta tocar nada.

**Ajustes** (`SettingsView`) gana tres preferencias y una acción:

- Idioma del OCR (Automático/Español/Inglés) — `OCRLanguagePreference`, en
  `TextRecognizer.swift`. `TextRecognizer.recognize` acepta ahora `languages`
  y `automaticallyDetectsLanguage`, con los valores de siempre como default.
- Filtro por defecto para páginas capturadas con la cámara (sin cuadrilátero
  detectado, que solo pasa en Fotos/Archivos): `PageIngestor.ingest` acepta
  `defaultFilter`, `ScanCoordinator` lo lee de `UserDefaults` (no `@AppStorage`
  directo: no combina con `@Observable`) y lo pasa al ingest.
- Calidad de exportación por defecto: `ExportView` y la exportación en lote
  de la biblioteca leen `settings.exportCompression` en vez de tener `.high`
  fijo.
- "Regenerar miniaturas": `ScanCoordinator.regenerateThumbnails()` recorre
  `DocumentStore.allThumbnailTargets()` y rehace cada miniatura desde su
  procesado.

Enlace a política de privacidad: **no añadido** — no hay URL real en el
repo ni se ha inventado una; el texto explicativo se deja como estaba.

**OCR: fallo visible y reintento.** `ScanPage.ocrFailed` (nuevo campo) se
pone a `true` en el `catch` de `ScanCoordinator.runOCR` en vez de tragarse el
error en silencio, y a `false` en cuanto un reconocimiento tiene éxito.
`DocumentDetailView` enseña una insignia de aviso sobre la página con el
texto fallido y un botón que llama a `ScanCoordinator.retryOCR(pageID:documentID:)`.

**68 tests, todos en verde** (11 nuevos: papelera en lote, borrado
definitivo, expiración por fecha de corte, mover de carpeta en lote, y el
flag `ocrFailed`).

### Pendiente de la Sprint 5

- **Accesibilidad completa**, deliberadamente fuera de esta ronda: etiquetas
  de VoiceOver exhaustivas, verificación con tamaños de Dynamic Type de
  accesibilidad y con el inspector de accesibilidad.
- ~~Enlace a política de privacidad~~ añadido en Ajustes.
- Verificación en dispositivo físico de todo lo de esta sprint.

## Sprint 6 — Monetización (compila y tests en verde; ciclo StoreKit sin probar a mano)

Escrita en un contenedor Linux y verificada después en el Mac (29/09/2026):
`xcodegen generate && xcodebuild … test` compila sin warnings de Swift y
pasa **98 tests en 19 suites, todos en verde**. Sigue sin probarse a mano el
ciclo de compra en el simulador.

### Piezas nuevas (`Nitido/Purchases/`)

- **`OCRQuota`**: `struct Sendable` puro con la aritmética del contador
  mensual. Recibe estado y fecha, devuelve estado nuevo; ni `UserDefaults` ni
  StoreKit dentro. Es lo que de verdad se prueba.
- **`StoreManager`**: `@MainActor @Observable`, mismo molde que
  `ScanCoordinator`. Catálogo con `Product.products(for:)`, compra con
  `purchase()`, derechos con `Transaction.currentEntitlements` y escucha
  permanente de `Transaction.updates` arrancada desde su `init`. El estado Pro
  se cachea en `UserDefaults` (`purchases.isPro`) solo para que el primer
  fotograma salga correcto: `currentEntitlements` ya responde sin red, así que
  el modo avión funciona por sí solo.
- **`Entitlements`**: el único sitio que decide qué está permitido. Depende de
  `ProStateProviding` —protocolo, con `StoreManager` como implementación— para
  que los gates se puedan probar sin levantar la tienda.

### Reparto de gratis y Pro

Los cinco gates de la sección 11 del HANDOFF, enganchados donde corresponde:

| Gate | Dónde |
|---|---|
| OCR ilimitado | `ScanCoordinator.runOCR`, consumo por página |
| Idioma manual de OCR | `ScanCoordinator.ocrLanguagePreference` + `SettingsView` |
| PDF buscable | `PDFExportOptions.includesTextLayer` + `ExportView` |
| Contraseña de PDF | `ExportView`, con `exportsPassword` |
| Exportación por lotes | `LibraryView.selectionActionBar` y `exportSelection()` |

Los dos gates de exportación se aplican con propiedades calculadas
(`exportsTextLayer`, `exportsPassword`) en vez de tocando el `@State`: así
basta con que caduque la suscripción para que el interruptor vuelva a su sitio
y el fichero salga como toca, sin depender de haber limpiado ninguna
preferencia guardada.

### Decisiones de producto de esta sprint

- **La cuota se cobra una vez por página.** `ScanPage.ocrCounted` se marca en
  el primer reconocimiento; reintentar tras un fallo o rehacer las cajas tras
  recortar no vuelve a descontar. Recortar una factura no debe costarte el mes.
- **Cuando se agota a mitad de un lote, se reconocen las páginas que quepan** y
  el resto se marcan con `ScanPage.ocrDeferred`. Vuelven solas al empezar el
  mes (`ScanCoordinator.resumeDeferredOCR`, llamado desde `RootView`) o al
  comprar Pro. Los documentos se reanudan de uno en uno, esperando a cada lote:
  lanzarlos a la vez reventaría la memoria por la misma razón por la que el
  bucle de `runOCR` es secuencial.
- **El paywall no se abre solo.** Tocar un control de pago muestra un aviso con
  lo que hace esa función, y solo el botón explícito presenta la hoja.
- **El interruptor de capa de texto es nuevo.** Antes la capa se generaba
  siempre y no había forma de saber qué llevaba dentro el PDF.

Los dos campos nuevos de `ScanPage` llevan valor por defecto, como el resto del
modelo, así que la migración sigue siendo ligera: no hace falta
`VersionedSchema` ni `MigrationPlan`, ni tocar `Schema.nitido`.

### Reloj y cuota

`OCRQuota.rolledOver(to:)` solo reinicia cuando el mes avanza de verdad. Si la
fecha del sistema va hacia atrás, ni se pone a cero el contador ni retrocede
`periodStart`. Adelantar el reloj sí concede un reinicio, pero deja
`periodStart` en el futuro y volver atrás no concede otro. Sin red no hay reloj
de confianza al que preguntar; lo que se cierra es el caso fácil y repetible.

### Fichero `.storekit`

`Nitido/Resources/Nitido.storekit`, con el anual (P1Y, 12,99, oferta
introductoria `free`/`P1W`) y el vitalicio (`NonConsumable`, 29,99). En
`project.yml` se declara en `schemes.Nitido.run.storeKitConfiguration` y se
excluye de `sources`, porque con `sources: - path: Nitido` cualquier fichero
que no sea Swift acabaría copiado dentro del bundle. **Xcode puede normalizar
el JSON la primera vez que lo abra**; es esperable.

### Texto de privacidad

`settings.privacy.claim` decía "Nítido no usa la red". Con StoreKit eso deja de
ser literalmente cierto, así que ahora dice que los documentos no salen del
dispositivo y que la única conexión es la del sistema con App Store al comprar.
Sigue siendo la afirmación fuerte que era, y además es verdad.

### Tests

18 nuevos, todos sin red ni StoreKit: la aritmética de `OCRQuota` (incluido el
retraso de reloj), los gates de `Entitlements`, el marcado de páginas contadas
y aplazadas en `DocumentStore`, y un PDF exportado sin capa de texto que
efectivamente no se puede buscar.

### Pendiente de la Sprint 6

- **Comprobación manual del ciclo completo**: comprar anual y vitalicio con el
  `.storekit`, cerrar, reinstalar, restaurar y recuperar Pro; agotar la cuota y
  ver que las páginas aplazadas vuelven solas.
- ~~URLs legales~~ hechas (29/09/2026): `LegalLinks` apunta a
  `apps.threedotsdev.com/terms/nitido` y `/privacy/nitido`; Ajustes enlaza las
  dos. **Falta comprobar que las páginas existen y cargan** antes de subir.
- **Alta de los dos productos en App Store Connect** con los identificadores
  exactos, para poder probar en sandbox.
- ~~22 claves de la Sprint 5 sin traducir~~ resueltas en Sprint 7 T3.

## Sprint 7 — Integración con el sistema y salida a tienda (T1–T6 hechas; falta TestFlight y prueba en dispositivo)

Decisiones (29/09/2026): **sin App Intents** (ni Atajos, ni Siri, ni Centro de
Control) y **sin Share Extension** (exigiría App Group). Plan completo en
tareas T1–T6.

### T1 — «Copiar a Nítido» ✅
`CFBundleDocumentTypes` (PDF e imagen, rango `Alternate`, no en el sitio) en
`Info.plist`; `RootView.onOpenURL` → `ScanCoordinator.receiveIncomingFile`, que
encola los ficheros y los importa de uno en uno (un documento por fichero) y
borra la copia de `Inbox` al acabar (`discardIfInbox`, solo si está en `Inbox`).
99 tests en verde. Verificado en el simulador: PDF de 2 páginas desde Archivos →
Compartir → Nítido → documento nuevo abierto y OCR en marcha.
Límite conocido: desde Fotos no aparece Nítido para imágenes (Fotos usa su
propia fila de apps); cubre Archivos, Mail, Safari, etc.

### T2 — iPad ✅
`TARGETED_DEVICE_FAMILY: "1,2"`; orientaciones `~ipad` con las cuatro (iPhone sigue
solo vertical). `RootView` usa `.tabViewStyle(.sidebarAdaptable)`: en iPad la barra
de pestañas se puede plegar a barra lateral, en iPhone no cambia. Las tres
cuadrículas (biblioteca, carpeta, detalle) pasan a `DS.Layout.adaptiveGridColumns`
(`DesignTokens+Layout.swift`, anchura mínima 2 × `Spacing.x20` = 160 pt, sin valor
nuevo): iPhone sigue en 2 columnas, iPad 11" vertical muestra 5. 99 tests en verde.
Verificado en simulador iPad Pro 11" (biblioteca vacía y con datos, detalle) y en
iPhone. **Sin probar**: giro a horizontal (el simulador no lo permite desde aquí),
editor de página y exportación en iPad.
Pendiente menor: el estado vacío dice «este iPhone» también en iPad
(`library.empty`); se resuelve en T3.

### T3 — Localización ES/EN ✅
Catálogo al día: 22 claves de la Sprint 5 añadidas (es + en), las 20 de
`page.*`/`pageEditor.*` completadas en inglés, 4 huérfanas borradas. Las claves con
número usan `%lld`/`%@`. `InfoPlist.xcstrings` nuevo (nombre y dos textos de
permiso, es/en; se compila a `InfoPlist.strings` por idioma). El estado vacío de la
biblioteca dice «este dispositivo» en vez de «este iPhone». `Scripts/audit-strings.py`
compara las claves del código con el catálogo y falla si falta es o en. Verificado en
simulador con `-AppleLanguages (en)`: Ajustes y Papelera, todo en inglés. 99 tests en
verde. Sin revisar pantalla a pantalla el resto de la app en inglés, ni la longitud
de los textos ingleses en Dynamic Type grande (va con accesibilidad).

### T4 — Icono y AccentColor ✅
`Nitido/Assets.xcassets` con `AppIcon` (un solo PNG 1024, `icon-1024.png`) y
`AccentColor` (emerald de `DesignTokens`, claro `h160 s84 l39` y oscuro `h152 s76
l44`, convertidos a sRGB). Declarados en `project.yml`
(`ASSETCATALOG_COMPILER_APPICON_NAME` / `..._GLOBAL_ACCENT_COLOR_NAME`).
`icon.png` original de la raíz **tenía canal alfa** (App Store lo rechaza): el
de la app es el mismo dibujo aplanado sobre blanco, sin alfa. El original queda
en la raíz sin tocar y sin versionar. Verificado en simulador: el icono aparece
en la pantalla de inicio. 99 tests en verde.
Observaciones sobre el dibujo (decisión de Raúl, no se ha tocado): los colores
(cian y amarillo) no son los emerald de la marca, y el marco del móvil llega al
borde del lienzo, así que la máscara redondeada de iOS recorta un poco arriba y
abajo. Además parece un icono de un paquete de iconos: comprobar que su licencia
permite uso comercial en App Store y si exige atribución.

### T5 — Ficha de App Store ✅
`docs/appstore-listing.md`: nombre, subtítulo, texto promocional, palabras clave,
descripción y «novedades» en español e inglés (límites de Apple comprobados),
metadatos, notas para el revisor y guion de 6 capturas. La descripción dice lo que
la app no hace y trae precio, renovación y enlaces (3.1.2); presenta como Pro el PDF
buscable y la contraseña, tal como está en el código. Sin código tocado.
Falta: crear la app y los dos productos en App Store Connect, hacer las capturas
con la app real y con documentos ficticios (las hace Raúl), y responder el
cuestionario de clasificación por edad (se propone 4+).

### T6 — Checklist de App Review (§12) ✅ revisión / ⏳ lo que solo puede hacer Raúl
Compilación **Release para dispositivo** (`generic/platform=iOS`, sin firmar): sin
warnings ni errores; el bundle lleva `PrivacyInfo.xcprivacy`, icono, `Assets.car`,
`es.lproj` y `en.lproj`, iOS mínimo 18.0, iPhone + iPad.

| Punto | Resultado |
|---|---|
| **3.1.2** paywall | ✅ Precio visible antes de comprar (`displayPrice`), texto de renovación con las 24 h, restaurar compras, botón Cerrar, enlaces a términos y privacidad (ya reales y con 200). Sin cuenta atrás ni «oferta que expira» (grep). Sin productos (offline) muestra `unavailablePlans`, no un spinner. |
| **4.2** primera ejecución | ✅ Abre en la biblioteca con estado vacío; no hay registro ni onboarding; la cámara solo se pide al tocar escanear. |
| **4.3** diferenciación | ✅ Ficha (T5) y nombre sin palabras clave. Solo Raúl puede juzgar el resultado. |
| **5.1.1** privacidad | ✅ Sin `URLSession`/WebKit/Safari en todo el código. Manifiesto: `UserDefaults` `CA92.1` declarado y es la única API de motivo obligatorio en uso (grep de fechas de fichero, espacio libre y uptime: cero; `totalFileAllocatedSize` no está en la lista). Sin SDKs. Ficha en «Data Not Collected». |
| **2.3** capturas | ⏳ Las hace Raúl con la app real (guion en `docs/appstore-listing.md`). |
| Cámara denegada | ✅ Probado en simulador (Sprint 1). |
| Sin espacio en disco | ⚠️ Solo por lectura de código: `createDocument` captura el fallo, borra el directorio a medio escribir y enseña el error. No probado. |
| Modo avión | ✅ Por diseño: no hay red; Pro sale de caché y `currentEntitlements`. Sin probar con el interruptor real. |

Decisiones de Raúl que no he tomado por él:
- **`ITSAppUsesNonExemptEncryption`**: no está en `Info.plist`. La contraseña de PDF usa
  el cifrado estándar del sistema (PDFKit), que normalmente cuenta como exento. Poner
  `false` evita la pregunta en cada subida, pero es una declaración legal tuya.
- **`NSPhotoLibraryAddUsageDescription`**: está declarada (HANDOFF §6) pero ningún código
  guarda en Fotos (exportar va por `ShareLink`). No causa rechazo; se puede quitar o
  dejar.
- **Versión**: `MARKETING_VERSION 0.1.0`, build `1`. Para la primera versión pública
  hace falta decidir si sale como `1.0.0`.

Sigue sin hacerse (requiere cuenta o dispositivo de Raúl): archivar y subir a TestFlight,
prueba en su iPhone y en el de otra persona (criterio de aceptación de la Sprint 7), y
los pendientes de dispositivo listados más arriba.

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
