-- Advisor 0028/0029: public.rls_auto_enable() is SECURITY DEFINER and was callable over the API
-- (/rest/v1/rpc/rls_auto_enable) by anon and signed-in users. It's only meant to run from the
-- `ensure_rls` event trigger (which turns on row-level security for new public tables), and
-- event triggers don't need EXECUTE grants to fire, so take the API roles' access away.
revoke execute on function public.rls_auto_enable() from public, anon, authenticated;
