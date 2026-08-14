# App IA — Vídeos para TikTok Shop (V1, Etapas 1 e 2)

Etapa 1: **setup do projeto + autenticação + schema do banco**.
Etapa 2: **upload de vídeos + extração de metadados**.

## O que já funciona

- Projeto Next.js (App Router) + TypeScript + Tailwind
- Autenticação via magic link (Supabase Auth)
- Middleware protegendo `/dashboard`
- Schema completo do banco (`supabase/schema.sql`) com Row Level Security
- Bucket privado de storage para vídeos (`supabase/storage.sql`), isolado por usuário
- Dashboard inicial listando projetos do usuário
- API `POST /api/projects` e `GET /api/projects` (criar/listar projetos)
- Tela `/dashboard/new`: upload múltiplo de MP4/MOV/WebM direto do navegador,
  com validação de tipo/tamanho, reordenação, remoção e extração de
  duração/resolução no próprio cliente (via `<video>` oculto) antes do envio
- API `POST /api/media` e `GET /api/media` (registra/lista vídeos de um projeto)
- Página `/dashboard/projects/[id]`: mostra os vídeos já enviados ao projeto

**Observação sobre FPS:** o navegador não expõe FPS de forma confiável, então
esse campo fica `null` nesta etapa — será preenchido pelo `VideoAnalyzer`
(job com ffprobe) na Etapa 3.

## Como rodar

1. Crie um projeto gratuito em https://supabase.com
2. No SQL Editor do Supabase, rode o conteúdo de `supabase/schema.sql`
3. Em seguida, rode também o conteúdo de `supabase/storage.sql` (cria o
   bucket `videos` e as políticas de acesso)
4. Copie `.env.example` para `.env.local` e preencha:
   - `NEXT_PUBLIC_SUPABASE_URL` e `NEXT_PUBLIC_SUPABASE_ANON_KEY` (em Project Settings → API)
5. Instale as dependências e rode:

```bash
npm install
npm run dev
```

6. Acesse `http://localhost:3000/login`, entre com seu e-mail (chega um link mágico) e você será redirecionado para `/dashboard`.
7. Toque em "Criar novo vídeo", selecione alguns arquivos de vídeo e envie —
   você deve cair na página do projeto vendo a lista de vídeos enviados.

## Estrutura

```
src/
  app/
    login/page.tsx                    → tela de login (magic link)
    dashboard/page.tsx                → lista de projetos + "criar novo vídeo"
    dashboard/new/page.tsx            → upload múltiplo de vídeos
    dashboard/projects/[id]/page.tsx  → detalhe do projeto + vídeos enviados
    api/auth/callback/                → troca o código do magic link pela sessão
    api/projects/route.ts             → cria e lista projetos
    api/media/route.ts                → registra e lista vídeos de um projeto
  lib/supabase/
    client.ts                         → cliente Supabase para o browser
    server.ts                         → cliente Supabase para Server Components/Routes
  lib/media/extractMetadata.ts        → valida e extrai duração/resolução no navegador
  middleware.ts                        → protege rotas de /dashboard
supabase/
  schema.sql                           → todas as tabelas da V1 + RLS
  storage.sql                          → bucket de vídeos + políticas de acesso
```

## Próxima etapa (Etapa 3)

Cadastro de produto (manual + extração de prints/PDF) e fila de jobs
(BullMQ/Redis) para rodar o `VideoAnalyzer`: extrair frames com ffmpeg,
transcrever áudio com Whisper e gerar a análise estruturada de cada vídeo
(incluindo o FPS, via ffprobe).
