create extension if not exists pgcrypto;

create table if not exists public.model_versions (
  id uuid primary key default gen_random_uuid(),
  model_id text not null,
  architecture text not null,
  version text not null,
  input_size text,
  checksum text,
  created_at timestamptz not null default now(),
  unique (model_id, version)
);

create table if not exists public.scans (
  id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),
  status text not null check (status in ('verified', 'rescan_required')),
  total_trays integer,
  total_eggs integer,
  model_version text not null,
  device_model text,
  latency_ms integer not null,
  inference_mode text not null,
  constraint rejected_scan_has_no_totals check (
    status = 'verified' or (total_trays is null and total_eggs is null)
  )
);

create table if not exists public.stack_results (
  id uuid primary key default gen_random_uuid(),
  scan_id uuid not null references public.scans(id) on delete cascade,
  physical_stack_id text not null,
  left_count integer,
  right_count integer,
  straight_count integer,
  final_count integer,
  confidence double precision not null check (confidence between 0 and 1),
  accepted boolean not null,
  reason text not null,
  unique (scan_id, physical_stack_id)
);

alter table public.model_versions enable row level security;
alter table public.scans enable row level security;
alter table public.stack_results enable row level security;

create policy "users read own scans" on public.scans
  for select using (auth.uid() = user_id);
create policy "users insert own scans" on public.scans
  for insert with check (auth.uid() = user_id);
create policy "users read own stack results" on public.stack_results
  for select using (
    exists (select 1 from public.scans where scans.id = stack_results.scan_id and scans.user_id = auth.uid())
  );
