begin;

create table public.goals_profiles (
    user_id uuid primary key references auth.users(id) on delete cascade,
    nickname text not null check (length(nickname) between 1 and 32),
    invite_code uuid not null unique default gen_random_uuid()
);

create table public.goals_friendships (
    requester uuid not null references public.goals_profiles(user_id) on delete cascade,
    recipient uuid not null references public.goals_profiles(user_id) on delete cascade,
    accepted boolean not null default false,
    primary key (requester, recipient),
    check (requester <> recipient)
);

create unique index goals_friendship_pair on public.goals_friendships
    (least(requester, recipient), greatest(requester, recipient));

create table public.goals_word_state (
    user_id uuid not null references auth.users(id) on delete cascade,
    word_id text not null check (length(word_id) between 1 and 256),
    kind text not null check (kind in ('word', 'progress', 'favorite', 'dismissed')),
    value jsonb not null,
    revision bigint not null default 1,
    primary key (user_id, word_id, kind)
);

create table public.goals_review_events (
    user_id uuid not null references auth.users(id) on delete cascade,
    event_id uuid not null,
    word_id text not null check (length(word_id) between 1 and 256),
    spelling text not null check (length(spelling) between 1 and 256),
    reviewed_at timestamptz not null,
    active_seconds integer not null check (active_seconds between 0 and 60),
    level integer not null check (level between 0 and 5),
    primary key (user_id, event_id)
);

create index goals_daily_events on public.goals_review_events(user_id, reviewed_at desc);

alter table public.goals_profiles enable row level security;
alter table public.goals_friendships enable row level security;
alter table public.goals_word_state enable row level security;
alter table public.goals_review_events enable row level security;

revoke all on public.goals_profiles, public.goals_friendships, public.goals_word_state,
    public.goals_review_events from public, anon, authenticated;

create function public.goals_sync(changes jsonb default '[]', events jsonb default '[]')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    me uuid := auth.uid();
    item record;
    result jsonb;
begin
    if me is null then raise exception 'Sign in required'; end if;
    if jsonb_array_length(changes) > 300 or jsonb_array_length(events) > 300 then
        raise exception 'Sync batch is too large';
    end if;
    for item in
        select * from jsonb_to_recordset(changes) as x(word_id text, kind text, value jsonb, revision bigint)
        order by word_id, kind
    loop
        item.value := coalesce(item.value, 'null'::jsonb);
        if length(item.value::text) > 20000 or
           (item.kind in ('favorite', 'dismissed') and jsonb_typeof(item.value) <> 'boolean') or
           (item.kind = 'word' and item.value <> 'null' and
            (jsonb_typeof(item.value) <> 'object' or (item.value->>'id') is distinct from item.word_id
             or coalesce(length(item.value->>'word'), 0) not between 1 and 256
             or jsonb_typeof(item.value->'meaning') is distinct from 'string')) or
           (item.kind = 'progress' and item.value <> 'null' and
            (jsonb_typeof(item.value) <> 'object' or (item.value->>'wordID') is distinct from item.word_id
             or coalesce((item.value->>'level')::integer, -1) not between 0 and 5)) then
            raise exception 'Invalid learning record';
        end if;
        if item.revision = 0 then
            insert into public.goals_word_state(user_id, word_id, kind, value)
            values (me, item.word_id, item.kind, item.value) on conflict do nothing;
        else
            update public.goals_word_state as state set value = item.value, revision = state.revision + 1
            where state.user_id = me and state.word_id = item.word_id
                and state.kind = item.kind and state.revision = item.revision;
        end if;
    end loop;

    insert into public.goals_review_events(user_id, event_id, word_id, spelling, reviewed_at, active_seconds, level)
    select me, e.event_id, e.word_id, e.spelling, least(e.reviewed_at, now()), e.active_seconds, e.level
    from jsonb_to_recordset(events)
        as e(event_id uuid, word_id text, spelling text, reviewed_at timestamptz, active_seconds integer, level integer)
    on conflict do nothing;

    select coalesce(jsonb_agg(to_jsonb(state) - 'user_id' order by word_id, kind), '[]') into result
    from public.goals_word_state state where user_id = me;
    return result;
