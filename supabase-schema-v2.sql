-- ============================================================
-- Checktrades / Guild & Gable — Supabase Schema v2
-- New project, run once in Supabase SQL Editor (or via migrations)
--
-- Key changes vs v1:
--   * Anonymous (logged-out) homeowners can submit project requests
--   * Lead matching happens server-side via a trigger (security definer),
--     not in the browser — no client-side INSERT into leads needed
--   * supplier_postcodes table for proper outward-code (NG1/NG2) coverage
--   * Public-safe views for project summaries and reviewer names so
--     quotes.html / reviews can render without exposing private contact data
--   * contact_email is nullable (some trades only collect phone)
--   * supplier_credits table, ready for the pay-per-lead model
-- ============================================================

-- ------------------------------------------------------------
-- 1. PROFILES (extends Supabase Auth users)
-- ------------------------------------------------------------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  role text check (role in ('homeowner', 'supplier')) default 'homeowner',
  avatar_url text,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.profiles enable row level security;

create policy "Users can view their own profile"
  on public.profiles for select using (auth.uid() = id);

create policy "Users can update their own profile"
  on public.profiles for update using (auth.uid() = id);

create policy "Users can insert their own profile"
  on public.profiles for insert with check (auth.uid() = id);

-- Public view exposing only the columns safe to show alongside reviews etc.
create view public.profile_public
  with (security_invoker = false) as
  select id, full_name, avatar_url from public.profiles;

grant select on public.profile_public to anon, authenticated;

-- Auto-create a profile when a new user signs up
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, role)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'full_name', ''),
    coalesce(new.raw_user_meta_data->>'role', 'homeowner')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ------------------------------------------------------------
