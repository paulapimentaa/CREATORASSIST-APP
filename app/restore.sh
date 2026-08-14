#!/bin/bash
set -e
echo "Recriando pastas e arquivos..."
mkdir -p 'src/app/api/auth/callback'
cat > 'src/app/api/auth/callback/route.ts' << 'CLAUDE_EOF_MARKER'
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url);
  const code = searchParams.get("code");

  if (code) {
    const supabase = createClient();
    await supabase.auth.exchangeCodeForSession(code);
  }

  return NextResponse.redirect(`${origin}/dashboard`);
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app/api/media'
cat > 'src/app/api/media/route.ts' << 'CLAUDE_EOF_MARKER'
import { NextResponse } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

const mediaSchema = z.object({
  project_id: z.string().uuid(),
  storage_path: z.string().min(1),
  original_filename: z.string().min(1),
  duration_seconds: z.number().positive(),
  width: z.number().int().positive(),
  height: z.number().int().positive(),
  file_size_bytes: z.number().int().positive(),
  order_index: z.number().int().nonnegative().default(0),
});

export async function POST(request: Request) {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
  }

  const body = await request.json().catch(() => null);
  const parsed = mediaSchema.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json(
      { error: "Dados inválidos", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  // Confere que o projeto pertence ao usuário antes de vincular a mídia
  const { data: project } = await supabase
    .from("projects")
    .select("id")
    .eq("id", parsed.data.project_id)
    .eq("user_id", user.id)
    .single();

  if (!project) {
    return NextResponse.json(
      { error: "Projeto não encontrado" },
      { status: 404 }
    );
  }

  const { data, error } = await supabase
    .from("media")
    .insert({
      ...parsed.data,
      user_id: user.id,
    })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ media: data }, { status: 201 });
}

export async function GET(request: Request) {
  const supabase = createClient();
  const { searchParams } = new URL(request.url);
  const projectId = searchParams.get("project_id");

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
  }

  if (!projectId) {
    return NextResponse.json(
      { error: "project_id é obrigatório" },
      { status: 400 }
    );
  }

  const { data, error } = await supabase
    .from("media")
    .select("*")
    .eq("project_id", projectId)
    .order("order_index", { ascending: true });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ media: data });
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app/api/projects'
cat > 'src/app/api/projects/route.ts' << 'CLAUDE_EOF_MARKER'
import { NextResponse } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

const createProjectSchema = z.object({
  name: z.string().min(1).max(120).optional(),
});

export async function POST(request: Request) {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
  }

  const body = await request.json().catch(() => ({}));
  const parsed = createProjectSchema.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json(
      { error: "Dados inválidos", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

  const { data, error } = await supabase
    .from("projects")
    .insert({
      user_id: user.id,
      name: parsed.data.name ?? "Novo projeto",
    })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ project: data }, { status: 201 });
}

export async function GET() {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
  }

  const { data, error } = await supabase
    .from("projects")
    .select("*")
    .order("created_at", { ascending: false });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ projects: data });
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app/dashboard/new'
cat > 'src/app/dashboard/new/page.tsx' << 'CLAUDE_EOF_MARKER'
"use client";

import { useState, useCallback } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import {
  extractVideoMetadata,
  validateVideoFile,
} from "@/lib/media/extractMetadata";

type UploadItem = {
  file: File;
  id: string;
  status: "pendente" | "enviando" | "concluido" | "erro";
  errorMessage?: string;
  progressLabel?: string;
};

