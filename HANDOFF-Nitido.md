# HANDOFF — Nítido

**Escáner de documentos para iOS: captura, OCR y PDF buscable, todo en el dispositivo.**

Documento de traspaso para Claude Code. Autor del encargo: Raúl García Fernández (ThreeDotsDev).
Fecha: 26 de agosto de 2026.

El nombre comercial *Nítido* es provisional pero se usa de forma consistente en todo el documento. El target de Xcode y el módulo Swift se llaman `Nitido` (sin tilde, para evitar problemas con nombres de módulo); el nombre visible se cambia solo en `CFBundleDisplayName` si más adelante se decide otro.

---

## 1. Qué hay que construir

Una app iOS nativa que haga cuatro cosas muy bien y ninguna más:

1. Capturar documentos con la cámara, en tandas de varias páginas, con detección de bordes y corrección de perspectiva.
2. Limpiar la imagen resultante hasta que parezca un escaneo de verdad, no una foto de un papel.
3. Reconocer el texto en el dispositivo y guardarlo, para poder buscarlo después.
4. Exportar un PDF con una capa de texto invisible encima de la imagen, de manera que el PDF sea buscable en Preview, Adobe o cualquier visor.

Todo local. Sin cuenta, sin servidor, sin red.

El público objetivo es cualquier persona que necesite escanear un DNI, una factura, un contrato o unos apuntes. España y Latinoamérica primero, inglés después.

## 2. Qué NO hay que construir

Esto no está sujeto a interpretación y no se reabre a mitad del proyecto. La lista existe porque cada uno de estos puntos es exactamente lo que ha convertido el nicho del escáner en un vertedero.

- **Nada de cuentas de usuario.** Ni email, ni Google, ni Apple Sign In. La app funciona la primera vez que se abre, sin pantalla de registro.
- **Nada de backend.** No hay API propia, no hay base de datos remota, no hay sincronización en la v1.
- **Nada de red.** No se usa `URLSession` en ningún punto del código de la app. La única conexión que existe es la que hace el sistema por debajo para StoreKit. Esto es una decisión de producto, no una casualidad: es la afirmación de marketing más fuerte que tenemos y se puede verificar leyendo el código.
- **Nada de OCR en la nube.** Ni OpenAI, ni Google Vision, ni Azure. Todo con `Vision` de Apple.
- **Nada de SDKs de terceros.** Ni analítica, ni crash reporting, ni RevenueCat, ni Firebase. StoreKit 2 directamente.
- **Nada de anuncios.** En ninguna versión, ni siquiera en la gratuita.
- **Nada de marca de agua** en los PDF exportados por usuarios gratuitos.
- **Nada de suscripción semanal ni mensual.** Solo anual y de por vida (ver sección 11). Esto no es negociable: la propuesta de valor entera se apoya en no ser una de esas apps.
- **Nada de "IA"** más allá del OCR de Vision. Ni resúmenes, ni chat con el documento, ni clasificación automática. En la v1 no.

Si en algún momento parece que una funcionalidad requiere cruzar alguno de estos límites, **para y pregunta** en lugar de improvisar una solución.

## 3. La tesis del producto, en un párrafo

El escáner es una necesidad universal y el App Store está lleno de clones que cobran 9,99 $ a la semana tras una prueba engañosa, o que exigen cuenta de Adobe, o que meten anuncios entre página y página. Apple Notes escanea gratis pero no hace OCR real, no organiza y no exporta bien. El hueco no es técnico, es de honestidad: una app que hace bien el trabajo, no pide cuenta, no sube nada a ningún sitio y cuesta lo que vale. Todo lo que se construya debe defender esa posición. Cuando dudes entre dos opciones, elige la que un usuario describiría como "es que simplemente funciona y no me molesta".

## 4. Requisitos previos

Confírmalos con Raúl antes de arrancar. Si falta algo, dilo y espera.

| Requisito | Detalle |
|---|---|
| Apple Developer Program de pago | Necesario para probar en dispositivo con capacidades y para StoreKit. |
| Xcode reciente | Con el SDK de iOS actual. |
| iPhone físico | `VNDocumentCameraViewController` **no funciona en el simulador**. Todo lo que toque cámara se prueba en dispositivo. |
| Fichero de tokens de diseño | `DesignTokens.swift` lo entrega Raúl aparte, generado con su sistema propio. **No inventes colores, tipografías, espaciados ni radios.** Si el fichero no está cuando lo necesites, para y pídelo. |
| Documentos de prueba | Al menos: un DNI, una factura con tabla, un folio manuscrito y un documento de varias páginas grapado. Sirven de banco de pruebas del OCR. |

