-- Demo friend (#125): a second account, "Maya Chen", whose small library is shared with the demo
-- account (View only), so "Shared with you" has something to show. Re-runnable: it resets Maya's
-- library and membership. Run after demo_library.sql.
--
-- Replace DEMO_EMAIL (the demo account) and FRIEND_PASSWORD before running; don't commit them.

do $$
declare
    v_demo_email constant text := 'DEMO_EMAIL';
    v_friend_email constant text := 'maya.chen@bookplate.demo';
    v_friend_password constant text := 'FRIEND_PASSWORD';
    v_demo uuid;
    v_friend uuid;
    v_library uuid;
begin
    select id into v_demo from auth.users where email = v_demo_email;
    if v_demo is null then
        raise exception 'No account with email %', v_demo_email;
    end if;

    select id into v_friend from auth.users where email = v_friend_email;
    if v_friend is null then
        v_friend := gen_random_uuid();
        insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
            raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
            email_change_token_new, email_change)
        values ('00000000-0000-0000-0000-000000000000', v_friend, 'authenticated', 'authenticated', v_friend_email,
            extensions.crypt(v_friend_password, extensions.gen_salt('bf')), now(),
            '{"provider":"email","providers":["email"]}', '{"name":"Maya Chen"}', now(), now(), '', '', '', '');
        insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
        values (gen_random_uuid(), v_friend, v_friend::text,
            jsonb_build_object('sub', v_friend::text, 'email', v_friend_email, 'email_verified', true),
            'email', now(), now(), now());
    end if;

    delete from public.libraries where owner_id = v_friend;
    insert into public.libraries (owner_id, name, owner_name, position)
    values (v_friend, 'Maya''s Favorites', 'Maya Chen', 0) returning id into v_library;

    insert into public.shelves (user_id, library_id, id, name, position, is_locked) values
        (v_friend, v_library, 'shelf-maya-novels', 'Novels', 0, false),
        (v_friend, v_library, 'shelf-maya-nonfiction', 'Nonfiction', 1, false);

    create temp table maya_books (n int, id text, title text, authors text[], pages int, shelf text,
        status text, rating int, tags text[], finished date) on commit drop;
    insert into maya_books values
        (1, 'book-maya-circe', 'Circe', array['Madeline Miller'], 393, 'shelf-maya-novels', 'read', 5, array['myth','favorites'], '2026-03-02'),
        (2, 'book-maya-remains', 'The Remains of the Day', array['Kazuo Ishiguro'], 245, 'shelf-maya-novels', 'read', 5, array['classic'], '2026-05-18'),
        (3, 'book-maya-station', 'Station Eleven', array['Emily St. John Mandel'], 333, 'shelf-maya-novels', 'read', 4, array['literary'], '2026-07-09'),
        (4, 'book-maya-lessons', 'Lessons in Chemistry', array['Bonnie Garmus'], 386, 'shelf-maya-novels', 'reading', null, array['book club'], null),
        (5, 'book-maya-midnight', 'The Midnight Library', array['Matt Haig'], 288, 'shelf-maya-novels', 'want', null, array['literary'], null),
        (6, 'book-maya-braiding', 'Braiding Sweetgrass', array['Robin Wall Kimmerer'], 391, 'shelf-maya-nonfiction', 'read', 5, array['nature','favorites'], '2026-09-14'),
        (7, 'book-maya-quiet', 'Quiet', array['Susan Cain'], 333, 'shelf-maya-nonfiction', 'read', 4, array['psychology'], '2026-02-01'),
        (8, 'book-maya-range', 'Range', array['David Epstein'], 339, 'shelf-maya-nonfiction', 'want', null, array['big ideas'], null);

    insert into public.books (user_id, library_id, id, title, authors, page_count, created_at)
    select v_friend, v_library, b.id, b.title, b.authors, b.pages, timestamptz '2025-08-01 12:00+00' + b.n * interval '1 minute'
    from maya_books b;
    insert into public.book_meta (user_id, library_id, book_id, status, rating, tags, finished_at, started_at)
    select v_friend, v_library, b.id, b.status, b.rating, b.tags,
           b.finished::timestamptz + interval '20 hours', (b.finished - 12)::timestamptz + interval '20 hours'
    from maya_books b;
    insert into public.shelf_books (user_id, library_id, shelf_id, book_id, position)
    select v_friend, v_library, b.shelf, b.id, row_number() over (partition by b.shelf order by b.n) - 1
    from maya_books b;

    insert into public.library_members (library_id, user_id, role) values (v_library, v_demo, 'view');
end $$;
