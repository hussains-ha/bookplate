-- Per-user library settings (#61): the yearly reading goal for now; theme (#49) and
-- bookplate (#60) settings join later. One row per user, created on first save.
create table public.library_settings (
    user_id uuid primary key default auth.uid() references auth.users (id) on delete cascade,
    reading_goal integer not null default 24 check (reading_goal between 1 and 999),
    updated_at timestamptz not null default now()
);

alter table public.library_settings enable row level security;

create policy "Users manage their own settings" on public.library_settings for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

revoke all on table public.library_settings from anon;