## 5. Stack y decisiones cerradas

Ya están tomadas. No las reabras ni propongas alternativas.

- **Swift + SwiftUI**, nativo. Nada de Flutter, nada de UIKit salvo donde sea obligatorio (envolver `VNDocumentCameraViewController`).
- **Deployment target: iOS 18.** Da el API moderno de Vision en Swift, `@Entry`, controles de Centro de Control y una SwiftData ya asentada. La cobertura de parque en 2026 lo justifica.
- **Swift 6 con concurrencia estricta activada.** Es más trabajo al principio y ahorra una categoría entera de bugs después.
- **Cero dependencias externas.** Ni SPM, ni CocoaPods. Solo frameworks del sistema: SwiftUI, VisionKit, Vision, CoreImage, PDFKit, SwiftData, StoreKit, CoreSpotlight, UniformTypeIdentifiers, AppIntents.
- **Persistencia: SwiftData** para metadatos, **ficheros en el contenedor de la app** para las imágenes. Las imágenes nunca se guardan como `Data` dentro de SwiftData.
- **Arquitectura: MVVM ligero.** Vistas SwiftUI + clases `@Observable` como store por área funcional + una capa de servicios sin estado. No metas Clean Architecture de cuatro capas ni un contenedor de inyección de dependencias en una app de este tamaño. Inyección por inicializador y `.environment`.
- **Localización desde el principio** con String Catalog (`.xcstrings`). Base en español, inglés como segundo idioma. Nada de cadenas escritas a fuego en las vistas.

## 6. Configuración del proyecto

- **Bundle identifier:** `com.threedotsdev.nitido`
- **Nombre del target y del módulo:** `Nitido`
- **Categoría en App Store:** Productividad
- **Orientación:** vertical en iPhone; en iPad se admite todo (la adaptación a iPad es de la Sprint 7, pero no bloquees rotaciones desde el día uno).

### Info.plist

```xml
<key>NSCameraUsageDescription</key>
<string>Nítido usa la cámara para escanear tus documentos. Las imágenes se procesan en tu iPhone y no se envían a ningún servidor.</string>

<key>NSPhotoLibraryAddUsageDescription</key>
<string>Para guardar en Fotos los escaneos que exportes como imagen.</string>
```

No declares `NSPhotoLibraryUsageDescription`: la importación desde Fotos se hace con `PhotosPicker`, que no requiere permiso de lectura de la fototeca. Pedir un permiso que no necesitas es motivo de fricción en la revisión y de desconfianza en el usuario.

### Capacidades

Ninguna especial. Sin App Groups, sin iCloud, sin Background Modes en la v1. Si en algún momento crees que necesitas una capacidad nueva, para y explica por qué antes de añadirla.

### Privacy manifest

Crea `PrivacyInfo.xcprivacy` desde la primera sprint. Contenido:

- `NSPrivacyTracking`: `false`
- `NSPrivacyTrackingDomains`: array vacío
- `NSPrivacyCollectedDataTypes`: array vacío
- `NSPrivacyAccessedAPITypes`: declara las razones de las APIs que uses realmente. Como mínimo `NSPrivacyAccessedAPICategoryUserDefaults` con razón `CA92.1`, y `NSPrivacyAccessedAPICategoryFileTimestamp` con razón `C617.1` si acabas leyendo fechas de fichero. **No copies una lista genérica**: declara solo lo que uses, porque una declaración de más también se revisa.

En App Store Connect, la ficha de privacidad debe quedar en **Data Not Collected**. Si algo que implementas lo impide, es que ese algo no debería estar en la app.

## 7. Arquitectura y estructura de ficheros

