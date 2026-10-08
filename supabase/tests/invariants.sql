-- Execute as postgres in a dedicated test project. All fixtures are rolled back.
begin;
insert into auth.users(id) values('00000000-0000-4000-8000-000000000001'),('00000000-0000-4000-8000-000000000002');
insert into public.profiles(id,name,role) values('00000000-0000-4000-8000-000000000001','Test Admin','admin'),('00000000-0000-4000-8000-000000000002','Test Employee','employee');
insert into public.products(id,name,sku,price,wholesale,minimum,cost,stock) values('00000000-0000-4000-8000-000000000010','Producto test','TEST-RPC',250,220,200,100,10);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000001',true);
select public.register_device('00000000-0000-4000-8000-000000000020');
select public.grant_quota('00000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000010',6);
select public.apply_operation('00000000-0000-4000-8000-000000000030','cash_open','{"device_id":"00000000-0000-4000-8000-000000000020","opening":10000}'::jsonb,now());
select public.apply_operation('00000000-0000-4000-8000-000000000031','sale','{"device_id":"00000000-0000-4000-8000-000000000020","cash_id":"00000000-0000-4000-8000-000000000030","method":"Efectivo","total":500,"paid":500,"items":[{"product_id":"00000000-0000-4000-8000-000000000010","quantity":2,"price":250,"total":500}]}'::jsonb,now());
select public.apply_operation('00000000-0000-4000-8000-000000000031','sale','{"device_id":"00000000-0000-4000-8000-000000000020","cash_id":"00000000-0000-4000-8000-000000000030","method":"Efectivo","total":500,"paid":500,"items":[{"product_id":"00000000-0000-4000-8000-000000000010","quantity":2,"price":250,"total":500}]}'::jsonb,now());
select public.apply_operation('00000000-0000-4000-8000-000000000040','customer','{"device_id":"00000000-0000-4000-8000-000000000020","name":"Cliente Test","detail":""}'::jsonb,now());
select public.apply_operation('00000000-0000-4000-8000-000000000041','sale','{"device_id":"00000000-0000-4000-8000-000000000020","cash_id":"00000000-0000-4000-8000-000000000030","method":"Crédito","customer":"00000000-0000-4000-8000-000000000040","total":250,"paid":0,"items":[{"product_id":"00000000-0000-4000-8000-000000000010","quantity":1,"price":250,"total":250}]}'::jsonb,now());
select public.apply_operation('00000000-0000-4000-8000-000000000042','payment','{"device_id":"00000000-0000-4000-8000-000000000020","cash_id":"00000000-0000-4000-8000-000000000030","sale_id":"00000000-0000-4000-8000-000000000041","method":"Efectivo","amount":100}'::jsonb,now());
select public.apply_operation('00000000-0000-4000-8000-000000000043','stock_adjust','{"device_id":"00000000-0000-4000-8000-000000000020","product_id":"00000000-0000-4000-8000-000000000010","delta":2,"reason":"Conteo"}'::jsonb,now());
do $$ begin
 if (select stock from public.products where sku='TEST-RPC')<>9 then raise exception 'Stock/idempotencia falló'; end if;
 if (select remaining from public.allocations where device_id='00000000-0000-4000-8000-000000000020')<>5 then raise exception 'Cupo falló'; end if;
 if (select expected from public.cash_sessions where id='00000000-0000-4000-8000-000000000030')<>10600 then raise exception 'Caja/pagos falló'; end if;
 begin
 perform public.grant_quota('00000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000010',5);
 raise exception 'TEST: sobreasignación permitida';
 exception when others then if SQLERRM like 'TEST:%' then raise; end if; end;
 begin
 perform public.apply_operation('00000000-0000-4000-8000-000000000044','payment','{"device_id":"00000000-0000-4000-8000-000000000020","cash_id":"00000000-0000-4000-8000-000000000030","sale_id":"00000000-0000-4000-8000-000000000041","method":"Efectivo","amount":999}'::jsonb,now());
 raise exception 'TEST: sobrepago permitido';
 exception when others then if SQLERRM like 'TEST:%' then raise; end if; end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000002',true);
do $$ begin
 if exists(select 1 from public.operations where kind='sale') then raise exception 'RLS expone ventas ajenas'; end if;
 begin perform public.grant_quota('00000000-0000-4000-8000-000000000020','00000000-0000-4000-8000-000000000010',1);raise exception 'TEST: empleado asignó stock';
 exception when others then if SQLERRM like 'TEST:%' then raise; end if; end;
end $$;
set local role anon;
do $$ begin begin perform count(*) from public.products;raise exception 'TEST: acceso anónimo permitido';exception when insufficient_privilege then null;end;end $$;
reset role;
rollback;
select 'PASS: idempotencia, stock, cupos, caja, crédito, pagos, ajustes y RLS; fixtures revertidos' as resultado;
