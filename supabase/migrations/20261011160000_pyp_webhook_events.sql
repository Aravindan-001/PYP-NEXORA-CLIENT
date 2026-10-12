-- PYP: Webhook Deduplication & Order Concurrency Table
-- Forward-only migration for Stage 2 Edge Function integration

create table if not exists public.processed_webhook_events (
  event_id text primary key,
  event_type text not null,
  created_at timestamptz not null default now()
);

alter table public.processed_webhook_events enable row level security;
revoke all on public.processed_webhook_events from anon, authenticated, public;