```
Nitido/
├── NitidoApp.swift
├── DesignTokens.swift              // lo aporta Raúl. No editar.
├── Models/
│   ├── ScanDocument.swift          // @Model
│   ├── ScanPage.swift              // @Model
│   ├── ScanFolder.swift            // @Model
│   ├── PageFilter.swift            // enum
│   └── OCRBox.swift                // struct Codable
├── Storage/
│   ├── FileStore.swift             // rutas, escritura y borrado de imágenes en disco
│   ├── ThumbnailCache.swift
│   └── ModelContainer+Nitido.swift // configuración de SwiftData, migraciones
├── Scanning/
│   ├── DocumentCameraView.swift    // UIViewControllerRepresentable de VisionKit
│   ├── ImageImporter.swift         // Fotos y Archivos
│   └── QuadDetector.swift          // detección de bordes para imágenes importadas
├── Processing/
│   ├── ImageProcessor.swift        // CoreImage: filtros, recorte, rotación
│   ├── PerspectiveCorrector.swift
│   └── Downsampler.swift           // CGImageSource para miniaturas
├── Recognition/
│   ├── TextRecognizer.swift        // Vision
│   └── OCRResult.swift
├── Export/
│   ├── PDFExporter.swift           // PDF con capa de texto invisible
│   ├── PDFCompression.swift
│   └── ImageExporter.swift
├── Search/
│   ├── DocumentSearch.swift
│   └── SpotlightIndexer.swift
├── Purchases/
│   ├── StoreManager.swift          // StoreKit 2
│   └── Entitlements.swift          // qué desbloquea Pro
├── Intents/
│   └── ScanDocumentIntent.swift    // App Intents
└── Views/
    ├── Library/
    ├── DocumentDetail/
    ├── PageEditor/
    ├── Search/
    ├── Export/
    ├── Paywall/
    └── Settings/
```

Regla de dependencia: las vistas conocen los stores, los stores conocen los servicios, los servicios no conocen a nadie. Ningún servicio importa SwiftUI.

## 8. Modelo de datos y almacenamiento

### SwiftData

```swift
@Model final class ScanFolder {
    var id: UUID
    var name: String
    var createdAt: Date
    var sortIndex: Int
    @Relationship(deleteRule: .nullify, inverse: \ScanDocument.folder)
    var documents: [ScanDocument]
}

@Model final class ScanDocument {
    var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var isFavorite: Bool
    var deletedAt: Date?          // borrado lógico, papelera
    var folder: ScanFolder?
    var searchText: String        // concatenación del OCR de todas las páginas
    @Relationship(deleteRule: .cascade, inverse: \ScanPage.document)
    var pages: [ScanPage]
}

@Model final class ScanPage {
    var id: UUID
    var index: Int
    var originalFileName: String  // relativo, nunca ruta absoluta
    var processedFileName: String
    var thumbnailFileName: String
    var rotation: Int             // 0, 90, 180, 270
    var filterRaw: String         // PageFilter.rawValue
    var quadData: Data?           // 4 puntos normalizados, Codable
    var ocrText: String
    var ocrBoxesData: Data?       // [OCRBox] serializado
    var document: ScanDocument?
}
```

Dos avisos que ahorran una tarde entera:

- **Nunca guardes rutas absolutas.** El contenedor de la app cambia de UUID entre instalaciones y actualizaciones, y todas las imágenes dejarían de encontrarse. Guarda el nombre del fichero y reconstruye la ruta en tiempo de ejecución desde `FileStore`.
- **Nunca guardes imágenes como `Data` en el modelo.** Un documento de treinta páginas convertiría cada consulta en un problema de memoria.

### Disco

```
Application Support/Nitido/Documents/<documentUUID>/
    original-<pageUUID>.heic     // captura tal cual, HEIC para ahorrar espacio
    processed-<pageUUID>.jpg     // resultado de recorte + filtro, calidad 0.9
    thumb-<pageUUID>.jpg         // lado mayor 400 px
```

Aplica protección de datos a ese directorio: `.completeUnlessOpen`. Aquí dentro va a haber DNIs y nóminas, y si el iPhone se pierde con la pantalla bloqueada, esos ficheros deben ser ilegibles.

`FileStore` es el único punto del código que toca `FileManager`. Definelo detrás de un protocolo con implementación concreta local. Si algún día se añade sincronización, se sustituye ahí y en ningún otro sitio.

Excluye el directorio de miniaturas de la copia de seguridad de iCloud (`isExcludedFromBackupKey`), porque se puede regenerar. Los originales y los procesados sí entran en la copia.

## 9. Sprints

Cada sprint termina con algo que Raúl puede ejecutar en su iPhone. No avances a la siguiente sin enseñar resultado y sin que él lo confirme.

---

### Sprint 0 — Esqueleto y cimientos

