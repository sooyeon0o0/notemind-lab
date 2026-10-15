begin;
create extension if not exists vector with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  created_at timestamptz not null default now()
);
create table if not exists public.documents (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null check (length(title) between 1 and 240),
  storage_path text not null,
  status text not null default 'processing' check (status in ('processing','ready','failed')),
  chunk_count integer not null default 0,
  embedding_model text not null,
  error text,
  created_at timestamptz not null default now(),
  unique(id, user_id),
  check (split_part(storage_path, '/', 1) = user_id::text)
);
create table if not exists public.chunks (
  id bigint generated always as identity primary key,
  document_id uuid not null,
  user_id uuid not null default auth.uid(),
  position integer not null check (position >= 0),
  content text not null check (length(content) between 1 and 2000),
  embedding extensions.vector(1024) not null,
  foreign key (document_id,user_id) references public.documents(id,user_id) on delete cascade,
  unique(document_id,position)
);
create table if not exists public.conversations (
  id uuid primary key,
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  title text not null,
  mode text not null check (mode in ('chat','rag')),
  created_at timestamptz not null default now(),
  unique(id,user_id)
);
create table if not exists public.messages (
  id uuid primary key,
  conversation_id uuid not null,
  user_id uuid not null default auth.uid(),
  role text not null check (role in ('user','assistant')),
  content text not null default '',
  status text not null default 'complete' check (status in ('complete','generating','stopped','error')),
  sources jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now(),
  foreign key (conversation_id,user_id) references public.conversations(id,user_id) on delete cascade
);
-- Answer provenance belongs to each response: one conversation may contain both.
do $$ begin
  if not exists(select 1 from information_schema.columns
      where table_schema='public' and table_name='messages' and column_name='answer_kind') then
    alter table public.messages add column answer_kind text not null default 'document'
      check (answer_kind in ('document','no_evidence','general'));
    update public.messages m set answer_kind='general'
      from public.conversations c
      where m.conversation_id=c.id and m.role='assistant' and c.mode='chat';
    update public.messages set answer_kind='no_evidence'
      where role='assistant' and answer_kind='document' and status='complete'
        and ltrim(content) like '자료에 없습니다%';
  end if;
end $$;
alter table public.conversations add column if not exists document_id uuid;
do $$ begin
  if not exists(select 1 from pg_constraint where conname='conversations_document_owner_fk' and conrelid='public.conversations'::regclass) then
    alter table public.conversations add constraint conversations_document_owner_fk
      foreign key(document_id,user_id) references public.documents(id,user_id) on delete set null (document_id);
  end if;
end $$;
create index if not exists documents_user_idx on public.documents(user_id,created_at desc);
create index if not exists chunks_user_idx on public.chunks(user_id,document_id);
create index if not exists conversations_user_idx on public.conversations(user_id,created_at desc);
create index if not exists messages_conversation_idx on public.messages(conversation_id,created_at);

alter table public.profiles enable row level security;
alter table public.documents enable row level security;
alter table public.chunks enable row level security;
alter table public.conversations enable row level security;
alter table public.messages enable row level security;
do $$
declare t text;
begin
  foreach t in array array['documents','chunks','conversations','messages'] loop
    execute format('drop policy if exists own_rows on public.%I',t);
    execute format('create policy own_rows on public.%I for all to authenticated using ((select auth.uid())=user_id) with check ((select auth.uid())=user_id)',t);
  end loop;
end $$;
drop policy if exists own_profile on public.profiles;
create policy own_profile on public.profiles for all to authenticated
using ((select auth.uid())=id) with check ((select auth.uid())=id);
grant select,insert,update,delete on public.profiles,public.documents,public.chunks,public.conversations,public.messages to authenticated;
grant usage,select on sequence public.chunks_id_seq to authenticated;

-- Finish ingestion atomically: incomplete documents never enter retrieval.
create or replace function public.finish_document(p_document_id uuid, p_chunks jsonb)
returns void language plpgsql security invoker set search_path = public,extensions as $$
declare row_data jsonb; idx integer := 0;
begin
  perform 1 from documents where id=p_document_id and user_id=auth.uid() for update;
  if not found then raise exception 'Document unavailable'; end if;
  if jsonb_typeof(p_chunks) <> 'array' or jsonb_array_length(p_chunks) not between 1 and 2000 then
    raise exception 'Invalid chunk list';
  end if;
  delete from chunks where document_id=p_document_id;
  for row_data in select * from jsonb_array_elements(p_chunks) loop
    insert into chunks(document_id,user_id,position,content,embedding)
    values (p_document_id,auth.uid(),idx,row_data->>'content',(row_data->>'embedding')::vector(1024));
    idx := idx+1;
  end loop;
  update documents set status='ready',chunk_count=idx,error=null where id=p_document_id;
end $$;

create or replace function public.match_chunks(
  query_embedding extensions.vector(1024), p_model text,
  match_threshold float default 0.45, match_count integer default 5,
  p_document_id uuid default null
) returns table(id bigint,document_id uuid,title text,"position" integer,content text,similarity float)
language sql stable security invoker set search_path = public,extensions as $$
  select c.id,c.document_id,d.title,c.position,c.content,1-(c.embedding <=> query_embedding)
  from chunks c join documents d on d.id=c.document_id
  where c.user_id=(select auth.uid()) and d.status='ready' and d.embedding_model=p_model
    and (p_document_id is null or d.id=p_document_id)
    and 1-(c.embedding <=> query_embedding) >= greatest(0,least(match_threshold,1))
  order by c.embedding <=> query_embedding limit greatest(1,least(match_count,8));
$$;
revoke all on function public.finish_document(uuid,jsonb) from public,anon;
revoke all on function public.match_chunks(extensions.vector,text,float,integer,uuid) from public,anon;
grant execute on function public.finish_document(uuid,jsonb) to authenticated;
grant execute on function public.match_chunks(extensions.vector,text,float,integer,uuid) to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values ('documents','documents',false,20971520,array['application/pdf', 'text/plain','text/markdown','application/octet-stream'])
on conflict(id) do update set public=false,file_size_limit=20971520,allowed_mime_types=excluded.allowed_mime_types;
drop policy if exists notemind_files on storage.objects;
create policy notemind_files on storage.objects for all to authenticated
using (bucket_id='documents' and (storage.foldername(name))[1]=(select auth.uid())::text)
with check (bucket_id='documents' and (storage.foldername(name))[1]=(select auth.uid())::text);
notify pgrst,'reload schema';
commit;
