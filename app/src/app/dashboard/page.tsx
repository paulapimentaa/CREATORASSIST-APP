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
