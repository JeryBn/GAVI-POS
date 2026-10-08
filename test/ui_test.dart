import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gavi_pos/core/database.dart';
import 'package:gavi_pos/core/models.dart';
import 'package:gavi_pos/core/repository.dart';
import 'package:gavi_pos/main.dart';

void main(){
  testWidgets('empleado ve venta y no módulos administrativos',(tester)async{
    tester.view.physicalSize=const Size(1280,900);tester.view.devicePixelRatio=1;
    addTearDown(tester.view.resetPhysicalSize);addTearDown(tester.view.resetDevicePixelRatio);
    final repo=PosRepository(PosDatabase(NativeDatabase.memory()),demo:true);await repo.initialize();
    repo.operator=const Operator('employee','Empleado','employee');
    await tester.pumpWidget(MaterialApp(home:PosPage(repo:repo)));
    await tester.runAsync(()=>Future<void>.delayed(const Duration(milliseconds:100)));await tester.pumpAndSettle();
    expect(find.text('Venta rápida'),findsOneWidget);expect(find.text('Auditoría'),findsNothing);
    expect(find.text('Compras'),findsNothing);expect(find.text('Reportes'),findsNothing);
    await tester.pumpWidget(const SizedBox());await repo.db.close();
  });
}
