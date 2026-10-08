# GAVI POS — Especificación funcional v1.0

Fecha: 7 de octubre de 2026. Sistema privado de un negocio, sin SaaS ni registro público.
Dispositivos confirmados: 5 Android, 3 iPhone, 1 laptop y 2 impresoras. Moneda PEN, importes enteros en céntimos. Ticket PDF visible y compartible en móvil, impresión por diálogo del sistema. Modelo/conexión de impresoras y rubro pendientes.

## Arquitectura
Flutter/Dart en Android, iOS y web; SQLite/Drift por dispositivo; Supabase Auth y PostgreSQL centrales; Cloudflare Pages para HTTPS. iPhone inicialmente PWA; proyecto iOS preparado para Xcode. Productos por unidad entera en v1; venta por peso requerirá unidades fraccionarias explícitas. No asumir impuestos ni facturación SUNAT: ticket comercial no es comprobante fiscal.

## Roles
Administrador gestiona catálogo, mínimos, compras, trabajadores, permisos, caja, reportes, devoluciones, auditoría y respaldos. Empleado vende, consulta catálogo y maneja caja propia. Cambiar precio requiere permiso y respeta mínimo. El servidor valida permisos aunque se modifique la interfaz. No guardar contraseñas localmente. Dispositivo autorizado y sesión vigente para producción; autorización offline con vencimiento será requisito antes de habilitar operación comercial. Modo demostración aislado de datos reales.

## Venta e inventario
Buscar nombre/SKU/código, añadir, cambiar cantidades, aplicar precio autorizado, seleccionar cliente/medio de pago, cobrar y emitir PDF. Caja abierta obligatoria. Guardar venta, líneas, pago, movimiento, auditoría y cola en una transacción local. UUID para idempotencia; reintentos no duplican venta. Dinero entero. Stock bajo visible. Ajustes requieren administrador y motivo.

Servidor bloquea filas y valida stock transaccionalmente. Para vender sin Internet, cada dispositivo recibe cupos exclusivos de unidades. La suma de cupos no excede existencias. No vender por encima del cupo; no devolver automáticamente reservas de dispositivo perdido sin conciliación. Los movimientos son acumulativos, no reemplazos de contadores. Sin comunicación no hay stock global actualizado. Hub LAN opcional: autoridad local única, autenticación/HTTPS, sincronización y respaldo, pendiente de implementación y prueba.

## Caja y gestión
Abrir con fondo; cobrar efectivo/tarjeta/transferencia; registrar entradas/salidas con motivo; cerrar con esperado, contado y diferencia. Crédito opcional requiere cliente, permiso, vencimiento y libro de pagos parciales. Anulaciones/devoluciones usan documentos inversos vinculados, cantidades limitadas, motivo y autorización; nunca borrar venta original. Pedidos con estados y conversión a venta sin descontar doble. Compras por proveedor con recepción e incremento auditado. Catálogo: categoría, SKU/código único, costo, minorista, mayorista, mínimo y umbral. Clientes con mínimos datos personales. Trabajadores activos/inactivos y permisos. Reportes por fecha/producto/empleado, exportación CSV y alertas.

## Sincronización y seguridad
Cola durable, estados pendiente/aceptado/rechazado, reintentos seriales, error visible y conciliación; no ocultar ventas rechazadas. RLS sin acceso anónimo. Secretos service_role solo en servidor. Validar actor, dispositivo, precio y caja centralmente. HTTPS, bloqueo de dispositivos y revocación de sesiones. Respaldo central independiente de exportación local, restauración probada. Revisar cuotas/pausas del servicio gratuito. No confundir compilación con prueba en dispositivo.

## Aceptación
Venta persiste al reiniciar, no duplica al reintentar, no vende sin caja/stock/cupo ni bajo mínimo. Empleado no ajusta stock ni anula por API. Dos dispositivos no consumen la misma reserva. Corte de red conserva cola. Venta/devolución/cierre cuadran en céntimos y dejan auditoría. Android, Safari/iPhone y web comparten identidad/datos en pruebas reales. PDF muestra detalle y total. Respaldo se restaura. Empleado sin formación técnica completa venta. Informe señala resultados verificados y pendientes.

Este documento define el alcance completo; no certifica que esté completamente implementado.
