-- ============================================================
-- PEDALE ALLEGRO — Setup database Supabase
-- Da eseguire nella dashboard Supabase → SQL Editor → New query
-- (progetto: wrcvolbhjpzyraooldmt)
-- ============================================================

-- 1) PROFILI ------------------------------------------------------------
create table if not exists public.profiles (
  id uuid primary key references auth.users on delete cascade,
  nome text,
  is_admin boolean default false,
  bike_tag text,                -- es. "Pinarello Dogma · Groupy"
  created_at timestamptz default now()
);
alter table public.profiles add column if not exists bike_tag text;
alter table public.profiles add column if not exists created_at timestamptz default now();
alter table public.profiles enable row level security;

drop policy if exists "read profiles" on public.profiles;
create policy "read profiles" on public.profiles for select using (true);
drop policy if exists "insert own profile" on public.profiles;
create policy "insert own profile" on public.profiles for insert with check (auth.uid() = id);
drop policy if exists "update own profile" on public.profiles;
create policy "update own profile" on public.profiles for update using (auth.uid() = id);

-- Gli amministratori possono gestire i ruoli (necessario per l'Area Riservata:
-- leggere la lista dei profili e assegnare/rimuovere il ruolo admin).
drop policy if exists "admin manage profiles" on public.profiles;
create policy "admin manage profiles" on public.profiles for all
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

-- Crea automaticamente il profilo alla registrazione
create or replace function public.handle_new_user() returns trigger as $$
begin
  insert into public.profiles (id, nome)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', 'Atleta'));
  return new;
end; $$ language plpgsql security definer;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- 2) USCITE --------------------------------------------------------------
create table if not exists public.uscite (
  id bigint generated always as identity primary key,
  titolo text not null,
  data_uscita date,
  descrizione text,
  gpx_url text,
  distanza_km numeric(6,1),   -- distanza in km
  dislivello_m integer,       -- dislivello positivo in metri
  ora_ritrovo text,           -- es. "07:30"
  luogo_partenza text,        -- es. "Piazza Grande"
  ritmo text,                 -- T+ / T- / C+ / C- / M+ / M- / F / GF
  created_at timestamptz default now()
);
-- Aggiunge le colonne se la tabella esisteva già senza:
alter table public.uscite add column if not exists distanza_km numeric(6,1);
alter table public.uscite add column if not exists dislivello_m integer;
alter table public.uscite add column if not exists ora_ritrovo text;
alter table public.uscite add column if not exists luogo_partenza text;
alter table public.uscite add column if not exists ritmo text;
alter table public.uscite add column if not exists created_at timestamptz default now();
alter table public.uscite enable row level security;

drop policy if exists "read uscite" on public.uscite;
create policy "read uscite" on public.uscite for select using (true);
drop policy if exists "admin write uscite" on public.uscite;
create policy "admin write uscite" on public.uscite for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin))
  with check (exists (select 1 from public.profiles where id = auth.uid() and is_admin));

-- 3) GARE ----------------------------------------------------------------
create table if not exists public.gare (
  id bigint generated always as identity primary key,
  titolo text not null,
  data_gara date,
  luogo text,
  descrizione text,
  distanza_km numeric(6,1),   -- distanza in km
  dislivello_m integer,       -- dislivello positivo in metri
  ora_ritrovo text,           -- es. "08:00"
  ritmo text,                 -- categoria / difficoltà
  created_at timestamptz default now()
);
-- Aggiunge le colonne se la tabella esisteva già senza:
alter table public.gare add column if not exists distanza_km numeric(6,1);
alter table public.gare add column if not exists dislivello_m integer;
alter table public.gare add column if not exists descrizione text;
alter table public.gare add column if not exists ora_ritrovo text;
alter table public.gare add column if not exists ritmo text;
alter table public.gare add column if not exists created_at timestamptz default now();
alter table public.gare enable row level security;

