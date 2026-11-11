-- Demo library (#116): fills ONE existing account with a realistic library for demos.
-- Re-runnable: it first deletes that account's books, shelves, lists and settings, then reseeds them.
-- Nothing else (other users, the account itself) is touched.
--
-- How to run: replace DEMO_EMAIL below with the demo account's email (don't commit it), then run
-- the whole file in the Supabase SQL editor. Covers are left empty: the app looks them up and
-- saves them the first time the account signs in.

do $$
declare
    v_email constant text := 'DEMO_EMAIL';
    v_uid uuid;
begin
    select id into v_uid from auth.users where email = v_email;
    if v_uid is null then
        raise exception 'No account with email %', v_email;
    end if;

    -- Deleting books also deletes their details and shelf/list entries (foreign keys cascade).
    delete from public.books where user_id = v_uid;
    delete from public.shelves where user_id = v_uid;
    delete from public.lists where user_id = v_uid;
    delete from public.library_settings where user_id = v_uid;

    create temp table demo_shelves (n int, id text, name text, locked boolean) on commit drop;
    insert into demo_shelves values
        (0, 'shelf-demo-fiction',  'Fiction & Classics',        false),
        (1, 'shelf-demo-sff',      'Sci-Fi & Fantasy',          false),
        (2, 'shelf-demo-history',  'History & Ideas',           false),
        (3, 'shelf-demo-growth',   'Self-Improvement',          false),
        (4, 'shelf-demo-memoir',   'Memoir & Biography',        false),
        (5, 'shelf-demo-signed',   'Signed Copies',             true);

    -- n: order added; shelf: demo_shelves.n; status want/reading/read; dates are ISO dates or null.
    create temp table demo_books (
        n int, id text, title text, authors text[], pages int, isbn13 text, shelf int,
        status text, rating int, tags text[], notes text, started date, finished date
    ) on commit drop;
    insert into demo_books values
        ( 1, 'book-demo-pride',       'Pride and Prejudice', array['Jane Austen'], 432, '9780141439518', 0,
          'read', 5, array['classic','romance'], 'Reread for book club. Elizabeth''s letter scene still lands.', '2025-12-28', '2026-01-18'),
        ( 2, 'book-demo-gatsby',      'The Great Gatsby', array['F. Scott Fitzgerald'], 180, '9780743273565', 0,
          'read', 4, array['classic'], null, '2026-02-01', '2026-02-09'),
        ( 3, 'book-demo-kafka',       'Kafka on the Shore', array['Haruki Murakami'], 505, '9781400079278', 0,
          'read', 4, array['magical realism','japan'], null, '2026-02-10', '2026-02-27'),
        ( 4, 'book-demo-klara',       'Klara and the Sun', array['Kazuo Ishiguro'], 303, '9780593318171', 0,
          'read', 5, array['literary','favorites'], 'Quiet and devastating.', '2026-03-10', '2026-03-22'),
        ( 5, 'book-demo-tomorrow',    'Tomorrow, and Tomorrow, and Tomorrow', array['Gabrielle Zevin'], 416, '9780593321201', 0,
          'reading', null, array['literary','games'], null, '2026-11-01', null),
        ( 6, 'book-demo-anxious',     'Anxious People', array['Fredrik Backman'], 352, '9781501160837', 0,
          'want', null, array['book club'], null, null, null),
        ( 7, 'book-demo-dune',        'Dune', array['Frank Herbert'], 688, '9780441013593', 1,
          'read', 5, array['sci-fi','favorites'], 'The desert power chapters are the best part.', '2026-03-25', '2026-04-14'),
        ( 8, 'book-demo-hail-mary',   'Project Hail Mary', array['Andy Weir'], 476, '9780593135204', 1,
          'read', 5, array['sci-fi','favorites'], 'Rocky!', '2026-04-20', '2026-05-03'),
        ( 9, 'book-demo-left-hand',   'The Left Hand of Darkness', array['Ursula K. Le Guin'], 304, '9780441478125', 1,
          'read', 4, array['sci-fi','classic'], null, '2026-05-15', '2026-05-30'),
        (10, 'book-demo-name-wind',   'The Name of the Wind', array['Patrick Rothfuss'], 662, '9780756404741', 1,
          'read', 4, array['fantasy'], null, '2026-06-01', '2026-06-21'),
        (11, 'book-demo-three-body',  'The Three-Body Problem', array['Cixin Liu'], 400, '9780765382030', 1,
          'reading', null, array['sci-fi'], 'Halfway. The VR game sections are wild.', '2026-10-20', null),
        (12, 'book-demo-piranesi',    'Piranesi', array['Susanna Clarke'], 272, '9781635575637', 1,
          'want', null, array['fantasy'], null, null, null),
        (13, 'book-demo-good-omens',  'Good Omens', array['Terry Pratchett','Neil Gaiman'], 412, '9780060853983', 1,
          'want', null, array['fantasy','funny'], null, null, null),
        (14, 'book-demo-sapiens',     'Sapiens', array['Yuval Noah Harari'], 464, '9780062316097', 2,
          'read', 4, array['history','big ideas'], null, '2026-06-25', '2026-07-12'),
        (15, 'book-demo-guns',        'Guns, Germs, and Steel', array['Jared Diamond'], 528, '9780393354324', 2,
          'read', 3, array['history'], 'Dense but worth it.', '2025-09-01', '2025-10-05'),
        (16, 'book-demo-thinking',    'Thinking, Fast and Slow', array['Daniel Kahneman'], 499, '9780374533557', 2,
          'read', 4, array['psychology','big ideas'], null, '2026-07-15', '2026-08-04'),
        (17, 'book-demo-dawn',        'The Dawn of Everything', array['David Graeber','David Wengrow'], 704, '9780374157357', 2,
          'want', null, array['history'], null, null, null),
        (18, 'book-demo-emperor',     'The Emperor of All Maladies', array['Siddhartha Mukherjee'], 608, '9781439170915', 2,
          'want', null, array['science'], null, null, null),
        (19, 'book-demo-atomic',      'Atomic Habits', array['James Clear'], 320, '9780735211292', 3,
          'read', 5, array['habits','favorites'], 'Habit stacking: read 10 pages after morning coffee.', '2026-08-06', '2026-08-29'),
        (20, 'book-demo-deep-work',   'Deep Work', array['Cal Newport'], 296, '9781455586691', 3,
          'read', 4, array['productivity'], null, '2026-09-02', '2026-09-20'),
        (21, 'book-demo-four-thousand','Four Thousand Weeks', array['Oliver Burkeman'], 288, '9780374159122', 3,
          'read', 5, array['productivity','big ideas'], null, '2026-09-25', '2026-10-11'),
        (22, 'book-demo-psych-money', 'The Psychology of Money', array['Morgan Housel'], 256, '9780857197689', 3,
          'reading', null, array['money'], null, '2026-11-03', null),
        (23, 'book-demo-mindset',     'Mindset', array['Carol S. Dweck'], 320, '9780345472328', 3,
          'want', null, array['psychology'], null, null, null),
        (24, 'book-demo-educated',    'Educated', array['Tara Westover'], 352, '9780399590504', 4,
          'read', 5, array['memoir','book club'], null, '2026-10-14', '2026-10-30'),
        (25, 'book-demo-becoming',    'Becoming', array['Michelle Obama'], 448, '9781524763138', 4,
          'read', 4, array['memoir'], null, '2025-11-01', '2025-11-20'),
        (26, 'book-demo-born-crime',  'Born a Crime', array['Trevor Noah'], 304, '9780399588198', 4,
          'read', 5, array['memoir','funny'], null, '2026-11-01', '2026-11-06'),
        (27, 'book-demo-steve-jobs',  'Steve Jobs', array['Walter Isaacson'], 656, '9781451648539', 4,
          'reading', null, array['biography','tech'], null, '2026-09-15', null),
        (28, 'book-demo-shoe-dog',    'Shoe Dog', array['Phil Knight'], 400, '9781501135910', 4,
          'want', null, array['biography'], null, null, null),
        (29, 'book-demo-norwegian',   'Norwegian Wood', array['Haruki Murakami'], 296, '9780375704024', 5,
          'read', 4, array['japan','signed'], 'Signed at a reading in 2019.', '2025-07-01', '2025-07-20'),
        (30, 'book-demo-bird',        'Bird by Bird', array['Anne Lamott'], 237, '9780385480017', 5,
          'want', null, array['writing','signed'], null, null, null);

    -- Added a minute apart in order, so the library loads in a stable order.
    insert into public.books (user_id, id, title, authors, page_count, isbn13, cover_url, cover_lookup_attempted, created_at)
    select v_uid, b.id, b.title, b.authors, b.pages, b.isbn13, null, null,
           timestamptz '2025-06-01 12:00+00' + b.n * interval '1 minute'
    from demo_books b;

    insert into public.book_meta (user_id, book_id, status, rating, notes, tags, added_at, started_at, finished_at)
    select v_uid, b.id, b.status, b.rating, b.notes, b.tags,
           coalesce(b.started::timestamptz, timestamptz '2025-06-01 12:00+00') - interval '7 days',
           b.started::timestamptz + interval '20 hours', b.finished::timestamptz + interval '21 hours'
    from demo_books b;

    insert into public.shelves (user_id, id, name, position, is_locked)
    select v_uid, s.id, s.name, s.n, s.locked from demo_shelves s;

    insert into public.shelf_books (user_id, shelf_id, book_id, position)
    select v_uid, s.id, b.id, row_number() over (partition by b.shelf order by b.n) - 1
    from demo_books b join demo_shelves s on s.n = b.shelf;

    insert into public.lists (user_id, id, name, position) values
        (v_uid, 'list-demo-book-club', 'Book Club 2026', 0),
        (v_uid, 'list-demo-gifts',     'Gift Ideas',     1),
        (v_uid, 'list-demo-reread',    'To Re-read',     2),
        (v_uid, 'list-demo-vacation',  'Vacation Reads', 3);

    insert into public.list_books (user_id, list_id, book_id, position)
    select v_uid, l.list_id, l.book_id, l.pos from (values
        ('list-demo-book-club', 'book-demo-pride', 0), ('list-demo-book-club', 'book-demo-educated', 1),
        ('list-demo-book-club', 'book-demo-anxious', 2), ('list-demo-book-club', 'book-demo-tomorrow', 3),
        ('list-demo-gifts', 'book-demo-hail-mary', 0), ('list-demo-gifts', 'book-demo-atomic', 1),
        ('list-demo-gifts', 'book-demo-born-crime', 2),
        ('list-demo-reread', 'book-demo-dune', 0), ('list-demo-reread', 'book-demo-klara', 1),
        ('list-demo-reread', 'book-demo-left-hand', 2),
        ('list-demo-vacation', 'book-demo-piranesi', 0), ('list-demo-vacation', 'book-demo-good-omens', 1),
        ('list-demo-vacation', 'book-demo-shoe-dog', 2)
    ) as l(list_id, book_id, pos);

    insert into public.library_settings (user_id, reading_goal, appearance, bookplate)
    values (v_uid, 24, 'classic', '{"style":"classic","size":"medium","phrase":"","label_font":"sans","label_size":9}');
end $$;
