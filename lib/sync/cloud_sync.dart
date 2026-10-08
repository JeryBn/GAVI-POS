import 'dart:async';
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/models.dart';
import '../core/repository.dart';

class CloudSync {
  final PosRepository repo;
  final SupabaseClient client;
  bool running = false;
  String status = 'Sin conexión comprobada';
  CloudSync(this.repo, this.client);
  Future<Operator> signIn(String email, String password, {bool authenticated=false}) async {
    if(!authenticated){await client.auth.signInWithPassword(email: email.trim(), password: password);}
    final id = client.auth.currentUser!.id;
    final p = await client.from('profiles').select().eq('id', id).single();
    if (p['active'] != true) { await client.auth.signOut(); throw StateError('Usuario deshabilitado.'); }
    await client.rpc('register_device', params: {'p_device': repo.device});
    repo.authorizedUntil = DateTime.now().add(const Duration(hours: 8));
    return Operator(id, p['name'] as String, p['role'] as String,
      canEditPrice: p['can_edit_price'] == true, canCredit: p['can_credit'] == true);
  }
  Future<void> synchronize() async {
    if (running) { return; }
    running = true;
    try {
      if (client.auth.currentUser?.id != repo.user.id) { throw StateError('Sesión inválida.'); }
      // Ordered events preserve cash-open -> sale -> cash-close dependencies.
      for (final op in await repo.queue()) {
        if (op['state'] == 'accepted' || op['state'] == 'local') { continue; }
        if (op['actor'] != repo.user.id) {
          status = 'Hay operaciones de otro usuario: debe iniciar sesión para enviarlas.';
          return;
        }
        try {
          await client.rpc('apply_operation', params: {'p_id': op['id'],
            'p_kind': op['kind'], 'p_body': op['body'], 'p_created': op['created']});
          await repo.db.customStatement("UPDATE outbox SET state='accepted',error=NULL,acknowledged=?,attempts=attempts+1 WHERE id=?",
            [DateTime.now().toUtc().toIso8601String(), op['id']]);
        } on PostgrestException catch (e) {
          await repo.db.customStatement("UPDATE outbox SET state='rejected',error=?,attempts=attempts+1 WHERE id=?", [e.message, op['id']]);
          status = 'Operación rechazada: ${e.message}. Revise sincronización.';
          return;
        } catch (e) {
          await repo.db.customStatement("UPDATE outbox SET error=?,attempts=attempts+1 WHERE id=?", [e.toString(), op['id']]);
          status = 'Sin conexión. Los datos permanecen en este dispositivo.';
          return;
        }
      }
      final products = <Map<String,dynamic>>[];
      final quotas = <Map<String,dynamic>>[];
      for (var offset=0; ; offset+=500) {
        final batch=await client.from('products').select().eq('active',true).order('id').range(offset,offset+499);
        products.addAll(batch);if(batch.length<500){break;}
      }
      for (var offset=0; ; offset+=500) {
        final batch=await client.from('allocations').select().eq('device_id',repo.device).order('product_id').range(offset,offset+499);
        quotas.addAll(batch);if(batch.length<500){break;}
      }
      final quotaMap = {for (final q in quotas) q['product_id']: q['remaining']};
      final remoteDocs = <Map<String,dynamic>>[];
      var offset = 0;
      while (true) {
        final batch = await client.from('operations').select('*,profiles(name)').order('accepted_at').order('id').range(offset, offset+499);
        remoteDocs.addAll(batch);
        if (batch.length<500) { break; }
        offset+=500;
      }
      await repo.db.transaction(() async {
        // A sale may have been written while the request was in flight.
        final waiting = (await repo.queue()).any((o) => o['state'] != 'accepted');
        if (waiting) { return; }
        await repo.db.customStatement('UPDATE products SET active=0');
        for (final p in products) {
          await repo.writeProduct(Product.fromMap({...p, 'stock': quotaMap[p['id']] ?? 0}));
        }
        for (final d in remoteDocs) {
          final body = {...d['body'] as Map<String,dynamic>};
          body['operator_name'] = d['profiles']?['name'] ?? body['operator_name'] ?? d['actor'];
          await repo.db.customStatement('INSERT INTO documents VALUES (?,?,?,?,?) ON CONFLICT(id) DO NOTHING',
            [d['id'],d['kind'],d['client_created'],d['actor'],jsonEncode(body)]);
          await repo.db.customStatement("INSERT INTO outbox(id,state,acknowledged) VALUES (?,'accepted',?) ON CONFLICT(id) DO NOTHING",[d['id'],d['accepted_at']]);
        }
      });
      status = 'Conectado. Operaciones enviadas; cupos actualizados.';
    } catch (e) {
      status = 'No se pudo sincronizar: $e';
      rethrow;
    } finally { running = false; }
  }
  Future<String> exportLog() async => jsonEncode(await repo.queue());
}