drop policy if exists "read gare" on public.gare;
create policy "read gare" on public.gare for select using (true);
drop policy if exists "admin write gare" on public.gare;
create policy "admin write gare" on public.gare for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin))
  with check (exists (select 1 from public.profiles where id = auth.uid() and is_admin));

-- 4) ISCRIZIONI ----------------------------------------------------------
create table if not exists public.iscrizioni (
  user_id uuid references auth.users on delete cascade,
  gara_id bigint references public.gare on delete cascade,
  primary key (user_id, gara_id)
);
alter table public.iscrizioni enable row level security;

drop policy if exists "read iscrizioni" on public.iscrizioni;
create policy "read iscrizioni" on public.iscrizioni for select using (true);
drop policy if exists "own iscrizione" on public.iscrizioni;
create policy "own iscrizione" on public.iscrizioni for insert with check (auth.uid() = user_id);
drop policy if exists "own cancellazione" on public.iscrizioni;
create policy "own cancellazione" on public.iscrizioni for delete using (auth.uid() = user_id);
-- Gli admin possono gestire le iscrizioni di tutti (es. sostituire un ritirato)
drop policy if exists "admin manage iscrizioni" on public.iscrizioni;
create policy "admin manage iscrizioni" on public.iscrizioni for all
  using (exists (select 1 from public.profiles where id = auth.uid() and is_admin))
  with check (exists (select 1 from public.profiles where id = auth.uid() and is_admin));

-- 5) BACHECA (messaggi) ---------------------------------------------------
create table if not exists public.messaggi (
  id bigint generated always as identity primary key,
  user_id uuid references auth.users on delete cascade not null,
  testo text not null check (char_length(testo) <= 500),
  created_at timestamptz default now()
);
alter table public.messaggi enable row level security;

drop policy if exists "read messaggi" on public.messaggi;
create policy "read messaggi" on public.messaggi for select using (true);
drop policy if exists "write propri messaggi" on public.messaggi;
create policy "write propri messaggi" on public.messaggi for insert
  with check (auth.uid() = user_id);
drop policy if exists "delete propri o admin messaggi" on public.messaggi;
create policy "delete propri o admin messaggi" on public.messaggi for delete
  using (auth.uid() = user_id
     or exists (select 1 from public.profiles where id = auth.uid() and is_admin));

-- 6) STORAGE per i file GPX ---------------------------------------------
insert into storage.buckets (id, name, public)
values ('tracce-gpx', 'tracce-gpx', true)
on conflict (id) do nothing;

drop policy if exists "public read tracce-gpx" on storage.objects;
create policy "public read tracce-gpx" on storage.objects for select
  using (bucket_id = 'tracce-gpx');
drop policy if exists "authenticated upload tracce-gpx" on storage.objects;
create policy "authenticated upload tracce-gpx" on storage.objects for insert
  with check (bucket_id = 'tracce-gpx' and auth.role() = 'authenticated');

-- ============================================================
-- DOPO AVER ESEGUITO QUESTO SCRIPT:
-- 1) Registrati sul portale con la tua email/password.
--    (Opzionale: per saltare la conferma email vai in
--     Authentication → Sign In / Up Providers → Email →
--     disattiva "Confirm email")
-- 2) Renditi admin sostituendo il tuo UUID:
--    update public.profiles set is_admin = true
--    where id = '<uuid-del-tuo-utente>';
--    (trovi l'UUID in Authentication → Users → Copy UUID)
-- ============================================================

-- 7) UTILE: rendi il tuo account amministratore (sostituisci l'UUID) -----------
-- Se non ricordi chi è admin, controlla con:
--   select id, nome, is_admin from public.profiles;
-- poi assegna il ruolo:
-- update public.profiles set is_admin = true where id = '<uuid-del-tuo-utente>';
-- In alternativa, dopo la prima registrazione puoi passarti il ruolo anche dal
-- portale: tab 🛡️ Admin → "Ruoli amministratori" (richiede almeno un admin attivo).
