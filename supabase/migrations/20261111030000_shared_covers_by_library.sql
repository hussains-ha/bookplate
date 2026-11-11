-- Share a library (#124), review fix: members could read every custom cover in the owner's folder,
-- including covers from libraries that weren't shared with them. Limit it to books in a library
-- they're a member of. Covers are stored at "<owner id>/<book id>.jpg".
drop policy "Members read shared covers" on storage.objects;

create policy "Members read shared covers" on storage.objects for select to authenticated
    using (
        bucket_id = 'book-covers'
        and exists (
            select 1 from public.library_members m
            join public.books b on b.library_id = m.library_id
            where m.user_id = (select auth.uid())
              and b.user_id::text = (storage.foldername(name))[1]
              and b.id || '.jpg' = storage.filename(name)
        )
    );
