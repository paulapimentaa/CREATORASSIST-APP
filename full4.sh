#!/bin/bash
set -e
mkdir -p 'src/lib/queue'
cat > 'src/lib/queue/connection.ts' << 'CLAUDE_EOF_MARKER'
import IORedis from "ioredis";

let connection: IORedis | null = null;

/**
 * Conexão única de Redis, reaproveitada entre a API e o worker.
 * Em produção, aponte REDIS_URL para o Upstash (ou outro Redis gerenciado).
 */
export function getRedisConnection(): IORedis {
  if (!connection) {
    const url = process.env.REDIS_URL;
    if (!url) {
      throw new Error(
        "REDIS_URL não configurado. Defina no .env.local (ex.: Upstash Redis)."
      );
    }
    connection = new IORedis(url, { maxRetriesPerRequest: null });
  }
  return connection;
}

CLAUDE_EOF_MARKER
mkdir -p 'src/lib/queue'
cat > 'src/lib/queue/videoAnalysisQueue.ts' << 'CLAUDE_EOF_MARKER'
import { Queue } from "bullmq";
import { getRedisConnection } from "./connection";

export type VideoAnalysisJobData = {
  mediaId: string;
  projectId: string;
  userId: string;
};

export const VIDEO_ANALYSIS_QUEUE_NAME = "video-analysis";

let queue: Queue<VideoAnalysisJobData> | null = null;

export function getVideoAnalysisQueue(): Queue<VideoAnalysisJobData> {
  if (!queue) {
    queue = new Queue<VideoAnalysisJobData>(VIDEO_ANALYSIS_QUEUE_NAME, {
      connection: getRedisConnection(),
      defaultJobOptions: {
        attempts: 3,
        backoff: { type: "exponential", delay: 5000 },
        removeOnComplete: 100,
        removeOnFail: 500,
      },
    });
  }
  return queue;
}

CLAUDE_EOF_MARKER
mkdir -p 'src/lib/ai'
cat > 'src/lib/ai/anthropicClient.ts' << 'CLAUDE_EOF_MARKER'
import Anthropic from "@anthropic-ai/sdk";

let client: Anthropic | null = null;

function getClient(): Anthropic {
  if (!client) {
    const apiKey = process.env.ANTHROPIC_API_KEY;
    if (!apiKey) {
      throw new Error("ANTHROPIC_API_KEY não configurado no .env.local.");
    }
    client = new Anthropic({ apiKey });
  }
  return client;
}

export type StructuredPromptInput = {
  systemPrompt: string;
  userText: string;
  images?: { base64: string; mediaType: "image/jpeg" | "image/png" }[];
  maxTokens?: number;
};

/**
 * Chamada de IA que força saída em JSON, usada por todos os módulos
 * (VideoAnalyzer, ScriptGenerator, PerformanceAnalyzer, etc).
 * Trocar de fornecedor de IA no futuro significa mexer só aqui.
 */
export async function callStructuredAI(
  input: StructuredPromptInput
): Promise<{ raw: string; costUsd: number }> {
  const anthropic = getClient();

  const content: Anthropic.MessageParam["content"] = [];

  for (const image of input.images ?? []) {
    content.push({
      type: "image",
      source: {
        type: "base64",
        media_type: image.mediaType,
        data: image.base64,
      },
    });
  }

  content.push({ type: "text", text: input.userText });

  const response = await anthropic.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: input.maxTokens ?? 2000,
    system: input.systemPrompt,
    messages: [{ role: "user", content }],
  });

  const textBlock = response.content.find((b) => b.type === "text");
  const raw = textBlock && "text" in textBlock ? textBlock.text : "";

  // Estimativa simplificada de custo — ajustar conforme tabela de preços vigente.
  const inputCostPerMTok = 3;
  const outputCostPerMTok = 15;
  const costUsd =
    (response.usage.input_tokens / 1_000_000) * inputCostPerMTok +
    (response.usage.output_tokens / 1_000_000) * outputCostPerMTok;

  return { raw, costUsd };
}

