-- =========================================================================
-- 00000_master_schema.sql: Combined master schema for TzionStockly
-- Contains all tables, functions, RLS policies and seed data.
-- =========================================================================

-- 1. EXTENSIONS
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. CUSTOM TYPES & ENUMS
DO $$ BEGIN
    CREATE TYPE user_role AS ENUM ('admin', 'staff');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

DO $$ BEGIN
    CREATE TYPE transaction_type AS ENUM ('CHECK_IN', 'CHECK_OUT');
EXCEPTION
    WHEN duplicate_object THEN null;
END $$;

-- 3. UPDATED_AT TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 4. BUSINESSES TABLE (Multi-tenant foundation)
CREATE TABLE IF NOT EXISTS public.businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL DEFAULT 'Tzion Stockly Shop',
    currency TEXT NOT NULL DEFAULT 'TZS',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_businesses_updated_at ON public.businesses;
CREATE TRIGGER trg_businesses_updated_at
    BEFORE INSERT OR UPDATE ON public.businesses
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_businesses_updated ON public.businesses(updated_at);

-- Seed default business matching Flutter DatabaseService.defaultBusinessId
INSERT INTO public.businesses (id, name, currency)
VALUES ('00000000-0000-0000-0000-000000000001', 'Tzion Stockly Main', 'TZS')
ON CONFLICT (id) DO NOTHING;

-- 5. BUSINESS MEMBERS (Multi-tenant memberships)
CREATE TABLE IF NOT EXISTS public.business_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'manager', 'staff')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE (user_id, business_id)
);

DROP TRIGGER IF EXISTS trg_business_members_updated_at ON public.business_members;
CREATE TRIGGER trg_business_members_updated_at
    BEFORE INSERT OR UPDATE ON public.business_members
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_business_members_user ON public.business_members(user_id, business_id);

-- 6. USER PROFILES TABLE (Queried by Flutter AuthNotifier)
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

DROP TRIGGER IF EXISTS trg_user_profiles_updated_at ON public.user_profiles;
CREATE TRIGGER trg_user_profiles_updated_at
    BEFORE INSERT OR UPDATE ON public.user_profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_user_profiles_business_id ON public.user_profiles(business_id);
CREATE INDEX IF NOT EXISTS idx_user_profiles_role ON public.user_profiles(role);

-- 7. PROFILES TABLE (Dual-write compatibility for Web App)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'staff',
    phone_number TEXT,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW())
);

-- 8. AUTO-SYNC TRIGGER FROM auth.users TO user_profiles & profiles
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger AS $$
DECLARE
    user_role_val TEXT;
    user_name_val TEXT;
    user_phone_val TEXT;
