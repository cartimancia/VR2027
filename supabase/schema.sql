-- =====================================================================
-- Vera & Ricardo — RSVP backend (Supabase / Postgres)
-- Run once in Supabase > SQL Editor. Safe to re-run: functions and
-- policies are replaced; tables are only created if missing.
--
-- Security model
--   * Guests never touch tables directly. They call two RPC functions
--     (guest_login, guest_submit) with invite code + first name. The
--     functions run as owner and only ever read/write that household.
--   * Admins sign in with Supabase Auth (email + password). Row Level
--     Security lets them read/write everything if their email is listed
--     in public.admins.
--   * The anon role has no table policies, so direct REST access to the
--     tables returns nothing.
-- =====================================================================

create extension if not exists unaccent with schema extensions;

-- ---------- Tables ---------------------------------------------------
create table if not exists public.households (
  id           uuid primary key default gen_random_uuid(),
  code         text not null unique check (code ~ '^[A-Z0-9]{6,12}$'),
  label        text not null,                 -- e.g. "Família Silva"
  message      text,                          -- message from guests
  responded_at timestamptz,
  created_at   timestamptz not null default now()
);

create table if not exists public.guests (
  id           uuid primary key default gen_random_uuid(),
  household_id uuid not null references public.households(id) on delete cascade,
  name         text not null,
  is_plus_one  boolean not null default false, -- guest may rename it
  attending    boolean,                        -- null = no answer yet
  dietary      text,
  sort         int not null default 0
);
create index if not exists guests_household_idx on public.guests(household_id);

create table if not exists public.admins (
  email text primary key
);

alter table public.households enable row level security;
alter table public.guests     enable row level security;
alter table public.admins     enable row level security;

-- ---------- Admin access ---------------------------------------------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.admins
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

drop policy if exists admin_all on public.households;
create policy admin_all on public.households for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists admin_all on public.guests;
create policy admin_all on public.guests for all to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists admin_read on public.admins;
create policy admin_read on public.admins for select to authenticated
  using (public.is_admin());

-- ---------- Guest RPC ------------------------------------------------
create or replace function public.norm_name(t text) returns text
language sql stable set search_path = public, extensions as $$
  select lower(extensions.unaccent(regexp_replace(trim(coalesce(t, '')), '\s+', ' ', 'g')));
$$;

-- Returns the household id when code + name match, else null.
-- Name matches a (non plus-one) guest's full name or its leading words,
-- ignoring case and accents: "joao" matches "João Pedro Silva".
create or replace function public._find_household(p_code text, p_name text) returns uuid
language plpgsql stable security definer set search_path = public, extensions as $$
declare
  n text := public.norm_name(p_name);
  c text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g'));
  h uuid;
begin
  if length(n) < 2 or length(c) < 6 then return null; end if;
  select hh.id into h
  from public.households hh
  where hh.code = c
    and exists (
      select 1 from public.guests g
      where g.household_id = hh.id and not g.is_plus_one
        and (public.norm_name(g.name) = n or public.norm_name(g.name) like n || ' %')
    );
  return h;
end $$;

create or replace function public.guest_login(p_code text, p_name text) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare h uuid := public._find_household(p_code, p_name);
begin
  if h is null then return null; end if;
  return (
    select jsonb_build_object(
      'label', hh.label,
      'message', hh.message,
      'responded_at', hh.responded_at,
      'guests', coalesce((
        select jsonb_agg(jsonb_build_object(
                 'id', g.id, 'name', g.name, 'is_plus_one', g.is_plus_one,
                 'attending', g.attending, 'dietary', g.dietary)
               order by g.sort, g.name)
        from public.guests g where g.household_id = h), '[]'::jsonb))
    from public.households hh where hh.id = h
  );
end $$;

-- p_guests: [{ "id": uuid, "attending": bool, "dietary": text, "name": text }]
-- "name" is only applied to plus-one rows.
create or replace function public.guest_submit(p_code text, p_name text, p_guests jsonb, p_message text)
returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  h uuid := public._find_household(p_code, p_name);
  g jsonb;
begin
  if h is null then raise exception 'invalid_login' using errcode = '28000'; end if;
  if jsonb_typeof(p_guests) <> 'array' or jsonb_array_length(p_guests) > 20 then
    raise exception 'bad_payload' using errcode = '22023';
  end if;

  for g in select * from jsonb_array_elements(p_guests) loop
    update public.guests set
      attending = (g ->> 'attending')::boolean,
      dietary   = nullif(left(trim(coalesce(g ->> 'dietary', '')), 300), ''),
      name      = case
                    when is_plus_one and length(trim(coalesce(g ->> 'name', ''))) > 0
                    then left(trim(g ->> 'name'), 120)
                    else name
                  end
    where id = (g ->> 'id')::uuid and household_id = h;
  end loop;

  update public.households
     set message = nullif(left(trim(coalesce(p_message, '')), 2000), ''),
         responded_at = now()
   where id = h;

  return public.guest_login(p_code, p_name);
end $$;

-- ---------- Grants ---------------------------------------------------
revoke execute on function public._find_household(text, text) from public, anon, authenticated;
revoke execute on function public.guest_login(text, text) from public;
revoke execute on function public.guest_submit(text, text, jsonb, text) from public;
grant  execute on function public.guest_login(text, text) to anon, authenticated;
grant  execute on function public.guest_submit(text, text, jsonb, text) to anon, authenticated;
revoke execute on function public.is_admin() from public, anon;
grant  execute on function public.is_admin() to authenticated;

-- ---------- First admins (edit and run) -------------------------------
-- insert into public.admins(email) values ('you@example.com'), ('vera@example.com');
