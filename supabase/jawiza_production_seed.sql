-- =============================================================================
-- TZIONSTOCKLY: JAWIZA STORE PRODUCTION SEED & SYNC SCRIPT FOR SUPABASE
-- Run this complete script in Supabase SQL Editor:
-- Dashboard -> SQL Editor -> New Query -> Paste & Run
-- =============================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 2. ENSURE ALL TABLES & COLUMNS EXIST (Prevents "column does not exist" errors)
CREATE TABLE IF NOT EXISTS public.businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL DEFAULT 'Jawiza',
    currency TEXT NOT NULL DEFAULT 'TZS',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS store_code TEXT;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'TZS';
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS subscription_tier TEXT DEFAULT 'active';
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Crucial: Add any missing product columns before inserting
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS store_id UUID;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sku TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS barcode TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'pcs';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'General';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS cost_price BIGINT NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS selling_price BIGINT NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS cost_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS selling_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS stock_quantity INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS min_threshold INTEGER NOT NULL DEFAULT 5;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS reorder_level INT NOT NULL DEFAULT 5;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

CREATE TABLE IF NOT EXISTS public.user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS store_id UUID;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS role TEXT NOT NULL DEFAULT 'staff';
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS full_name TEXT;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS phone_number TEXT;
ALTER TABLE public.user_profiles ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- 3. INSERT / UPDATE JAWIZA STORE (Default Business ID)
INSERT INTO public.businesses (
    id, name, store_code, currency, phone, address, subscription_tier
) VALUES (
    '00000000-0000-0000-0000-000000000001',
    'Jawiza',
    'TZ-JAWIZA',
    'TZS',
    '+255755123456',
    'Dar es Salaam, Tanzania',
    'active'
)
ON CONFLICT (id) DO UPDATE SET
    name = 'Jawiza',
    store_code = 'TZ-JAWIZA',
    phone = '+255755123456',
    address = 'Dar es Salaam, Tanzania',
    subscription_tier = 'active',
    updated_at = NOW();

-- Also sync stores table if exists
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'stores') THEN
        INSERT INTO public.stores (
            id, name, owner_name, owner_phone, monthly_fee_tzs, status,
            subscription_renews_at, is_locked
        ) VALUES (
            '00000000-0000-0000-0000-000000000001',
            'Jawiza',
            'Jawiza Admin',
            '+255755123456',
            50000.00,
            'active',
            NOW() + INTERVAL '60 days',
            false
        )
        ON CONFLICT (id) DO UPDATE SET
            name = 'Jawiza',
            owner_name = 'Jawiza Admin',
            status = 'active',
            is_locked = false;
    END IF;
END $$;

