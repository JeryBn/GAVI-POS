# GAVI POS

POS privado para un negocio, Flutter/Dart, Android, proyecto iOS y web instalable. Moneda PEN. Web: https://gavi-pos.pages.dev

## Estado y ejecución

Versión 0.1.0 de validación. Ventas, caja, inventario, clientes, pedidos, proveedores/recepciones, devoluciones completas, crédito/abonos, reportes CSV, auditoría, PDF 58/80 mm y sincronización implementados. 17 pruebas aprobadas, análisis sin problemas y pruebas transaccionales en PostgreSQL real. Hardware, firma comercial y restauración productiva pendientes. Leer docs/INFORME-OPERACION.md.

Ejecutar `flutter pub get`, `flutter test` y `flutter run -d chrome`. Sin configuración inicia demostración local. Copiar config.production.example.json a config.production.json para configurar URL, clave publishable y ENABLE_PRODUCTION. Nunca incluir service_role ni contraseña de PostgreSQL en el cliente.

- [Learn Flutter](https://docs.flutter.dev/get-started/learn-flutter)
Web: `flutter build web --release --no-web-resources-cdn --dart-define-from-file=config.production.json`, después `python scripts/prepare_pwa.py`. Publicar build/web completo, incluyendo _headers y gavi_sw.js, en Cloudflare Pages.

Android: `flutter build apk --release --split-per-abi --dart-define-from-file=config.production.json`. Los APK actuales usan firma debug del scaffold: solo pruebas. Cambiar a firma privada custodiada por el propietario antes de distribución comercial.

iOS: abrir ios/Runner.xcworkspace en Xcode/macOS y configurar firma; no compilado en este entorno Windows. Primera vía: Safari → Compartir → Añadir a pantalla de inicio.

## Arquitectura

lib/core contiene base SQLite y operaciones; lib/sync autentica y envía cola; lib/tickets crea PDF; lib/main.dart contiene interfaz; supabase/migrations configura PostgreSQL, RLS y funciones; supabase/tests prueba invariantes con rollback. Aplicar migraciones en orden únicamente en proyecto vacío. Crear usuarios en Auth y perfiles aprobados. El administrador asigna cupos por dispositivo para evitar vender la misma unidad desde varios equipos offline.

Implementación propia, sin código copiado de otros POS. Dependencias con sus licencias originales. El repositorio no concede automáticamente licencia de reventa a terceros; el propietario debe definir contrato de uso. No subir datos del negocio, credenciales, firmas ni respaldos al repositorio.

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
