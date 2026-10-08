-- Resolve ambiguity between operation body column and function variable.
create or replace function public.apply_operation(p_id uuid,p_kind text,p_body jsonb,p_created timestamptz)
returns jsonb language plpgsql security definer set search_path=public as $$
declare u profiles%rowtype; d uuid; existing operations%rowtype; c cash_sessions%rowtype;
 p products%rowtype; item jsonb; before_product products%rowtype; pid uuid; delta integer;
 original operations%rowtype; amount bigint; balance bigint; total bigint:=0;
 payload jsonb:=p_body; result jsonb; supplier text;
begin
 select * into u from profiles where id=auth.uid() and active;
 if not found then raise exception 'Usuario no autorizado'; end if;
 d:=(payload->>'device_id')::uuid;
 perform 1 from devices where id=d and owner=u.id and active for update;
 if not found then raise exception 'Dispositivo no autorizado'; end if;
 select * into existing from operations where id=p_id;
 if found then
   if existing.actor<>u.id or existing.device_id<>d or existing.kind<>p_kind or existing.body<>payload then raise exception 'UUID reutilizado con contenido diferente'; end if;
   return jsonb_build_object('id',p_id,'duplicate',true);
 end if;
 if p_kind in ('cash_open','cash_close') then return public.apply_sale_cash(p_id,p_kind,payload,p_created); end if;
 if p_kind='sale' then
   if coalesce(payload->>'customer','')<>'' and not exists(select 1 from contacts where id=(payload->>'customer')::uuid and kind='customer') then raise exception 'Cliente inválido'; end if;
   if coalesce(payload->>'order_id','')<>'' then
     perform 1 from operations where id=(payload->>'order_id')::uuid and kind='order' for update;
     if not found or exists(select 1 from order_sales where order_id=(payload->>'order_id')::uuid) then raise exception 'Pedido inválido o vendido'; end if;
   end if;
   -- Base path currently accepts full payments only. Credit uses a separate
   -- immutable debit event followed by payment events; offline credit gated.
   result:=public.apply_sale_cash(p_id,p_kind,payload,p_created);
   if coalesce(payload->>'order_id','')<>'' then insert into order_sales values((payload->>'order_id')::uuid,p_id); end if;
   return result;
 end if;
 if p_kind not in ('customer','supplier','order','product','stock_adjust','purchase','cash_movement','refund','payment') then raise exception 'Operación no habilitada'; end if;
 if p_kind not in ('customer','order') and u.role<>'admin' then raise exception 'Requiere administrador'; end if;
 if p_kind in ('customer','supplier') then
   if length(trim(coalesce(payload->>'name','')))=0 then raise exception 'Nombre obligatorio'; end if;
   insert into contacts values(p_id,p_kind,payload->>'name',coalesce(payload->>'detail',''));
 elsif p_kind='product' then
   item:=payload->'after'; pid:=(item->>'id')::uuid;
   select * into before_product from products where id=pid for update;
   if trim(coalesce(item->>'name',''))='' or trim(coalesce(item->>'sku',''))='' then raise exception 'Nombre/SKU obligatorios'; end if;
   if found then
     update products set name=item->>'name',sku=item->>'sku',barcode=coalesce(item->>'barcode',''),price=(item->>'price')::bigint,
       wholesale=(item->>'wholesale')::bigint,minimum=(item->>'minimum')::bigint,cost=(item->>'cost')::bigint,low=(item->>'low')::integer,
       active=(item->>'active')::integer=1 where id=pid;
   else
     insert into products values(pid,item->>'name',item->>'sku',coalesce(item->>'barcode',''),(item->>'price')::bigint,(item->>'wholesale')::bigint,
       (item->>'minimum')::bigint,(item->>'cost')::bigint,(item->>'stock')::integer,(item->>'low')::integer,(item->>'active')::integer=1);
     insert into allocations values(d,pid,(item->>'stock')::integer);
   end if;
 elsif p_kind in ('stock_adjust','purchase') then
   pid:=(payload->>'product_id')::uuid; delta:=(payload->>'delta')::integer;
   if delta is null or delta=0 or trim(coalesce(payload->>'reason',''))='' or (p_kind='purchase' and delta<0) then raise exception 'Cantidad/motivo inválido'; end if;
   select * into p from products where id=pid and active for update;
   if not found or p.stock+delta<0 then raise exception 'Stock inválido'; end if;
   if delta<0 then
     update allocations set remaining=remaining+delta where device_id=d and product_id=pid and remaining>=-delta;
     if not found then raise exception 'Ajuste excede cupo propio; concilie otros dispositivos'; end if;
   else
     insert into allocations values(d,pid,delta) on conflict(device_id,product_id) do update set remaining=allocations.remaining+excluded.remaining;
   end if;
   update products set stock=stock+delta where id=pid;
 elsif p_kind='order' then
   if coalesce(payload->>'customer','')='' or not exists(select 1 from contacts where id=(payload->>'customer')::uuid and kind='customer') then raise exception 'Cliente obligatorio'; end if;
   if jsonb_typeof(payload->'items') is distinct from 'array' or jsonb_array_length(payload->'items')=0 then raise exception 'Pedido vacío'; end if;
   for item in select value from jsonb_array_elements(payload->'items') loop
     select * into p from products where id=(item->>'product_id')::uuid and active;
     if not found or coalesce((item->>'quantity')::integer,0)<=0 or coalesce((item->>'price')::bigint,-1)<p.minimum then raise exception 'Línea de pedido inválida'; end if;
     if (item->>'price')::bigint<>p.price and not (u.role='admin' or u.can_edit_price) then raise exception 'Precio no autorizado'; end if;
     total:=total+(item->>'quantity')::integer*(item->>'price')::bigint;
   end loop;
   if total is distinct from (payload->>'total')::bigint then raise exception 'Total inválido'; end if;
 elsif p_kind in ('cash_movement','refund','payment') then
   select * into c from cash_sessions where id=(payload->>'cash_id')::uuid and device_id=d and not closed for update;
   if not found then raise exception 'Caja no disponible'; end if;
   if p_kind='cash_movement' then
     amount:=(payload->>'amount')::bigint;
     if amount is null or amount=0 or c.expected+amount<0 or trim(coalesce(payload->>'reason',''))='' then raise exception 'Movimiento inválido'; end if;
     update cash_sessions set expected=expected+amount where id=c.id;
   else
     select * into original from operations where id=(payload->>'sale_id')::uuid and kind='sale' for update;
     if not found or exists(select 1 from refunds where sale_id=original.id) then raise exception 'Venta inválida o devuelta'; end if;
     if p_kind='refund' then
       if exists(select 1 from credit_payments where sale_id=original.id) then raise exception 'Conciliar abonos antes de devolver'; end if;
       if trim(coalesce(payload->>'reason',''))='' then raise exception 'Motivo obligatorio'; end if;
       amount:=(original.body->>'paid')::bigint+coalesce((select sum(cp.amount) from credit_payments cp where sale_id=original.id),0);
       if amount is distinct from (payload->>'amount')::bigint or payload->>'method' is distinct from original.body->>'method' then raise exception 'Devolución requiere conciliación de pagos'; end if;
       if original.body->'items' is distinct from payload->'items' or (payload->>'total')::bigint is distinct from (original.body->>'total')::bigint then raise exception 'Líneas de devolución inválidas'; end if;
       for item in select value from jsonb_array_elements(original.body->'items') order by value->>'product_id' loop
         pid:=(item->>'product_id')::uuid;delta:=(item->>'quantity')::integer;
         perform 1 from products where id=pid for update;
         update products set stock=stock+delta where id=pid;
         insert into allocations values(d,pid,delta) on conflict(device_id,product_id) do update set remaining=allocations.remaining+excluded.remaining;
       end loop;
       if original.body->>'method'='Efectivo' then
         if c.expected<amount then raise exception 'Efectivo insuficiente'; end if;
         update cash_sessions set expected=expected-amount where id=c.id;
       end if;
     else
       balance:=(original.body->>'total')::bigint-(original.body->>'paid')::bigint-coalesce((select sum(cp.amount) from credit_payments cp where sale_id=original.id),0);
       amount:=(payload->>'amount')::bigint;
       if amount is null or amount<=0 or amount>balance or coalesce(payload->>'method','') not in ('Efectivo','Tarjeta','Transferencia') then raise exception 'Pago inválido'; end if;
       if payload->>'method'='Efectivo' then update cash_sessions set expected=expected+amount where id=c.id; end if;
     end if;
   end if;
 end if;
 insert into operations values(p_id,u.id,d,p_kind,payload,p_created,now());
 if p_kind='refund' then insert into refunds values(p_id,(payload->>'sale_id')::uuid); end if;
 if p_kind='payment' then insert into credit_payments values(p_id,(payload->>'sale_id')::uuid,(payload->>'amount')::bigint,payload->>'method'); end if;
 return jsonb_build_object('id',p_id,'duplicate',false);
end $$;
