-- Signed-out requests have no business with books. Without this, a request that lost its token
-- runs as anon and RLS quietly returns no rows; now it fails with a permission error instead.
revoke all on table public.books from anon;
