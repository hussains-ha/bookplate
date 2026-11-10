-- #36: custom covers in Supabase Storage.
-- Each user's covers live at book-covers/{user id}/{book id}.jpg in a private bucket.

-- Storage path of the book's custom cover (e.g. "<user id>/<book id>.jpg"), or null.
-- A version suffix ("?v=<id>") is kept on the value so a replaced cover isn't served from an old cache.
alter table public.book_meta add column custom_cover text;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('book-covers', 'book-covers', false, 5242880, array['image/jpeg'])
on conflict (id) do nothing;

-- Users can only read and write objects under their own folder.
create policy "Users read their own covers" on storage.objects for select to authenticated
    using (bucket_id = 'book-covers' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Users add their own covers" on storage.objects for insert to authenticated
    with check (bucket_id = 'book-covers' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Users replace their own covers" on storage.objects for update to authenticated
    using (bucket_id = 'book-covers' and (storage.foldername(name))[1] = (select auth.uid())::text)
    with check (bucket_id = 'book-covers' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "Users delete their own covers" on storage.objects for delete to authenticated
    using (bucket_id = 'book-covers' and (storage.foldername(name))[1] = (select auth.uid())::text);
