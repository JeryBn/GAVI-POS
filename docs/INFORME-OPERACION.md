# GAVI POS — Informe de funcionamiento 0.1.0

Fecha: 8/10/2026. Un negocio, soles PEN. Equipos previstos: cinco Android, tres iPhone, una laptop y dos impresoras Bluetooth de 58 y 80 mm.

## Resultado y verificación

Proyecto Flutter ejecutable, PostgreSQL/Supabase real con tablas privadas, publicación HTTPS https://gavi-pos.pages.dev y APK Android de pruebas. La demostración conserva ejemplos localmente sin enviarlos a la nube. El negocio usa Supabase Auth y perfiles aprobados. Administrador temporal creado por el propietario; contraseña no guardada en el código.

17 pruebas Flutter aprobadas, análisis sin problemas, compilaciones web/Android correctas. La base real pasó pruebas transaccionales de stock, cupos, idempotencia, caja, crédito, pagos, devoluciones, auditoría, ajustes y permisos/RLS; todos los fixtures se revirtieron. PDF 58/80 mm generados, renderizados e inspeccionados. Venta demo y previsualización PDF operadas en Chrome sobre la URL pública. Ingreso del administrador temporal y sincronización real con cero pendientes comprobados. Falta el piloto físico de los ocho teléfonos y ambas impresoras. La entrega es una versión de validación y no una certificación comercial.

## Uso diario

Ensayo real del 8/10: artículo GAVI-TEST-001 con tres unidades, caja inicial cero, venta de una unidad a S/ 1.00, sincronización, devolución auditada y cierre en cero sin diferencia. PostgreSQL confirmó stock/cupo tres y caja cerrada. Artículo desactivado después del ensayo; la venta y devolución de prueba permanecen en historial y deben distinguirse de operaciones comerciales al iniciar el piloto.

1. Entrar con cuenta del trabajador; para practicar elegir un rol demo. Cada usuario tiene almacenamiento separado en ese equipo.
2. Abrir Caja con fondo inicial. Cada dispositivo tiene su propia sesión; no existe una caja única compartida entre los nueve equipos.
3. Buscar producto por nombre, SKU o código escrito por un lector de teclado. Tocar producto y ajustar cantidad. Si el perfil tiene permiso puede editar precio respetando el mínimo autorizado.
4. Elegir cliente y medio de pago. Confirmar venta; documento y stock se guardan juntos. El total se calcula con céntimos enteros. UUID evita duplicados al reintentar.
5. Abrir PDF, compartir o imprimir mediante el sistema operativo. En Ayuda elegir 58/80 mm. El ticket es interno y no reemplaza comprobante fiscal.
6. Revisar Sincronización. Pendientes y rechazos permanecen visibles; cuando vuelve Internet se reintenta. No borrar datos ni reinstalar si hay pendientes.
7. Contar efectivo y cerrar Caja; quedan esperado, contado y diferencia. Tarjeta/transferencia no aumentan efectivo físico.

## Módulos, permisos y alcance real

| Módulo | Implementado | Límite |
|---|---|---|
| Productos | SKU, código, precio, mayorista, mínimo, costo, unidades, umbral | Sin peso, lotes/vencimientos ni cambio automático a tarifa mayorista |
| Ventas | Cantidad, cliente, medios y precio autorizado; stock automático | Sin descuentos porcentuales ni facturación SUNAT |
| Caja | Apertura, entrada/salida con motivo, cierre/diferencia | Por dispositivo |
| Clientes/crédito | Contactos, crédito autorizado, abonos y saldo | Abonos administrados; sin intereses ni cuotas programadas |
| Pedidos | Guardar y convertir una vez | No reserva stock ni entregas parciales |
| Compras/proveedores | Contacto y recepción de unidades/costo con historial | Sin cuentas por pagar u orden de compra completa |
| Inventario | Ajustes auditados y alertas visuales de bajo stock | En negocio la disponibilidad local corresponde al cupo asignado |
| Devoluciones | Completa, motivo, autorización y reposición | Sin parcial; pagos mixtos posteriores requieren conciliación y se bloquean |
| Reportes | Bruto, devoluciones, neto, ranking bruto, filtro desde fecha y CSV | No utilidad contable, impuestos ni balance financiero |
| Trabajadores | Rol, activo, permiso de precio/crédito | Credenciales iniciales desde Supabase Auth; sin invitación automática en app |
| Auditoría | Operaciones en interfaz y before/after central de productos/perfiles | audit_log central se consulta con admin/consola |
| Respaldo | Exportación JSON local | Restauración demo probada en repositorio; restauración productiva y backup central automático pendientes |

Empleado puede vender, usar caja, crear clientes/pedidos y consultar sus operaciones. Administrador gestiona inventario, proveedores, recepciones, devoluciones, abonos, reportes, trabajadores y cupos. Los permisos se verifican en servidor, no solo ocultando botones. Para cambiar administrador, crear el definitivo, comprobar ingreso y luego desactivar el temporal. El servidor protege al último administrador activo y conserva identidad/historial.

## Arquitectura y datos

Flutter comparte lógica e interfaz. SQLite/Drift almacena meta, products, documents y outbox. Cada usuario/dispositivo conserva UUID propio. Web usa SQLite WASM y almacenamiento persistente disponible en el navegador. Service worker guarda recursos estáticos propios, sin cachear respuestas de Auth/API. El navegador puede desalojar almacenamiento; los pendientes requieren respaldo antes de limpiar datos.

