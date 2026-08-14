-- =========================================================
-- Schema inicial: App de IA para criadores TikTok Shop (V1)
-- Rodar no SQL Editor do Supabase (ou via CLI: supabase db push)
-- =========================================================

create extension if not exists "uuid-ossp";

-- ---------------------------------------------------------
-- PROJECTS
-- ---------------------------------------------------------
create table projects (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'Novo projeto',
  status text not null default 'rascunho'
    check (status in (
      'rascunho', 'analisando', 'criando', 'pronto_para_revisao',
      'aguardando_narracao', 'renderizando', 'pronto', 'publicado',
      'analisando_resultados', 'aprendizado_atualizado'
    )),
  objective text check (objective in ('vender','curiosidade','identificacao','comentarios','retencao')),
  style text,
  sales_level text check (sales_level in ('discreta','natural','direta')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- MEDIA (vídeos brutos enviados pelo usuário)
-- ---------------------------------------------------------
create table media (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null,
  original_filename text,
  duration_seconds numeric,
  width int,
  height int,
  fps numeric,
  file_size_bytes bigint,
  order_index int not null default 0,
  analysis jsonb, -- saída estruturada do VideoAnalyzer
  analyzed_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- REFERENCE_VIDEOS
-- ---------------------------------------------------------
create table reference_videos (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text,
  structure jsonb, -- estrutura abstrata (gancho, ritmo, cta, etc.)
  analyzed_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- PRODUCTS
-- ---------------------------------------------------------
create table products (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text,
  description text,
  benefits text[],
  features text[],
  audience text,
  price numeric,
  promotion text,
  coupon text,
  differentiators text,
  link text,
  source jsonb, -- dados extraídos automaticamente de prints/PDF, antes da confirmação do usuário
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- SCRIPTS (roteiros gerados — normalmente 3 por projeto)
-- ---------------------------------------------------------
create table scripts (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  variant text not null, -- 'A_curiosidade' | 'B_identificacao' | 'C_problema_solucao'
  content jsonb not null, -- blocos com timing: [{start,end,text}]
  selected boolean not null default false,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- VIDEO_PLANS (plano de edição estruturado, em JSON)
-- ---------------------------------------------------------
create table video_plans (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  script_id uuid references scripts(id) on delete set null,
  scenes jsonb not null, -- [{time, media_id, trim_start, trim_end, objective, text, effect}]
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- VOICEOVERS
-- ---------------------------------------------------------
create table voiceovers (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  storage_path text not null,
  transcript jsonb, -- saída do Whisper com timestamps por palavra/frase
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- VIDEO_VERSIONS (cada "criar outra versão")
-- ---------------------------------------------------------
create table video_versions (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  video_plan_id uuid references video_plans(id) on delete set null,
  storage_path text, -- MP4 final, preenchido após render
  status text not null default 'pendente' check (status in ('pendente','renderizando','pronto','erro')),
  version_number int not null default 1,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- RENDER_JOBS
-- ---------------------------------------------------------
create table render_jobs (
  id uuid primary key default uuid_generate_v4(),
  video_version_id uuid not null references video_versions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pendente' check (status in ('pendente','processando','concluido','erro')),
  error_message text,
  cost_usd numeric,
  started_at timestamptz,
  finished_at timestamptz,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- PUBLISHED_VIDEOS
-- ---------------------------------------------------------
create table published_videos (
  id uuid primary key default uuid_generate_v4(),
  project_id uuid not null references projects(id) on delete cascade,
  video_version_id uuid not null references video_versions(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  published_at timestamptz not null default now(),
  caption text,
  hashtags text[]
);

-- ---------------------------------------------------------
-- PERFORMANCE_SNAPSHOTS (um registro por print enviado)
-- ---------------------------------------------------------
create table performance_snapshots (
  id uuid primary key default uuid_generate_v4(),
  published_video_id uuid not null references published_videos(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  screenshot_storage_path text not null,
  raw_extraction jsonb, -- o que a IA detectou, antes da confirmação
  confirmed boolean not null default false,
  captured_at timestamptz, -- momento a que o print se refere (ex.: "24h depois")
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- PERFORMANCE_METRICS (métricas normalizadas, após confirmação)
-- ---------------------------------------------------------
create table performance_metrics (
  id uuid primary key default uuid_generate_v4(),
  performance_snapshot_id uuid not null references performance_snapshots(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  views bigint,
  likes bigint,
  comments bigint,
  shares bigint,
  saves bigint,
  new_followers bigint,
  avg_watch_time_seconds numeric,
  retention_pct numeric,
  clicks bigint,
  visits bigint,
  orders bigint,
  conversions bigint,
  revenue numeric,
  commission numeric,
  ctr numeric,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- LEARNINGS (padrões identificados pelo LearningEngine)
-- ---------------------------------------------------------
create table learnings (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text not null, -- ex: 'hook_type', 'duration', 'cta_style'
  insight text not null,
  confidence text not null check (confidence in ('baixa','media','alta')),
  sample_size int not null,
  evidence jsonb,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------
-- AI_ANALYSES (log de toda chamada de IA)
-- ---------------------------------------------------------
create table ai_analyses (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references auth.users(id) on delete cascade,
  project_id uuid references projects(id) on delete set null,
  module text not null, -- 'VideoAnalyzer' | 'ScriptGenerator' | etc.
  input_summary jsonb,
  output jsonb,
  cost_usd numeric,
  created_at timestamptz not null default now()
);

-- =========================================================
-- ROW LEVEL SECURITY: isolamento total por usuário
-- =========================================================
do $$
declare
  t text;
begin
  for t in select unnest(array[
    'projects','media','reference_videos','products','scripts',
    'video_plans','voiceovers','video_versions','render_jobs',
    'published_videos','performance_snapshots','performance_metrics',
    'learnings','ai_analyses'
  ])
  loop
    execute format('alter table %I enable row level security;', t);
    execute format(
      'create policy "own_rows_%1$s" on %1$I for all using (auth.uid() = user_id) with check (auth.uid() = user_id);',
      t
    );
  end loop;
end $$;

-- Índices básicos para as consultas mais comuns
create index on media (project_id);
create index on scripts (project_id);
create index on performance_metrics (user_id);
create index on learnings (user_id, category);