-- 2. SUPPLIERS
-- ------------------------------------------------------------
create table public.suppliers (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade,
  company_name text not null,
  trade_type text not null check (trade_type in (
    'Aerial Survey', 'Roof Inspection', 'Thermal Imaging', 'Mapping & 3D Models', 'Site Monitoring'
  )),
  years_in_business int default 0,
  primary_postcode text not null,
  postcode_coverage text[] default '{}',
  description text,
  contact_email text,
  contact_phone text,
  is_verified boolean default false,
  is_active boolean default true,
  consultation_price numeric(10,2),
  survey_price numeric(10,2),
  project_price numeric(10,2),
  rating_avg numeric(3,2) default 0,
  review_count int default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.suppliers enable row level security;

create policy "Suppliers are publicly readable"
  on public.suppliers for select using (true);

create policy "Suppliers can update their own record"
  on public.suppliers for update using (auth.uid() = user_id);

create policy "Authenticated users can register as supplier"
  on public.suppliers for insert with check (auth.uid() = user_id);

create index idx_suppliers_trade on public.suppliers(trade_type);
create index idx_suppliers_postcode on public.suppliers(primary_postcode);
create index idx_suppliers_active on public.suppliers(is_active) where is_active = true;


-- ------------------------------------------------------------
-- 2b. SUPPLIER POSTCODES (outward-code coverage, e.g. NG1, NG2, DE1)
-- ------------------------------------------------------------
create table public.supplier_postcodes (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid references public.suppliers(id) on delete cascade,
  postcode_prefix text not null,
  unique(supplier_id, postcode_prefix)
);

alter table public.supplier_postcodes enable row level security;

create policy "Supplier postcodes are publicly readable"
  on public.supplier_postcodes for select using (true);

create policy "Suppliers manage their own postcodes"
  on public.supplier_postcodes for all using (
    exists (select 1 from public.suppliers s where s.id = supplier_postcodes.supplier_id and s.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.suppliers s where s.id = supplier_postcodes.supplier_id and s.user_id = auth.uid())
  );

create index idx_supplier_postcodes_supplier on public.supplier_postcodes(supplier_id);
create index idx_supplier_postcodes_prefix on public.supplier_postcodes(postcode_prefix);


-- ------------------------------------------------------------
-- 3. PROJECTS (client service requests)
-- ------------------------------------------------------------
create table public.projects (
  id uuid primary key default gen_random_uuid(),
  homeowner_id uuid references public.profiles(id) on delete set null,
  trade_type text not null check (trade_type in (
    'Aerial Survey', 'Roof Inspection', 'Thermal Imaging', 'Mapping & 3D Models', 'Site Monitoring'
  )),
  survey_type text,
  property_postcode text not null,
  property_type text,
  bedrooms int,
  contact_name text not null,
  contact_phone text,
  contact_email text,
  scope_notes text,
  budget_range text,
  status text check (status in ('open', 'quoted', 'in_progress', 'completed', 'cancelled')) default 'open',
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.projects enable row level security;

-- Anyone (logged in or not) can submit a project request — this is the main
-- conversion path and must not require auth.
create policy "Anyone can submit a project request"
  on public.projects for insert with check (
    homeowner_id is null or homeowner_id = auth.uid()
  );

create policy "Homeowners can view their own projects"
  on public.projects for select using (auth.uid() = homeowner_id);

create policy "Suppliers can view projects matched to them"
  on public.projects for select using (
    exists (
      select 1 from public.leads l
      join public.suppliers s on s.id = l.supplier_id
      where l.project_id = projects.id and s.user_id = auth.uid()
    )
  );

-- Public-safe summary (no contact details) for quotes.html etc.
create view public.project_summary
  with (security_invoker = false) as
  select id, trade_type, survey_type, property_postcode, property_type,
         bedrooms, budget_range, status, created_at
  from public.projects;

grant select on public.project_summary to anon, authenticated;

create index idx_projects_status on public.projects(status);
create index idx_projects_trade on public.projects(trade_type);


-- ------------------------------------------------------------
-- 4. LEADS (suppliers matched to projects — populated by trigger)
-- ------------------------------------------------------------
create table public.leads (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete cascade,
  status text check (status in ('new', 'accepted', 'declined', 'contacted')) default 'new',
  decline_reason text,
  created_at timestamptz default now(),
  unique(project_id, supplier_id)
);

alter table public.leads enable row level security;

create policy "Suppliers can view their own leads"
  on public.leads for select using (
    exists (select 1 from public.suppliers s where s.id = leads.supplier_id and s.user_id = auth.uid())
  );

create policy "Suppliers can update their own leads"
  on public.leads for update using (
    exists (select 1 from public.suppliers s where s.id = leads.supplier_id and s.user_id = auth.uid())
  );

create index idx_leads_supplier on public.leads(supplier_id);
create index idx_leads_project on public.leads(project_id);

-- Server-side lead matching: runs as the function owner (bypasses RLS),
-- so it works for anonymous project submissions too.
create or replace function public.match_project_suppliers()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  outward text;
  area text;
begin
  outward := upper(regexp_replace(trim(new.property_postcode), '\s+', '', 'g'));
  outward := substring(outward from '^[A-Z]{1,2}[0-9][A-Z0-9]?');
  if outward is null then
    outward := upper(split_part(trim(new.property_postcode), ' ', 1));
  end if;
  area := regexp_replace(outward, '[0-9].*$', '');

  insert into public.leads (project_id, supplier_id, status)
  select new.id, s.id, 'new'
  from public.suppliers s
  where s.trade_type = new.trade_type
    and s.is_active = true
    and (
      outward = any(s.postcode_coverage)
      or area = any(s.postcode_coverage)
      or exists (
        select 1 from public.supplier_postcodes sp
        where sp.supplier_id = s.id and sp.postcode_prefix in (outward, area)
      )
    )
  on conflict (project_id, supplier_id) do nothing;

  return new;
end;
$$;

create trigger trg_match_project_suppliers
  after insert on public.projects
  for each row execute function public.match_project_suppliers();


-- ------------------------------------------------------------
-- 5. QUOTES
-- ------------------------------------------------------------
create table public.quotes (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete cascade,
  supplier_id uuid references public.suppliers(id) on delete cascade,
  price_min numeric(10,2) not null,
  price_max numeric(10,2) not null,
  message text,
  status text check (status in ('pending', 'accepted', 'rejected')) default 'pending',
  created_at timestamptz default now()
);

alter table public.quotes enable row level security;

create policy "Homeowners can view quotes on their projects"
  on public.quotes for select using (
    exists (select 1 from public.projects p where p.id = quotes.project_id and p.homeowner_id = auth.uid())
  );

create policy "Suppliers can insert quotes"
  on public.quotes for insert with check (
    exists (select 1 from public.suppliers s where s.id = quotes.supplier_id and s.user_id = auth.uid())
  );

create policy "Suppliers can view their own quotes"
  on public.quotes for select using (
    exists (select 1 from public.suppliers s where s.id = quotes.supplier_id and s.user_id = auth.uid())
  );

create index idx_quotes_project on public.quotes(project_id);


-- ------------------------------------------------------------
-- 6. REVIEWS
-- ------------------------------------------------------------
create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  supplier_id uuid references public.suppliers(id) on delete cascade,
  reviewer_id uuid references public.profiles(id) on delete set null,
  project_id uuid references public.projects(id) on delete set null,
  overall_rating int not null check (overall_rating between 1 and 5),
  quality_rating int check (quality_rating between 1 and 5),
  communication_rating int check (communication_rating between 1 and 5),
  value_rating int check (value_rating between 1 and 5),
  narrative text,
  is_verified boolean default false,
  created_at timestamptz default now()
);

alter table public.reviews enable row level security;

create policy "Reviews are publicly readable"
  on public.reviews for select using (true);

create policy "Authenticated users can create reviews"
  on public.reviews for insert with check (auth.uid() = reviewer_id);

create index idx_reviews_supplier on public.reviews(supplier_id);

-- Auto-update supplier rating when a review is added
create or replace function public.update_supplier_rating()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.suppliers
  set
    rating_avg = (select coalesce(avg(overall_rating), 0) from public.reviews where supplier_id = new.supplier_id),
    review_count = (select count(*) from public.reviews where supplier_id = new.supplier_id),
    updated_at = now()
  where id = new.supplier_id;
  return new;
end;
$$;

create trigger on_review_created
  after insert on public.reviews
  for each row execute function public.update_supplier_rating();


-- ------------------------------------------------------------
-- 7. TRADE REQUIREMENTS (detailed specs from requirement forms)
-- ------------------------------------------------------------
create table public.trade_requirements (
  id uuid primary key default gen_random_uuid(),
  project_id uuid references public.projects(id) on delete cascade,
  trade_type text not null,
  service_category text,
  budget_range text,
  scope_notes text,
  postcode text,
  contact_name text,
  contact_number text,
  created_at timestamptz default now()
);

alter table public.trade_requirements enable row level security;

create policy "Requirements are viewable by project owner"
  on public.trade_requirements for select using (
    exists (select 1 from public.projects p where p.id = trade_requirements.project_id and p.homeowner_id = auth.uid())
  );

-- Must allow anonymous submissions, same as projects.
create policy "Anyone can create requirements"
  on public.trade_requirements for insert with check (true);

create index idx_trade_requirements_project on public.trade_requirements(project_id);


-- ------------------------------------------------------------
-- 8. SUPPLIER CREDITS (foundation for pay-per-lead model)
-- ------------------------------------------------------------
create table public.supplier_credits (
  supplier_id uuid primary key references public.suppliers(id) on delete cascade,
  balance numeric(10,2) not null default 0,
  updated_at timestamptz default now()
);

alter table public.supplier_credits enable row level security;

create policy "Suppliers can view their own credit balance"
  on public.supplier_credits for select using (
    exists (select 1 from public.suppliers s where s.id = supplier_credits.supplier_id and s.user_id = auth.uid())
  );

-- Give new suppliers a starting credit row
create or replace function public.handle_new_supplier()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.supplier_credits (supplier_id, balance) values (new.id, 0)
  on conflict (supplier_id) do nothing;
  return new;
end;
$$;

create trigger on_supplier_created
  after insert on public.suppliers
  for each row execute function public.handle_new_supplier();


-- ------------------------------------------------------------
-- MIGRATION (run on an EXISTING database to switch to drone services)
-- ------------------------------------------------------------
-- alter table public.suppliers drop constraint suppliers_trade_type_check;
-- alter table public.suppliers add constraint suppliers_trade_type_check
--   check (trade_type in ('Aerial Survey', 'Roof Inspection', 'Thermal Imaging', 'Mapping & 3D Models', 'Site Monitoring'));
-- alter table public.projects drop constraint projects_trade_type_check;
-- alter table public.projects add constraint projects_trade_type_check
--   check (trade_type in ('Aerial Survey', 'Roof Inspection', 'Thermal Imaging', 'Mapping & 3D Models', 'Site Monitoring'));
