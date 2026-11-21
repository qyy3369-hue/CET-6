create table public.goals_flashcard_mnemonics (
    user_id uuid not null references auth.users(id) on delete cascade,
    word_key text not null check (length(word_key) between 1 and 120),
    hint text not null check (length(hint) between 5 and 200),
    primary key (user_id, word_key)
);

alter table public.goals_flashcard_mnemonics enable row level security;
revoke all on public.goals_flashcard_mnemonics from public, anon, authenticated;

create function public.goals_mnemonics(additions jsonb default '{}', expected jsonb default '{}')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'Sign in required'; end if;
    if jsonb_typeof(additions) <> 'object' or jsonb_typeof(expected) <> 'object'
        or octet_length(additions::text) > 120000 or octet_length(expected::text) > 120000 then
        raise exception 'Invalid mnemonic batch';
    end if;

    insert into public.goals_flashcard_mnemonics as cache(user_id, word_key, hint)
    select me, item.key, item.value #>> '{}' from jsonb_each(additions) item
    where jsonb_typeof(item.value) = 'string'
      and length(item.key) between 1 and 120
      and item.key = lower(btrim(item.key))
      and length(item.value #>> '{}') between 5 and 200
    order by item.key
    on conflict (user_id, word_key) do update set hint = excluded.hint
        where expected ->> excluded.word_key = cache.hint;

    return coalesce((select jsonb_object_agg(word_key,hint)
        from public.goals_flashcard_mnemonics where user_id = me), '{}');
end;
$$;
revoke all on function public.goals_mnemonics(jsonb,jsonb) from public, anon;
grant execute on function public.goals_mnemonics(jsonb,jsonb) to authenticated;
