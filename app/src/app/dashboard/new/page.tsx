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
