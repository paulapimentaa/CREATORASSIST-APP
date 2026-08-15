#!/bin/bash
set -e
mkdir -p 'src/app'
cat > 'src/app/page.tsx' << 'CLAUDE_EOF_MARKER'
import { redirect } from "next/navigation";

export default function RootPage() {
  redirect("/login");
}

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
mkdir -p 'src/app'
cat > 'src/app/globals.css' << 'CLAUDE_EOF_MARKER'
@tailwind base;
@tailwind components;
@tailwind utilities;

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
mkdir -p 'src/lib/supabase'
cat > 'src/lib/supabase/serviceClient.ts' << 'CLAUDE_EOF_MARKER'
import { createClient as createSupabaseClient } from "@supabase/supabase-js";

/**
 * Usa a service role key — ignora Row Level Security.
 * Só deve ser usado no worker (processo de background), nunca
 * exposto a rotas acessíveis pelo navegador.
 */
export function createServiceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceKey) {
    throw new Error(
      "NEXT_PUBLIC_SUPABASE_URL e SUPABASE_SERVICE_ROLE_KEY são obrigatórios no worker."
    );
  }

  return createSupabaseClient(url, serviceKey, {
    auth: { persistSession: false },
  });
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
echo 'OK: full1.sh'
