-- Bookcase appearance (#49): classic, maple or modern.
alter table public.library_settings
    add column appearance text not null default 'classic' check (length(trim(appearance)) > 0);
