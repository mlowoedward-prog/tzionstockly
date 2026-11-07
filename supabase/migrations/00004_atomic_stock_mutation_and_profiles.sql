-- =========================================================================
-- Migration 00004: Atomic Stock Mutation, Profiles & RLS (TzionStockly DDL)
-- Compatible with PostgreSQL 15+ & Supabase Auth
-- Fully idempotent with existing tables (00001-00003)
-- =========================================================================

-- 1. Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Ensure businesses table exists
CREATE TABLE IF NOT EXISTS public.businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL DEFAULT 'Default Business',
    currency TEXT NOT NULL DEFAULT 'TZS',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

INSERT INTO public.businesses (id, name, currency)
VALUES ('00000000-0000-0000-0000-000000000001', 'Tzion Stockly Shop', 'TZS')
ON CONFLICT (id) DO NOTHING;

-- 2. User Roles & Profiles Table (Linked to Supabase Auth)
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('admin', 'staff');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'staff',
    phone_number TEXT,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW())
);

-- 3. Products Catalog Table (Ensure base table and all columns exist)
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    sku TEXT,
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'General',
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    min_threshold INTEGER NOT NULL DEFAULT 5 CHECK (min_threshold >= 1),
    cost_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (cost_price_tzs >= 0.00),
    selling_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (selling_price_tzs >= 0.00),
    cost_price BIGINT NOT NULL DEFAULT 0,
    selling_price BIGINT NOT NULL DEFAULT 0,
    unit TEXT NOT NULL DEFAULT 'pcs',
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW())
);

-- Idempotent column additions if products was created by another migration
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category TEXT DEFAULT 'General';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS stock_quantity INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS min_threshold INTEGER NOT NULL DEFAULT 5;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS cost_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS selling_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'pcs';

-- Index for high-velocity lookups
CREATE INDEX IF NOT EXISTS idx_products_sku ON public.products(sku);
CREATE INDEX IF NOT EXISTS idx_products_updated_at ON public.products(updated_at);
CREATE INDEX IF NOT EXISTS idx_products_business_id ON public.products(business_id);

-- 4. Stock Movement Log (Audit Trail & Delta Source)
DO $$ BEGIN
    CREATE TYPE transaction_type AS ENUM ('CHECK_IN', 'CHECK_OUT');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS public.stock_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    performed_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type transaction_type NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price_tzs NUMERIC(12, 2) NOT NULL,
    notes TEXT,
    device_created_at TIMESTAMPTZ NOT NULL,
    synced_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW())
);

CREATE INDEX IF NOT EXISTS idx_transactions_product_id ON public.stock_transactions(product_id);
CREATE INDEX IF NOT EXISTS idx_transactions_device_time ON public.stock_transactions(device_created_at);

-- 5. Atomic Stock Adjustment Stored Procedure
CREATE OR REPLACE FUNCTION process_stock_mutation(
    p_product_id UUID,
    p_user_id UUID,
    p_type transaction_type,
    p_quantity INTEGER,
    p_unit_price_tzs NUMERIC,
    p_notes TEXT,
    p_device_created_at TIMESTAMPTZ
) RETURNS VOID AS $$
DECLARE
    is_admin_user BOOLEAN := FALSE;
BEGIN
    -- Check admin or owner status across profiles or user_profiles
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND role = 'admin') THEN
        is_admin_user := TRUE;
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_profiles') THEN
        IF EXISTS (SELECT 1 FROM public.user_profiles WHERE id = p_user_id AND role IN ('admin', 'owner')) THEN
            is_admin_user := TRUE;
        END IF;
    END IF;

    -- Validate permissions inside transaction
    IF p_type = 'CHECK_IN' THEN
        IF NOT is_admin_user THEN
            RAISE EXCEPTION 'Access Denied: Only Admins can perform stock Check-In.';
        END IF;

        UPDATE public.products
        SET stock_quantity = stock_quantity + p_quantity,
            updated_at = TIMEZONE('utc', NOW())
        WHERE id = p_product_id;
    ELSE
        -- CHECK_OUT: Allowed for both Admin and Staff
        IF (SELECT stock_quantity FROM public.products WHERE id = p_product_id) < p_quantity THEN
            RAISE EXCEPTION 'Insufficient stock quantity available.';
        END IF;

        UPDATE public.products
        SET stock_quantity = stock_quantity - p_quantity,
            updated_at = TIMEZONE('utc', NOW())
        WHERE id = p_product_id;
    END IF;

    -- Record transaction
    INSERT INTO public.stock_transactions (
        product_id, performed_by, type, quantity, unit_price_tzs, notes, device_created_at
    ) VALUES (
        p_product_id, p_user_id, p_type, p_quantity, p_unit_price_tzs, p_notes, p_device_created_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Row Level Security (RLS) Policies
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_transactions ENABLE ROW LEVEL SECURITY;

-- Products: Everyone authenticated can view catalog
DROP POLICY IF EXISTS "Products viewable by authenticated" ON public.products;
CREATE POLICY "Products viewable by authenticated"
    ON public.products FOR SELECT
    TO authenticated
    USING (true);

-- Products: Admin/Owner can insert/update
DROP POLICY IF EXISTS "Products mutable by admin" ON public.products;
CREATE POLICY "Products mutable by admin"
    ON public.products FOR ALL
    TO authenticated
    USING (
        EXISTS (SELECT 1 FROM public.profiles WHERE id = (select auth.uid()) AND role = 'admin')
        OR
        EXISTS (SELECT 1 FROM public.user_profiles WHERE id = (select auth.uid()) AND role IN ('admin', 'owner'))
    );

-- Profiles: Users can view all profiles
DROP POLICY IF EXISTS "Profiles viewable by authenticated" ON public.profiles;
CREATE POLICY "Profiles viewable by authenticated"
    ON public.profiles FOR SELECT
    TO authenticated
    USING (true);

-- Stock Transactions: Audit log readable by authenticated
DROP POLICY IF EXISTS "Transactions viewable by authenticated" ON public.stock_transactions;
CREATE POLICY "Transactions viewable by authenticated"
    ON public.stock_transactions FOR SELECT
    TO authenticated
    USING (true);

-- Stock Transactions: Insert allowed for transactions performed by current user
DROP POLICY IF EXISTS "Transactions insertable by performer" ON public.stock_transactions;
CREATE POLICY "Transactions insertable by performer"
    ON public.stock_transactions FOR INSERT
    TO authenticated
    WITH CHECK (performed_by = (select auth.uid()));

-- Grants for Data API
GRANT EXECUTE ON FUNCTION process_stock_mutation TO authenticated;
GRANT SELECT ON public.products TO authenticated, anon;
GRANT SELECT ON public.profiles TO authenticated;
GRANT SELECT, INSERT ON public.stock_transactions TO authenticated;
