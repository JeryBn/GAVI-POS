begin;
-- Patch the constrained sale validator without relaxing stock/cash/idempotency.
do $migration$
declare source text; old_payment text := 'if total is distinct from (p_body->>''total'')::bigint or paid is distinct from total then raise exception ''Total/pago inválido''; end if;';
begin
 source:=pg_get_functiondef('public.apply_sale_cash(uuid,text,jsonb,timestamptz)'::regprocedure);
 if strpos(source,old_payment)=0 then raise exception 'No se encontró el validador esperado; revisar migración'; end if;
 source:=replace(source,'''Efectivo'',''Tarjeta'',''Transferencia''','''Efectivo'',''Tarjeta'',''Transferencia'',''Crédito''');
 source:=replace(source,old_payment,$replacement$
 if total is distinct from (p_body->>'total')::bigint or paid is null or paid<0 or paid>total then raise exception 'Total/pago inválido'; end if;
 if paid<total and (coalesce(p_body->>'customer','')='' or not(u.role='admin' or u.can_credit)) then raise exception 'Crédito no autorizado'; end if;
 if p_body->>'method'='Crédito' and paid<>0 then raise exception 'Crédito requiere pago inicial cero'; end if;
 $replacement$);
 execute source;
end $migration$;
-- Share contacts/orders within the one business, without exposing other sales.
create policy shared_contacts_orders on public.operations for select to authenticated using(public.is_staff() and kind in ('customer','order'));
commit;
