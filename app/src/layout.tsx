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