BEGIN
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

    -- 1. Insert/update user_profiles
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

    -- 2. Insert/update profiles
    INSERT INTO public.profiles (id, full_name, role, phone_number)
    VALUES (
        NEW.id,
        user_name_val,
        CASE WHEN user_role_val IN ('admin', 'owner') THEN 'admin'::user_role ELSE 'staff'::user_role END,
        user_phone_val
    )
    ON CONFLICT (id) DO UPDATE
    SET full_name = EXCLUDED.full_name,
        phone_number = COALESCE(EXCLUDED.phone_number, public.profiles.phone_number),
        updated_at = NOW();

    -- 3. Default business membership
    INSERT INTO public.business_members (user_id, business_id, role)
    VALUES (
        NEW.id,
        '00000000-0000-0000-0000-000000000001'::UUID,
        CASE WHEN user_role_val IN ('admin', 'owner') THEN 'owner' ELSE 'staff' END
    )
    ON CONFLICT (user_id, business_id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created_sync ON auth.users;
CREATE TRIGGER on_auth_user_created_sync
    AFTER INSERT OR UPDATE ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_auth_user();

-- 9. CATEGORIES TABLE
CREATE TABLE IF NOT EXISTS public.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_categories_updated_at ON public.categories;
CREATE TRIGGER trg_categories_updated_at
    BEFORE INSERT OR UPDATE ON public.categories
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_categories_biz_updated ON public.categories(business_id, updated_at);

-- 10. PRODUCTS CATALOG TABLE (Supports Flutter Drift Sync & Web PWA Atomic Mutations)
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sku TEXT,
    barcode TEXT,
    unit TEXT NOT NULL DEFAULT 'pcs',
    category TEXT NOT NULL DEFAULT 'General',
    category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL,
    cost_price BIGINT NOT NULL DEFAULT 0,
    selling_price BIGINT NOT NULL DEFAULT 0,
    cost_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (cost_price_tzs >= 0.00),
    selling_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00 CHECK (selling_price_tzs >= 0.00),
    stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
    reorder_level INT NOT NULL DEFAULT 5,
    min_threshold INTEGER NOT NULL DEFAULT 5 CHECK (min_threshold >= 1),
    image_path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

-- Idempotent column additions for existing products table
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS sku TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS barcode TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS unit TEXT NOT NULL DEFAULT 'pcs';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'General';
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS category_id UUID REFERENCES public.categories(id) ON DELETE SET NULL;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS cost_price BIGINT NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS selling_price BIGINT NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS cost_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS selling_price_tzs NUMERIC(12, 2) NOT NULL DEFAULT 0.00;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS stock_quantity INTEGER NOT NULL DEFAULT 0;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS reorder_level INT NOT NULL DEFAULT 5;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS min_threshold INTEGER NOT NULL DEFAULT 5;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS image_path TEXT;
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ;

DROP TRIGGER IF EXISTS trg_products_updated_at ON public.products;
CREATE TRIGGER trg_products_updated_at
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_products_biz_updated ON public.products(business_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON public.products(barcode);
CREATE INDEX IF NOT EXISTS idx_products_sku ON public.products(sku);

-- 11. PARTNERS TABLE (Suppliers & Customers)
CREATE TABLE IF NOT EXISTS public.partners (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    type TEXT NOT NULL CHECK (type IN ('supplier', 'customer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_partners_updated_at ON public.partners;
CREATE TRIGGER trg_partners_updated_at
    BEFORE INSERT OR UPDATE ON public.partners
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_partners_biz_updated ON public.partners(business_id, updated_at);

-- 12. STOCK MOVEMENTS (Flutter Append-Only Signed Ledger)
CREATE TABLE IF NOT EXISTS public.stock_movements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('purchase', 'sale', 'adjustment', 'return', 'damage')),
    quantity INT NOT NULL,
    unit_cost BIGINT NOT NULL DEFAULT 0,
    unit_price BIGINT NOT NULL DEFAULT 0,
    partner_id UUID REFERENCES public.partners(id) ON DELETE SET NULL,
    note TEXT,
    created_by TEXT NOT NULL DEFAULT 'local_user',
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

DROP TRIGGER IF EXISTS trg_stock_movements_updated_at ON public.stock_movements;
CREATE TRIGGER trg_stock_movements_updated_at
    BEFORE INSERT OR UPDATE ON public.stock_movements
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_stock_movements_biz_updated ON public.stock_movements(business_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_prod_time ON public.stock_movements(product_id, occurred_at);

-- 13. STOCK TRANSACTIONS (Web PWA Audit Trail & Mutation Log)
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

-- 14. PRODUCT COSTS TABLE (Owner/Manager role restricted pricing)
CREATE TABLE IF NOT EXISTS public.product_costs (
    product_id UUID PRIMARY KEY REFERENCES public.products(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    cost_price INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 15. HEALTH CHECK TABLE (Keep-alive pings)
CREATE TABLE IF NOT EXISTS public.health_check (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    status TEXT NOT NULL DEFAULT 'ok',
    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.health_check (id, status)
VALUES ('00000000-0000-0000-0000-000000000001', 'ok')
ON CONFLICT (id) DO NOTHING;

-- 16. ATOMIC STOCK ADJUSTMENT RPC PROCEDURE
CREATE OR REPLACE FUNCTION public.process_stock_mutation(
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
    -- Check permissions (admin or owner in either user_profiles or profiles)
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND role = 'admin') THEN
        is_admin_user := TRUE;
    ELSIF EXISTS (SELECT 1 FROM public.user_profiles WHERE id = p_user_id AND role IN ('admin', 'owner')) THEN
        is_admin_user := TRUE;
    END IF;

    IF p_type = 'CHECK_IN' THEN
        IF NOT is_admin_user THEN
            RAISE EXCEPTION 'Access Denied: Only Admins can perform stock Check-In.';
        END IF;

        UPDATE public.products
        SET stock_quantity = stock_quantity + p_quantity,
            updated_at = NOW()
        WHERE id = p_product_id;
    ELSE
        -- CHECK_OUT: Allowed for Admin and Staff
        IF (SELECT stock_quantity FROM public.products WHERE id = p_product_id) < p_quantity THEN
            RAISE EXCEPTION 'Insufficient stock quantity available.';
        END IF;

        UPDATE public.products
        SET stock_quantity = stock_quantity - p_quantity,
            updated_at = NOW()
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

-- 17. ROW LEVEL SECURITY (RLS) POLICIES
-- Uses (select auth.uid()) for optimal Postgres query planning & execution
ALTER TABLE public.businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.business_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.product_costs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.health_check ENABLE ROW LEVEL SECURITY;

-- Helper RLS membership function
CREATE OR REPLACE FUNCTION public.is_business_member(biz_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.business_members
        WHERE business_id = biz_id
          AND user_id = (select auth.uid())
          AND deleted_at IS NULL
    ) OR EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE business_id = biz_id
          AND id = (select auth.uid())
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Helper RLS owner/manager function
CREATE OR REPLACE FUNCTION public.is_owner_or_manager(biz_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.business_members
        WHERE business_id = biz_id
          AND user_id = (select auth.uid())
          AND role IN ('owner', 'manager')
    ) OR EXISTS (
        SELECT 1 FROM public.user_profiles
        WHERE business_id = biz_id
          AND id = (select auth.uid())
          AND role IN ('owner', 'manager', 'admin')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Businesses Policies
DROP POLICY IF EXISTS "Members can view their business" ON public.businesses;
CREATE POLICY "Members can view their business" ON public.businesses
    FOR SELECT TO authenticated USING (is_business_member(id) OR id = '00000000-0000-0000-0000-000000000001');

DROP POLICY IF EXISTS "Members can update their business" ON public.businesses;
CREATE POLICY "Members can update their business" ON public.businesses
    FOR UPDATE TO authenticated USING (is_owner_or_manager(id));

DROP POLICY IF EXISTS "Authenticated can insert business" ON public.businesses;
CREATE POLICY "Authenticated can insert business" ON public.businesses
    FOR INSERT TO authenticated WITH CHECK (true);

-- Business Members Policies
DROP POLICY IF EXISTS "Users can view memberships" ON public.business_members;
CREATE POLICY "Users can view memberships" ON public.business_members
    FOR SELECT TO authenticated USING (user_id = (select auth.uid()) OR is_owner_or_manager(business_id));

DROP POLICY IF EXISTS "Users can insert membership" ON public.business_members;
CREATE POLICY "Users can insert membership" ON public.business_members
    FOR INSERT TO authenticated WITH CHECK (user_id = (select auth.uid()) OR is_owner_or_manager(business_id));

DROP POLICY IF EXISTS "Owners can update membership" ON public.business_members;
CREATE POLICY "Owners can update membership" ON public.business_members
    FOR UPDATE TO authenticated USING (is_owner_or_manager(business_id));

-- User Profiles Policies
DROP POLICY IF EXISTS "Users can read own profile" ON public.user_profiles;
CREATE POLICY "Users can read own profile" ON public.user_profiles
    FOR SELECT TO authenticated USING ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Users can insert own profile" ON public.user_profiles;
CREATE POLICY "Users can insert own profile" ON public.user_profiles
    FOR INSERT TO authenticated WITH CHECK ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Users can update own profile" ON public.user_profiles;
CREATE POLICY "Users can update own profile" ON public.user_profiles
    FOR UPDATE TO authenticated
    USING ((select auth.uid()) = id)
    WITH CHECK ((select auth.uid()) = id);

DROP POLICY IF EXISTS "Coworkers in same business can view profiles" ON public.user_profiles;
CREATE POLICY "Coworkers in same business can view profiles" ON public.user_profiles
    FOR SELECT TO authenticated
    USING (
        business_id IS NOT NULL AND business_id IN (
            SELECT up.business_id FROM public.user_profiles up WHERE up.id = (select auth.uid())
        )
    );

-- Profiles Policies
DROP POLICY IF EXISTS "Profiles viewable by authenticated" ON public.profiles;
CREATE POLICY "Profiles viewable by authenticated" ON public.profiles
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Profiles editable by owner" ON public.profiles;
CREATE POLICY "Profiles editable by owner" ON public.profiles
    FOR ALL TO authenticated USING ((select auth.uid()) = id);

-- Categories Policies
DROP POLICY IF EXISTS "Members can view categories" ON public.categories;
CREATE POLICY "Members can view categories" ON public.categories
    FOR SELECT TO authenticated USING (is_business_member(business_id));

DROP POLICY IF EXISTS "Members can insert categories" ON public.categories;
CREATE POLICY "Members can insert categories" ON public.categories
    FOR INSERT TO authenticated WITH CHECK (is_business_member(business_id));

DROP POLICY IF EXISTS "Members can update categories" ON public.categories;
CREATE POLICY "Members can update categories" ON public.categories
    FOR UPDATE TO authenticated USING (is_business_member(business_id));

-- Products Policies
DROP POLICY IF EXISTS "Products viewable by authenticated" ON public.products;
CREATE POLICY "Products viewable by authenticated" ON public.products
    FOR SELECT TO authenticated
    USING (business_id IS NULL OR is_business_member(business_id) OR business_id = '00000000-0000-0000-0000-000000000001');

DROP POLICY IF EXISTS "Products mutable by business member" ON public.products;
CREATE POLICY "Products mutable by business member" ON public.products
    FOR ALL TO authenticated
    USING (business_id IS NULL OR is_business_member(business_id) OR business_id = '00000000-0000-0000-0000-000000000001');

-- Partners Policies
DROP POLICY IF EXISTS "Members can view partners" ON public.partners;
CREATE POLICY "Members can view partners" ON public.partners
    FOR SELECT TO authenticated USING (is_business_member(business_id));

DROP POLICY IF EXISTS "Members can insert partners" ON public.partners;
CREATE POLICY "Members can insert partners" ON public.partners
    FOR INSERT TO authenticated WITH CHECK (is_business_member(business_id));

DROP POLICY IF EXISTS "Members can update partners" ON public.partners;
CREATE POLICY "Members can update partners" ON public.partners
    FOR UPDATE TO authenticated USING (is_business_member(business_id));

-- Stock Movements Policies (Append-only)
DROP POLICY IF EXISTS "Members can view stock movements" ON public.stock_movements;
CREATE POLICY "Members can view stock movements" ON public.stock_movements
    FOR SELECT TO authenticated USING (is_business_member(business_id));

DROP POLICY IF EXISTS "Members can insert stock movements" ON public.stock_movements;
CREATE POLICY "Members can insert stock movements" ON public.stock_movements
    FOR INSERT TO authenticated WITH CHECK (is_business_member(business_id));

-- Stock Transactions Policies (Web PWA)
DROP POLICY IF EXISTS "Transactions viewable by authenticated" ON public.stock_transactions;
CREATE POLICY "Transactions viewable by authenticated" ON public.stock_transactions
    FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Transactions insertable by performer" ON public.stock_transactions;
CREATE POLICY "Transactions insertable by performer" ON public.stock_transactions
    FOR INSERT TO authenticated WITH CHECK (performed_by = (select auth.uid()));

-- Product Costs Policies (Restricted to Owner/Manager)
DROP POLICY IF EXISTS "Owners and Managers can read product costs" ON public.product_costs;
CREATE POLICY "Owners and Managers can read product costs" ON public.product_costs
    FOR SELECT TO authenticated USING (is_owner_or_manager(business_id));

DROP POLICY IF EXISTS "Owners and Managers can modify product costs" ON public.product_costs;
CREATE POLICY "Owners and Managers can modify product costs" ON public.product_costs
    FOR ALL TO authenticated USING (is_owner_or_manager(business_id));

-- Health Check Policies (Anon and Authenticated for keepalive)
DROP POLICY IF EXISTS "Anyone can read health check" ON public.health_check;
CREATE POLICY "Anyone can read health check" ON public.health_check
    FOR SELECT TO anon, authenticated USING (true);

-- 18. POSTGREST API GRANTS
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_stock_mutation TO authenticated;
