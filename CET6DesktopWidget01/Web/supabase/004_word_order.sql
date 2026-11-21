create table public.goals_word_library_order (
    user_id uuid primary key references auth.users(id) on delete cascade,
    word_ids text[] not null default '{}'
);
alter table public.goals_word_library_order enable row level security;
revoke all on public.goals_word_library_order from public, anon, authenticated;

create function public.goals_word_order(word_ids text[] default '{}')
returns text[] language plpgsql security definer set search_path = '' as $$
declare
    me uuid := auth.uid();
    existing text[];
    additions text[];
begin
    if me is null then raise exception 'Sign in required'; end if;
    if cardinality(word_ids) > 15000 or exists (
        select 1 from unnest(word_ids) id where id is null or length(id) not between 1 and 256
    ) then raise exception 'Invalid word order'; end if;
    if cardinality(word_ids) = 0 then
        return coalesce((select r.word_ids from public.goals_word_library_order r where r.user_id = me), '{}');
    end if;
    insert into public.goals_word_library_order(user_id) values(me) on conflict do nothing;
    select r.word_ids into existing from public.goals_word_library_order r where r.user_id = me for update;
    select coalesce(array_agg(ordered.id order by ordered.first_position), '{}') into additions
    from (
        select proposed.id, min(proposed.position) as first_position
        from unnest(word_ids) with ordinality as proposed(id, position)
        join public.goals_word_state state on state.user_id = me and state.word_id = proposed.id
            and state.kind = 'word' and state.value <> 'null'
        where not proposed.id = any(existing)
        group by proposed.id
    ) ordered;
    existing := additions || existing;
    if cardinality(additions) > 0 then
        update public.goals_word_library_order r set word_ids = existing where r.user_id = me;
    end if;
    return existing;
end;
$$;
revoke all on function public.goals_word_order(text[]) from public, anon;
grant execute on function public.goals_word_order(text[]) to authenticated;
