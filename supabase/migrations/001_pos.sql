-- Run in a NEW Supabase project. No public signup; provision profiles manually.
begin;
create table public.profiles (
 id uuid primary key references auth.users(id), name text not null,
 role text not null check(role in ('admin','employee')), active boolean not null default true,
 can_edit_price boolean not null default false, can_credit boolean not null default false
);
create table public.devices (id uuid primary key, owner uuid not null references public.profiles(id), active boolean not null default true);
create table public.products (
 id uuid primary key, name text not null, sku text not null unique, barcode text not null default '',
 price bigint not null check(price>=0), wholesale bigint not null check(wholesale>=0),
 minimum bigint not null check(minimum>=0), cost bigint not null check(cost>=0),
 stock integer not null check(stock>=0), low integer not null default 5 check(low>=0),
 active boolean not null default true, check(price>=minimum),check(wholesale>=minimum)
);
create unique index product_barcode on public.products(barcode) where barcode<>'';
create table public.allocations (
 device_id uuid references public.devices(id), product_id uuid references public.products(id),
 remaining integer not null check(remaining>=0), primary key(device_id,product_id)
);
create table public.operations (
 id uuid primary key, actor uuid not null references public.profiles(id), device_id uuid not null references public.devices(id),
 kind text not null, body jsonb not null, client_created timestamptz not null,
 accepted_at timestamptz not null default now()
);
create table public.cash_sessions (
 id uuid primary key references public.operations(id), device_id uuid not null references public.devices(id),
 actor uuid not null references public.profiles(id), opening bigint not null check(opening>=0),
 expected bigint not null check(expected>=0), closed boolean not null default false,
 counted bigint, difference bigint
);
create unique index one_open_cash on public.cash_sessions(device_id) where not closed;
create table public.sale_lines (
 sale_id uuid references public.operations(id), product_id uuid references public.products(id),
 quantity integer not null check(quantity>0), price bigint not null check(price>=0),
 primary key(sale_id,product_id)
);
create function public.is_staff() returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from profiles where id=auth.uid() and active) $$;
create function public.is_admin() returns boolean language sql stable security definer set search_path = public
as $$ select exists(select 1 from profiles where id=auth.uid() and active and role='admin') $$;
alter table public.profiles enable row level security;
alter table public.devices enable row level security;
alter table public.products enable row level security;
alter table public.allocations enable row level security;
alter table public.operations enable row level security;
alter table public.cash_sessions enable row level security;
alter table public.sale_lines enable row level security;
create policy profile_read on public.profiles for select to authenticated using(id=auth.uid() or public.is_admin());
create policy device_read on public.devices for select to authenticated using(owner=auth.uid() or public.is_admin());
create policy product_read on public.products for select to authenticated using(public.is_staff());
create policy quota_read on public.allocations for select to authenticated using(public.is_admin() or exists(select 1 from public.devices d where d.id=device_id and d.owner=auth.uid()));
create policy operation_read on public.operations for select to authenticated using(public.is_admin() or actor=auth.uid());
create policy cash_read on public.cash_sessions for select to authenticated using(public.is_admin() or actor=auth.uid());
create policy lines_read on public.sale_lines for select to authenticated using(exists(select 1 from public.operations o where o.id=sale_id and (o.actor=auth.uid() or public.is_admin())));
-- All writes through functions. No client-side direct stock/profile writes.
revoke all on public.profiles,public.devices,public.products,public.allocations,public.operations,public.cash_sessions,public.sale_lines from anon,authenticated;
grant select on public.profiles,public.devices,public.products,public.allocations,public.operations,public.cash_sessions,public.sale_lines to authenticated;

create function public.register_device(p_device uuid) returns void language plpgsql security definer set search_path = public as $$
begin
 if not public.is_staff() then raise exception 'Usuario no autorizado'; end if;
 insert into devices(id,owner) values(p_device,auth.uid()) on conflict(id) do nothing;
 if not exists(select 1 from devices where id=p_device and owner=auth.uid() and active) then raise exception 'Dispositivo no autorizado'; end if;
end $$;

create function public.grant_quota(p_device uuid,p_product uuid,p_quantity integer) returns void language plpgsql security definer set search_path = public as $$
declare available integer;
begin
 if not public.is_admin() or p_quantity<=0 then raise exception 'Asignación no autorizada'; end if;
 select stock into available from products where id=p_product and active for update;
 if available is null then raise exception 'Producto inválido'; end if;
 if not exists(select 1 from devices where id=p_device and active) then raise exception 'Dispositivo inválido'; end if;
 available := available - coalesce((select sum(remaining) from allocations where product_id=p_product),0);
 if p_quantity>available then raise exception 'Stock libre insuficiente'; end if;
 insert into allocations values(p_device,p_product,p_quantity) on conflict(device_id,product_id)
 do update set remaining=allocations.remaining+excluded.remaining;
 insert into operations(id,actor,device_id,kind,body,client_created)
 values(gen_random_uuid(),auth.uid(),p_device,'quota_grant',jsonb_build_object('product_id',p_product,'quantity',p_quantity),now());
