-- ==========================================
-- Migration 00003: Health check table for keep-alive pings
-- ==========================================
-- Used by .github/workflows/keepalive.yml to keep the Supabase free tier
-- project from auto-pausing. Contains no business data.

CREATE TABLE IF NOT EXISTS public.health_check (
    id INTEGER PRIMARY KEY
);

INSERT INTO public.health_check (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.health_check ENABLE ROW LEVEL SECURITY;

-- Read-only for everyone (anon + authenticated); no write policies are defined.
DROP POLICY IF EXISTS "Anyone can read health check" ON public.health_check;
CREATE POLICY "Anyone can read health check"
    ON public.health_check FOR SELECT
    USING (true);
