-- ==========================================
-- Migration 00003: Health check table for keep-alive pings
-- ==========================================
-- Used by .github/workflows/keepalive.yml to keep the Supabase free tier
-- project from auto-pausing. Contains no business data.

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

CREATE TABLE IF NOT EXISTS public.health_check (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    status TEXT NOT NULL DEFAULT 'ok',
    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.health_check (id, status)
VALUES ('00000000-0000-0000-0000-000000000001', 'ok')
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.health_check ENABLE ROW LEVEL SECURITY;

-- Read-only for everyone (anon + authenticated); no write policies are defined.
DROP POLICY IF EXISTS "Anyone can read health check" ON public.health_check;
CREATE POLICY "Anyone can read health check"
    ON public.health_check FOR SELECT
    TO anon, authenticated
    USING (true);

GRANT SELECT ON public.health_check TO anon, authenticated;
