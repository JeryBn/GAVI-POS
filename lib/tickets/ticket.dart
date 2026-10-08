import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../core/models.dart';

Future<Uint8List> ticketPdf(Map<String,dynamic> sale, {bool demo = false, int paperMm = 80}) async {
  if (paperMm != 58 && paperMm != 80) { throw ArgumentError('Papel permitido: 58 o 80 mm'); }
  final b = sale['body'] as Map<String,dynamic>;
  final peruTime=DateTime.parse(sale['created'] as String).toUtc().subtract(const Duration(hours:5));
  final estimatedHeight=(110+(b['items'] as List).length*13).clamp(110,297).toDouble();
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(pageFormat: PdfPageFormat(paperMm * PdfPageFormat.mm,
    estimatedHeight * PdfPageFormat.mm, marginAll: 5 * PdfPageFormat.mm),
    build: (_) => [
      pw.Center(child: pw.Text('GAVI POS', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
      if (demo) pw.Center(child: pw.Text('DEMOSTRACION - SIN VALOR COMERCIAL')),
      pw.Text('Ticket de venta - no es comprobante fiscal', style: const pw.TextStyle(fontSize: 8)),
      pw.SizedBox(height: 8),
      pw.Text('Venta: ${sale['id']}', style: const pw.TextStyle(fontSize: 8)),
      pw.Text('Fecha Perú (UTC-05): ${DateFormat('dd/MM/yyyy HH:mm').format(peruTime)}', style: const pw.TextStyle(fontSize: 8)),
      pw.Text('Atendió: ${b['operator_name']}'),
      pw.Divider(),
      for (final item in b['items'] as List) ...[
        pw.Text(item['name'] as String),
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
          pw.Text('${item['quantity']} x ${money(item['price'] as int)}'),
          pw.Text(money(item['total'] as int)),
        ]), pw.SizedBox(height: 5),
      ],
      pw.Divider(),
      pw.Text('TOTAL PEN: ${money(b['total'] as int)}', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      pw.Text('${b['method']}: ${money(b['paid'] as int)}'),
      if (b['paid'] != b['total']) pw.Text('Saldo inicial: ${money((b['total'] as int) - (b['paid'] as int))}'),
      pw.SizedBox(height: 10), pw.Center(child: pw.Text('Gracias por su compra')),
    ]));
  return doc.save();
}

Future<void> printTicket(Map<String,dynamic> sale, {bool demo = false, int paperMm = 80}) async {
  final bytes = await ticketPdf(sale, demo: demo, paperMm: paperMm);
  await Printing.layoutPdf(name: 'GAVI-${sale['id']}.pdf', onLayout: (_) async => bytes);
}
Future<void> shareTicket(Map<String,dynamic> sale, {bool demo = false, int paperMm = 80}) async {
  await Printing.sharePdf(bytes: await ticketPdf(sale, demo: demo, paperMm: paperMm), filename: 'GAVI-${sale['id']}.pdf');
}