Montar el proyecto, la estructura de carpetas de la sección 7, el `PrivacyInfo.xcprivacy`, el String Catalog con español e inglés, e integrar `DesignTokens.swift` tal como lo entregue Raúl. Configurar el `ModelContainer` y `FileStore` con sus tests unitarios básicos: crear directorio de documento, escribir un fichero, borrarlo, comprobar que la ruta se reconstruye bien tras simular un cambio de contenedor.

Navegación principal esbozada con `NavigationStack` y pantallas vacías conectadas.

**Criterio de aceptación:** la app compila con concurrencia estricta sin warnings, arranca en el iPhone, muestra una biblioteca vacía y `FileStore` pasa sus tests.

---

### Sprint 1 — Captura y biblioteca

El corazón de la app. `DocumentCameraView` envolviendo `VNDocumentCameraViewController` con `UIViewControllerRepresentable`, con su coordinador manejando los tres callbacks del delegado (finalizado, cancelado, error). VisionKit ya da gratis la detección de bordes, la corrección de perspectiva, el disparo automático y la captura de varias páginas seguidas; no reimplementes nada de eso.

Al terminar la captura: guardar originales en HEIC, generar procesados y miniaturas, crear el `ScanDocument` con sus `ScanPage` y volver a la biblioteca con el documento nuevo ya visible.

Título por defecto: `Escaneo` más la fecha corta localizada. Editable después.

Biblioteca: lista y cuadrícula conmutables, ordenación por fecha o nombre, miniatura de la primera página, número de páginas, fecha. Estado vacío con `ContentUnavailableView`.

Detalle de documento: cuadrícula de páginas, renombrar, borrar (a papelera), añadir más páginas escaneando o importando.

Importación desde Fotos con `PhotosPicker` y desde Archivos con `fileImporter`, aceptando imágenes y PDFs. Un PDF importado se rasteriza página a página con PDFKit y entra como documento normal.

**Criterio de aceptación:** Raúl escanea un documento de cinco páginas, lo ve en la biblioteca, lo abre, añade una sexta importándola de Fotos, cierra la app, la vuelve a abrir y todo sigue ahí.

---

### Sprint 2 — Editor de página

Recorte manual con cuatro tiradores arrastrables sobre la imagen, con lupa o zoom en la esquina para colocarlos con precisión, porque en un móvil el dedo tapa justo lo que hay que ajustar. Los cuatro puntos se guardan normalizados en `quadData`, de modo que el recorte sea reversible y se pueda reeditar.

Corrección de perspectiva con `CIPerspectiveCorrection`.

Para las imágenes importadas, que no pasan por VisionKit, detección automática del cuadrilátero con `VNDetectDocumentSegmentationRequest` como punto de partida del recorte.

Filtros, implementados con CoreImage y aplicados de forma no destructiva (el original nunca se toca):

- **Original**: sin cambios.
- **Color mejorado**: `CIColorControls` con un ligero empujón de contraste y saturación.
- **Escala de grises**: `CIPhotoEffectMono` o `CIColorControls` con saturación cero.
- **Documento**: `CIDocumentEnhancer` con el parámetro de intensidad expuesto en un deslizador. Este es el modo que hace que un folio fotografiado parezca escaneado, y debería ser el que se sugiere por defecto para páginas mayoritariamente de texto.
- **Blanco y negro**: umbral duro, para faxes y firmas.

Rotación en pasos de 90 grados. Reordenar páginas arrastrando. Eliminar página.

La previsualización del filtro se hace sobre una versión reducida de la imagen; el filtro definitivo se aplica a resolución completa solo al confirmar. Si aplicas el filtro a resolución completa en cada movimiento del deslizador, la app se arrastra.

**Criterio de aceptación:** una foto torcida de una factura, tomada a mano y con sombra, queda recta, recortada y legible en menos de cinco toques.

---

### Sprint 3 — OCR y búsqueda

`TextRecognizer` sobre el API moderno de Vision en Swift (`RecognizeTextRequest`), con nivel de reconocimiento preciso, corrección lingüística activada y detección automática de idioma, con español e inglés como candidatos prioritarios.

El OCR se ejecuta sobre la imagen procesada, no sobre la original: el contraste del modo documento mejora bastante la tasa de acierto.

Se guardan dos cosas: el texto plano en `ocrText`, y las cajas normalizadas de cada observación en `ocrBoxesData`. Las cajas no son un extra: son lo que permite el PDF buscable de la Sprint 4. Si las descartas aquí, hay que rehacer el OCR después.