/**
 * Extrai o primeiro bloco JSON válido de uma resposta de texto,
 * tolerando texto extra ou blocos ```json ao redor.
 */
export function extractJson<T>(raw: string): T {
  const cleaned = raw.replace(/```json|```/g, "").trim();
  return JSON.parse(cleaned) as T;
}

CLAUDE_EOF_MARKER
mkdir -p 'src/lib/ai'
cat > 'src/lib/ai/videoAnalyzer.ts' << 'CLAUDE_EOF_MARKER'
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { mkdtemp, readdir, readFile, rm } from "node:fs/promises";
import { tmpdir } from "node:os";
import path from "node:path";
import { z } from "zod";
import { callStructuredAI, extractJson } from "./anthropicClient";

const execFileAsync = promisify(execFile);

const videoAnalysisSchema = z.object({
  fps: z.number().nullable(),
  description: z.string(),
  relevant_segments: z.array(
    z.object({
      start_seconds: z.number(),
      end_seconds: z.number(),
      label: z.string(),
    })
  ),
  quality: z.enum(["baixa", "media", "boa", "otima"]),
  potential: z.enum(["baixo", "medio", "alto"]),
});

export type VideoAnalysis = z.infer<typeof videoAnalysisSchema>;

const SYSTEM_PROMPT = `Você é o módulo VideoAnalyzer de um sistema de criação de vídeos para
TikTok Shop. Você recebe frames extraídos de um vídeo bruto e deve descrever
objetivamente o conteúdo, identificar trechos relevantes com timestamps, e
avaliar qualidade e potencial para uso em um vídeo de conversão.

Responda APENAS com um JSON válido, sem nenhum texto antes ou depois, no formato:
{
  "fps": number | null,
  "description": string,
  "relevant_segments": [{ "start_seconds": number, "end_seconds": number, "label": string }],
  "quality": "baixa" | "media" | "boa" | "otima",
  "potential": "baixo" | "medio" | "alto"
}

Não invente informações que não sejam observáveis nos frames.`;

/**
 * Baixa o vídeo do Supabase Storage para um diretório temporário local.
 */
async function downloadToTemp(
  supabase: ReturnType<
    typeof import("@/lib/supabase/serviceClient").createServiceClient
  >,
  storagePath: string,
  destDir: string
): Promise<string> {
  const { data, error } = await supabase.storage
    .from("videos")
    .download(storagePath);

  if (error || !data) {
    throw new Error(`Falha ao baixar vídeo do storage: ${error?.message}`);
  }

  const filePath = path.join(destDir, "input.mp4");
  const buffer = Buffer.from(await data.arrayBuffer());
  await import("node:fs/promises").then((fs) => fs.writeFile(filePath, buffer));
  return filePath;
}

/**
 * Extrai o FPS real do vídeo via ffprobe.
 */
async function extractFps(filePath: string): Promise<number | null> {
  try {
    const { stdout } = await execFileAsync("ffprobe", [
      "-v",
      "0",
      "-select_streams",
      "v:0",
      "-show_entries",
      "stream=r_frame_rate",
      "-of",
      "csv=p=0",
      filePath,
    ]);
    const [num, den] = stdout.trim().split("/").map(Number);
    if (!num) return null;
    return den ? num / den : num;
  } catch {
    return null; // ffprobe pode não estar disponível em todo ambiente — não falha o job por isso
  }
}

/**
 * Extrai frames-chave (1 a cada ~1.5s) e retorna os caminhos gerados.
 */
async function extractFrames(
  filePath: string,
  destDir: string
): Promise<string[]> {
  const pattern = path.join(destDir, "frame-%03d.jpg");
  await execFileAsync("ffmpeg", [
    "-i",
    filePath,
    "-vf",
    "fps=1/1.5",
    "-q:v",
    "3",
    pattern,
  ]);

  const files = await readdir(destDir);
  return files
    .filter((f) => f.startsWith("frame-"))
    .sort()
    .map((f) => path.join(destDir, f))
    .slice(0, 12); // limite de frames por análise, por custo
}

