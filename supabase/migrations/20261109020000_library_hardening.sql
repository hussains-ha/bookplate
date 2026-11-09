-- Review fixes for #59.
-- 1. Replacing a shelf's or list's books skips IDs of books that don't exist (e.g. a book whose save
--    was refused), so one bad book can't make every later reorder of that shelf fail.
-- 2. Signed-out requests are refused outright instead of quietly seeing no rows.

create or replace function public.set_shelf_books(p_shelf_id text, p_book_ids text[])
returns void
language sql
security invoker
set search_path = ''
as $$
    delete from public.shelf_books where user_id = auth.uid() and shelf_id = p_shelf_id;
    insert into public.shelf_books (user_id, shelf_id, book_id, position)
    select auth.uid(), p_shelf_id, t.book_id, t.ord - 1
    from unnest(p_book_ids) with ordinality as t(book_id, ord)
    join public.books b on b.user_id = auth.uid() and b.id = t.book_id;
$$;

create or replace function public.set_list_books(p_list_id text, p_book_ids text[])
returns void
language sql
security invoker
set search_path = ''
as $$
    delete from public.list_books where user_id = auth.uid() and list_id = p_list_id;
    insert into public.list_books (user_id, list_id, book_id, position)
    select auth.uid(), p_list_id, t.book_id, t.ord - 1
    from unnest(p_book_ids) with ordinality as t(book_id, ord)
    join public.books b on b.user_id = auth.uid() and b.id = t.book_id;
$$;

revoke all on table public.shelves, public.shelf_books, public.book_meta, public.lists, public.list_books from anon;