-- 4. INSERT / UPDATE CATEGORIES FOR JAWIZA
INSERT INTO public.categories (id, business_id, name)
VALUES 
    ('c0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'unga'),
    ('c0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'poultry'),
    ('c0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'appetizer')
ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name;

-- 5. INSERT / UPDATE EXACT 7 PRODUCTS WITH TZS PRICING & STOCK
INSERT INTO public.products (
    id, business_id, name, sku, category, unit,
    cost_price, selling_price, cost_price_tzs, selling_price_tzs,
    stock_quantity, min_threshold
) VALUES
    ('p0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000001', 'mbilimbi', 'APP-MBI-001', 'appetizer', 'fungu', 1000, 1500, 1000.00, 1500.00, 50, 10),
    ('p0000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000001', 'kuku', 'PLT-KUK-001', 'poultry', 'kuku', 12000, 15000, 12000.00, 15000.00, 30, 5),
    ('p0000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000001', 'Uji Mtamu', 'UNG-UJI-001', 'unga', 'pakiti', 2500, 3500, 2500.00, 3500.00, 40, 10),
    ('p0000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000001', 'mayai', 'PLT-MAY-001', 'poultry', 'trei', 9000, 11000, 9000.00, 11000.00, 25, 5),
    ('p0000000-0000-0000-0000-000000000005', '00000000-0000-0000-0000-000000000001', 'mtama mwekundu', 'UNG-MTM-001', 'unga', 'kg', 1800, 2500, 1800.00, 2500.00, 50, 10),
    ('p0000000-0000-0000-0000-000000000006', '00000000-0000-0000-0000-000000000001', 'mtama mweupe', 'UNG-MTW-002', 'unga', 'kg', 1800, 2500, 1800.00, 2500.00, 50, 10),
    ('p0000000-0000-0000-0000-000000000007', '00000000-0000-0000-0000-000000000001', 'Njano mix', 'UNG-NJM-003', 'unga', 'pakiti', 2500, 3500, 2500.00, 3500.00, 40, 10)
ON CONFLICT (id) DO UPDATE SET
    name = EXCLUDED.name,
    category = EXCLUDED.category,
    unit = EXCLUDED.unit,
    cost_price = EXCLUDED.cost_price,
    selling_price = EXCLUDED.selling_price,
    cost_price_tzs = EXCLUDED.cost_price_tzs,
    selling_price_tzs = EXCLUDED.selling_price_tzs,
    stock_quantity = EXCLUDED.stock_quantity;

-- 6. CREATE / SYNC AUTH ACCOUNTS: Admin & Maria
DO $$
DECLARE
    v_admin_id UUID;
    v_maria_id UUID;
BEGIN
    -- Check or Insert Admin (admin@jawiza.com / Jawiza@Admin2026)
    SELECT id INTO v_admin_id FROM auth.users WHERE email = 'admin@jawiza.com';
    IF v_admin_id IS NULL THEN
        v_admin_id := uuid_generate_v4();
        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password,
            email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
            created_at, updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            v_admin_id,
            'authenticated',
            'authenticated',
            'admin@jawiza.com',
            crypt('Jawiza@Admin2026', gen_salt('bf')),
            NOW(),
            jsonb_build_object('provider', 'email', 'providers', array['email'], 'role', 'admin'),
            jsonb_build_object('full_name', 'Jawiza Admin', 'role', 'admin'),
            NOW(),
            NOW()
        );
    ELSE
        UPDATE auth.users 
        SET encrypted_password = crypt('Jawiza@Admin2026', gen_salt('bf')),
            raw_app_meta_data = jsonb_build_object('provider', 'email', 'providers', array['email'], 'role', 'admin'),
            raw_user_meta_data = jsonb_build_object('full_name', 'Jawiza Admin', 'role', 'admin'),
            email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
            updated_at = NOW()
        WHERE id = v_admin_id;
    END IF;

    -- Check or Insert Maria (maria@jawiza.com / Maria@Jawiza2026)
    SELECT id INTO v_maria_id FROM auth.users WHERE email = 'maria@jawiza.com';
    IF v_maria_id IS NULL THEN
        v_maria_id := uuid_generate_v4();
        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password,
            email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
            created_at, updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            v_maria_id,
            'authenticated',
            'authenticated',
            'maria@jawiza.com',
            crypt('Maria@Jawiza2026', gen_salt('bf')),
            NOW(),
            jsonb_build_object('provider', 'email', 'providers', array['email'], 'role', 'staff'),
            jsonb_build_object('full_name', 'Maria', 'role', 'staff'),
            NOW(),
            NOW()
        );
    ELSE
        UPDATE auth.users 
        SET encrypted_password = crypt('Maria@Jawiza2026', gen_salt('bf')),
            raw_app_meta_data = jsonb_build_object('provider', 'email', 'providers', array['email'], 'role', 'staff'),
            raw_user_meta_data = jsonb_build_object('full_name', 'Maria', 'role', 'staff'),
            email_confirmed_at = COALESCE(email_confirmed_at, NOW()),
            updated_at = NOW()
        WHERE id = v_maria_id;
    END IF;

    -- Link User Profiles
    INSERT INTO public.user_profiles (id, email, business_id, role, full_name)
    VALUES (v_admin_id, 'admin@jawiza.com', '00000000-0000-0000-0000-000000000001', 'owner', 'Jawiza Admin')
    ON CONFLICT (id) DO UPDATE SET business_id = '00000000-0000-0000-0000-000000000001', role = 'owner', full_name = 'Jawiza Admin';

    INSERT INTO public.user_profiles (id, email, business_id, role, full_name)
    VALUES (v_maria_id, 'maria@jawiza.com', '00000000-0000-0000-0000-000000000001', 'staff', 'Maria')
    ON CONFLICT (id) DO UPDATE SET business_id = '00000000-0000-0000-0000-000000000001', role = 'staff', full_name = 'Maria';

    -- Optional: If legacy profiles table exists, link there too
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
        INSERT INTO public.profiles (id, full_name, role)
        VALUES 
            (v_admin_id, 'Jawiza Admin', 'admin'::public.user_role),
            (v_maria_id, 'Maria', 'staff'::public.user_role)
        ON CONFLICT (id) DO NOTHING;
    END IF;

    -- Optional: If business_members exists, link there too
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'business_members') THEN
        INSERT INTO public.business_members (user_id, business_id, role)
        VALUES 
            (v_admin_id, '00000000-0000-0000-0000-000000000001', 'owner'),
            (v_maria_id, '00000000-0000-0000-0000-000000000001', 'staff')
        ON CONFLICT (user_id, business_id) DO NOTHING;
    END IF;

    RAISE NOTICE 'SUCCESS: Jawiza store, Admin, Maria, and 7 products synchronized to Supabase!';
END $$;
