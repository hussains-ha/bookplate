-- Books owned by each user (#10). Mirrors the app's `Book` model.
-- Each user owns their own rows; IDs are the app's text IDs (e.g. "book-<uuid>"),
-- unique per user.
create table public.books (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    id text not null,
    title text not null check (length(trim(title)) > 0),
    authors text[] not null default '{}',
    page_count integer check (page_count > 0),
    cover_url text,
    isbn13 text,
    cover_lookup_attempted boolean,
    created_at timestamptz not null default now(),
    primary key (user_id, id)
);

alter table public.books enable row level security;

create policy "Users read their own books"
    on public.books for select to authenticated
    using ((select auth.uid()) = user_id);

create policy "Users add their own books"
    on public.books for insert to authenticated
    with check ((select auth.uid()) = user_id);

create policy "Users update their own books"
    on public.books for update to authenticated
    using ((select auth.uid()) = user_id)
    with check ((select auth.uid()) = user_id);

create policy "Users delete their own books"
    on public.books for delete to authenticated
    using ((select auth.uid()) = user_id);
