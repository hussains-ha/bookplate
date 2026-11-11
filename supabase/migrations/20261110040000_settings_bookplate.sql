-- Bookplate designer (#60): style, size, phrase, and shelf label font and size, as one JSON object.
-- The app fills in defaults for missing keys.
alter table public.library_settings
    add column bookplate jsonb not null default '{}'::jsonb check (jsonb_typeof(bookplate) = 'object');