end;
$$;

create function public.goals_social(action text default 'list', target text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    me uuid := auth.uid();
    peer uuid;
    my_profile public.goals_profiles;
    today_start timestamptz := date_trunc('day', now() at time zone 'Asia/Shanghai') at time zone 'Asia/Shanghai';
    next_day timestamptz := today_start + interval '24 hours';
    ranks jsonb;
    requests jsonb;
    words jsonb;
begin
    if me is null then raise exception 'Sign in required'; end if;
    if action = 'nickname' then
        insert into public.goals_profiles(user_id, nickname) values (me, btrim(target))
        on conflict (user_id) do update set nickname = excluded.nickname;
    end if;
    select * into my_profile from public.goals_profiles where user_id = me;
    if not found then
        if action = 'list' then return jsonb_build_object('profile', null, 'ranking', '[]'::jsonb, 'requests', '[]'::jsonb); end if;
        raise exception 'Create a nickname first';
    end if;

    case action
        when 'invite' then
            select user_id into peer from public.goals_profiles where invite_code = target::uuid;
            if peer is null or peer = me then raise exception 'Invalid friend code'; end if;
            insert into public.goals_friendships(requester, recipient) values (me, peer) on conflict do nothing;
        when 'accept' then
            update public.goals_friendships set accepted = true where recipient = me and requester = target::uuid;
        when 'remove' then
            peer := target::uuid;
            delete from public.goals_friendships
            where (requester = me and recipient = peer) or (requester = peer and recipient = me);
        when 'detail' then
            peer := target::uuid;
            if peer <> me and not exists (
                select 1 from public.goals_friendships where accepted and
                    ((requester = me and recipient = peer) or (requester = peer and recipient = me))
            ) then raise exception 'Friend access required'; end if;

            select coalesce(jsonb_agg(jsonb_build_object(
                'word', latest.spelling, 'level', coalesce((current_state.value->>'level')::integer, latest.level)
            ) order by latest.reviewed_at desc, latest.word_id), '[]') into words
            from (
                select distinct on (word_id) word_id, spelling, reviewed_at, level
                from public.goals_review_events
                where user_id = peer and reviewed_at >= today_start and reviewed_at < next_day
                order by word_id, reviewed_at desc, event_id desc
            ) latest left join public.goals_word_state current_state
                on current_state.user_id = peer and current_state.word_id = latest.word_id and current_state.kind = 'progress';
            return jsonb_build_object('words', words);
        when 'list' then null;
        when 'nickname' then null;
        else raise exception 'Unknown action';
    end case;

    select coalesce(jsonb_agg(to_jsonb(summary) order by word_count desc, seconds desc, nickname, user_id), '[]') into ranks
    from (
        select p.user_id, p.nickname, p.user_id = me as is_me,
            count(distinct e.word_id) as word_count, coalesce(sum(e.active_seconds), 0) as seconds
        from public.goals_profiles p left join public.goals_review_events e
            on e.user_id = p.user_id and e.reviewed_at >= today_start and e.reviewed_at < next_day
        where p.user_id = me or p.user_id in (
            select case when requester = me then recipient else requester end
            from public.goals_friendships where accepted and (requester = me or recipient = me)
        )
        group by p.user_id, p.nickname
    ) summary;

    select coalesce(jsonb_agg(jsonb_build_object(
        'user_id', p.user_id, 'nickname', p.nickname, 'incoming', f.recipient = me
    ) order by p.nickname, p.user_id), '[]') into requests
    from public.goals_friendships f join public.goals_profiles p
        on p.user_id = case when f.requester = me then f.recipient else f.requester end
    where not f.accepted and (f.requester = me or f.recipient = me);

    return jsonb_build_object(
        'profile', jsonb_build_object('nickname', my_profile.nickname, 'invite_code', my_profile.invite_code),
        'ranking', ranks, 'requests', requests
    );
end;
$$;

revoke all on function public.goals_sync(jsonb, jsonb), public.goals_social(text, text) from public, anon;
grant execute on function public.goals_sync(jsonb, jsonb), public.goals_social(text, text) to authenticated;

commit;
