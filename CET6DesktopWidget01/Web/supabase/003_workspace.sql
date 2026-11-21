create table public.goals_workspace_records (
    user_id uuid not null references auth.users(id) on delete cascade,
    id uuid not null,
    kind text not null check (kind in ('goal','plan','task','translation','writing')),
    value jsonb not null check (jsonb_typeof(value) = 'object' and octet_length(value::text) <= 65536),
    updated_at timestamptz not null default now(),
    primary key (user_id,id)
);

create table public.goals_deepseek_settings (
    user_id uuid primary key references auth.users(id) on delete cascade,
    secret_id uuid not null references vault.secrets(id),
    model text not null check (model in ('deepseek-flash','deepseek-v4-pro'))
);

alter table public.goals_workspace_records enable row level security;
alter table public.goals_deepseek_settings enable row level security;
revoke all on public.goals_workspace_records, public.goals_deepseek_settings from public, anon, authenticated;

create function public.goals_workspace(action text default 'list', record_id uuid default null,
    record_kind text default null, payload jsonb default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    me uuid := auth.uid();
begin
    if me is null then raise exception 'Sign in required'; end if;
    case action
    when 'save' then
        insert into public.goals_workspace_records(user_id,id,kind,value)
        values (me, record_id, record_kind, payload)
        on conflict (user_id,id) do update set value=excluded.value, updated_at=now()
        where goals_workspace_records.kind = excluded.kind;
        if not found then raise exception 'Record type mismatch'; end if;
    when 'remove' then
        delete from public.goals_workspace_records where user_id=me and id=record_id;
    when 'list' then null;
    else raise exception 'Invalid action';
    end case;
    return (select coalesce(jsonb_agg(to_jsonb(r)-'user_id' order by r.updated_at desc),'[]'::jsonb)
            from public.goals_workspace_records r where r.user_id=me);
end;
$$;

create function public.goals_ai_settings(account_id uuid, action text, api_key text default null, model_name text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
    current_config public.goals_deepseek_settings;
begin
    perform pg_advisory_xact_lock(hashtextextended(account_id::text, 0));
    select * into current_config from public.goals_deepseek_settings where user_id = account_id;
    if action = 'save' then
        if model_name is null or model_name not in ('deepseek-flash','deepseek-v4-pro') then
            raise exception 'Invalid model';
        end if;
        if api_key is not null and (length(api_key) not between 8 and 160 or api_key !~ '^[A-Za-z0-9_-]+$') then
            raise exception 'Invalid API key';
        end if;
        if current_config.user_id is null then
            if api_key is null then raise exception 'API key required'; end if;
            current_config.secret_id := vault.create_secret(api_key);
            insert into public.goals_deepseek_settings values (account_id, current_config.secret_id, model_name);
        else
            if api_key is not null then perform vault.update_secret(current_config.secret_id, api_key); end if;
            update public.goals_deepseek_settings set model = model_name where user_id = account_id;
        end if;
        current_config.model := model_name;
    elsif action = 'remove' then
        delete from public.goals_deepseek_settings where user_id=account_id;
        delete from vault.secrets where id=current_config.secret_id;
        return jsonb_build_object('configured',false);
    elsif action = 'read' then
        return (select jsonb_build_object('key', secret.decrypted_secret, 'model', current_config.model)
                from vault.decrypted_secrets secret where secret.id=current_config.secret_id);
    elsif action <> 'status' then
        raise exception 'Invalid action';
    end if;
    return jsonb_build_object('configured',current_config.secret_id is not null, 'model',current_config.model);
end;
$$;

create function public.goals_delete_ai_secret()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
    delete from vault.secrets where id=old.secret_id;
    return old;
end;
$$;

create trigger goals_delete_ai_secret after delete on public.goals_deepseek_settings
    for each row execute function public.goals_delete_ai_secret();

revoke all on function public.goals_workspace(text, uuid, text, jsonb) from public, anon;
grant execute on function public.goals_workspace(text, uuid, text, jsonb) to authenticated;
revoke all on function public.goals_ai_settings(uuid, text, text, text), public.goals_delete_ai_secret() from public, anon, authenticated;
grant execute on function public.goals_ai_settings(uuid, text, text, text) to service_role;
