import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { PGlite } from '@electric-sql/pglite';

const SUPABASE = fileURLToPath(new URL('..', import.meta.url));
const ALICE = '11111111-1111-1111-1111-111111111111';

const SUPABASE_STUBS = `
  create schema auth;
  create table auth.users (
    id uuid primary key,
    email text,
    raw_user_meta_data jsonb not null default '{}'::jsonb
  );
  create function auth.uid() returns uuid language sql stable as $$
    select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
  $$;
  create role anon nologin;
  create role authenticated nologin;
  grant usage on schema public, auth to anon, authenticated;
`;

test('corrigir-banco.sql roda duas vezes e repara perfil ausente', async () => {
  const db = new PGlite();
  try {
    await db.exec(SUPABASE_STUBS);
    const schema = readFileSync(`${SUPABASE}/schema.sql`, 'utf8').replace(
      'alter publication supabase_realtime add table public.messages;',
      '-- pulado no teste local',
    );
    await db.exec(schema);

    // Simula uma conta criada antes do gatilho: remove o perfil.
    await db.query(
      `insert into auth.users (id, email) values ($1, 'ana@x.com')`,
      [ALICE],
    );
    await db.query('delete from public.profiles where id = $1', [ALICE]);

    const repair = readFileSync(`${SUPABASE}/corrigir-banco.sql`, 'utf8').replace(
      /-- 4\) Garante que as mensagens chegam pelo Realtime[\s\S]*$/,
      '-- pulado no teste local: publication só existe no Supabase',
    );

    await db.exec(repair);
    await db.exec(repair); // idempotente

    const profile = (
      await db.query('select username from public.profiles where id = $1', [ALICE])
    ).rows[0];
    assert.equal(profile.username, 'ana');

    const room = (
      await db.query(
        'insert into public.rooms (name, created_by) values ($1, $2) returning id',
        ['Sala reparada', ALICE],
      )
    ).rows[0];
    assert.ok(room.id);
  } finally {
    await db.close();
  }
});