/**
 * Módulo principal: baixa o vídeo, extrai frames + fps, e pede ao modelo
 * uma análise estruturada e validada (VideoAnalyzer da arquitetura).
 */
export async function analyzeVideo(params: {
  supabase: ReturnType<
    typeof import("@/lib/supabase/serviceClient").createServiceClient
  >;
  storagePath: string;
}): Promise<{ analysis: VideoAnalysis; costUsd: number }> {
  const tempDir = await mkdtemp(path.join(tmpdir(), "video-analysis-"));

  try {
    const filePath = await downloadToTemp(
      params.supabase,
      params.storagePath,
      tempDir
    );

    const [fps, framePaths] = await Promise.all([
      extractFps(filePath),
      extractFrames(filePath, tempDir),
    ]);

    const images = await Promise.all(
      framePaths.map(async (p) => ({
        base64: (await readFile(p)).toString("base64"),
        mediaType: "image/jpeg" as const,
      }))
    );

    const { raw, costUsd } = await callStructuredAI({
      systemPrompt: SYSTEM_PROMPT,
      userText:
        "Analise os frames deste vídeo e responda com o JSON estruturado descrito nas instruções.",
      images,
      maxTokens: 1000,
    });

    const parsedJson = extractJson<Record<string, unknown>>(raw);
    const analysis = videoAnalysisSchema.parse({
      ...parsedJson,
      fps: parsedJson.fps ?? fps,
    });

    return { analysis, costUsd };
  } finally {
    await rm(tempDir, { recursive: true, force: true });
  }
}

CLAUDE_EOF_MARKER
mkdir -p 'src/worker'
cat > 'src/worker/index.ts' << 'CLAUDE_EOF_MARKER'
import "dotenv/config";
import { Worker } from "bullmq";
import { getRedisConnection } from "@/lib/queue/connection";
import {
  VIDEO_ANALYSIS_QUEUE_NAME,
  type VideoAnalysisJobData,
} from "@/lib/queue/videoAnalysisQueue";
import { createServiceClient } from "@/lib/supabase/serviceClient";
import { analyzeVideo } from "@/lib/ai/videoAnalyzer";

const supabase = createServiceClient();

const worker = new Worker<VideoAnalysisJobData>(
  VIDEO_ANALYSIS_QUEUE_NAME,
  async (job) => {
    const { mediaId, userId, projectId } = job.data;

    const { data: media, error: mediaError } = await supabase
      .from("media")
      .select("id, storage_path")
      .eq("id", mediaId)
      .single();

    if (mediaError || !media) {
      throw new Error(`Mídia não encontrada: ${mediaId}`);
    }

    const { analysis, costUsd } = await analyzeVideo({
      supabase,
      storagePath: media.storage_path,
    });

    await supabase
      .from("media")
      .update({ analysis, analyzed_at: new Date().toISOString() })
      .eq("id", mediaId);

    await supabase.from("ai_analyses").insert({
      user_id: userId,
      project_id: projectId,
      module: "VideoAnalyzer",
      input_summary: { media_id: mediaId },
      output: analysis,
      cost_usd: costUsd,
    });

    return { mediaId, costUsd };
  },
  {
    connection: getRedisConnection(),
    concurrency: 2, // limite de jobs simultâneos, por custo e carga
  }
);

worker.on("completed", (job) => {
  console.log(`[VideoAnalyzer] Job ${job.id} concluído`, job.returnvalue);
});

worker.on("failed", (job, err) => {
  console.error(`[VideoAnalyzer] Job ${job?.id} falhou:`, err.message);
});

console.log("Worker de análise de vídeo rodando. Aguardando jobs...");

CLAUDE_EOF_MARKER
echo 'OK: full4.sh'
