begin;
create table public.audit_log(id bigint generated always as identity primary key,actor uuid,entity text not null,record_id uuid not null,before_data jsonb,after_data jsonb,changed_at timestamptz not null default now());
alter table public.audit_log enable row level security;
revoke all on public.audit_log from anon,authenticated;
grant select on public.audit_log to authenticated;
create policy audit_admin on public.audit_log for select to authenticated using(public.is_admin());
create function public.audit_change() returns trigger language plpgsql security definer set search_path=public as $$
begin
 if TG_OP='INSERT' then insert into audit_log(actor,entity,record_id,after_data) values(auth.uid(),TG_TABLE_NAME,new.id,to_jsonb(new));
 else insert into audit_log(actor,entity,record_id,before_data,after_data) values(auth.uid(),TG_TABLE_NAME,new.id,to_jsonb(old),to_jsonb(new)); end if;
 return new;
end $$;
create trigger product_audit after insert or update on public.products for each row execute function public.audit_change();
create trigger profile_audit after insert or update on public.profiles for each row execute function public.audit_change();
create function public.manage_profile(p_id uuid,p_name text,p_role text,p_active boolean,p_edit_price boolean,p_credit boolean) returns void language plpgsql security definer set search_path=public as $$
declare old_profile profiles%rowtype;
begin
 if not public.is_admin() then raise exception 'Requiere administrador'; end if;
 if p_role not in ('admin','employee') or trim(coalesce(p_name,''))='' then raise exception 'Perfil inválido'; end if;
 lock table profiles in share row exclusive mode;
 select * into old_profile from profiles where id=p_id;
 if not found then raise exception 'Cree primero el usuario de Auth'; end if;
 if old_profile.active and old_profile.role='admin' and (not p_active or p_role<>'admin') and
   (select count(*) from profiles where active and role='admin')<=1 then raise exception 'Debe conservar un administrador activo'; end if;
 update profiles set name=p_name,role=p_role,active=p_active,can_edit_price=p_edit_price,can_credit=p_credit where id=p_id;
end $$;
revoke all on function public.audit_change(),public.manage_profile(uuid,text,text,boolean,boolean,boolean) from public,anon,authenticated;
grant execute on function public.manage_profile(uuid,text,text,boolean,boolean,boolean) to authenticated;
commit;
