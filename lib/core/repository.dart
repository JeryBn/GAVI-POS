import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';
import 'database.dart';
import 'models.dart';

class PosRepository {
  final PosDatabase db;
  final bool demo;
  Operator? operator;
  DateTime? authorizedUntil;
  String device = '';
  PosRepository(this.db, {required this.demo});
  static const uuid = Uuid();
  Operator get user => operator ?? (throw StateError('Inicie sesión.'));
  void ensureAuthorized() {
    if (!demo && (authorizedUntil == null || DateTime.now().isAfter(authorizedUntil!))) {
      throw StateError('Autorización vencida. Inicie sesión con Internet.');
    }
    if (operator == null) { throw StateError('Inicie sesión.'); }
  }
  void requireAdmin() { if (!user.admin) { throw StateError('Requiere administrador.'); } }
  Future<void> initialize() async {
    final rows = await db.customSelect("SELECT value FROM meta WHERE key='device'").get();
    if (rows.isEmpty) {
      device = uuid.v4();
      await db.customStatement('INSERT INTO meta VALUES (?,?)', ['device', device]);
    } else { device = rows.first.read<String>('value'); }
    if (demo && (await products()).isEmpty) {
      for (final p in [
        Product(id: uuid.v4(), name: 'Agua mineral 625 ml', sku: 'AGUA01', barcode: '775000000001', price: 250, wholesale: 200, minimum: 180, cost: 120, stock: 40, low: 10),
        Product(id: uuid.v4(), name: 'Arroz 1 kg', sku: 'ARROZ01', barcode: '775000000002', price: 480, wholesale: 430, minimum: 400, cost: 320, stock: 30, low: 8),
        Product(id: uuid.v4(), name: 'Aceite 1 litro', sku: 'ACEITE01', barcode: '775000000003', price: 950, wholesale: 850, minimum: 800, cost: 650, stock: 12, low: 5),
        Product(id: uuid.v4(), name: 'Galletas de chocolate', sku: 'GALLETA01', price: 180, wholesale: 150, minimum: 130, cost: 90, stock: 5, low: 8),
      ]) { await writeProduct(p); }
    }
  }
  Future<List<Product>> products() async => (await db.customSelect(
    'SELECT * FROM products ORDER BY name').get()).map((r) => Product.fromMap(r.data)).toList();
  Future<void> writeProduct(Product p) async {
    final m = p.toMap();
    await db.customStatement('INSERT INTO products (${m.keys.join(',')}) VALUES (${List.filled(m.length, '?').join(',')}) ON CONFLICT(id) DO UPDATE SET ${m.keys.where((k) => k != 'id').map((k) => '$k=excluded.$k').join(',')}', m.values.toList());
  }
  Future<List<Map<String, dynamic>>> documents([String? kind]) async {
    final rows = await db.customSelect(
      'SELECT * FROM documents ${kind == null ? '' : 'WHERE kind=?'} ORDER BY created DESC',
      variables: kind == null ? [] : [Variable(kind)]).get();
    return rows.map((r) => {...r.data, 'body': jsonDecode(r.read<String>('body'))}).toList();
  }
  Future<String> record(String kind, Map<String, dynamic> body, {String? id}) async {
    ensureAuthorized();
    return db.transaction(() async {
    final key = id ?? uuid.v4();
    await db.customStatement('INSERT INTO documents VALUES (?,?,?,?,?)',
      [key, kind, DateTime.now().toUtc().toIso8601String(), user.id,
        jsonEncode({...body, 'device_id': device, 'operator_name': user.name})]);
    await db.customStatement('INSERT INTO outbox(id,state) VALUES (?,?)', [key, demo ? 'local' : 'pending']);
    return key;
    });
  }
  Future<void> saveProduct(Product p) async {
    requireAdmin();
    if (p.name.trim().isEmpty || p.sku.trim().isEmpty || p.minimum > p.price || p.minimum > p.wholesale) {
      throw StateError('Nombre/SKU obligatorios y precios no inferiores al mínimo.');
    }
    await db.transaction(() async {
      final old = (await products()).where((x) => x.id == p.id).firstOrNull;
      if (old != null && p.stock != old.stock) { throw StateError('Use ajuste de stock con motivo.'); }
      await writeProduct(p);
      await record('product', {'before': old?.toMap(), 'after': p.toMap()});
    });
  }
  Future<Map<String, dynamic>?> openCash() async {
    final all = await documents();
    final closed = all.where((d) => d['kind'] == 'cash_close')
      .map((d) => d['body']['cash_id']).toSet();
    return all.where((d) => d['kind'] == 'cash_open' &&
      d['body']['device_id'] == device && !closed.contains(d['id'])).firstOrNull;
  }
  Future<void> startCash(int opening) async {
    if (opening < 0) { throw StateError('Fondo inválido.'); }
    await db.transaction(() async {
      if (await openCash() != null) { throw StateError('Ya hay una caja abierta.'); }
      await record('cash_open', {'opening': opening});
    });
  }
  Future<int> expectedCash(String cashId) async {
    final all = await documents();
    final opening = all.firstWhere((d) => d['id'] == cashId)['body']['opening'] as int;
    var total = opening;
    for (final d in all) {
      final b = d['body'] as Map<String, dynamic>;
      if (b['cash_id'] != cashId) { continue; }
      if (d['kind'] == 'sale' && b['method'] == 'Efectivo') { total += b['paid'] as int; }
      if (d['kind'] == 'payment' && b['method'] == 'Efectivo') { total += b['amount'] as int; }
      if (d['kind'] == 'refund' && b['method'] == 'Efectivo') { total -= b['amount'] as int; }
      if (d['kind'] == 'cash_movement') { total += b['amount'] as int; }
    }
    return total;
  }
  Future<void> closeCash(int counted) async {
    await db.transaction(() async {
      final cash = await openCash() ?? (throw StateError('No hay caja abierta.'));
      if (cash['actor'] != user.id && !user.admin) { throw StateError('Caja de otro empleado.'); }
      final expected = await expectedCash(cash['id'] as String);
      await record('cash_close', {'cash_id': cash['id'], 'expected': expected,
        'counted': counted, 'difference': counted - expected});
    });
  }
  Future<void> cashMovement(int amount, String reason) async {
    requireAdmin();
    if (reason.trim().isEmpty || amount == 0) { throw StateError('Importe y motivo obligatorios.'); }
    await db.transaction(() async {
      final cash = await openCash() ?? (throw StateError('Abra una caja.'));
      if (await expectedCash(cash['id'] as String) + amount < 0) { throw StateError('La salida excede el efectivo esperado.'); }
      await record('cash_movement', {'cash_id': cash['id'], 'amount': amount, 'reason': reason});
    });
  }
  Future<String> sell(List<CartLine> cart, {required String method,
    String customer = '', int? paid, String? operationId, String? orderId}) async {
    final key = operationId ?? uuid.v4();
    return db.transaction(() async {
      final existing = await db.customSelect('SELECT * FROM documents WHERE id=?', variables: [Variable(key)]).get();
      if (existing.isNotEmpty) {
        final row = existing.first;
        final b = jsonDecode(row.read<String>('body')) as Map<String,dynamic>;
        final oldLines = b['items'] as List;
        final matching = cart.map((line)=>line.product.id).toSet().length == cart.length && oldLines.length == cart.length && cart.every((line) => oldLines.any((item) =>
          item['product_id'] == line.product.id && item['quantity'] == line.quantity && item['price'] == line.price));
        if (row.read<String>('kind') != 'sale' || row.read<String>('actor') != user.id || !matching ||
          b['method'] != method || b['customer'] != customer || b['order_id'] != orderId ||
          b['paid'] != (paid ?? (method == 'Crédito' ? 0 : cart.fold<int>(0,(s,line)=>s+line.total)))) { throw StateError('Identificador reutilizado con otra venta.'); }
        return key;
      }
      final cash = await openCash() ?? (throw StateError('Abra la caja antes de vender.'));
      if (cash['actor'] != user.id && !user.admin) { throw StateError('La caja pertenece a otro empleado.'); }
      if (cart.isEmpty || !['Efectivo','Tarjeta','Transferencia','Crédito'].contains(method)) { throw StateError('Venta inválida.'); }
      if (customer.isNotEmpty && !(await documents('customer')).any((d)=>d['id']==customer)) { throw StateError('Cliente inexistente.'); }
      if (orderId != null) {
        if ((await documents('sale')).any((d) => d['body']['order_id'] == orderId)) { throw StateError('Pedido ya vendido.'); }
      }
      final catalog = {for (final p in await products()) p.id: p};
      final seen = <String>{};
      var total = 0;
      final lines = <Map<String,dynamic>>[];
      for (final line in cart) {
        final p = catalog[line.product.id] ?? (throw StateError('Producto inexistente.'));
        if (!seen.add(p.id) || !p.active || line.quantity <= 0 || line.quantity > p.stock) { throw StateError('Stock/cupo insuficiente: ${p.name}.'); }
        if (line.price < p.minimum || (line.price != p.price && !(user.admin || user.canEditPrice))) { throw StateError('Precio no autorizado: ${p.name}.'); }
        total += line.total;
        lines.add({...line.toMap(), 'name': p.name, 'sku': p.sku});
      }
      final amountPaid = paid ?? (method == 'Crédito' ? 0 : total);
      if (amountPaid < 0 || amountPaid > total) { throw StateError('Pago inválido.'); }
      if (amountPaid != total && (customer.isEmpty || !(user.admin || user.canCredit))) {
        throw StateError('Crédito requiere cliente y permiso.');
      }
      if (method == 'Crédito' && amountPaid != 0) { throw StateError('Seleccione el medio real del pago parcial.'); }
      for (final line in cart) {
        await db.customStatement('UPDATE products SET stock=stock-? WHERE id=?', [line.quantity, line.product.id]);
      }
      await record('sale', {'cash_id': cash['id'], 'items': lines, 'total': total,
        'paid': amountPaid, 'method': method, 'customer': customer, 'order_id': orderId}, id: key);
      return key;
    });
  }
  Future<void> adjustStock(String productId, int delta, String reason, {String kind = 'stock_adjust', String supplier = ''}) async {
    requireAdmin();
    if (delta == 0 || reason.trim().isEmpty) { throw StateError('Cantidad y motivo obligatorios.'); }
    await db.transaction(() async {
      final p = (await products()).firstWhere((p) => p.id == productId);
      if (p.stock + delta < 0) { throw StateError('El stock no puede ser negativo.'); }
      await db.customStatement('UPDATE products SET stock=stock+? WHERE id=?', [delta, productId]);
      await record(kind, {'product_id': productId, 'name': p.name, 'before': p.stock,
        'delta': delta, 'after': p.stock + delta, 'reason': reason, 'supplier': supplier,
        'cost_total': kind == 'purchase' ? delta * p.cost : 0});
    });
  }
  Future<void> saveContact(String kind, String name, String detail) async {
    if (!['customer', 'supplier'].contains(kind) || name.trim().isEmpty) { throw StateError('Nombre obligatorio.'); }
    if (kind == 'supplier') { requireAdmin(); }
    await record(kind, {'name': name.trim(), 'detail': detail.trim()});
  }
  Future<void> saveOrder(List<CartLine> lines, String customer) async {
    if (lines.isEmpty || customer.isEmpty) { throw StateError('Seleccione cliente y productos.'); }
    if (!(await documents('customer')).any((d)=>d['id']==customer)) { throw StateError('Cliente inexistente.'); }
    await record('order', {'items': lines.map((l) => l.toMap()).toList(),
      'customer': customer, 'status': 'Confirmado', 'total': lines.fold(0, (s, l) => s + l.total)});
  }
  Future<void> refund(String saleId, String reason) async {
    requireAdmin();
    if (reason.trim().isEmpty) { throw StateError('Motivo obligatorio.'); }
    await db.transaction(() async {
      final sale = (await documents('sale')).firstWhere((s) => s['id'] == saleId);
      if ((await documents('refund')).any((d) => d['body']['sale_id'] == saleId)) { throw StateError('Venta ya devuelta.'); }
      final cash = await openCash() ?? (throw StateError('Abra caja para devolver.'));
      final b = sale['body'] as Map<String,dynamic>;
      for (final item in b['items'] as List) {
        await db.customStatement('UPDATE products SET stock=stock+? WHERE id=?', [item['quantity'], item['product_id']]);
      }
      final payments = (await documents('payment')).where((d) => d['body']['sale_id'] == saleId);
      if (payments.any((d) => d['body']['method'] != b['method'])) { throw StateError('Devolución con pagos mixtos requiere conciliación.'); }
      final paid = (b['paid'] as int) + payments.fold<int>(0, (s,d) => s + (d['body']['amount'] as int));
      await record('refund', {'sale_id': saleId, 'cash_id': cash['id'], 'reason': reason,
        'amount': paid, 'total': b['total'], 'method': b['method'], 'items': b['items']});
    });
  }
  Future<int> balance(String saleId) async {
    final sale = (await documents('sale')).firstWhere((d) => d['id'] == saleId);
    if ((await documents('refund')).any((d) => d['body']['sale_id'] == saleId)) { return 0; }
    final payments = (await documents('payment')).where((d) => d['body']['sale_id'] == saleId);
    return (sale['body']['total'] as int) - (sale['body']['paid'] as int) -
      payments.fold<int>(0, (s,d) => s + (d['body']['amount'] as int));
  }
  Future<void> payCredit(String saleId, int amount, String method) async {
    requireAdmin();
    await db.transaction(() async {
      final cash = await openCash() ?? (throw StateError('Abra caja.'));
      if (amount <= 0 || amount > await balance(saleId) || !['Efectivo','Tarjeta','Transferencia'].contains(method)) { throw StateError('Pago inválido o mayor al saldo.'); }
      await record('payment', {'sale_id': saleId, 'cash_id': cash['id'], 'amount': amount, 'method': method});
    });
  }
  Future<List<Map<String,dynamic>>> queue() async => (await db.customSelect(
    'SELECT o.*,d.kind,d.created,d.actor,d.body FROM outbox o JOIN documents d ON d.id=o.id ORDER BY d.created').get())
      .map((r) => {...r.data, 'body': jsonDecode(r.read<String>('body'))}).toList();
  Future<String> exportBackup() async => jsonEncode({'format': 'gavi-local-v1',
    'demo': demo, 'device': device, 'created': DateTime.now().toUtc().toIso8601String(),
    'products': (await products()).map((p) => p.toMap()).toList(),
    'documents': await documents(), 'outbox': await queue()});
  Future<void> restoreDemoBackup(String source) async {
    requireAdmin();
    if(!demo){throw StateError('Restauración productiva requiere conciliación central.');}
    final data=jsonDecode(source) as Map<String,dynamic>;
    if(data['format']!='gavi-local-v1'||data['demo']!=true){throw StateError('Se requiere respaldo de demostración válido.');}
    if((await documents()).isNotEmpty){throw StateError('Restaure en una instalación de prueba sin operaciones.');}
    final restoredProducts=(data['products'] as List).map((p)=>Product.fromMap(Map<String,dynamic>.from(p as Map))).toList();
    final restoredDevice=data['device'] as String;
    await db.transaction(()async{
      await db.customStatement('DELETE FROM products');
      for(final p in restoredProducts){await writeProduct(p);}
      for(final row in data['documents'] as List){
        await db.customStatement('INSERT INTO documents VALUES (?,?,?,?,?)',[row['id'],row['kind'],row['created'],row['actor'],jsonEncode(row['body'])]);
        await db.customStatement("INSERT INTO outbox(id,state) VALUES (?,'local')",[row['id']]);
      }
      await db.customStatement("UPDATE meta SET value=? WHERE key='device'",[restoredDevice]);
    });
    device=restoredDevice;
  }
}
