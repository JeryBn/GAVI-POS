import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gavi_pos/tickets/ticket.dart';

void main(){
  test('PDF de 58 y 80 mm con nombres y totales',()async{
    final sale=<String,dynamic>{'id':'00000000-0000-4000-8000-000000000123','created':'2026-10-08T03:00:00Z','body':{
      'operator_name':'Empleado de prueba','method':'Efectivo','total':1730,'paid':1730,'items':[
        {'name':'Agua mineral 625 ml','quantity':2,'price':250,'total':500},
        {'name':'Arroz 1 kg','quantity':1,'price':480,'total':480},
        {'name':'Galletas de chocolate','quantity':3,'price':250,'total':750}]}};
    for(final width in [58,80]){
      final bytes=await ticketPdf(sale,demo:true,paperMm:width);
      expect(String.fromCharCodes(bytes.take(5)),'%PDF-');
      if(Platform.environment['GAVI_EXPORT_TICKETS']=='1'){
        final output=Directory('../tickets');await output.create(recursive:true);
        await File('${output.path}/GAVI-ticket-ejemplo-${width}mm.pdf').writeAsBytes(bytes);
      }
    }
  });
}