El OCR corre en segundo plano al terminar de guardar un documento, página a página, con indicador de progreso discreto en la ficha del documento. Nunca bloquea la interfaz ni la captura.

Búsqueda global sobre título y texto reconocido, con resaltado del fragmento coincidente en los resultados. Indexación en Core Spotlight con `CSSearchableItem`, para que los documentos aparezcan al buscar desde la pantalla de inicio del iPhone. Deep link desde Spotlight al documento.

Pantalla de texto reconocido por página, con opción de copiar y de exportar `.txt`.

**Criterio de aceptación:** Raúl escanea una factura, busca desde la app una palabra que aparece en mitad de ella y la encuentra; busca esa misma palabra desde el buscador del sistema y el documento aparece.

---

### Sprint 4 — Exportación a PDF

La parte que más va a diferenciar la app y donde más fácil es equivocarse.

Generación con `UIGraphicsPDFRenderer`. Para cada página: se dibuja la imagen procesada y encima se dibuja el texto reconocido **en modo invisible**, colocado en las coordenadas de sus cajas. El resultado es un PDF que se ve como una imagen y se puede seleccionar y buscar como texto.

Detalles concretos:

- El texto invisible se consigue con `cgContext.setTextDrawingMode(.invisible)` antes de dibujar. Si por lo que sea no funciona en tu implementación, la alternativa es dibujar con color `.clear`; comprueba cuál de las dos produce un PDF donde la búsqueda encuentra las palabras y quédate con esa.
- Las coordenadas de Vision son normalizadas y con origen abajo a la izquierda. Las de Core Graphics en un contexto PDF también parten de abajo a la izquierda, pero las de UIKit no. **Ten el eje Y controlado y verifícalo visualmente** dibujando temporalmente el texto en rojo durante el desarrollo, para ver que cae encima de las palabras reales, y solo entonces ponlo en invisible.
- El tamaño de fuente hay que calcularlo para que la anchura de la cadena coincida con la anchura de su caja. Mide la cadena a un tamaño de referencia y escala proporcionalmente. Si usas un tamaño fijo, la selección de texto quedará desplazada respecto a lo que se ve.

Opciones de exportación:

- **Tamaño de página**: ajustar a la imagen (por defecto), A4 o Carta con márgenes.
- **Compresión**: alta (lado mayor 3000 px, JPEG 0.85), media (2000 px, 0.6), baja (1400 px, 0.4). Muestra el peso estimado del fichero antes de exportar; es la información que la gente busca cuando tiene que subir un documento a una sede electrónica con límite de tamaño.
- **Protección con contraseña**, escribiendo con las opciones de propietario y usuario de `PDFDocument`.
- Exportación también a JPG y PNG, página suelta o todas.
- Compartir con la hoja del sistema y guardar en Archivos.

Nombre de fichero por defecto: el título del documento saneado, sin caracteres problemáticos.

**Criterio de aceptación:** el PDF exportado se abre en Preview de macOS y en Adobe Reader, se busca con Cmd+F una palabra que aparece en el documento y el visor la encuentra y la resalta en el sitio correcto.

---

### Sprint 5 — Organización y calidad de vida

Carpetas: crear, renombrar, borrar, mover documentos. Un solo nivel de anidamiento; no hagas un árbol, nadie lo usa y complica la interfaz.

Favoritos. Papelera con borrado lógico mediante `deletedAt` y purga automática de lo que lleve más de treinta días, ejecutada al arrancar. Restaurar desde papelera.

Selección múltiple en la biblioteca para mover, borrar o exportar en lote.

Ajustes: idioma preferido del OCR, filtro por defecto, calidad de exportación por defecto, tamaño ocupado en disco con opción de regenerar miniaturas, enlace a la política de privacidad, versión.

Accesibilidad, y aquí no vale con pasar por encima: etiquetas de VoiceOver en todos los controles, Dynamic Type funcionando hasta los tamaños de accesibilidad sin que se rompan las celdas, contraste suficiente y objetivos táctiles de al menos 44 puntos. Prueba con el inspector de accesibilidad antes de dar la sprint por cerrada.

Estados vacíos, de carga y de error en todas las pantallas. Ningún error se traga en silencio: si el OCR falla en una página, se dice en la ficha del documento y se ofrece reintentar.

**Criterio de aceptación:** se navega la app entera con VoiceOver activado y tamaño de texto grande sin encontrar un control sin etiqueta ni un texto cortado.

