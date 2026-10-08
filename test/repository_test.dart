import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gavi_pos/core/database.dart';
import 'package:gavi_pos/core/models.dart';
import 'package:gavi_pos/core/repository.dart';
import 'package:gavi_pos/tickets/ticket.dart';

void main() {
  late PosRepository r;
  setUp(() async {
    r=PosRepository(PosDatabase(NativeDatabase.memory()),demo:true);
    await r.initialize();
    r.operator=const Operator('admin','Administrador','admin',canCredit:true);
  });
  tearDown(()async=>r.db.close());
  test('importes sin pérdida de céntimos y entrada decimal inválida',(){
    expect(parseMoney('0.29'),29);expect(parseMoney('10,05'),1005);
    expect(()=>parseMoney('1.999'),throwsFormatException);
    expect(()=>parseMoney('-2'),throwsFormatException);
  });
  test('venta requiere caja y rechaza cantidades sin consumir stock',()async{
    final p=(await r.products()).first;
    await expectLater(r.sell([CartLine(p)],method:'Efectivo'),throwsStateError);
    await r.startCash(10000);
    await expectLater(r.sell([CartLine(p,quantity:p.stock+1)],method:'Efectivo'),throwsStateError);
    expect((await r.products()).first.stock,p.stock);
    expect(await r.documents('sale'),isEmpty);
  });
  test('venta es atómica e idempotente y caja separa tarjeta',()async{
    await r.startCash(10000);final p=(await r.products()).first;
    final key=PosRepository.uuid.v4();
    await r.sell([CartLine(p,quantity:2)],method:'Efectivo',operationId:key);
    await r.sell([CartLine(p,quantity:2)],method:'Efectivo',operationId:key);
    expect((await r.products()).first.stock,p.stock-2);
    expect((await r.documents('sale')).length,1);
    await r.sell([CartLine(p)],method:'Tarjeta');
    final cash=await r.openCash();expect(await r.expectedCash(cash!['id'] as String),10000+2*p.price);
    await r.closeCash(10000+2*p.price);expect(await r.openCash(),isNull);
    expect((await r.documents('cash_close')).first['body']['difference'],0);
  });
  test('empleado no ajusta stock ni cambia precio ni devuelve',()async{
    await r.startCash(0);final p=(await r.products()).first;
    r.operator=const Operator('employee','Empleado','employee');
    await expectLater(r.adjustStock(p.id,2,'conteo'),throwsStateError);
    await expectLater(r.refund('inexistente','motivo'),throwsStateError);
    // Caja del propio empleado para aislar validación de precio.
    r.operator=const Operator('admin','Empleado','employee');
    await expectLater(r.sell([CartLine(p,price:p.price-1)],method:'Efectivo'),throwsStateError);
  });
  test('fallo en segunda línea revierte toda la venta',()async{
    await r.startCash(0);final ps=await r.products();
    await expectLater(r.sell([CartLine(ps[0]),CartLine(ps[1],quantity:ps[1].stock+1)],method:'Efectivo'),throwsStateError);
    expect((await r.products()).first.stock,ps.first.stock);expect(await r.documents('sale'),isEmpty);
  });
  test('ajuste requiere motivo; compra deja evidencia',()async{
    final p=(await r.products()).first;
    await expectLater(r.adjustStock(p.id,2,''),throwsStateError);
    await r.adjustStock(p.id,2,'Compra F001',kind:'purchase',supplier:'Proveedor');
    expect((await r.products()).first.stock,p.stock+2);
    expect((await r.documents('purchase')).first['body']['before'],p.stock);
  });
  test('devolución completa repone una sola vez y resta efectivo',()async{
    await r.startCash(5000);final p=(await r.products()).first;
    final id=await r.sell([CartLine(p)],method:'Efectivo');
    await r.refund(id,'Producto devuelto');
    await expectLater(r.refund(id,'Duplicado'),throwsStateError);
    expect((await r.products()).first.stock,p.stock);
    expect(await r.expectedCash((await r.openCash())!['id'] as String),5000);
  });
  test('crédito y pagos parciales no permiten cobrar más del saldo',()async{
    await r.startCash(0);final p=(await r.products()).first;
    await r.saveContact('customer','Cliente','');final customer=(await r.documents('customer')).first['id'] as String;
    final id=await r.sell([CartLine(p)],method:'Crédito',customer:customer);
    expect(await r.balance(id),p.price);
    await r.payCredit(id,100,'Efectivo');expect(await r.balance(id),p.price-100);
    await expectLater(r.payCredit(id,p.price,'Efectivo'),throwsStateError);
  });
  test('pedido se convierte a venta una sola vez',()async{
    await r.startCash(0);final p=(await r.products()).first;
    await r.saveContact('customer','Cliente','');final customer=(await r.documents('customer')).first['id'] as String;
    await r.saveOrder([CartLine(p)],customer);final id=(await r.documents('order')).first['id'] as String;
    await r.sell([CartLine(p)],method:'Efectivo',orderId:id);
    await expectLater(r.sell([CartLine(p)],method:'Efectivo',orderId:id),throwsStateError);
  });
  test('UUID no puede usarse con otra cantidad o pago',()async{
    await r.startCash(0);final p=(await r.products()).first;final id=PosRepository.uuid.v4();
    await r.sell([CartLine(p)],method:'Efectivo',operationId:id);
    await expectLater(r.sell([CartLine(p,quantity:2)],method:'Efectivo',operationId:id),throwsStateError);
  });
  test('salida no puede dejar efectivo esperado negativo',()async{
    await r.startCash(100);await expectLater(r.cashMovement(-200,'Salida'),throwsStateError);
  });
  test('respaldo demo restaura stock, ventas y dispositivo',()async{
    await r.startCash(0);final p=(await r.products()).first;await r.sell([CartLine(p)],method:'Efectivo');
    final source=await r.exportBackup();final restored=PosRepository(PosDatabase(NativeDatabase.memory()),demo:true);
    await restored.initialize();restored.operator=r.operator;await restored.restoreDemoBackup(source);
    expect(restored.device,r.device);expect((await restored.documents('sale')).length,1);
    expect((await restored.products()).first.stock,p.stock-1);await restored.db.close();
  });
  test('autorización productiva vencida no escribe documentos',()async{
    final repo=PosRepository(PosDatabase(NativeDatabase.memory()),demo:false);await repo.initialize();repo.operator=r.operator;
    repo.authorizedUntil=DateTime.now().subtract(const Duration(minutes:1));
    await expectLater(repo.startCash(0),throwsStateError);expect(await repo.documents(),isEmpty);await repo.db.close();
  });
  test('PDF tiene encabezado válido y venta persistente',()async{
    await r.startCash(0);final p=(await r.products()).first;
    await r.sell([CartLine(p)],method:'Efectivo');
    final bytes=await ticketPdf((await r.documents('sale')).first,demo:true);
    expect(String.fromCharCodes(bytes.take(5)),'%PDF-');expect(bytes.length,greaterThan(1000));
  });
  test('SQLite conserva ventas y dispositivo tras cerrar y reabrir',()async{
    final folder=await Directory.systemTemp.createTemp('gavi-test-');final file=File('${folder.path}/pos.sqlite');
    var repo=PosRepository(PosDatabase(NativeDatabase(file)),demo:true);await repo.initialize();repo.operator=r.operator;
    final device=repo.device;await repo.startCash(0);final p=(await repo.products()).first;
    await repo.sell([CartLine(p)],method:'Efectivo');await repo.db.close();
    repo=PosRepository(PosDatabase(NativeDatabase(file)),demo:true);await repo.initialize();
    expect(repo.device,device);expect((await repo.documents('sale')).length,1);expect((await repo.products()).first.stock,p.stock-1);
    await repo.db.close();await folder.delete(recursive:true);
  });
}
