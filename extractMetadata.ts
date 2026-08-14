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
