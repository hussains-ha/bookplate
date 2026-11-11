-- Share a library (#124).
-- A library's owner can give other accounts View or Edit access. Members read the library;
-- editors can change it (rows are still saved as the owner's, see #123).

create table public.library_members (
    library_id uuid not null references public.libraries (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    role text not null check (role in ('view', 'edit')),
    created_at timestamptz not null default now(),
    primary key (library_id, user_id)
);
create index library_members_user_idx on public.library_members (user_id);
alter table public.library_members enable row level security;
revoke all on table public.library_members from anon;

-- Members see their own membership; owners see everyone in their library. Adding or changing
-- members goes through share_library(). Owners can remove anyone; members can leave.
create policy "Members and owners see members" on public.library_members for select to authenticated
    using (user_id = (select auth.uid()) or public.library_owner(library_id) = (select auth.uid()));
create policy "Owners remove members, members leave" on public.library_members for delete to authenticated
    using (user_id = (select auth.uid()) or public.library_owner(library_id) = (select auth.uid()));

create or replace function public.can_read_library(p_library uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (select 1 from public.libraries where id = p_library and owner_id = auth.uid())
        or exists (select 1 from public.library_members where library_id = p_library and user_id = auth.uid())
$$;

create or replace function public.can_edit_library(p_library uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
    select exists (select 1 from public.libraries where id = p_library and owner_id = auth.uid())
        or exists (select 1 from public.library_members
                   where library_id = p_library and user_id = auth.uid() and role = 'edit')
$$;

-- Everyone in a library you own, with their email and name. Owner only.
create function public.library_member_list(p_library_id uuid)
returns table (user_id uuid, email text, name text, role text)
language sql stable security definer set search_path = ''
as $$
    select m.user_id, u.email::text, nullif(trim(u.raw_user_meta_data ->> 'name'), ''), m.role
    from public.library_members m
    join public.libraries l on l.id = m.library_id
    join auth.users u on u.id = m.user_id
    where m.library_id = p_library_id and l.owner_id = auth.uid()
    order by m.created_at
$$;

-- Gives the account with this email access to a library you own, or changes their role.
-- Errors (all SQLSTATE 22023): not_owner, invalid_role, no_account, self.
create function public.share_library(p_library_id uuid, p_email text, p_role text)
returns table (user_id uuid, email text, name text, role text)
language plpgsql security definer set search_path = ''
as $$
declare
    v_user uuid;
begin
    if p_role not in ('view', 'edit') then
        raise exception 'invalid_role' using errcode = '22023';
    end if;
    if not exists (select 1 from public.libraries where id = p_library_id and owner_id = auth.uid()) then
        raise exception 'not_owner' using errcode = '22023';
    end if;
    select u.id into v_user from auth.users u where lower(u.email) = lower(trim(p_email));
    if v_user is null then
        raise exception 'no_account' using errcode = '22023';
    end if;
    if v_user = auth.uid() then
        raise exception 'self' using errcode = '22023';
    end if;
    insert into public.library_members (library_id, user_id, role)
    values (p_library_id, v_user, p_role)
    on conflict on constraint library_members_pkey do update set role = excluded.role;
    return query select * from public.library_member_list(p_library_id);
end $$;

revoke execute on function public.library_member_list(uuid), public.share_library(uuid, text, text) from public, anon;
grant execute on function public.library_member_list(uuid), public.share_library(uuid, text, text) to authenticated;

-- Members can see the custom covers of libraries shared with them (covers live under the owner's folder).
create policy "Members read shared covers" on storage.objects for select to authenticated
    using (
        bucket_id = 'book-covers'
        and exists (
            select 1 from public.libraries l
            join public.library_members m on m.library_id = l.id
            where l.owner_id::text = (storage.foldername(name))[1] and m.user_id = (select auth.uid())
        )
    );