export default function NewProjectPage() {
  const router = useRouter();
  const supabase = createClient();

  const [items, setItems] = useState<UploadItem[]>([]);
  const [projectId, setProjectId] = useState<string | null>(null);
  const [isUploading, setIsUploading] = useState(false);
  const [globalError, setGlobalError] = useState<string | null>(null);

  const handleFilesSelected = useCallback(
    (fileList: FileList | null) => {
      if (!fileList) return;

      const newItems: UploadItem[] = [];
      for (const file of Array.from(fileList)) {
        const validationError = validateVideoFile(file);
        newItems.push({
          file,
          id: `${file.name}-${file.size}-${Date.now()}`,
          status: validationError ? "erro" : "pendente",
          errorMessage: validationError ?? undefined,
        });
      }
      setItems((prev) => [...prev, ...newItems]);
    },
    []
  );

  function removeItem(id: string) {
    setItems((prev) => prev.filter((i) => i.id !== id));
  }

  function moveItem(id: string, direction: -1 | 1) {
    setItems((prev) => {
      const index = prev.findIndex((i) => i.id === id);
      const newIndex = index + direction;
      if (newIndex < 0 || newIndex >= prev.length) return prev;
      const copy = [...prev];
      [copy[index], copy[newIndex]] = [copy[newIndex], copy[index]];
      return copy;
    });
  }

  async function ensureProject(): Promise<string> {
    if (projectId) return projectId;

    const res = await fetch("/api/projects", { method: "POST" });
    if (!res.ok) throw new Error("Não foi possível criar o projeto.");
    const { project } = await res.json();
    setProjectId(project.id);
    return project.id;
  }

  async function handleUploadAll() {
    setGlobalError(null);
    const validItems = items.filter((i) => i.status !== "erro");

    if (validItems.length === 0) {
      setGlobalError("Adicione pelo menos um vídeo válido antes de enviar.");
      return;
    }

    setIsUploading(true);

    try {
      const currentProjectId = await ensureProject();

      const {
        data: { user },
      } = await supabase.auth.getUser();

      if (!user) throw new Error("Sessão expirada. Faça login novamente.");

      for (let i = 0; i < validItems.length; i++) {
        const item = validItems[i];

        setItems((prev) =>
          prev.map((it) =>
            it.id === item.id
              ? { ...it, status: "enviando", progressLabel: "lendo vídeo…" }
              : it
          )
        );

        try {
          const metadata = await extractVideoMetadata(item.file);

          const storagePath = `${user.id}/${currentProjectId}/${Date.now()}-${item.file.name}`;

          setItems((prev) =>
            prev.map((it) =>
              it.id === item.id
                ? { ...it, progressLabel: "enviando…" }
                : it
            )
          );

          const { error: uploadError } = await supabase.storage
            .from("videos")
            .upload(storagePath, item.file, {
              cacheControl: "3600",
              upsert: false,
            });

          if (uploadError) throw uploadError;

          const res = await fetch("/api/media", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              project_id: currentProjectId,
              storage_path: storagePath,
              original_filename: item.file.name,
              duration_seconds: metadata.durationSeconds,
              width: metadata.width,
              height: metadata.height,
              file_size_bytes: item.file.size,
              order_index: i,
            }),
          });

          if (!res.ok) {
            const body = await res.json().catch(() => ({}));
            throw new Error(body.error ?? "Falha ao salvar o vídeo.");
          }

          setItems((prev) =>
            prev.map((it) =>
              it.id === item.id
                ? { ...it, status: "concluido", progressLabel: undefined }
                : it
            )
          );
        } catch (err) {
          setItems((prev) =>
            prev.map((it) =>
              it.id === item.id
                ? {
                    ...it,
                    status: "erro",
                    errorMessage:
                      err instanceof Error ? err.message : "Erro ao enviar.",
                  }
                : it
            )
          );
        }
      }

      router.push(`/dashboard/projects/${currentProjectId}`);
    } catch (err) {
      setGlobalError(
        err instanceof Error ? err.message : "Erro inesperado ao enviar."
      );
    } finally {
      setIsUploading(false);
    }
  }

  return (
    <main className="mx-auto max-w-md px-4 py-8">
      <h1 className="mb-1 text-xl font-semibold">Enviar vídeos</h1>
      <p className="mb-6 text-sm text-neutral-500">
        Envie os vídeos brutos gravados no seu celular. Aceita MP4, MOV ou
        WebM.
      </p>

      <label className="mb-4 flex cursor-pointer flex-col items-center justify-center rounded-xl border-2 border-dashed border-neutral-300 px-4 py-10 text-center">
        <span className="mb-1 font-medium">Toque para escolher vídeos</span>
        <span className="text-xs text-neutral-500">
          Pode selecionar vários de uma vez
        </span>
        <input
          type="file"
          accept="video/mp4,video/quicktime,video/webm"
          multiple
          className="hidden"
          onChange={(e) => handleFilesSelected(e.target.files)}
        />
      </label>

      {items.length > 0 && (
        <ul className="mb-6 space-y-2">
          {items.map((item, index) => (
            <li
              key={item.id}
              className="flex items-center justify-between rounded-lg border border-neutral-200 px-3 py-2"
            >
              <div className="min-w-0 flex-1">
                <p className="truncate text-sm font-medium">
                  {item.file.name}
                </p>
                <p className="text-xs text-neutral-500">
                  {(item.file.size / 1024 / 1024).toFixed(1)}MB
                  {item.progressLabel ? ` · ${item.progressLabel}` : ""}
                  {item.status === "concluido" ? " · enviado ✓" : ""}
                </p>
                {item.errorMessage && (
                  <p className="text-xs text-red-600">{item.errorMessage}</p>
                )}
              </div>

              <div className="ml-2 flex shrink-0 items-center gap-1">
                <button
                  type="button"
                  disabled={index === 0 || isUploading}
                  onClick={() => moveItem(item.id, -1)}
                  className="rounded px-2 py-1 text-sm disabled:opacity-30"
                >
                  ↑
                </button>
                <button
                  type="button"
                  disabled={index === items.length - 1 || isUploading}
                  onClick={() => moveItem(item.id, 1)}
                  className="rounded px-2 py-1 text-sm disabled:opacity-30"
                >
                  ↓
                </button>
                <button
                  type="button"
                  disabled={isUploading}
                  onClick={() => removeItem(item.id)}
                  className="rounded px-2 py-1 text-sm text-red-600 disabled:opacity-30"
                >
                  ✕
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}

      {globalError && (
        <p className="mb-4 text-sm text-red-600">{globalError}</p>
      )}

      <button
        type="button"
        disabled={isUploading || items.length === 0}
        onClick={handleUploadAll}
        className="w-full rounded-xl bg-neutral-900 px-4 py-4 text-center font-medium text-white disabled:opacity-40"
      >
        {isUploading ? "Enviando…" : "Enviar e continuar"}
      </button>
    </main>
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app/dashboard'
cat > 'src/app/dashboard/page.tsx' << 'CLAUDE_EOF_MARKER'
import { createClient } from "@/lib/supabase/server";
import Link from "next/link";

export default async function DashboardPage() {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const { data: projects } = await supabase
    .from("projects")
    .select("id, name, status, created_at")
    .order("created_at", { ascending: false });

  return (
    <main className="mx-auto max-w-md px-4 py-8">
      <header className="mb-6 flex items-center justify-between">
        <div>
          <p className="text-sm text-neutral-500">Olá,</p>
          <p className="font-medium">{user?.email}</p>
        </div>
      </header>

      <Link
        href="/dashboard/new"

        className="mb-6 block w-full rounded-xl bg-neutral-900 px-4 py-4 text-center font-medium text-white"
      >
        + Criar novo vídeo
      </Link>

      <section>
        <h2 className="mb-3 text-sm font-medium text-neutral-500">
          Meus projetos
        </h2>

        {!projects || projects.length === 0 ? (
          <p className="rounded-xl border border-dashed border-neutral-300 p-6 text-center text-sm text-neutral-500">
            Você ainda não criou nenhum vídeo. Toque em "Criar novo vídeo"
            para começar.
          </p>
        ) : (
          <ul className="space-y-2">
            {projects.map((p) => (
              <li key={p.id}>
                <Link
                  href={`/dashboard/projects/${p.id}`}
                  className="flex items-center justify-between rounded-xl border border-neutral-200 px-4 py-3"
                >
                  <span className="font-medium">{p.name}</span>
                  <span className="rounded-full bg-neutral-100 px-2 py-1 text-xs text-neutral-600">
                    {p.status}
                  </span>
                </Link>
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app/dashboard/projects/[id]'
cat > 'src/app/dashboard/projects/[id]/page.tsx' << 'CLAUDE_EOF_MARKER'
import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";

export default async function ProjectPage({
  params,
}: {
  params: { id: string };
}) {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) notFound();

  const { data: project } = await supabase
    .from("projects")
    .select("*")
    .eq("id", params.id)
    .eq("user_id", user.id)
    .single();

  if (!project) notFound();

  const { data: media } = await supabase
    .from("media")
    .select("*")
    .eq("project_id", project.id)
    .order("order_index", { ascending: true });

  return (
    <main className="mx-auto max-w-md px-4 py-8">
      <h1 className="mb-1 text-xl font-semibold">{project.name}</h1>
      <p className="mb-6 text-sm text-neutral-500">
        Status: <span className="font-medium">{project.status}</span>
      </p>

      <section>
        <h2 className="mb-3 text-sm font-medium text-neutral-500">
          Vídeos enviados ({media?.length ?? 0})
        </h2>

        {!media || media.length === 0 ? (
          <p className="rounded-xl border border-dashed border-neutral-300 p-6 text-center text-sm text-neutral-500">
            Nenhum vídeo enviado ainda.
          </p>
        ) : (
          <ul className="space-y-2">
            {media.map((m) => (
              <li
                key={m.id}
                className="rounded-lg border border-neutral-200 px-3 py-2"
              >
                <p className="truncate text-sm font-medium">
                  {m.original_filename}
                </p>
                <p className="text-xs text-neutral-500">
                  {m.duration_seconds
                    ? `${m.duration_seconds.toFixed(1)}s`
                    : "duração desconhecida"}{" "}
                  · {m.width}×{m.height} ·{" "}
                  {(m.file_size_bytes / 1024 / 1024).toFixed(1)}MB
                </p>
              </li>
            ))}
          </ul>
        )}
      </section>
    </main>
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app'
cat > 'src/app/globals.css' << 'CLAUDE_EOF_MARKER'
@tailwind base;
@tailwind components;
@tailwind utilities;

CLAUDE_EOF_MARKER
mkdir -p 'src/app'
cat > 'src/app/layout.tsx' << 'CLAUDE_EOF_MARKER'
import "./globals.css";
import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "App IA — Vídeos para TikTok Shop",
  description: "Grave, envie e deixe a IA criar seus vídeos de conversão.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="pt-BR">
      <body className="min-h-screen bg-neutral-50 text-neutral-900 antialiased">
        {children}
      </body>
    </html>
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app/login'
cat > 'src/app/login/page.tsx' << 'CLAUDE_EOF_MARKER'
"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const supabase = createClient();

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);

    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: {
        emailRedirectTo: `${window.location.origin}/api/auth/callback`,
      },
    });

    if (error) {
      setError(error.message);
    } else {
      setSent(true);
    }
  }

  return (
    <main className="flex min-h-screen flex-col items-center justify-center px-6">
      <div className="w-full max-w-sm space-y-6">
        <div className="text-center">
          <h1 className="text-2xl font-semibold">Entrar</h1>
          <p className="mt-1 text-sm text-neutral-500">
            Envie seus vídeos e deixe a IA fazer o trabalho pesado.
          </p>
        </div>

        {sent ? (
          <p className="rounded-lg bg-green-50 p-4 text-sm text-green-700">
            Enviamos um link de acesso para {email}. Confira sua caixa de
            entrada.
          </p>
        ) : (
          <form onSubmit={handleSubmit} className="space-y-3">
            <input
              type="email"
              required
              placeholder="seu@email.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="w-full rounded-lg border border-neutral-300 px-4 py-3 text-sm"
            />
            {error && <p className="text-sm text-red-600">{error}</p>}
            <button
              type="submit"
              className="w-full rounded-lg bg-neutral-900 px-4 py-3 text-sm font-medium text-white"
            >
              Enviar link de acesso
            </button>
          </form>
        )}
      </div>
    </main>
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src/lib/media'
cat > 'src/lib/media/extractMetadata.ts' << 'CLAUDE_EOF_MARKER'
export type ExtractedVideoMetadata = {
  durationSeconds: number;
  width: number;
  height: number;
};

const ACCEPTED_TYPES = ["video/mp4", "video/quicktime", "video/webm"];
const MAX_SIZE_BYTES = 500 * 1024 * 1024; // 500MB — limite provisório da V1

export function validateVideoFile(file: File): string | null {
  if (!ACCEPTED_TYPES.includes(file.type)) {
    return `Formato não suportado: ${file.type || "desconhecido"}. Envie MP4, MOV ou WebM.`;
  }
  if (file.size > MAX_SIZE_BYTES) {
    return `Arquivo muito grande (${(file.size / 1024 / 1024).toFixed(0)}MB). Limite: 500MB.`;
  }
  return null;
}

/**
 * Extrai duração e resolução do vídeo no próprio navegador, usando um
 * elemento <video> oculto. FPS não é confiável de extrair no browser —
 * isso fica para o job de análise no worker (ffprobe), na Etapa 3.
 */
export function extractVideoMetadata(
  file: File
): Promise<ExtractedVideoMetadata> {
  return new Promise((resolve, reject) => {
    const video = document.createElement("video");
    video.preload = "metadata";
    video.muted = true;

    const objectUrl = URL.createObjectURL(file);
    video.src = objectUrl;

    video.onloadedmetadata = () => {
      URL.revokeObjectURL(objectUrl);
      resolve({
        durationSeconds: video.duration,
        width: video.videoWidth,
        height: video.videoHeight,
      });
    };

    video.onerror = () => {
      URL.revokeObjectURL(objectUrl);
      reject(new Error("Não foi possível ler os metadados do vídeo."));
    };
  });
}

CLAUDE_EOF_MARKER
mkdir -p 'src/lib/supabase'
cat > 'src/lib/supabase/client.ts' << 'CLAUDE_EOF_MARKER'
import { createBrowserClient } from "@supabase/ssr";

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src/lib/supabase'
cat > 'src/lib/supabase/server.ts' << 'CLAUDE_EOF_MARKER'
import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";

export function createClient() {
  const cookieStore = cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // chamado de um Server Component — ok ignorar se houver middleware
            // atualizando a sessão.
          }
        },
      },
    }
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src'
cat > 'src/middleware.ts' << 'CLAUDE_EOF_MARKER'
import { createServerClient } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({ request });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value }) =>
            request.cookies.set(name, value)
          );
          response = NextResponse.next({ request });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const isProtected = request.nextUrl.pathname.startsWith("/dashboard");

  if (isProtected && !user) {
    const url = request.nextUrl.clone();
    url.pathname = "/login";
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  matcher: ["/dashboard/:path*"],
};

CLAUDE_EOF_MARKER
mkdir -p 'supabase'
cat > 'supabase/schema.sql' << 'CLAUDE_EOF_MARKER'
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

CLAUDE_EOF_MARKER
mkdir -p 'supabase'
cat > 'supabase/storage.sql' << 'CLAUDE_EOF_MARKER'
-- =========================================================
-- Etapa 2: Storage de vídeos
-- Rodar depois do schema.sql principal
-- =========================================================

-- Bucket privado para os vídeos brutos.
-- Estrutura de caminho: {user_id}/{project_id}/{filename}
insert into storage.buckets (id, name, public)
values ('videos', 'videos', false)
on conflict (id) do nothing;

-- Cada usuário só pode ler, enviar e apagar arquivos dentro da
-- sua própria pasta (primeiro segmento do caminho = seu user_id).
create policy "own_videos_select" on storage.objects
  for select using (
    bucket_id = 'videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own_videos_insert" on storage.objects
  for insert with check (
    bucket_id = 'videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

create policy "own_videos_delete" on storage.objects
  for delete using (
    bucket_id = 'videos'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

CLAUDE_EOF_MARKER
echo "Pronto! Pastas src/ e supabase/ recriadas."
