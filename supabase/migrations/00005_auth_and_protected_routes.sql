-- =========================================================================
-- Migration 00005: Supabase Auth, User Profiles, RBAC & Protected Routes
-- Follows Supabase Security Checklist & Postgres Best Practices
-- Self-contained: creates public.businesses if it does not already exist
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Ensure user_role enum exists
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('admin', 'staff');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 1. BUSINESSES TABLE (Ensure table exists before foreign key reference)
CREATE TABLE IF NOT EXISTS public.businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL DEFAULT 'Default Business',
    currency TEXT NOT NULL DEFAULT 'TZS',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- Seed default local business if missing (matches DatabaseService.defaultBusinessId)
INSERT INTO public.businesses (id, name, currency)
VALUES ('00000000-0000-0000-0000-000000000001', 'Tzion Stockly Shop', 'TZS')
ON CONFLICT (id) DO NOTHING;

-- 2. USER PROFILES TABLE (Mirrors Auth State for Local & Cloud)
CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'staff' CHECK (role IN ('owner', 'manager', 'staff', 'admin')),
    full_name TEXT,
    phone_number TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Index for tenant & auth lookups (critical for RLS performance)
CREATE INDEX IF NOT EXISTS idx_user_profiles_business_id ON public.user_profiles(business_id);
CREATE INDEX IF NOT EXISTS idx_user_profiles_role ON public.user_profiles(role);

-- 3. SERVER TIMESTAMP TRIGGER
CREATE OR REPLACE FUNCTION public.set_user_profiles_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_user_profiles_updated_at ON public.user_profiles;
CREATE TRIGGER trg_user_profiles_updated_at
    BEFORE UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_user_profiles_updated_at();

-- 4. AUTO-SYNC TRIGGER FROM auth.users
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger AS $$
DECLARE
    user_role_val TEXT;
    user_name_val TEXT;
    user_phone_val TEXT;
BEGIN
    -- Read role from app_metadata (secure) or fallback to user_metadata
    user_role_val := COALESCE(
        NEW.raw_app_meta_data->>'role',
        NEW.raw_user_meta_data->>'role',
        'staff'
    );

    user_name_val := COALESCE(
        NEW.raw_user_meta_data->>'full_name',
        split_part(NEW.email, '@', 1),
        'User'
    );

    user_phone_val := NEW.raw_user_meta_data->>'phone_number';

    -- Insert or update user_profiles
    INSERT INTO public.user_profiles (id, email, business_id, role, full_name, phone_number, created_at, updated_at)
    VALUES (
        NEW.id,
        COALESCE(NEW.email, ''),
        '00000000-0000-0000-0000-000000000001'::UUID,
        user_role_val,
        user_name_val,
        user_phone_val,
        NOW(),
        NOW()
    )
    ON CONFLICT (id) DO UPDATE
    SET email = EXCLUDED.email,
        full_name = COALESCE(EXCLUDED.full_name, public.user_profiles.full_name),
        phone_number = COALESCE(EXCLUDED.phone_number, public.user_profiles.phone_number),
        updated_at = NOW();

    -- Dual-write compatibility with profiles table if it exists
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
        INSERT INTO public.profiles (id, full_name, role, phone_number)
        VALUES (
            NEW.id,
            user_name_val,
            CASE WHEN user_role_val IN ('admin', 'owner') THEN 'admin'::user_role ELSE 'staff'::user_role END,
            user_phone_val
        )
        ON CONFLICT (id) DO UPDATE
        SET full_name = EXCLUDED.full_name,
            phone_number = COALESCE(EXCLUDED.phone_number, public.profiles.phone_number);
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created_sync ON auth.users;
CREATE TRIGGER on_auth_user_created_sync
    AFTER INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- 5. ROW LEVEL SECURITY (RLS) FOR USER PROFILES & BUSINESSES
ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;

-- Policies for businesses
DROP POLICY IF EXISTS "Authenticated users can read businesses" ON public.businesses;
CREATE POLICY "Authenticated users can read businesses"
    ON public.businesses FOR SELECT
    TO authenticated
    USING (true);

DROP POLICY IF EXISTS "Authenticated users can insert businesses" ON public.businesses;
CREATE POLICY "Authenticated users can insert businesses"
    ON public.businesses FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- Allow user to view their own profile
DROP POLICY IF EXISTS "Users can read own profile" ON public.user_profiles;
CREATE POLICY "Users can read own profile"
    ON public.user_profiles FOR SELECT
    TO authenticated
    USING ((select auth.uid()) = id);

-- Allow user to insert their own profile on signup
DROP POLICY IF EXISTS "Users can insert own profile" ON public.user_profiles;
CREATE POLICY "Users can insert own profile"
    ON public.user_profiles FOR INSERT
    TO authenticated
    WITH CHECK ((select auth.uid()) = id);

-- Allow user to update their own profile
DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
CREATE POLICY "Users can update own profile"
    ON public.user_profiles FOR UPDATE
    TO authenticated
    USING ((select auth.uid()) = id)
    WITH CHECK ((select auth.uid()) = id);

-- Allow members of the same business to view each other
DROP POLICY IF EXISTS "Coworkers in same business can view profiles" ON public.user_profiles;
CREATE POLICY "Coworkers in same business can view profiles"
    ON public.user_profiles FOR SELECT
    TO authenticated
    USING (
        business_id IS NOT NULL AND business_id IN (
            SELECT up.business_id FROM public.user_profiles up WHERE up.id = (select auth.uid())
        )
    );

-- Allow Owners to update roles of members in their business
DROP POLICY IF EXISTS "Business owners can update member profiles" ON public.user_profiles;
CREATE POLICY "Business owners can update member profiles"
    ON public.user_profiles FOR UPDATE
    TO authenticated
    USING (
        business_id IS NOT NULL AND business_id IN (
            SELECT up.business_id FROM public.user_profiles up WHERE up.id = (select auth.uid()) AND up.role = 'owner'
        )
    )
    WITH CHECK (
        business_id IS NOT NULL AND business_id IN (
            SELECT up.business_id FROM public.user_profiles up WHERE up.id = (select auth.uid()) AND up.role = 'owner'
        )
    );

-- 6. GRANTS FOR POSTGREST DATA API
GRANT SELECT, INSERT, UPDATE ON TABLE public.businesses TO authenticated;
GRANT SELECT ON TABLE public.businesses TO anon;
GRANT SELECT, INSERT, UPDATE ON TABLE public.user_profiles TO authenticated;
GRANT SELECT ON TABLE public.user_profiles TO anon;
