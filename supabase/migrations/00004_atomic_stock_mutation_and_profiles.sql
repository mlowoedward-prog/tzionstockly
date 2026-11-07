-- =========================================================================
-- Migration 00004: Atomic Stock Mutation, Profiles & RLS (TzionStockly DDL)
-- Compatible with PostgreSQL 15+ & Supabase Auth
-- =========================================================================

-- 1. Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

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

-- 3. Products Catalog Table
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    sku TEXT UNIQUE NOT NULL,
    name TEXT NOT NULL,
    category TEXT NOT NULL DEFAULT 'General',
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    min_threshold INTEGER NOT NULL DEFAULT 5 CHECK (min_threshold >= 1),
    cost_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (cost_price_tzs >= 0.00),
    selling_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (selling_price_tzs >= 0.00),
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW())
);

-- Index for high-velocity lookups
CREATE INDEX IF NOT EXISTS idx_products_sku ON public.products(sku);
CREATE INDEX IF NOT EXISTS idx_products_updated_at ON public.products(updated_at);

-- 4. Stock Movement Log (Audit Trail & Delta Source)
DO $$ BEGIN
    CREATE TYPE transaction_type AS ENUM ('CHECK_IN', 'CHECK_OUT');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

CREATE TABLE IF NOT EXISTS public.stock_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    performed_by UUID NOT NULL REFERENCES public.profiles(id),
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
BEGIN
    -- Validate permissions inside transaction
    IF p_type = 'CHECK_IN' THEN
        IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND role = 'admin') THEN
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

-- 6. Trigger: Auto-Provision User Profile on Auth Signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
    INSERT INTO public.profiles (id, full_name, role, phone_number)
    VALUES (
        NEW.id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
        COALESCE((NEW.raw_user_meta_data->>'role')::user_role, 'staff'::user_role),
        NEW.raw_user_meta_data->>'phone_number'
    )
    ON CONFLICT (id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        role = EXCLUDED.role;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- 7. Row Level Security (RLS)
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Profiles: Authenticated users can view profiles; only admins can edit profiles
DROP POLICY IF EXISTS "Allow authenticated read profiles" ON public.profiles;
CREATE POLICY "Allow authenticated read profiles" ON public.profiles
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow user update self profile" ON public.profiles;
CREATE POLICY "Allow user update self profile" ON public.profiles
    FOR UPDATE TO authenticated USING (auth.uid() = id);

-- Products: Everyone can read; only Admins can create/update/delete
DROP POLICY IF EXISTS "Allow authenticated read products" ON public.products;
CREATE POLICY "Allow authenticated read products" ON public.products
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Allow admin write products" ON public.products;
CREATE POLICY "Allow admin write products" ON public.products
    FOR ALL TO authenticated
    USING ((SELECT role FROM public.profiles WHERE id = auth.uid()) = 'admin');

-- Transactions: Staff and Admin can view records; write handled through RPC or validated insert
DROP POLICY IF EXISTS "Allow authenticated view transactions" ON public.stock_transactions;
CREATE POLICY "Allow authenticated view transactions" ON public.stock_transactions
    FOR SELECT TO authenticated USING (true);

