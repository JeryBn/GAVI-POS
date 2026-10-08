import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/database.dart';
import 'core/models.dart';
import 'core/repository.dart';
import 'sync/cloud_sync.dart';
import 'tickets/ticket.dart';

const cloudUrl = String.fromEnvironment('SUPABASE_URL');
const cloudKey = String.fromEnvironment('SUPABASE_ANON_KEY');
const productionEnabled = bool.fromEnvironment('ENABLE_PRODUCTION');
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (cloudUrl.isNotEmpty && cloudKey.isNotEmpty) {
    await Supabase.initialize(url: cloudUrl, publishableKey: cloudKey);
  }
  runApp(const GaviApp());
}
class GaviApp extends StatelessWidget {
  const GaviApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'GAVI POS', debugShowCheckedModeBanner: false,
    locale: const Locale('es','PE'), supportedLocales: const [Locale('es','PE')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff087f74)),
      scaffoldBackgroundColor: const Color(0xfff4f7f8),
      inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48,48))),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.all(6))),
    home: const LoginPage());
}
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState()=>_LoginPageState();
}
class _LoginPageState extends State<LoginPage> {
  final email=TextEditingController(), password=TextEditingController();
  bool busy=false;
  String? error;
  Future<void> enter([String? role]) async {
    setState((){busy=true;error=null;});
    PosRepository? repo;
    try {
      final demo=role!=null;
      String databaseName='gavi_demo_v1';
      if(!demo){
        final auth=await Supabase.instance.client.auth.signInWithPassword(email:email.text.trim(),password:password.text);
        databaseName='gavi_production_${auth.user!.id.replaceAll('-','')}';
      }
      repo=PosRepository(PosDatabase.open(databaseName),demo:demo);
      await repo.initialize();
      CloudSync? cloud;
      if(demo){repo.operator=Operator(role=='admin'?'demo-admin':'demo-employee',role=='admin'?'Administrador demo':'Empleado demo',role,canCredit:role=='admin');}
      else {cloud=CloudSync(repo,Supabase.instance.client);repo.operator=await cloud.signIn(email.text,password.text,authenticated:true);await cloud.synchronize();}
      if(!mounted){await repo.db.close();return;}
      await Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>PosPage(repo:repo!,cloud:cloud)));
      await repo.db.close();
    } catch(e){await repo?.db.close();if(mounted){setState(()=>error='$e');}}
    finally{if(mounted){setState(()=>busy=false);}}
  }
  @override
  void dispose(){email.dispose();password.dispose();super.dispose();}
  @override
  Widget build(BuildContext context)=>Scaffold(body:Center(child:SingleChildScrollView(padding:const EdgeInsets.all(24),
    child:SizedBox(width:440,child:Card(child:Padding(padding:const EdgeInsets.all(28),child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Icon(Icons.point_of_sale_rounded,size:56,color:Color(0xff087f74)),const SizedBox(height:12),
      const Text('GAVI POS',textAlign:TextAlign.center,style:TextStyle(fontSize:32,fontWeight:FontWeight.w800)),
      const Text('Tu negocio, en orden',textAlign:TextAlign.center),const SizedBox(height:24),
      if(productionEnabled&&cloudUrl.isNotEmpty&&cloudKey.isNotEmpty)...[
        TextField(controller:email,decoration:const InputDecoration(labelText:'Correo del trabajador')),
        const SizedBox(height:12),TextField(controller:password,obscureText:true,decoration:const InputDecoration(labelText:'Contraseña')),
        const SizedBox(height:12),FilledButton(onPressed:busy?null:()=>enter(),child:const Text('Ingresar al negocio')),const Divider(height:32)],
      const Text('Prueba local',style:TextStyle(fontSize:20,fontWeight:FontWeight.bold)),
      const Text('Datos de ejemplo guardados en este dispositivo. No se envían a la nube. Esta versión requiere validación antes de operar el negocio.'),const SizedBox(height:16),
      FilledButton.tonal(onPressed:busy?null:()=>enter('admin'),child:const Text('Probar como administrador')),const SizedBox(height:8),
      OutlinedButton(onPressed:busy?null:()=>enter('employee'),child:const Text('Probar como empleado')),
      if(busy)const Padding(padding:EdgeInsets.all(16),child:LinearProgressIndicator()),
      if(error!=null)Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error)),
    ])))))));
}
class PosPage extends StatefulWidget {
  final PosRepository repo;
  final CloudSync? cloud;
  const PosPage({super.key,required this.repo,this.cloud});
  @override
  State<PosPage> createState()=>_PosPageState();
}
class _PosPageState extends State<PosPage> {
  PosRepository get r=>widget.repo;
  List<Product> products=[];
  List<Map<String,dynamic>> docs=[],queue=[];
  Map<String,dynamic>? cash;
  final cart=<CartLine>[];
  final search=TextEditingController();
  String page='Vender',method='Efectivo',customer='';
  bool busy=false,loading=true,mobileBasket=false;
  int expected=0;
  int paperMm=80;
  String? orderId;
  DateTime? reportFrom;
  Timer? timer;
  @override
  void initState(){super.initState();refresh();if(widget.cloud!=null){timer=Timer.periodic(const Duration(seconds:30),(_){if(!busy&&mounted){act(()=>widget.cloud!.synchronize(),success:false);}});}}
  @override
  void dispose(){timer?.cancel();search.dispose();super.dispose();}
  Future<void> refresh()async{
    final ps=await r.products();final ds=await r.documents();final qs=await r.queue();final cs=await r.openCash();
    final ex=cs==null?0:await r.expectedCash(cs['id'] as String);
    if(mounted){setState((){products=ps;docs=ds;queue=qs;cash=cs;expected=ex;loading=false;});}
  }
  void message(String text){if(mounted){ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));}}
  Future<void> act(Future<void> Function() action,{bool success=true})async{
    if(busy){return;}setState(()=>busy=true);
    try{await action();await refresh();if(success){message('Guardado correctamente.');}}
    catch(e){message(e.toString().replaceFirst('Bad state: ',''));}
    finally{if(mounted){setState(()=>busy=false);}}
  }
  List<Map<String,dynamic>> of(String kind)=>docs.where((d)=>d['kind']==kind).toList();
  int get total=>cart.fold(0,(s,l)=>s+l.total);
  List<String> get pages=>['Vender','Caja','Ventas','Pedidos','Productos','Clientes',if(r.user.admin)...['Compras','Proveedores','Reportes','Trabajadores','Dispositivos','Auditoría'],'Sincronización','Ayuda'];
  Future<Map<String,String>?> form(String title,Map<String,String> fields)async{
    final cs={for(final e in fields.entries)e.key:TextEditingController(text:e.value)};
    final result=await showDialog<Map<String,String>>(context:context,builder:(ctx)=>AlertDialog(title:Text(title),
      content:SizedBox(width:440,child:SingleChildScrollView(child:Column(mainAxisSize:MainAxisSize.min,children:[
        for(final e in cs.entries)Padding(padding:const EdgeInsets.symmetric(vertical:6),child:TextField(controller:e.value,decoration:InputDecoration(labelText:e.key)))]))),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancelar')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,{for(final e in cs.entries)e.key:e.value.text}),child:const Text('Guardar'))]));
    await Future<void>.delayed(const Duration(milliseconds:300));
    for(final c in cs.values){c.dispose();}return result;
  }
  Widget heading(String title,String desc,[Widget? action])=>Padding(padding:const EdgeInsets.fromLTRB(16,16,16,8),child:Wrap(spacing:16,runSpacing:8,
    crossAxisAlignment:WrapCrossAlignment.center,children:[Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text(title,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w800)),Text(desc)]),?action]));
  Widget panel(List<Widget> children)=>ListView(padding:const EdgeInsets.all(12),children:children);
  @override
  Widget build(BuildContext context){
    final wide=MediaQuery.sizeOf(context).width>=980;
    final nav=ListView(children:[const DrawerHeader(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(Icons.point_of_sale,size:32),SizedBox(height:8),FittedBox(child:Text('GAVI POS',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold))),
      SizedBox(height:8),Text('Un negocio. Un sistema.',style:TextStyle(fontSize:12))])),
      for(final p in pages)ListTile(selected:page==p,title:Text(p),onTap:busy?null:(){setState(()=>page=p);if(!wide){Navigator.pop(context);}}),
      ListTile(title:const Text('Salir'),leading:const Icon(Icons.logout),onTap:busy?null:()async{
        if(widget.cloud!=null){await widget.cloud!.client.auth.signOut();}if(context.mounted){Navigator.pop(context);}})]);
    return Scaffold(appBar:AppBar(title:Text(page),actions:[Padding(padding:const EdgeInsets.all(12),child:Text(r.user.name))]),drawer:wide?null:Drawer(child:nav),
      body:Column(children:[Container(width:double.infinity,color:r.demo?const Color(0xffffe8b8):const Color(0xffd5f1ec),
        padding:const EdgeInsets.symmetric(horizontal:16,vertical:8),child:Text(r.demo?'DEMOSTRACIÓN LOCAL · PEN · Datos de prueba en este dispositivo':
          '${widget.cloud?.status} · ${queue.where((q)=>q['state']!='accepted').length} operaciones por enviar')),
        if(busy)const LinearProgressIndicator(),Expanded(child:Row(children:[if(wide)SizedBox(width:210,child:nav),
          Expanded(child:loading?const Center(child:CircularProgressIndicator()):body())]))]));
  }
  Widget body()=>switch(page){'Vender'=>salePage(),'Caja'=>cashPage(),'Productos'=>productPage(),'Ventas'=>historyPage(),
    'Clientes'=>contactPage('customer'),'Proveedores'=>contactPage('supplier'),'Compras'=>purchasePage(),'Pedidos'=>ordersPage(),
    'Reportes'=>reportsPage(),'Trabajadores'=>staffPage(),'Dispositivos'=>devicesPage(),'Auditoría'=>auditPage(),'Sincronización'=>syncPage(),_=>helpPage()};
  void add(Product p){final line=cart.where((l)=>l.product.id==p.id).firstOrNull;
    if((line?.quantity??0)>=p.stock){message('Sin stock/cupo disponible.');return;}
    setState((){if(line==null){cart.add(CartLine(p));}else{line.quantity++;}});}
  Widget salePage(){
    final query=search.text.toLowerCase();final filtered=products.where((p)=>p.active&&'${p.name} ${p.sku} ${p.barcode}'.toLowerCase().contains(query)).toList();
    final catalog=Column(children:[heading('Venta rápida',cash==null?'Abra la caja para cobrar.':'Caja abierta · Añada productos'),
      Padding(padding:const EdgeInsets.all(16),child:TextField(controller:search,onChanged:(_)=>setState((){}),onSubmitted:(code){
        final p=products.where((p)=>p.barcode==code||p.sku==code).firstOrNull;if(p!=null){add(p);search.clear();}else{message('Código no encontrado.');}},
        decoration:const InputDecoration(prefixIcon:Icon(Icons.search),labelText:'Nombre, SKU o código de barras'))),
      Expanded(child:filtered.isEmpty?const Center(child:Text('No hay productos.')):GridView.builder(padding:const EdgeInsets.symmetric(horizontal:12),
        gridDelegate:const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent:240,mainAxisExtent:166,crossAxisSpacing:6,mainAxisSpacing:6),
        itemCount:filtered.length,itemBuilder:(_,i){final p=filtered[i];return Card(child:InkWell(onTap:busy?null:()=>add(p),borderRadius:BorderRadius.circular(12),
          child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(p.name,maxLines:2,style:const TextStyle(fontWeight:FontWeight.w700,fontSize:17)),const Spacer(),
            Text(money(p.price),style:const TextStyle(fontSize:22,fontWeight:FontWeight.bold,color:Color(0xff087f74))),
            Text('${r.demo?'Stock':'Cupo'}: ${p.stock} · ${p.sku}',style:TextStyle(color:p.stock<=p.low?Colors.deepOrange:Colors.black54))]))));}))]);
    return LayoutBuilder(builder:(_,c)=>c.maxWidth>=760?Row(children:[Expanded(child:catalog),SizedBox(width:340,child:basket())]):
      mobileBasket?Column(children:[TextButton.icon(onPressed:()=>setState(()=>mobileBasket=false),icon:const Icon(Icons.arrow_back),label:const Text('Añadir más productos')),Expanded(child:basket())]):
      Column(children:[Expanded(child:catalog),Padding(padding:const EdgeInsets.all(12),child:SizedBox(width:double.infinity,child:FilledButton.icon(
        onPressed:()=>setState(()=>mobileBasket=true),icon:const Icon(Icons.shopping_cart_outlined),label:Text('Ver venta · ${cart.length} productos · ${money(total)}'))))]));
  }
  Widget basket()=>Card(child:Column(children:[ListTile(title:Text('Tu venta · ${cart.length} productos',style:const TextStyle(fontWeight:FontWeight.bold)),
    trailing:IconButton(tooltip:'Vaciar venta',onPressed:busy?null:()=>setState((){cart.clear();orderId=null;}),icon:const Icon(Icons.delete_outline))),
    Expanded(child:ListView(children:[for(final l in cart)ListTile(title:Text(l.product.name),subtitle:Wrap(crossAxisAlignment:WrapCrossAlignment.center,children:[
      IconButton(onPressed:busy?null:()=>setState((){if(l.quantity>1){l.quantity--;}else{cart.remove(l);}}),icon:const Icon(Icons.remove_circle_outline)),Text('${l.quantity}'),
      IconButton(onPressed:busy?null:()=>add(l.product),icon:const Icon(Icons.add_circle_outline)),
      TextButton(onPressed:busy||!(r.user.admin||r.user.canEditPrice)?null:()async{final v=await form('Precio autorizado',{'Precio PEN':(l.price/100).toStringAsFixed(2)});
        if(v!=null){try{final price=parseMoney(v['Precio PEN']!);if(price<l.product.minimum){throw StateError('Mínimo ${money(l.product.minimum)}');}
          if(mounted){setState(()=>l.price=price);}}catch(e){message('$e');}}},child:Text(money(l.price)))]),trailing:Text(money(l.total)))])),
    Padding(padding:const EdgeInsets.symmetric(horizontal:16),child:Column(children:[
      DropdownButtonFormField<String>(key:ValueKey('customer-$customer'),initialValue:customer,isExpanded:true,decoration:const InputDecoration(labelText:'Cliente'),
        items:[const DropdownMenuItem(value:'',child:Text('Público general')),for(final d in of('customer'))DropdownMenuItem(value:d['id'] as String,child:Text(d['body']['name'] as String))],
        onChanged:busy?null:(v)=>setState(()=>customer=v!)),const SizedBox(height:8),
      DropdownButtonFormField<String>(initialValue:method,decoration:const InputDecoration(labelText:'Pago'),items:[for(final m in ['Efectivo','Tarjeta','Transferencia',
        if(r.user.admin||r.user.canCredit)'Crédito'])DropdownMenuItem(value:m,child:Text(m))],onChanged:busy?null:(v)=>setState(()=>method=v!)),
      Padding(padding:const EdgeInsets.symmetric(vertical:12),child:Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[const Text('TOTAL',style:TextStyle(fontWeight:FontWeight.bold)),
        Text(money(total),style:const TextStyle(fontSize:26,fontWeight:FontWeight.w800))])),
      SizedBox(width:double.infinity,child:FilledButton.icon(onPressed:busy||cart.isEmpty||cash==null?null:checkout,icon:const Icon(Icons.check_circle_outline),label:const Text('Cobrar y emitir ticket'))),
      TextButton(onPressed:busy||cart.isEmpty?null:()=>act(()async{await r.saveOrder(cart,customer);setState((){cart.clear();page='Pedidos';});}),child:const Text('Guardar como pedido')),
      const SizedBox(height:8)]))]));
  Future<void> checkout()async{
    final confirmed=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Confirmar cobro'),content:Text('${cart.fold<int>(0,(s,l)=>s+l.quantity)} unidades · ${money(total)}\nMedio: $method'),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),child:const Text('Volver')),FilledButton(onPressed:()=>Navigator.pop(ctx,true),child:const Text('Confirmar venta'))]));
    if(confirmed!=true){return;}await act(()async{final id=await r.sell(cart,method:method,customer:customer,orderId:orderId);setState((){cart.clear();orderId=null;});
      final sale=(await r.documents('sale')).firstWhere((d)=>d['id']==id);if(mounted){await receipt(sale);}},success:false);
  }
  Future<void> receipt(Map<String,dynamic> sale)=>showDialog<void>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Venta guardada'),
    content:Text('${money(sale['body']['total'] as int)}\nEl PDF está disponible en el historial.'),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cerrar')),
      TextButton(onPressed:(){Navigator.push(context,MaterialPageRoute<void>(builder:(_)=>Scaffold(appBar:AppBar(title:const Text('Ticket PDF')),
        body:PdfPreview(canChangePageFormat:false,canChangeOrientation:false,allowPrinting:true,allowSharing:true,
          pdfFileName:'GAVI-${sale['id']}.pdf',build:(_)=>ticketPdf(sale,demo:r.demo,paperMm:paperMm)))));},child:const Text('Ver PDF')),
      TextButton(onPressed:()async{try{await shareTicket(sale,demo:r.demo,paperMm:paperMm);}catch(e){message('$e');}},child:const Text('Compartir')),
      FilledButton(onPressed:()async{try{await printTicket(sale,demo:r.demo,paperMm:paperMm);}catch(e){message('$e');}},child:const Text('Imprimir'))]));
  Widget cashPage()=>panel([heading('Caja',cash==null?'Cerrada':'Abierta · ${cash!['body']['operator_name']}'),
    if(cash==null)Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('Registre el dinero inicial antes de vender.'),const SizedBox(height:16),FilledButton(onPressed:busy?null:()async{
        final v=await form('Abrir caja',{'Fondo inicial PEN':'0.00'});if(v!=null){await act(()=>r.startCash(parseMoney(v['Fondo inicial PEN']!)));}},child:const Text('Abrir caja'))])))
    else Card(child:Padding(padding:const EdgeInsets.all(20),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Text('Efectivo esperado: ${money(expected)}',style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold)),const Text('Tarjeta y transferencia no aumentan el efectivo.'),const SizedBox(height:16),
      Wrap(spacing:12,runSpacing:12,children:[FilledButton(onPressed:busy?null:()async{final v=await form('Cerrar caja',{'Efectivo contado PEN':(expected/100).toStringAsFixed(2)});
        if(v!=null){await act(()=>r.closeCash(parseMoney(v['Efectivo contado PEN']!)));}},child:const Text('Contar y cerrar')),
        if(r.user.admin)OutlinedButton(onPressed:busy?null:()async{final v=await form('Entrada / salida',{'Importe PEN (negativo para salida)':'','Motivo':''});
          if(v!=null){await act(()async{final raw=v['Importe PEN (negativo para salida)']!.trim();await r.cashMovement(parseMoney(raw.replaceFirst(RegExp(r'^-'),''))*(raw.startsWith('-')?-1:1),v['Motivo']!);});}},child:const Text('Entrada / salida'))])]))),
    for(final d in of('cash_close').where((d)=>r.user.admin||d['actor']==r.user.id))Card(child:ListTile(title:Text('Cierre · ${money(d['body']['counted'] as int)}'),
      subtitle:Text('${d['created']}\nDiferencia: ${money(d['body']['difference'] as int)}')))]);
  Widget productPage()=>panel([heading('Productos','Precios PEN · ${products.length} productos',r.user.admin?FilledButton.icon(onPressed:busy?null:()=>editProduct(),
    icon:const Icon(Icons.add),label:const Text('Nuevo producto')):null),for(final p in products)Card(child:ListTile(title:Text(p.name),
      subtitle:Text('${p.sku} · ${money(p.price)} · Mayorista ${money(p.wholesale)}\n${r.demo?'Stock':'Cupo del dispositivo'} ${p.stock}${p.stock<=p.low?' · STOCK BAJO':''}'),
      trailing:r.user.admin?Wrap(children:[IconButton(tooltip:'Editar',onPressed:busy?null:()=>editProduct(p),icon:const Icon(Icons.edit_outlined)),
        IconButton(tooltip:'Ajustar stock',onPressed:busy?null:()=>adjust(p),icon:const Icon(Icons.inventory_2_outlined))]):null))]);
  Future<void> editProduct([Product? p])async{
    final v=await form(p==null?'Nuevo producto':'Editar producto',{'Nombre':p?.name??'','SKU':p?.sku??'','Código de barras':p?.barcode??'',
      'Precio minorista PEN':((p?.price??0)/100).toStringAsFixed(2),'Precio mayorista PEN':((p?.wholesale??0)/100).toStringAsFixed(2),
      'Mínimo autorizado PEN':((p?.minimum??0)/100).toStringAsFixed(2),'Costo PEN':((p?.cost??0)/100).toStringAsFixed(2),if(p==null)'Stock inicial':'0','Alerta stock bajo':'${p?.low??5}'});
    if(v!=null){await act(()=>r.saveProduct(Product(id:p?.id??PosRepository.uuid.v4(),name:v['Nombre']!,sku:v['SKU']!,barcode:v['Código de barras']!,price:parseMoney(v['Precio minorista PEN']!),
      wholesale:parseMoney(v['Precio mayorista PEN']!),minimum:parseMoney(v['Mínimo autorizado PEN']!),cost:parseMoney(v['Costo PEN']!),stock:p?.stock??int.parse(v['Stock inicial']!),low:int.parse(v['Alerta stock bajo']!))));}}
  Future<void> adjust(Product p)async{final v=await form('Ajustar ${p.name}',{'Cambio de unidades (+ o -)':'','Motivo':''});if(v!=null){await act(()=>r.adjustStock(p.id,int.parse(v['Cambio de unidades (+ o -)']!),v['Motivo']!));}}
  Widget contactPage(String kind)=>panel([heading(kind=='customer'?'Clientes':'Proveedores','Contactos del negocio',FilledButton.icon(onPressed:busy?null:()async{
    final v=await form('Nuevo contacto',{'Nombre':'','Referencia / contacto':''});if(v!=null){await act(()=>r.saveContact(kind,v['Nombre']!,v['Referencia / contacto']!));}},icon:const Icon(Icons.person_add_alt),label:const Text('Añadir'))),
    for(final d in of(kind))Card(child:ListTile(leading:const Icon(Icons.person_outline),title:Text(d['body']['name'] as String),subtitle:Text(d['body']['detail'] as String)))]);
  Widget purchasePage()=>panel([heading('Compras','Recepción de unidades · No registra pago al proveedor'),for(final p in products)Card(child:ListTile(title:Text(p.name),
    subtitle:Text('Costo de referencia ${money(p.cost)}'),trailing:FilledButton.tonal(onPressed:busy?null:()async{final v=await form('Recibir ${p.name}',{'Unidades recibidas':'','Proveedor':'','Documento / motivo':''});
      if(v!=null){await act(()async{final qty=int.parse(v['Unidades recibidas']!);if(qty<=0){throw StateError('Cantidad positiva obligatoria.');}await r.adjustStock(p.id,qty,v['Documento / motivo']!,kind:'purchase',supplier:v['Proveedor']!);});}},child:const Text('Recibir')))),
    for(final d in of('purchase'))Card(child:ListTile(title:Text('${d['body']['name']} · +${d['body']['delta']}'),subtitle:Text('${d['body']['supplier']} · ${d['body']['reason']}')))]);
  Widget ordersPage()=>panel([heading('Pedidos','Guarde desde Vender. No reserva stock.'),for(final d in of('order'))Card(child:ListTile(
    title:Text('Pedido ${shortId(d['id'])} · ${money(d['body']['total'] as int)}'),subtitle:Text(of('sale').any((s)=>s['body']['order_id']==d['id'])?'Entregado / vendido':'Confirmado · Pendiente de venta'),
    trailing:OutlinedButton(onPressed:busy||of('sale').any((s)=>s['body']['order_id']==d['id'])?null:(){try{final lines=<CartLine>[];
      for(final item in d['body']['items'] as List){final p=products.firstWhere((p)=>p.id==item['product_id']);lines.add(CartLine(p,quantity:item['quantity'] as int,price:item['price'] as int));}
      setState((){cart.clear();cart.addAll(lines);customer=d['body']['customer'] as String;orderId=d['id'] as String;page='Vender';});}catch(e){message('Producto no disponible: $e');}},child:const Text('Pasar a venta'))))]);
  String shortId(dynamic id)=>id.toString().substring(0,8);
  Widget historyPage()=>panel([heading('Ventas','Tickets PDF y operaciones de venta'),for(final d in of('sale').where((d)=>r.user.admin||d['actor']==r.user.id))Card(
    child:Padding(padding:const EdgeInsets.all(16),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('${shortId(d['id'])} · ${money(d['body']['total'] as int)}',
      style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold)),Text('${d['body']['operator_name']} · ${d['body']['method']} · ${d['created']}'),
      if(of('refund').any((x)=>x['body']['sale_id']==d['id']))const Text('DEVUELTA',style:TextStyle(color:Colors.deepOrange)),
      Wrap(spacing:8,children:[TextButton.icon(onPressed:()=>receipt(d),icon:const Icon(Icons.picture_as_pdf),label:const Text('Ticket PDF')),
        if(r.user.admin)TextButton(onPressed:busy?null:()async{final v=await form('Devolver venta completa',{'Motivo':''});if(v!=null){await act(()=>r.refund(d['id'] as String,v['Motivo']!));}},child:const Text('Devolver')),
        if(r.user.admin&&d['body']['paid']!=d['body']['total'])TextButton(onPressed:busy?null:()async{final saldo=await r.balance(d['id'] as String);if(!mounted){return;}
          final v=await form('Saldo ${money(saldo)}',{'Pago PEN':'','Medio (Efectivo/Tarjeta/Transferencia)':'Efectivo'});if(v!=null){await act(()=>r.payCredit(d['id'] as String,parseMoney(v['Pago PEN']!),v['Medio (Efectivo/Tarjeta/Transferencia)']!));}},child:const Text('Registrar abono'))])])))]);
  List<Map<String,dynamic>> get reportSales=>of('sale').where((d)=>reportFrom==null||!DateTime.parse(d['created'] as String).isBefore(reportFrom!)).toList();
  Widget metric(String label,String value)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(label),Text(value,style:const TextStyle(fontSize:26,fontWeight:FontWeight.bold))]);
  Widget reportsPage(){final sales=reportSales;final ids=sales.map((d)=>d['id']).toSet();final refunds=of('refund').where((d)=>ids.contains(d['body']['sale_id']));
    final gross=sales.fold<int>(0,(s,d)=>s+(d['body']['total'] as int));final returned=refunds.fold<int>(0,(s,d)=>s+(d['body']['total'] as int));
    final ranking=<String,int>{};for(final d in sales){final name=d['body']['operator_name'] as String;ranking[name]=(ranking[name]??0)+(d['body']['total'] as int);}
    final sorted=ranking.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
    return panel([heading('Reportes',r.demo?'Datos locales de demostración':'Datos centrales de la última sincronización + pendientes locales'),Wrap(spacing:8,children:[OutlinedButton(onPressed:()async{
      final date=await showDatePicker(context:context,firstDate:DateTime(2020),lastDate:DateTime.now(),initialDate:DateTime.now());if(date!=null){setState(()=>reportFrom=date);}},
      child:Text(reportFrom==null?'Filtrar desde fecha':'Desde ${reportFrom.toString().split(' ').first}')),TextButton(onPressed:()=>setState(()=>reportFrom=null),child:const Text('Todo')),
      FilledButton.tonal(onPressed:()=>act(()=>shareText(salesCsv(sales),'gavi-ventas.csv'),success:false),child:const Text('Exportar CSV'))]),
      Card(child:Padding(padding:const EdgeInsets.all(24),child:Wrap(spacing:32,runSpacing:16,children:[metric('Ventas',sales.length.toString()),metric('Bruto',money(gross)),metric('Devoluciones',money(returned)),metric('Neto',money(gross-returned))]))),
      const ListTile(title:Text('Ventas brutas por empleado')),for(final e in sorted)Card(child:ListTile(title:Text(e.key),trailing:Text(money(e.value)))),
      const ListTile(title:Text('Stock bajo')),for(final p in products.where((p)=>p.stock<=p.low))Card(child:ListTile(title:Text(p.name),trailing:Text('${p.stock} unidades')))]);}
  String salesCsv(List<Map<String,dynamic>> sales){String escape(dynamic v){var s=v.toString();if(RegExp(r'^[=+\-@\t\r]').hasMatch(s)){s="'$s";}return '"${s.replaceAll('"','""')}"';}
    return 'id,fecha_utc,empleado,total_centimos,pagado_centimos,medio\r\n${sales.map((d)=>[d['id'],d['created'],d['body']['operator_name'],d['body']['total'],d['body']['paid'],d['body']['method']].map(escape).join(',')).join('\r\n')}';}
  Future<void> shareText(String content,String name)=>SharePlus.instance.share(ShareParams(files:[XFile.fromData(utf8.encode(content),mimeType:name.endsWith('.csv')?'text/csv':'application/json')],fileNameOverrides:[name])).then((_){});
  Widget auditPage()=>panel([heading('Auditoría','Registro local de operaciones · No elimina documentos'),FilledButton.tonal(onPressed:busy?null:()=>act(()async{
    await shareText(await r.exportBackup(),'gavi-respaldo-local.json');},success:false),child:const Text('Exportar respaldo local')),
    for(final d in docs)Card(child:ExpansionTile(title:Text('${d['kind']} · ${shortId(d['id'])}'),subtitle:Text('${d['body']['operator_name']} · ${d['created']}'),
      children:[Padding(padding:const EdgeInsets.all(16),child:SelectableText(const JsonEncoder.withIndent('  ').convert(d['body'])))]))]);
  Widget syncPage()=>panel([heading('Sincronización',r.demo?'Demostración: datos locales':widget.cloud!.status),SelectableText('Dispositivo: ${r.device}'),const SizedBox(height:12),
    if(widget.cloud!=null)FilledButton.icon(onPressed:busy?null:()=>act(()=>widget.cloud!.synchronize(),success:false),icon:const Icon(Icons.sync),label:const Text('Sincronizar ahora')),
    const Text('No borre los datos del navegador ni desinstale con operaciones pendientes. Un rechazo requiere conciliación; no se marca como enviado.'),
    for(final q in queue)Card(child:ListTile(title:Text('${q['kind']} · ${shortId(q['id'])}'),subtitle:Text('${q['state']} · intentos ${q['attempts']}${q['error']==null?'':'\n${q['error']}'}')))]);
  Widget staffPage(){
    if(widget.cloud==null){return panel([heading('Trabajadores','Demostración con dos roles'),const Text('Pruebe los permisos saliendo e ingresando como empleado. Los usuarios reales se crean en Supabase Auth; sus contraseñas no se almacenan en el catálogo local.')]);}
    return FutureBuilder<List<Map<String,dynamic>>>(future:widget.cloud!.client.from('profiles').select().order('name'),builder:(_,snap){
      if(snap.hasError){return Center(child:Text('${snap.error}'));}if(!snap.hasData){return const Center(child:CircularProgressIndicator());}
      return panel([heading('Trabajadores','Usuarios existentes en Supabase Auth · Gestión en línea'),
        const Text('Para un trabajador nuevo, cree primero su cuenta en Supabase Auth y su perfil. No comparta cuentas ni contraseñas.'),
        for(final p in snap.data!)Card(child:ListTile(title:Text(p['name'] as String),subtitle:Text('${p['role']} · ${p['active']==true?'Activo':'Deshabilitado'}'),
          trailing:OutlinedButton(onPressed:busy?null:()async{final v=await form('Permisos de trabajador',{'Nombre':p['name'] as String,'Rol (admin/employee)':p['role'] as String,
            'Activo (si/no)':p['active']==true?'si':'no','Editar precio (si/no)':p['can_edit_price']==true?'si':'no','Crédito (si/no)':p['can_credit']==true?'si':'no'});
            if(v!=null){await act(()async{for(final key in ['Activo (si/no)','Editar precio (si/no)','Crédito (si/no)']){if(!['si','no'].contains(v[key])){throw StateError('Use si o no.');}}
              await widget.cloud!.client.rpc('manage_profile',params:{'p_id':p['id'],'p_name':v['Nombre'],'p_role':v['Rol (admin/employee)'],'p_active':v['Activo (si/no)']=='si','p_edit_price':v['Editar precio (si/no)']=='si','p_credit':v['Crédito (si/no)']=='si'});});}},child:const Text('Permisos'))))]);
    });
  }
  Widget devicesPage(){
    if(widget.cloud==null){return panel([heading('Dispositivos','Modo local de prueba'),SelectableText('Este dispositivo: ${r.device}'),
      const Text('En producción, cada dispositivo recibe cupos de stock exclusivos. Los cupos no se recuperan automáticamente de un dispositivo perdido.')]);}
    return FutureBuilder<List<Map<String,dynamic>>>(future:widget.cloud!.client.from('devices').select().order('id'),builder:(_,snap){
      if(snap.hasError){return Center(child:Text('${snap.error}'));}if(!snap.hasData){return const Center(child:CircularProgressIndicator());}
      return panel([heading('Dispositivos','Asignación de stock en línea · Solo administrador'),
        for(final d in snap.data!)Card(child:ListTile(title:Text('${shortId(d['id'])} · ${d['id']==r.device?'Este dispositivo':'Otro dispositivo'}'),subtitle:Text('Responsable: ${d['owner']}'),
          trailing:FilledButton.tonal(onPressed:busy||d['active']!=true?null:()async{final v=await form('Asignar cupo',{'SKU del producto':'','Unidades':''});
            if(v!=null){await act(()async{final p=products.firstWhere((p)=>p.sku==v['SKU del producto']);await widget.cloud!.client.rpc('grant_quota',params:{'p_device':d['id'],'p_product':p.id,'p_quantity':int.parse(v['Unidades']!)});
              await widget.cloud!.synchronize();});}},child:const Text('Asignar stock'))))]);
    });
  }
  Widget helpPage()=>panel([heading('Cómo operar','GAVI POS · PEN'),Wrap(spacing:12,children:[
    const Text('Ancho de ticket PDF:'),for(final width in [58,80])ChoiceChip(label:Text('$width mm'),selected:paperMm==width,onSelected:(_)=>setState(()=>paperMm=width))]),
    const Padding(padding:EdgeInsets.all(12),child:Text('Impresoras Bluetooth: la conexión directa depende del modelo. El PDF funciona con aplicaciones de impresión compatibles; iPhone requiere compatibilidad iOS/AirPrint o la app del fabricante.')),
    const Card(child:Padding(padding:EdgeInsets.all(20),child:Text(
    '1. Abra Caja y registre fondo inicial.\n2. En Vender busque el producto o lea su código.\n3. Ajuste cantidades; seleccione cliente y pago.\n4. Confirme y vea/comparta o imprima el PDF.\n5. Cuente el efectivo y cierre caja.\n\nEl empleado no ve módulos administrativos. Stock bajo se resalta. En producción la cantidad es el cupo de este dispositivo.\n\nEntrega de desarrollo para probar flujos locales. Faltan puesta en marcha de nube, autorización offline tras reinicio, impresoras por modelo y pruebas en teléfonos. No usar aún como caja comercial.')))]);
}
