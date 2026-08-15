#!/bin/bash
set -e
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
mkdir -p 'src/app/api/products'
cat > 'src/app/api/products/route.ts' << 'CLAUDE_EOF_MARKER'
import { NextResponse } from "next/server";
import { z } from "zod";
import { createClient } from "@/lib/supabase/server";

const productSchema = z.object({
  project_id: z.string().uuid(),
  name: z.string().min(1).optional(),
  description: z.string().optional(),
  benefits: z.array(z.string()).optional(),
  features: z.array(z.string()).optional(),
  audience: z.string().optional(),
  price: z.number().positive().optional(),
  promotion: z.string().optional(),
  coupon: z.string().optional(),
  differentiators: z.string().optional(),
  link: z.string().url().optional(),
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
  const parsed = productSchema.safeParse(body);

  if (!parsed.success) {
    return NextResponse.json(
      { error: "Dados inválidos", details: parsed.error.flatten() },
      { status: 400 }
    );
  }

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
    .from("products")
    .insert({ ...parsed.data, user_id: user.id })
    .select()
    .single();

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ product: data }, { status: 201 });
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
    .from("products")
    .select("*")
    .eq("project_id", projectId)
    .order("created_at", { ascending: false });

  if (error) {
    return NextResponse.json({ error: error.message }, { status: 500 });
  }

  return NextResponse.json({ products: data });
}

CLAUDE_EOF_MARKER
echo 'OK: full2b.sh'