---

### Sprint 6 — Monetización

`StoreManager` con StoreKit 2. Carga de productos con `Product.products(for:)`, compra con `purchase()`, comprobación de derechos con `Transaction.currentEntitlements` y escucha permanente de `Transaction.updates` desde el arranque para capturar compras hechas fuera de la app.

El estado Pro se cachea localmente para que la app funcione sin conexión: si el usuario compró y está en un avión, sigue siendo Pro. La comprobación remota nunca bloquea el arranque ni muestra un spinner a pantalla completa.

Los gates exactos están en la sección 11. Aplica el gate en un único sitio (`Entitlements`), nunca repartido por las vistas.

Paywall: precio visible antes de cualquier acción, condiciones de renovación en texto legible, botón de restaurar compras siempre presente, y salida clara sin trucos. Nada de cuenta atrás, nada de "oferta que expira", nada de cerrar disfrazado.

Fichero `.storekit` de configuración para poder probar compras en el simulador y en dispositivo sin subir nada a App Store Connect.

**Criterio de aceptación:** se puede comprar el plan anual y el vitalicio en entorno de pruebas, cerrar la app, reinstalarla, restaurar compras y recuperar el estado Pro.

---

### Sprint 7 — Integración con el sistema y salida a tienda

App Intents con una acción "Escanear documento" para Atajos, Siri y el Centro de Control de iOS 18. Es barato de implementar y hace que la app se sienta parte del teléfono.

Share Extension para recibir imágenes y PDFs desde otras apps y convertirlos en documentos de Nítido.

Adaptación a iPad: la biblioteca en `NavigationSplitView`, cuadrículas que aprovechen el ancho.

Revisión de localización completa en español e inglés, incluyendo los textos de permisos y los metadatos.

Icono de app, capturas de pantalla, texto de la ficha. En la descripción, di explícitamente lo que la app no hace: sin cuenta, sin anuncios, sin subir nada a internet. Es el argumento de venta.

Repaso final contra el checklist de la sección 12.

**Criterio de aceptación:** el build sube a TestFlight sin avisos, Raúl lo instala en su iPhone y en el de otra persona, y ambos escanean, buscan y exportan sin incidencias.

---

## 10. Trampas técnicas conocidas

Esta sección existe para que no pierdas días redescubriéndolas.

**El simulador no tiene cámara de documentos.** `VNDocumentCameraViewController.isSupported` devuelve falso. Comprueba esa propiedad y muestra un camino alternativo (importar desde Fotos) en lugar de dejar un botón que no hace nada.

**La memoria es el enemigo.** Una captura de un iPhone reciente son varios megapíxeles. Si abres un documento de treinta páginas y decodificas todas las imágenes a resolución completa, la app muere. Usa `CGImageSourceCreateThumbnailAtIndex` para todo lo que se muestre en cuadrículas, procesa las páginas de una en una envueltas en `autoreleasepool`, y no mantengas `UIImage` a resolución completa en propiedades de vistas.

**Concurrencia estricta y Vision.** `CIContext`, las peticiones de Vision y el renderizado de PDF no deben correr en el hilo principal, pero SwiftData y las vistas sí están atadas al actor principal. Usa un `ModelActor` para las escrituras en segundo plano y cruza la frontera con tipos `Sendable` sencillos (identificadores, rutas, structs), nunca pasando modelos de SwiftData entre actores. Es la fuente número uno de errores raros en este tipo de app.

**Reutiliza el `CIContext`.** Crear uno por operación es lento y consume memoria. Uno solo, compartido, creado una vez.

**El eje Y.** Vision devuelve coordenadas normalizadas con origen abajo a la izquierda; UIKit dibuja con origen arriba a la izquierda; el contexto PDF de Core Graphics va abajo a la izquierda. Cada vez que muevas cajas de un espacio a otro, verifícalo visualmente antes de seguir.

**No confíes en el orden de lectura de Vision.** Las observaciones no vienen necesariamente ordenadas como leería una persona. Para el texto plano, ordénalas por posición vertical y luego horizontal antes de concatenar, o el `.txt` exportado saldrá desordenado en documentos a dos columnas.

**HEIC no siempre está disponible.** Codifica en HEIC con `CGImageDestination` comprobando el resultado, y cae a JPEG de calidad alta si falla, en lugar de dar por hecho que funcionó.

