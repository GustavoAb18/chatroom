-- ChatRoom: script de reparo do banco
-- Execute este arquivo inteiro no SQL Editor do Supabase se o app não criar
-- salas, se o perfil não aparecer ou se alguma ação der erro de permissão.
-- Ele pode ser executado quantas vezes quiser: só recria o que estiver faltando.

-- 1) Garante o gatilho que cria o perfil de todo novo usuário ---------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, avatar_color)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''),
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'Usuário'
    ),
    (array['#2563EB', '#7C3AED', '#DB2777', '#059669', '#D97706', '#DC2626', '#0891B2'])
      [1 + floor(random() * 7)]
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 2) Cria os perfis que ficaram faltando ------------------------------------
-- Contas criadas antes do gatilho não têm linha em profiles. Sem ela, a
-- criação de salas falha por causa da chave estrangeira.
insert into public.profiles (id, username, avatar_color)
select
  u.id,
  coalesce(
    nullif(trim(u.raw_user_meta_data ->> 'full_name'), ''),
    nullif(split_part(coalesce(u.email, ''), '@', 1), ''),
    'Usuário'
  ),
  '#2563EB'
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null
on conflict (id) do nothing;

-- 3) Garante RLS, políticas e permissões ------------------------------------
alter table public.profiles enable row level security;
alter table public.rooms enable row level security;
alter table public.room_members enable row level security;
alter table public.messages enable row level security;

grant usage on schema public to anon, authenticated;

drop policy if exists "Perfis: leitura para quem está logado" on public.profiles;
create policy "Perfis: leitura para quem está logado"
  on public.profiles for select to authenticated using (true);

drop policy if exists "Perfis: atualizar o próprio" on public.profiles;
create policy "Perfis: atualizar o próprio"
  on public.profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id);

grant select, update on public.profiles to authenticated;

drop policy if exists "Salas: leitura para quem está logado" on public.rooms;
create policy "Salas: leitura para quem está logado"
  on public.rooms for select to authenticated using (true);

drop policy if exists "Salas: criar como dono" on public.rooms;
create policy "Salas: criar como dono"
  on public.rooms for insert to authenticated
  with check (auth.uid() = created_by);

grant select, insert on public.rooms to authenticated;

create or replace function public.is_room_member(p_room_id uuid)
returns boolean
language sql
security definer
stable
set search_path = public
as $$
  select exists (
    select 1 from public.room_members
    where room_id = p_room_id and user_id = auth.uid()
  );
$$;

revoke all on function public.is_room_member(uuid) from public;
grant execute on function public.is_room_member(uuid) to authenticated;

drop policy if exists "Membros: a própria linha e os colegas de sala" on public.room_members;
create policy "Membros: a própria linha e os colegas de sala"
  on public.room_members for select to authenticated
  using (user_id = auth.uid() or public.is_room_member(room_id));

drop policy if exists "Membros: entrar como eu mesmo" on public.room_members;
create policy "Membros: entrar como eu mesmo"
  on public.room_members for insert to authenticated
  with check (user_id = auth.uid());

drop policy if exists "Membros: sair (apagar a própria linha)" on public.room_members;
create policy "Membros: sair (apagar a própria linha)"
  on public.room_members for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, delete on public.room_members to authenticated;

drop policy if exists "Mensagens: ler as das salas em que estou" on public.messages;
create policy "Mensagens: ler as das salas em que estou"
  on public.messages for select to authenticated
  using (public.is_room_member(room_id));

drop policy if exists "Mensagens: enviar nas salas em que estou" on public.messages;
create policy "Mensagens: enviar nas salas em que estou"
  on public.messages for insert to authenticated
  with check (user_id = auth.uid() and public.is_room_member(room_id));

drop policy if exists "Mensagens: apagar as próprias" on public.messages;
create policy "Mensagens: apagar as próprias"
  on public.messages for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, delete on public.messages to authenticated;

-- 4) Garante que as mensagens chegam pelo Realtime --------------------------
do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'messages'
  ) then
    alter publication supabase_realtime add table public.messages;
  end if;
end
$$;
