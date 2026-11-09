-- Shelves, lists and personal book details (#59).
-- Every table is owned per user like `books`: user_id defaults to the session,
-- keys are (user_id, id), and row-level security limits rows to their owner.
-- Custom covers and note photos stay on the device until #36.

create table public.shelves (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    id text not null,
    name text not null check (length(trim(name)) > 0),
    position integer not null,
    is_locked boolean not null default false,
    created_at timestamptz not null default now(),
    primary key (user_id, id)
);

-- A shelf's books in order. A book may be on more than one shelf until #29.
create table public.shelf_books (
    user_id uuid not null default auth.uid(),
    shelf_id text not null,
    book_id text not null,
    position integer not null,
    primary key (user_id, shelf_id, book_id),
    foreign key (user_id, shelf_id) references public.shelves (user_id, id) on delete cascade,
    foreign key (user_id, book_id) references public.books (user_id, id) on delete cascade
);
create index shelf_books_book_idx on public.shelf_books (user_id, book_id);

create table public.book_meta (
    user_id uuid not null default auth.uid(),
    book_id text not null,
    status text not null default 'want' check (length(trim(status)) > 0),
    rating smallint check (rating between 1 and 5),
    notes text,
    tags text[] not null default '{}',
    added_at timestamptz not null default now(),
    started_at timestamptz,
    finished_at timestamptz,
    primary key (user_id, book_id),
    foreign key (user_id, book_id) references public.books (user_id, id) on delete cascade
);

create table public.lists (
    user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    id text not null,
    name text not null check (length(trim(name)) > 0),
    position integer not null,
    created_at timestamptz not null default now(),
    primary key (user_id, id)
);

create table public.list_books (
    user_id uuid not null default auth.uid(),
    list_id text not null,
    book_id text not null,
    position integer not null,
    primary key (user_id, list_id, book_id),
    foreign key (user_id, list_id) references public.lists (user_id, id) on delete cascade,
    foreign key (user_id, book_id) references public.books (user_id, id) on delete cascade
);
create index list_books_book_idx on public.list_books (user_id, book_id);

alter table public.shelves enable row level security;
alter table public.shelf_books enable row level security;
alter table public.book_meta enable row level security;
alter table public.lists enable row level security;
alter table public.list_books enable row level security;

create policy "Users manage their own shelves" on public.shelves for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users manage their own shelf books" on public.shelf_books for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users manage their own book details" on public.book_meta for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users manage their own lists" on public.lists for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);
create policy "Users manage their own list books" on public.list_books for all to authenticated
    using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

-- Replace a shelf's or list's books in one transaction, so a reorder never leaves
-- half-written rows. SECURITY INVOKER: row-level security still applies.
create function public.set_shelf_books(p_shelf_id text, p_book_ids text[])
returns void
language sql
security invoker
set search_path = ''
as $$
    delete from public.shelf_books where user_id = auth.uid() and shelf_id = p_shelf_id;
    insert into public.shelf_books (user_id, shelf_id, book_id, position)
    select auth.uid(), p_shelf_id, t.book_id, t.ord - 1
    from unnest(p_book_ids) with ordinality as t(book_id, ord);
$$;

create function public.set_list_books(p_list_id text, p_book_ids text[])
returns void
language sql
security invoker
set search_path = ''
as $$
    delete from public.list_books where user_id = auth.uid() and list_id = p_list_id;
    insert into public.list_books (user_id, list_id, book_id, position)
    select auth.uid(), p_list_id, t.book_id, t.ord - 1
    from unnest(p_book_ids) with ordinality as t(book_id, ord);
$$;

revoke execute on function public.set_shelf_books(text, text[]) from public, anon;
revoke execute on function public.set_list_books(text, text[]) from public, anon;
grant execute on function public.set_shelf_books(text, text[]) to authenticated;
grant execute on function public.set_list_books(text, text[]) to authenticated;