**SwiftData no tiene búsqueda de texto completo.** Con predicados sobre `searchText` basta para miles de documentos. Si en pruebas con volúmenes grandes se nota lento, dilo y lo hablamos; no montes un índice invertido por tu cuenta.

**Las miniaturas se pueden perder.** Si un fichero de miniatura no existe al pintar la celda, regenéralo desde el procesado en lugar de mostrar un hueco.

## 11. Monetización: gates exactos

Identificadores de producto:

- `com.threedotsdev.nitido.pro.yearly` — Pro anual, 12,99 €, con 7 días de prueba.
- `com.threedotsdev.nitido.pro.lifetime` — Pro de por vida, compra única no consumible, 29,99 €.

No hay plan semanal ni mensual. No se añaden más adelante.

**Gratis, sin límite de tiempo y sin marca de agua:**

- Escaneo de páginas y documentos ilimitados.
- Todos los filtros, recorte, rotación y reordenación.
- Carpetas, favoritos, papelera y búsqueda.
- Exportación a PDF, JPG y PNG.
- Reconocimiento de texto hasta 15 páginas al mes, con contador visible y reinicio el día 1.

**Pro:**

- Reconocimiento de texto sin límite.
- PDF con capa de texto buscable.
- Protección de PDF con contraseña.
- Exportación por lotes de varios documentos.
- Selección manual del idioma de OCR.

El límite del plan gratuito se cuenta en páginas con OCR ejecutado, se guarda localmente y **no se pierde si el usuario cambia la fecha del sistema hacia atrás** (guarda la fecha del último reinicio y compárala de forma monótona). Cuando se agota, la app lo explica sin dramatizar y sigue siendo perfectamente usable para escanear y exportar.

## 12. Checklist de App Review

- **3.1.2**: precios y condiciones de renovación visibles en el paywall antes de comprar; enlace a términos y privacidad; botón de restaurar compras.
- **4.2**: la app tiene funcionalidad de sobra, pero asegúrate de que la primera ejecución muestra valor sin pedir nada.
- **4.3**: hay miles de escáneres. La ficha y las capturas deben dejar claro qué hace distinto esta: procesamiento en el dispositivo, sin cuenta, sin anuncios, PDF buscable. Nada de palabras clave repetidas ni de nombre del tipo "Scanner PDF OCR Doc Scan".
- **5.1.1**: ficha de privacidad en *Data Not Collected*, `PrivacyInfo.xcprivacy` correcto, textos de permiso que explican el porqué en lenguaje humano.
- **2.3**: las capturas se hacen con la app real, no con maquetas.
- Comprueba que la app funciona con la cámara denegada, sin espacio en disco y en modo avión.

## 13. Cómo quiere Raúl que trabajes

- **No avances de sprint sin enseñar resultado.** Cada sprint termina con algo instalable y un resumen corto de qué salió y qué quedó pendiente.
- **No inventes diseño.** Los colores, la tipografía, los espaciados y los radios vienen del fichero de tokens. Si necesitas un valor que no está, pídelo, no lo improvises.
- **Comentarios en castellano** en la lógica de procesado de imagen, en el cálculo de coordenadas del PDF y en cualquier sitio donde haya una decisión no obvia. Esa es la parte que nadie recuerda a los seis meses.
- **Si algo no funciona como esperabas, dilo.** Vale mucho más "el texto invisible del PDF sale desplazado en documentos a dos columnas y no sé por qué" que una implementación que disimula el problema.
- **Prefiere borrar a acumular.** Si una funcionalidad no cabe con calidad en la sprint, se pospone entera; no se entrega a medias.
- **Prueba en dispositivo, siempre.** Lo que funciona en el simulador no dice nada sobre la cámara, la memoria ni el rendimiento real.

## 14. Referencias

- [VisionKit — VNDocumentCameraViewController](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller)
- [Vision — Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
- [Core Image Filter Reference — CIDocumentEnhancer](https://developer.apple.com/documentation/coreimage/cifilter)
- [PDFKit](https://developer.apple.com/documentation/pdfkit)
- [SwiftData](https://developer.apple.com/documentation/swiftdata)
- [StoreKit 2 — In-App Purchase](https://developer.apple.com/documentation/storekit/in-app-purchase)
- [Core Spotlight — CSSearchableItem](https://developer.apple.com/documentation/corespotlight/cssearchableitem)
- [App Store Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [Privacy manifest files](https://developer.apple.com/documentation/bundleresources/privacy-manifest-files)
