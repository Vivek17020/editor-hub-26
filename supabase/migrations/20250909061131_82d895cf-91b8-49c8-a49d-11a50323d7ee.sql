-- Harden profiles schema and the signup handler to prevent JSON parsing errors during Google OAuth callbacks
-- Create profiles table if it doesn’t exist, with safe defaults
create table if not exists public.profiles (
  id uuid primary key,
  full_name text,
  avatar_url text,
  role text not null default 'reader',
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Enable Row Level Security
alter table public.profiles enable row level security;

-- Idempotent RLS policies
do $$ begin
  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='Users can view own profile'
  ) then
    create policy "Users can view own profile"
      on public.profiles for select
      using (auth.uid() = id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='Users can insert own profile'
  ) then
    create policy "Users can insert own profile"
      on public.profiles for insert
      with check (auth.uid() = id);
  end if;

  if not exists (
    select 1 from pg_policies where schemaname='public' and tablename='profiles' and policyname='Users can update own profile'
  ) then
    create policy "Users can update own profile"
      on public.profiles for update
      using (auth.uid() = id);
  end if;
end $$;

-- Keep updated_at fresh
create or replace function public.update_updated_at_column()
returns trigger as $$
begin
  new.updated_at = now();
  return new;
end;
$$ language plpgsql set search_path = public;

do $$ begin
  if not exists (select 1 from pg_trigger where tgname = 'update_profiles_updated_at') then
    create trigger update_profiles_updated_at
    before update on public.profiles
    for each row execute function public.update_updated_at_column();
  end if;
end $$;

-- Robust signup handler used by the auth trigger (if present)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  raw_meta jsonb;
  name text;
  avatar text;
begin
  -- Ensure raw_user_meta_data is valid jsonb to avoid "invalid input syntax for type json"
  raw_meta := coalesce(new.raw_user_meta_data, '{}'::jsonb);

  name := coalesce(raw_meta->>'full_name', raw_meta->>'name', new.email);
  avatar := coalesce(raw_meta->>'avatar_url', raw_meta->>'picture', null);

  insert into public.profiles (id, full_name, avatar_url, metadata)
  values (new.id, name, avatar, raw_meta)
  on conflict (id) do update
    set full_name = excluded.full_name,
        avatar_url = excluded.avatar_url,
        metadata = coalesce(excluded.metadata, '{}'::jsonb),
        updated_at = now();

  return new;
end;
$$;