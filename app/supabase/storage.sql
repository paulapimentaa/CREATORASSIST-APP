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
