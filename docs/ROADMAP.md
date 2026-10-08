# Roadmap

| Fase | Entrega | Cierre verificable |
|---|---|---|
| 0 | Especificación, arquitectura, contexto | Requisitos y supuestos explícitos |
| 1 | Venta/catálogo/caja local, SQLite, PDF, auditoría | Persistencia y transacciones probadas |
| 2 | Auth/RLS, stock reservado y sincronización | Pruebas en nube y dos dispositivos |
| 3 | Compras, pedidos, crédito, devoluciones, administración completa | Flujos y permisos de extremo a extremo |
| 4 | PWA, Android release, proyecto iOS, hosting/GitHub | URL real, APK y pruebas Android/Safari; iOS con Mac |
| 5 | Impresoras, hub LAN si procede, respaldo/entrenamiento | Cortes de red y restauración en el negocio |

Avanzar independientemente de aclaraciones menores. Dependencias: cuentas Supabase/hosting, identidad GitHub, modelos de impresora, rubro y política fiscal. Código inicial no cierra todas las fases; conservar evidencia.

Estado 8/10/2026: fases 0 y núcleo local implementadas/probadas. Fase 2 con base, permisos y venta/devolución/cierre de extremo a extremo verificados en una sesión Chrome; falta prueba simultánea de dispositivos físicos. Fase 3 implementada con límites explicitados en el informe. Fase 4 web/GitHub publicados y APK compilados, iOS nativo y hardware pendientes. Fase 5 impresión directa Bluetooth, hub si procede, restauración productiva y piloto todavía abiertos.
