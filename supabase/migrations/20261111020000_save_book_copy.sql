-- Shared with you (#125): copy a book from a library you can read into one you own.
-- The copy is Want to Read, goes on the target's first unlocked shelf (if any), and keeps the
-- title, authors, pages, cover link and ISBN. Errors (SQLSTATE 22023): not_allowed, not_owner,
-- no_book, already_saved (same title and first author already there).
create function public.save_book_copy(p_source_library uuid, p_book_id text, p_target_library uuid)
returns text
language plpgsql security definer set search_path = ''
as $$
declare
    v_book public.books;
    v_new text;
    v_shelf text;
begin
    if not public.can_read_library(p_source_library) then
        raise exception 'not_allowed' using errcode = '22023';
    end if;
    if not exists (select 1 from public.libraries where id = p_target_library and owner_id = auth.uid()) then
        raise exception 'not_owner' using errcode = '22023';
    end if;
    select * into v_book from public.books where library_id = p_source_library and id = p_book_id;
    if not found then
        raise exception 'no_book' using errcode = '22023';
    end if;
    if exists (
        select 1 from public.books
        where library_id = p_target_library
          and lower(trim(title)) = lower(trim(v_book.title))
          and lower(coalesce(authors[1], '')) = lower(coalesce(v_book.authors[1], ''))
    ) then
        raise exception 'already_saved' using errcode = '22023';
    end if;

    v_new := 'book-' || gen_random_uuid()::text;
    insert into public.books (user_id, library_id, id, title, authors, page_count, cover_url, isbn13, cover_lookup_attempted)
    values (auth.uid(), p_target_library, v_new, v_book.title, v_book.authors, v_book.page_count,
            v_book.cover_url, v_book.isbn13, v_book.cover_lookup_attempted);
    insert into public.book_meta (user_id, library_id, book_id, status)
    values (auth.uid(), p_target_library, v_new, 'want');

    select id into v_shelf from public.shelves
    where library_id = p_target_library and not is_locked order by position limit 1;
    if v_shelf is not null then
        insert into public.shelf_books (user_id, library_id, shelf_id, book_id, position)
        values (auth.uid(), p_target_library, v_shelf, v_new,
                coalesce((select max(position) + 1 from public.shelf_books
                          where library_id = p_target_library and shelf_id = v_shelf), 0));
    end if;
    return v_new;
end $$;

revoke execute on function public.save_book_copy(uuid, text, uuid) from public, anon;
grant execute on function public.save_book_copy(uuid, text, uuid) to authenticated;
