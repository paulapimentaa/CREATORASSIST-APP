#!/bin/bash
set -e
mkdir -p 'src/app/dashboard/projects/[id]'
cat > 'src/app/dashboard/projects/[id]/page.tsx' << 'CLAUDE_EOF_MARKER'
import { createClient } from "@/lib/supabase/server";
import { notFound } from "next/navigation";
import Link from "next/link";
import { AnalyzeButton } from "./AnalyzeButton";

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

  const { data: product } = await supabase
    .from("products")
    .select("*")
    .eq("project_id", project.id)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();

  const pendingAnalysis = (media ?? []).some((m) => !m.analyzed_at);

  return (
    <main className="mx-auto max-w-md px-4 py-8">
      <h1 className="mb-1 text-xl font-semibold">{project.name}</h1>
      <p className="mb-6 text-sm text-neutral-500">
        Status: <span className="font-medium">{project.status}</span>
      </p>

      <section className="mb-6">
        <Link
          href={`/dashboard/projects/${project.id}/product`}
          className="flex items-center justify-between rounded-xl border border-neutral-200 px-4 py-3"
        >
          <span className="font-medium">
            {product ? `Produto: ${product.name ?? "sem nome"}` : "Cadastrar produto"}
          </span>
          <span className="text-sm text-neutral-400">
            {product ? "editar" : "adicionar"}
          </span>
        </Link>
      </section>

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
                  {m.analyzed_at ? " · analisado ✓" : " · aguardando análise"}
                </p>
                {m.analysis && (
                  <p className="mt-1 text-xs text-neutral-600">
                    {(m.analysis as { description?: string }).description}
                  </p>
                )}
              </li>
            ))}
          </ul>
        )}

        {media && media.length > 0 && (
          <div className="mt-4">
            <AnalyzeButton
              projectId={project.id}
              disabled={!pendingAnalysis}
            />
          </div>
        )}
      </section>
    </main>
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app/dashboard/projects/[id]'
cat > 'src/app/dashboard/projects/[id]/AnalyzeButton.tsx' << 'CLAUDE_EOF_MARKER'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export function AnalyzeButton({
  projectId,
  disabled,
}: {
  projectId: string;
  disabled: boolean;
}) {
  const router = useRouter();
  const [isLoading, setIsLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function handleClick() {
    setIsLoading(true);
    setMessage(null);

    try {
      const res = await fetch(`/api/projects/${projectId}/analyze`, {
        method: "POST",
      });
      const body = await res.json();

      if (!res.ok) {
        throw new Error(body.error ?? "Falha ao iniciar análise.");
      }

      setMessage(
        `${body.enqueued} vídeo(s) enviado(s) para análise. Isso roda em segundo plano — atualize a página em alguns minutos.`
      );
      router.refresh();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "Erro inesperado.");
    } finally {
      setIsLoading(false);
    }
  }

  return (
    <div>
      <button
        type="button"
        onClick={handleClick}
        disabled={disabled || isLoading}
        className="w-full rounded-xl bg-neutral-900 px-4 py-4 text-center font-medium text-white disabled:opacity-40"
      >
        {isLoading
          ? "Enviando…"
          : disabled
            ? "Todos os vídeos já analisados"
            : "Analisar vídeos com IA"}
      </button>
      {message && (
        <p className="mt-2 text-xs text-neutral-500">{message}</p>
      )}
    </div>
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app/dashboard/projects/[id]/product'
cat > 'src/app/dashboard/projects/[id]/product/page.tsx' << 'CLAUDE_EOF_MARKER'
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";

export default function ProductPage({
  params,
}: {
  params: { id: string };
}) {
  const router = useRouter();
  const [name, setName] = useState("");
  const [description, setDescription] = useState("");
  const [price, setPrice] = useState("");
  const [link, setLink] = useState("");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setIsSaving(true);

    try {
      const res = await fetch("/api/products", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          project_id: params.id,
          name: name || undefined,
          description: description || undefined,
          price: price ? Number(price) : undefined,
          link: link || undefined,
        }),
      });

      if (!res.ok) {
        const body = await res.json().catch(() => ({}));
        throw new Error(body.error ?? "Falha ao salvar produto.");
      }

      router.push(`/dashboard/projects/${params.id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Erro inesperado.");
    } finally {
      setIsSaving(false);
    }
  }

  return (
    <main className="mx-auto max-w-md px-4 py-8">
      <h1 className="mb-1 text-xl font-semibold">Sobre o produto</h1>
      <p className="mb-6 text-sm text-neutral-500">
        Preencha o que souber — nenhum campo é obrigatório.
      </p>

      <form onSubmit={handleSubmit} className="space-y-3">
        <input
          placeholder="Nome do produto"
          value={name}
          onChange={(e) => setName(e.target.value)}
          className="w-full rounded-lg border border-neutral-300 px-4 py-3 text-sm"
        />
        <textarea
          placeholder="Descrição, benefícios, diferenciais..."
          value={description}
          onChange={(e) => setDescription(e.target.value)}
          rows={4}
          className="w-full rounded-lg border border-neutral-300 px-4 py-3 text-sm"
        />
        <input
          placeholder="Preço (opcional)"
          type="number"
          step="0.01"
          value={price}
          onChange={(e) => setPrice(e.target.value)}
          className="w-full rounded-lg border border-neutral-300 px-4 py-3 text-sm"
        />
        <input
          placeholder="Link do produto (opcional)"
          value={link}
          onChange={(e) => setLink(e.target.value)}
          className="w-full rounded-lg border border-neutral-300 px-4 py-3 text-sm"
        />

        {error && <p className="text-sm text-red-600">{error}</p>}

        <button
          type="submit"
          disabled={isSaving}
          className="w-full rounded-xl bg-neutral-900 px-4 py-4 text-center font-medium text-white disabled:opacity-40"
        >
          {isSaving ? "Salvando…" : "Salvar e continuar"}
        </button>
      </form>
    </main>
  );
}

CLAUDE_EOF_MARKER
mkdir -p 'src/app/api/projects/[id]/analyze'
cat > 'src/app/api/projects/[id]/analyze/route.ts' << 'CLAUDE_EOF_MARKER'
import { NextResponse } from "next/server";
import { createClient } from "@/lib/supabase/server";
import { getVideoAnalysisQueue } from "@/lib/queue/videoAnalysisQueue";

export async function POST(
  request: Request,
  { params }: { params: { id: string } }
) {
  const supabase = createClient();

  const {
    data: { user },
  } = await supabase.auth.getUser();

  if (!user) {
    return NextResponse.json({ error: "Não autenticado" }, { status: 401 });
  }

  const { data: project } = await supabase
    .from("projects")
    .select("id")
    .eq("id", params.id)
    .eq("user_id", user.id)
    .single();

  if (!project) {
    return NextResponse.json(
      { error: "Projeto não encontrado" },
      { status: 404 }
    );
  }

  const { data: mediaList, error: mediaError } = await supabase
    .from("media")
    .select("id")
    .eq("project_id", params.id)
    .is("analyzed_at", null);

  if (mediaError) {
    return NextResponse.json({ error: mediaError.message }, { status: 500 });
  }

  if (!mediaList || mediaList.length === 0) {
    return NextResponse.json(
      { error: "Nenhum vídeo pendente de análise neste projeto" },
      { status: 400 }
    );
  }

  const queue = getVideoAnalysisQueue();

  await Promise.all(
    mediaList.map((m) =>
      queue.add("analyze", {
        mediaId: m.id,
        projectId: params.id,
        userId: user.id,
      })
    )
  );

  await supabase
    .from("projects")
    .update({ status: "analisando" })
    .eq("id", params.id);

  return NextResponse.json({ enqueued: mediaList.length });
}

CLAUDE_EOF_MARKER
echo 'OK: full3.sh'