end $$;

create function public.apply_operation(p_id uuid,p_kind text,p_body jsonb,p_created timestamptz)
returns jsonb language plpgsql security definer set search_path = public as $$
declare u profiles%rowtype; d uuid; existing operations%rowtype; c cash_sessions%rowtype;
 item jsonb; p products%rowtype; q integer; unit_price bigint; total bigint:=0; paid bigint; seen uuid[]:='{}';
begin
 select * into u from profiles where id=auth.uid() and active;
 if not found then raise exception 'Usuario no autorizado'; end if;
 d := (p_body->>'device_id')::uuid;
 -- Serialize all operations from a device, including duplicate IDs.
 perform 1 from devices where id=d and owner=u.id and active for update;
 if not found then raise exception 'Dispositivo no autorizado'; end if;
 select * into existing from operations where id=p_id;
 if found then
   if existing.actor<>u.id or existing.device_id<>d or existing.kind<>p_kind or existing.body<>p_body then raise exception 'UUID reutilizado con contenido diferente'; end if;
   return jsonb_build_object('id',p_id,'duplicate',true);
 end if;
 if p_kind not in ('cash_open','cash_close','sale') then raise exception 'Tipo de operación no habilitado'; end if;
 if p_kind='cash_open' then
   if (p_body->>'opening')::bigint<0 or p_body->>'opening' is null then raise exception 'Fondo inválido'; end if;
   insert into operations values(p_id,u.id,d,p_kind,p_body,p_created,now());
   insert into cash_sessions(id,device_id,actor,opening,expected) values(p_id,d,u.id,(p_body->>'opening')::bigint,(p_body->>'opening')::bigint);
 else
   select * into c from cash_sessions where id=(p_body->>'cash_id')::uuid and device_id=d and not closed for update;
   if not found or (c.actor<>u.id and u.role<>'admin') then raise exception 'Caja no disponible'; end if;
   if p_kind='cash_close' then
     if (p_body->>'counted')::bigint<0 or p_body->>'counted' is null then raise exception 'Conteo inválido'; end if;
     if (p_body->>'expected')::bigint is distinct from c.expected then raise exception 'Caja requiere conciliación'; end if;
     update cash_sessions set closed=true,counted=(p_body->>'counted')::bigint,difference=(p_body->>'counted')::bigint-expected where id=c.id;
     insert into operations values(p_id,u.id,d,p_kind,p_body,p_created,now());
   else
     if coalesce(p_body->>'method','') not in ('Efectivo','Tarjeta','Transferencia') then raise exception 'Medio no habilitado'; end if;
     if jsonb_typeof(p_body->'items') is distinct from 'array' or jsonb_array_length(p_body->'items')=0 then raise exception 'Venta vacía'; end if;
     -- Sort IDs so concurrent devices lock products in the same order.
     for item in select value from jsonb_array_elements(p_body->'items') order by value->>'product_id' loop
       q := (item->>'quantity')::integer; unit_price := (item->>'price')::bigint;
       select * into p from products where id=(item->>'product_id')::uuid and active for update;
       if not found or p.id=any(seen) or q is null or q<=0 or unit_price is null or unit_price<p.minimum then raise exception 'Producto/cantidad/precio inválido'; end if;
       seen:=array_append(seen,p.id);
       if unit_price<>p.price and not (u.role='admin' or u.can_edit_price) then raise exception 'Precio no autorizado'; end if;
       if p.stock<q then raise exception 'Stock insuficiente'; end if;
       update allocations set remaining=remaining-q where device_id=d and product_id=p.id and remaining>=q;
       if not found then raise exception 'Cupo insuficiente'; end if;
       update products set stock=stock-q where id=p.id;
       if (item->>'total')::bigint is distinct from q::bigint*unit_price then raise exception 'Total de línea inválido'; end if;
       total:=total+q::bigint*unit_price;
     end loop;
     paid := (p_body->>'paid')::bigint;
     if total is distinct from (p_body->>'total')::bigint or paid is distinct from total then raise exception 'Total/pago inválido'; end if;
     insert into operations values(p_id,u.id,d,p_kind,p_body,p_created,now());
     for item in select value from jsonb_array_elements(p_body->'items') loop
       insert into sale_lines values(p_id,(item->>'product_id')::uuid,(item->>'quantity')::integer,(item->>'price')::bigint);
     end loop;
     if p_body->>'method'='Efectivo' then update cash_sessions set expected=expected+paid where id=c.id; end if;
   end if;
 end if;
 return jsonb_build_object('id',p_id,'duplicate',false);
end $$;
revoke all on function public.is_staff(),public.is_admin(),public.register_device(uuid),public.grant_quota(uuid,uuid,integer),public.apply_operation(uuid,text,jsonb,timestamptz) from public,anon;
grant execute on function public.is_staff(),public.is_admin(),public.register_device(uuid),public.grant_quota(uuid,uuid,integer),public.apply_operation(uuid,text,jsonb,timestamptz) to authenticated;
commit;
