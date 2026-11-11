-- Multiple libraries (#123).
-- A user can own several libraries. Books, details, shelves, lists and their entries belong to one
-- library. Rows keep `user_id` = the library's owner, so keys stay (user_id, id) as before.
-- Access goes through can_read_library / can_edit_library; #124 extends them to shared members.

create table public.libraries (
    id uuid primary key default gen_random_uuid(),
    owner_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
    name text not null check (length(trim(name)) between 1 and 40),
    -- The owner's display name, shown on the bookplate to people the library is shared with.
    owner_name text,
    position integer not null default 0,
    created_at timestamptz not null default now()
);
create index libraries_owner_idx on public.libraries (owner_id);
alter table public.libraries enable row level security;
revoke all on table public.libraries from anon;

-- Helpers for row security. SECURITY DEFINER so policies on other tables can look up a library
-- without recursing into the libraries policy.
create function public.library_owner(p_library uuid)
returns uuid language sql stable security definer set search_path = ''
as $$ select owner_id from public.libraries where id = p_library $$;

create function public.can_read_library(p_library uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.libraries where id = p_library and owner_id = auth.uid()) $$;

create function public.can_edit_library(p_library uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.libraries where id = p_library and owner_id = auth.uid()) $$;

revoke execute on function public.library_owner(uuid), public.can_read_library(uuid), public.can_edit_library(uuid)
    from public, anon;
grant execute on function public.library_owner(uuid), public.can_read_library(uuid), public.can_edit_library(uuid)
    to authenticated;

create policy "Readers see libraries" on public.libraries for select to authenticated
    using (owner_id = (select auth.uid()) or public.can_read_library(id));
create policy "Owners add libraries" on public.libraries for insert to authenticated
    with check (owner_id = (select auth.uid()));
create policy "Owners change libraries" on public.libraries for update to authenticated
    using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
create policy "Owners delete libraries" on public.libraries for delete to authenticated
    using (owner_id = (select auth.uid()));

-- Every library table gets its library. Deleting a library deletes everything in it.
alter table public.books add column library_id uuid references public.libraries (id) on delete cascade;
alter table public.book_meta add column library_id uuid references public.libraries (id) on delete cascade;
alter table public.shelves add column library_id uuid references public.libraries (id) on delete cascade;
alter table public.shelf_books add column library_id uuid references public.libraries (id) on delete cascade;
alter table public.lists add column library_id uuid references public.libraries (id) on delete cascade;
alter table public.list_books add column library_id uuid references public.libraries (id) on delete cascade;

-- Existing accounts: one "My Library" holding everything they have.
insert into public.libraries (owner_id, name, owner_name, position)
select u.id, 'My Library', nullif(trim(u.raw_user_meta_data ->> 'name'), ''), 0
from auth.users u
where exists (select 1 from public.books where user_id = u.id)
   or exists (select 1 from public.shelves where user_id = u.id)
   or exists (select 1 from public.lists where user_id = u.id);

update public.books t set library_id = l.id from public.libraries l where l.owner_id = t.user_id;
update public.book_meta t set library_id = l.id from public.libraries l where l.owner_id = t.user_id;
update public.shelves t set library_id = l.id from public.libraries l where l.owner_id = t.user_id;
update public.shelf_books t set library_id = l.id from public.libraries l where l.owner_id = t.user_id;
update public.lists t set library_id = l.id from public.libraries l where l.owner_id = t.user_id;
update public.list_books t set library_id = l.id from public.libraries l where l.owner_id = t.user_id;

-- A row saved without a library (an older app build) goes to the owner's first library.
create function public.fill_library_id()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
    if new.library_id is null then
        select id into new.library_id from public.libraries
        where owner_id = new.user_id order by position, created_at limit 1;
        if new.library_id is null then
            insert into public.libraries (owner_id, name, owner_name, position)
            select new.user_id, 'My Library', nullif(trim(raw_user_meta_data ->> 'name'), ''), 0
            from auth.users where id = new.user_id
            returning id into new.library_id;
        end if;
    end if;
    return new;
end $$;
revoke execute on function public.fill_library_id() from public, anon, authenticated;

create trigger books_fill_library before insert on public.books for each row execute function public.fill_library_id();
create trigger book_meta_fill_library before insert on public.book_meta for each row execute function public.fill_library_id();
create trigger shelves_fill_library before insert on public.shelves for each row execute function public.fill_library_id();
create trigger shelf_books_fill_library before insert on public.shelf_books for each row execute function public.fill_library_id();
create trigger lists_fill_library before insert on public.lists for each row execute function public.fill_library_id();
create trigger list_books_fill_library before insert on public.list_books for each row execute function public.fill_library_id();

alter table public.books alter column library_id set not null;
alter table public.book_meta alter column library_id set not null;
alter table public.shelves alter column library_id set not null;
alter table public.shelf_books alter column library_id set not null;
alter table public.lists alter column library_id set not null;
alter table public.list_books alter column library_id set not null;

create index books_library_idx on public.books (library_id);
create index book_meta_library_idx on public.book_meta (library_id);
create index shelves_library_idx on public.shelves (library_id);
create index shelf_books_library_idx on public.shelf_books (library_id);
create index lists_library_idx on public.lists (library_id);
create index list_books_library_idx on public.list_books (library_id);

-- Row security by library: read if you can read the library; write if you can edit it, and only
-- as rows owned by the library's owner.
drop policy "Users read their own books" on public.books;
drop policy "Users add their own books" on public.books;
drop policy "Users update their own books" on public.books;
drop policy "Users delete their own books" on public.books;
drop policy "Users manage their own book details" on public.book_meta;
drop policy "Users manage their own shelves" on public.shelves;
drop policy "Users manage their own shelf books" on public.shelf_books;
drop policy "Users manage their own lists" on public.lists;
drop policy "Users manage their own list books" on public.list_books;

do $$
declare t text;
begin
    foreach t in array array['books', 'book_meta', 'shelves', 'shelf_books', 'lists', 'list_books'] loop
        execute format('create policy "Library readers read" on public.%I for select to authenticated
            using (public.can_read_library(library_id))', t);
        execute format('create policy "Library editors add" on public.%I for insert to authenticated
            with check (public.can_edit_library(library_id) and user_id = public.library_owner(library_id))', t);
        execute format('create policy "Library editors change" on public.%I for update to authenticated
            using (public.can_edit_library(library_id))
            with check (public.can_edit_library(library_id) and user_id = public.library_owner(library_id))', t);
        execute format('create policy "Library editors delete" on public.%I for delete to authenticated
            using (public.can_edit_library(library_id))', t);
    end loop;
end $$;

-- Replacing a shelf's or list's books now names the library, so editors write the owner's rows.
drop function public.set_shelf_books(text, text[]);
drop function public.set_list_books(text, text[]);

create function public.set_shelf_books(p_library_id uuid, p_shelf_id text, p_book_ids text[])
returns void language sql security invoker set search_path = ''
as $$
    delete from public.shelf_books where library_id = p_library_id and shelf_id = p_shelf_id;
    insert into public.shelf_books (user_id, library_id, shelf_id, book_id, position)
    select b.user_id, p_library_id, p_shelf_id, t.book_id, t.ord - 1
    from unnest(p_book_ids) with ordinality as t(book_id, ord)
    join public.books b on b.library_id = p_library_id and b.id = t.book_id;
$$;

create function public.set_list_books(p_library_id uuid, p_list_id text, p_book_ids text[])
returns void language sql security invoker set search_path = ''
as $$
    delete from public.list_books where library_id = p_library_id and list_id = p_list_id;
    insert into public.list_books (user_id, library_id, list_id, book_id, position)
    select b.user_id, p_library_id, p_list_id, t.book_id, t.ord - 1
    from unnest(p_book_ids) with ordinality as t(book_id, ord)
    join public.books b on b.library_id = p_library_id and b.id = t.book_id;
$$;

revoke execute on function public.set_shelf_books(uuid, text, text[]), public.set_list_books(uuid, text, text[])
    from public, anon;
grant execute on function public.set_shelf_books(uuid, text, text[]), public.set_list_books(uuid, text, text[])
    to authenticated;
