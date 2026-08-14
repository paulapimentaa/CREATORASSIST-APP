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
