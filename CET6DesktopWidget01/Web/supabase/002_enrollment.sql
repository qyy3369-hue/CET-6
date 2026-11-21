create table public.goals_enrollment (
    code_hash text primary key,
    expires_at timestamptz not null,
    claimed boolean not null default false
);

alter table public.goals_enrollment enable row level security;
revoke all on public.goals_enrollment from public, anon, authenticated;

create function public.goals_claim_enrollment(code text, release_claim boolean default false)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
    update public.goals_enrollment
       set claimed = not release_claim
       where code_hash = encode(sha256(convert_to(lower(code), 'UTF8')), 'hex')
       and expires_at > now() and claimed = release_claim;
    return found;
end;
$$;

revoke all on function public.goals_claim_enrollment(text, boolean) from public, anon, authenticated;
grant execute on function public.goals_claim_enrollment(text, boolean) to service_role;