PostgreSQL contiene profiles, devices, products, allocations, operations, cash_sessions, sale_lines, contacts, refunds, credit_payments, order_sales y audit_log. Supabase Auth conserva credenciales. Cliente recibe únicamente URL y clave publishable, nunca service_role o contraseña PostgreSQL.

apply_operation valida usuario activo/dueño de dispositivo, contenido, precios, cantidades, rol, referencias, caja y saldo. Transacciones y bloqueos protegen stock/caja; UUID con distinto contenido se rechaza. RLS limita lecturas y niega acceso anónimo. Escrituras de clientes solo mediante funciones aprobadas. Migraciones versionadas se aplicaron en consola SQL; no se registraron mediante Supabase CLI.

## Offline y sincronización

Cupos reservados evitan vender offline la misma última unidad. Diez unidades centrales pueden repartirse seis/cuatro a dos equipos. Cada equipo consume solo su cupo; no se permite asignar más que stock libre. Una venta sincronizada descuenta stock global y cupo atómicamente. Recepciones/ajustes positivos añaden disponibilidad al equipo que los registra. Sin cupo no podrá vender aunque otro dispositivo tenga unidades reservadas.

Sin Internet los otros equipos no conocen operaciones nuevas; convergen al sincronizar. Sincronización manual y aproximadamente cada 30 segundos mientras app abierta, con descarga paginada; sin actualización instantánea ni ejecución garantizada en segundo plano. No hay hub LAN; la laptop es otro cliente. Si se exige compartir ventas offline por LAN, añadir servidor local y validar su recuperación.

Ingreso productivo requiere Internet, también después de reiniciar la app. Una sesión abierta autoriza escrituras offline durante ocho horas desde el ingreso; al vencer requiere reconectar. No hay todavía recuperación de sesión offline tras reinicio ni autorización offline indefinida. Una revocación remota puede tardar hasta reconexión; la nube revalida. Un equipo manipulado puede producir una operación local que la nube rechace. Un rechazo detiene cola para revisión; no existe asistente completo de compensación/reconciliación. No declarar resueltos estos escenarios por tener SQLite.

## Instalación por plataforma e impresión

Android: APK arm64 y arm32 compilados en release para pruebas. Firma debug del scaffold; sustituir por firma privada del propietario y probar instalación física antes de distribución comercial. Alternativa PWA desde Chrome. No se conectó un teléfono real durante las pruebas.

iPhone: Safari → abrir web → Compartir → Añadir a pantalla de inicio. Primera vía PWA; proyecto ios preparado para abrir en Xcode/macOS y firmar. No se compiló IPA ni se probó Safari en iPhone en este entorno Windows. Validar persistencia, teclado, suspensión, PDF, compartir y actualizaciones en los tres equipos.

Laptop: navegador moderno. Pantalla amplia con catálogo/carrito; móvil ofrece acceso al carrito mediante resumen. No requiere servidor PostgreSQL local.

Impresoras: PDF de 58 y 80 mm y diálogo/servicio de impresión del sistema. No se implementó ESC/POS Bluetooth directo. Los modelos exactos determinarán compatibilidad y aplicaciones del fabricante. Bluetooth clásico disponible en Android no garantiza impresión desde iPhone. Falta prueba física; no prometer compatibilidad solo por ancho de papel.

## Seguridad, respaldos y mantenimiento

Cada trabajador usa cuenta propia. Credenciales establecidas por el propietario en Supabase; no compartir por chat. Desactivar en lugar de eliminar al cambiar responsable. SQLite local no está cifrado por la aplicación; proteger dispositivos con bloqueo y evaluar cifrado antes de datos sensibles. Exportaciones contienen información privada y deben guardarse protegidas, fuera de GitHub.

Actualizar web: compilar, regenerar service worker y subir build/web completo. Las pestañas viejas pueden mantener versión previa hasta cerrarse; sincronizar primero y cerrar/reabrir. No borrar datos para actualizar. Respaldo PostgreSQL fuera del proyecto, ensayo de restauración y backup local antes de migraciones. Backup productivo automatizado todavía no está implementado.

Supabase Free limita la base a 500 MB y puede restringir escrituras si se supera; también puede pausar proyectos con baja actividad. No ofrece capacidad/disponibilidad ilimitadas. Consultar [tamaño de base](https://supabase.com/docs/guides/platform/database-size) y [pausas](https://supabase.com/docs/guides/platform/free-project-pausing). Revisar uso semanal y costos antes de crecer. Cloudflare sirve la interfaz pública; los datos privados requieren autenticación/RLS.

## Aceptación antes de operar o vender

- Administrador definitivo, trabajadores reales, catálogo/conteo inicial y cupos por equipo.
- Ventas simultáneas con stock limitado, caída/retorno de Internet, reintento, agotamiento de cupos, permisos revocados y rechazo de operaciones.
- Ocho teléfonos y laptop, PDF y ambas impresoras; reinicio offline actualmente necesita reconexión para ingresar.
- Firma Android comercial, restauración central ensayada, pérdida de equipo, soporte y horarios pactados.
- Resolver caja compartida/hub, recuperación offline de sesión, conflictos, cifrado y facturación si se exigen en el alcance final.

Estos pendientes no se declaran completos por tener un APK, un repositorio o una URL. La valoración comercial se encuentra en VALORACION-COMERCIAL.md y supone cerrar el piloto.
