-- =========================================================================
-- TZIONSTOCKLY COMPLETE MASTER SCHEMA (MULTI-TENANT SAAS EDITION)
-- Production PostgreSQL 15+ DDL for Supabase
-- Fully idempotent: Multi-store partitioning, tenant isolation, and strict RLS.
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

-- 4. STORE CODE GENERATOR (e.g. TZ-7K9A2)
CREATE OR REPLACE FUNCTION public.generate_store_code()
RETURNS TEXT AS $$
DECLARE
    chars TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    result TEXT := 'TZ-';
    i INTEGER;
BEGIN
    FOR i IN 1..5 LOOP
        result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
    END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql VOLATILE;

-- 5. BUSINESSES (STORES) TABLE
CREATE TABLE IF NOT EXISTS public.businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL DEFAULT 'Tzion Stockly Shop',
    store_code TEXT UNIQUE,
    currency TEXT NOT NULL DEFAULT 'TZS',
    phone TEXT,
    address TEXT,
    tin_number TEXT,
    subscription_tier TEXT NOT NULL DEFAULT 'free',
    created_by UUID REFERENCES auth.users(id),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS store_code TEXT UNIQUE;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS tin_number TEXT;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS subscription_tier TEXT NOT NULL DEFAULT 'free';
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id);

DROP TRIGGER IF EXISTS trg_businesses_updated_at ON public.businesses;
CREATE TRIGGER trg_businesses_updated_at
    BEFORE INSERT OR UPDATE ON public.businesses
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_businesses_updated ON public.businesses(updated_at);
CREATE INDEX IF NOT EXISTS idx_businesses_code ON public.businesses(store_code);

-- Seed default local business matching Flutter DatabaseService.defaultBusinessId
INSERT INTO public.businesses (id, name, store_code, currency)
VALUES ('00000000-0000-0000-0000-000000000001', 'Tzion Stockly Main', 'TZ-MAIN', 'TZS')
ON CONFLICT (id) DO UPDATE SET store_code = COALESCE(public.businesses.store_code, 'TZ-MAIN');

UPDATE public.businesses SET store_code = public.generate_store_code() WHERE store_code IS NULL;

-- 6. BUSINESS MEMBERS (Store Memberships & Multi-Store Owners)
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
CREATE INDEX IF NOT EXISTS idx_business_members_biz ON public.business_members(business_id);

-- 7. STORE INVITATIONS (Cashier / Staff Onboarding via Join Codes)
CREATE TABLE IF NOT EXISTS public.store_invitations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    invite_code TEXT NOT NULL UNIQUE,
    role TEXT NOT NULL DEFAULT 'staff' CHECK (role IN ('manager', 'staff')),
    invited_email TEXT,
    invited_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    max_uses INTEGER NOT NULL DEFAULT 1,
    uses_count INTEGER NOT NULL DEFAULT 0,
    expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_store_invitations_code ON public.store_invitations(invite_code);
CREATE INDEX IF NOT EXISTS idx_store_invitations_biz ON public.store_invitations(business_id);

-- 8. USER PROFILES TABLE (Queried by Flutter & Web clients)
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

-- 9. PROFILES TABLE (Dual-write compatibility)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'staff',
    phone_number TEXT,
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW()),
    updated_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW())
);

-- 10. AUTO-SYNC TRIGGER FROM auth.users
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger AS $$
DECLARE
    user_role_val TEXT;
    user_name_val TEXT;
    user_phone_val TEXT;
    default_biz_id UUID := '00000000-0000-0000-0000-000000000001'::UUID;
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
    VALUES (NEW.id, COALESCE(NEW.email, ''), default_biz_id, user_role_val, user_name_val, user_phone_val, NOW(), NOW())
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
        phone_number = COALESCE(EXCLUDED.phone_number, public.profiles.phone_number);

    -- 3. Default business membership
    INSERT INTO public.business_members (user_id, business_id, role)
    VALUES (
        NEW.id,
        default_biz_id,
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

-- 11. CATEGORIES TABLE (Partitioned by Store)
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

-- 12. PRODUCTS CATALOG TABLE (Partitioned by Store)
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

-- Unique SKU per store (Multi-Tenant SaaS)
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_sku_key;
DROP INDEX IF EXISTS idx_products_sku;
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_biz_sku
    ON public.products(business_id, sku)
    WHERE deleted_at IS NULL AND sku IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_products_biz_updated ON public.products(business_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_products_biz_barcode ON public.products(business_id, barcode) WHERE deleted_at IS NULL;

DROP TRIGGER IF EXISTS trg_products_updated_at ON public.products;
CREATE TRIGGER trg_products_updated_at
    BEFORE INSERT OR UPDATE ON public.products
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- 13. PARTNERS TABLE (Partitioned by Store)
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

-- 14. STOCK MOVEMENTS (Partitioned by Store)
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

-- 15. STOCK TRANSACTIONS (Partitioned by Store)
CREATE TABLE IF NOT EXISTS public.stock_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    performed_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    type transaction_type NOT NULL,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    unit_price_tzs NUMERIC(12, 2) NOT NULL,
    notes TEXT,
    device_created_at TIMESTAMPTZ NOT NULL,
    synced_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW())
);

ALTER TABLE public.stock_transactions ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_transactions_biz_id ON public.stock_transactions(business_id);
CREATE INDEX IF NOT EXISTS idx_transactions_product_id ON public.stock_transactions(product_id);
CREATE INDEX IF NOT EXISTS idx_transactions_device_time ON public.stock_transactions(device_created_at);

-- 16. PRODUCT COSTS TABLE (Owner/Manager role restricted pricing)
CREATE TABLE IF NOT EXISTS public.product_costs (
    product_id UUID PRIMARY KEY REFERENCES public.products(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    cost_price INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 17. HEALTH CHECK TABLE (Keep-alive pings)
CREATE TABLE IF NOT EXISTS public.health_check (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    status TEXT NOT NULL DEFAULT 'ok',
    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.health_check (id, status)
VALUES ('00000000-0000-0000-0000-000000000001', 'ok')
ON CONFLICT (id) DO NOTHING;

-- 18. TENANT SECURITY DEFINER HELPER FUNCTIONS
CREATE OR REPLACE FUNCTION public.get_auth_business_ids()
RETURNS SETOF UUID AS $$
    SELECT business_id FROM public.business_members
    WHERE user_id = (select auth.uid()) AND deleted_at IS NULL
    UNION
    SELECT business_id FROM public.user_profiles
    WHERE id = (select auth.uid()) AND business_id IS NOT NULL;
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.is_business_member(biz_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.business_members
        WHERE business_id = biz_id
          AND user_id = (select auth.uid())
          AND deleted_at IS NULL
        UNION
        SELECT 1 FROM public.user_profiles
        WHERE business_id = biz_id
          AND id = (select auth.uid())
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

CREATE OR REPLACE FUNCTION public.is_business_owner_or_manager(biz_id UUID)
RETURNS BOOLEAN AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.business_members
        WHERE business_id = biz_id
          AND user_id = (select auth.uid())
          AND role IN ('owner', 'manager')
          AND deleted_at IS NULL
        UNION
        SELECT 1 FROM public.user_profiles
        WHERE business_id = biz_id
          AND id = (select auth.uid())
          AND role IN ('owner', 'manager', 'admin')
    );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- 19. MULTI-TENANT STORE MANAGEMENT PROCEDURES
-- A. Create New Store
CREATE OR REPLACE FUNCTION public.create_new_store(
    p_name TEXT,
    p_currency TEXT DEFAULT 'TZS',
    p_phone TEXT DEFAULT NULL,
    p_address TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    new_biz_id UUID;
    generated_code TEXT;
    result JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required to create a store.';
    END IF;

    generated_code := public.generate_store_code();

    INSERT INTO public.businesses (name, currency, phone, address, store_code, created_by)
    VALUES (p_name, COALESCE(p_currency, 'TZS'), p_phone, p_address, generated_code, auth.uid())
    RETURNING id INTO new_biz_id;

    INSERT INTO public.business_members (user_id, business_id, role)
    VALUES (auth.uid(), new_biz_id, 'owner')
    ON CONFLICT (user_id, business_id) DO UPDATE SET role = 'owner';

    UPDATE public.user_profiles
    SET business_id = new_biz_id,
        role = 'owner',
        updated_at = NOW()
    WHERE id = auth.uid();

    INSERT INTO public.categories (business_id, name)
    VALUES 
        (new_biz_id, 'General'),
        (new_biz_id, 'Beverages'),
        (new_biz_id, 'Groceries'),
        (new_biz_id, 'Electronics')
    ON CONFLICT DO NOTHING;

    SELECT jsonb_build_object(
        'id', new_biz_id,
        'name', p_name,
        'currency', COALESCE(p_currency, 'TZS'),
        'store_code', generated_code,
        'role', 'owner'
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- B. Join Store by Code
CREATE OR REPLACE FUNCTION public.join_store_by_code(
    p_code TEXT
)
RETURNS JSONB AS $$
DECLARE
    target_biz_id UUID;
    target_biz_name TEXT;
    assigned_role TEXT := 'staff';
    inv_id UUID;
    result JSONB;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required to join a store.';
    END IF;

    SELECT id, name INTO target_biz_id, target_biz_name
    FROM public.businesses
    WHERE UPPER(store_code) = UPPER(TRIM(p_code)) AND deleted_at IS NULL;

    IF target_biz_id IS NULL THEN
        SELECT si.id, si.business_id, b.name, si.role
        INTO inv_id, target_biz_id, target_biz_name, assigned_role
        FROM public.store_invitations si
        JOIN public.businesses b ON b.id = si.business_id
        WHERE UPPER(si.invite_code) = UPPER(TRIM(p_code))
          AND si.expires_at > NOW()
          AND si.uses_count < si.max_uses
        LIMIT 1;

        IF target_biz_id IS NOT NULL THEN
            UPDATE public.store_invitations
            SET uses_count = uses_count + 1
            WHERE id = inv_id;
        END IF;
    END IF;

    IF target_biz_id IS NULL THEN
        RAISE EXCEPTION 'Invalid or expired store code: %', p_code;
    END IF;

    INSERT INTO public.business_members (user_id, business_id, role)
    VALUES (auth.uid(), target_biz_id, assigned_role)
    ON CONFLICT (user_id, business_id) DO UPDATE SET role = EXCLUDED.role;

    UPDATE public.user_profiles
    SET business_id = target_biz_id,
        role = assigned_role,
        updated_at = NOW()
    WHERE id = auth.uid();

    SELECT jsonb_build_object(
        'business_id', target_biz_id,
        'business_name', target_biz_name,
        'role', assigned_role,
        'status', 'SUCCESS'
    ) INTO result;

    RETURN result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- C. Switch Active Store
CREATE OR REPLACE FUNCTION public.switch_active_store(
    p_business_id UUID
)
RETURNS JSONB AS $$
DECLARE
    user_role_val TEXT;
    biz_name TEXT;
BEGIN
    SELECT bm.role, b.name INTO user_role_val, biz_name
    FROM public.business_members bm
    JOIN public.businesses b ON b.id = bm.business_id
    WHERE bm.business_id = p_business_id
      AND bm.user_id = auth.uid()
      AND bm.deleted_at IS NULL;

    IF user_role_val IS NULL THEN
        RAISE EXCEPTION 'Access Denied: You are not a member of this store.';
    END IF;

    UPDATE public.user_profiles
    SET business_id = p_business_id,
        role = user_role_val,
        updated_at = NOW()
    WHERE id = auth.uid();

    RETURN jsonb_build_object(
        'active_business_id', p_business_id,
        'business_name', biz_name,
        'role', user_role_val
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- D. Atomic Stock Adjustment (With Multi-Tenant Enforcement)
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
    prod_biz_id UUID;
    user_biz_role TEXT;
BEGIN
    -- 1. Get product tenant
    SELECT business_id INTO prod_biz_id
    FROM public.products
    WHERE id = p_product_id;

    IF prod_biz_id IS NULL THEN
        RAISE EXCEPTION 'Product not found.';
    END IF;

    -- 2. Verify caller membership in the product's store
    SELECT role INTO user_biz_role
    FROM public.business_members
    WHERE business_id = prod_biz_id AND user_id = p_user_id AND deleted_at IS NULL;

    IF user_biz_role IS NULL THEN
        SELECT role INTO user_biz_role
        FROM public.user_profiles
        WHERE business_id = prod_biz_id AND id = p_user_id;
    END IF;

    IF user_biz_role IS NULL THEN
        RAISE EXCEPTION 'Security Violation: User does not belong to this store.';
    END IF;

    -- 3. Check-In requires Owner or Manager
    IF p_type = 'CHECK_IN' THEN
        IF user_biz_role NOT IN ('owner', 'manager', 'admin') THEN
            RAISE EXCEPTION 'Access Denied: Only Store Owners and Managers can perform stock Check-In.';
        END IF;

        UPDATE public.products
        SET stock_quantity = stock_quantity + p_quantity,
            updated_at = NOW()
        WHERE id = p_product_id;
    ELSE
        -- CHECK_OUT: Allowed for Staff, Manager, and Owner
        IF (SELECT stock_quantity FROM public.products WHERE id = p_product_id) < p_quantity THEN
            RAISE EXCEPTION 'Insufficient stock quantity available.';
        END IF;

        UPDATE public.products
        SET stock_quantity = stock_quantity - p_quantity,
            updated_at = NOW()
        WHERE id = p_product_id;
    END IF;

    -- 4. Record transaction with explicit business_id partitioning
    INSERT INTO public.stock_transactions (
        product_id, business_id, performed_by, type, quantity, unit_price_tzs, notes, device_created_at
    ) VALUES (
        p_product_id, prod_biz_id, p_user_id, p_type, p_quantity, p_unit_price_tzs, p_notes, p_device_created_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 20. ROW LEVEL SECURITY (RLS) POLICIES - ZERO TENANT LEAKAGE
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
ALTER TABLE public.store_invitations ENABLE ROW LEVEL SECURITY;

-- Businesses Policies
DROP POLICY IF EXISTS "Members can view their business" ON public.businesses;
CREATE POLICY "Members can view their business" ON public.businesses
    FOR SELECT TO authenticated
    USING (public.is_business_member(id) OR id = '00000000-0000-0000-0000-000000000001');

DROP POLICY IF EXISTS "Members can update their business" ON public.businesses;
CREATE POLICY "Members can update their business" ON public.businesses
    FOR UPDATE TO authenticated
    USING (public.is_business_owner_or_manager(id));

DROP POLICY IF EXISTS "Authenticated can insert business" ON public.businesses;
CREATE POLICY "Authenticated can insert business" ON public.businesses
    FOR INSERT TO authenticated WITH CHECK (true);

-- Business Members Policies
DROP POLICY IF EXISTS "Users can view memberships" ON public.business_members;
CREATE POLICY "Users can view memberships" ON public.business_members
    FOR SELECT TO authenticated
    USING (user_id = (select auth.uid()) OR public.is_business_owner_or_manager(business_id));

DROP POLICY IF EXISTS "Users can insert membership" ON public.business_members;
CREATE POLICY "Users can insert membership" ON public.business_members
    FOR INSERT TO authenticated
    WITH CHECK (user_id = (select auth.uid()) OR public.is_business_owner_or_manager(business_id));

DROP POLICY IF EXISTS "Owners can update membership" ON public.business_members;
CREATE POLICY "Owners can update membership" ON public.business_members
    FOR UPDATE TO authenticated
    USING (public.is_business_owner_or_manager(business_id));

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

-- Categories Policies: Strict store isolation
DROP POLICY IF EXISTS "Members can view categories" ON public.categories;
CREATE POLICY "Members can view categories" ON public.categories
    FOR SELECT TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

DROP POLICY IF EXISTS "Members can insert categories" ON public.categories;
CREATE POLICY "Members can insert categories" ON public.categories
    FOR INSERT TO authenticated
    WITH CHECK (business_id IS NOT NULL AND public.is_business_member(business_id));

DROP POLICY IF EXISTS "Members can update categories" ON public.categories;
CREATE POLICY "Members can update categories" ON public.categories
    FOR UPDATE TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

-- Products Policies: Strict store isolation
DROP POLICY IF EXISTS "Products viewable by authenticated" ON public.products;
CREATE POLICY "Products viewable by authenticated" ON public.products
    FOR SELECT TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

DROP POLICY IF EXISTS "Products mutable by business member" ON public.products;
CREATE POLICY "Products mutable by business member" ON public.products
    FOR ALL TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

-- Partners Policies: Strict store isolation
DROP POLICY IF EXISTS "Members can view partners" ON public.partners;
CREATE POLICY "Members can view partners" ON public.partners
    FOR SELECT TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

DROP POLICY IF EXISTS "Members can insert partners" ON public.partners;
CREATE POLICY "Members can insert partners" ON public.partners
    FOR INSERT TO authenticated
    WITH CHECK (business_id IS NOT NULL AND public.is_business_member(business_id));

DROP POLICY IF EXISTS "Members can update partners" ON public.partners;
CREATE POLICY "Members can update partners" ON public.partners
    FOR UPDATE TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

-- Stock Movements Policies (Append-only, strict store isolation)
DROP POLICY IF EXISTS "Members can view stock movements" ON public.stock_movements;
CREATE POLICY "Members can view stock movements" ON public.stock_movements
    FOR SELECT TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

DROP POLICY IF EXISTS "Members can insert stock movements" ON public.stock_movements;
CREATE POLICY "Members can insert stock movements" ON public.stock_movements
    FOR INSERT TO authenticated
    WITH CHECK (business_id IS NOT NULL AND public.is_business_member(business_id));

-- Stock Transactions Policies (Strict store isolation)
DROP POLICY IF EXISTS "Transactions viewable by authenticated" ON public.stock_transactions;
CREATE POLICY "Transactions viewable by authenticated" ON public.stock_transactions
    FOR SELECT TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

DROP POLICY IF EXISTS "Transactions insertable by performer" ON public.stock_transactions;
CREATE POLICY "Transactions insertable by performer" ON public.stock_transactions
    FOR INSERT TO authenticated
    WITH CHECK (
        business_id IS NOT NULL 
        AND public.is_business_member(business_id)
        AND performed_by = (select auth.uid())
    );

-- Product Costs Policies (Strictly Owner/Manager of this store)
DROP POLICY IF EXISTS "Owners and Managers can read product costs" ON public.product_costs;
CREATE POLICY "Owners and Managers can read product costs" ON public.product_costs
    FOR SELECT TO authenticated USING (public.is_business_owner_or_manager(business_id));

DROP POLICY IF EXISTS "Owners and Managers can modify product costs" ON public.product_costs;
CREATE POLICY "Owners and Managers can modify product costs" ON public.product_costs
    FOR ALL TO authenticated USING (public.is_business_owner_or_manager(business_id));

-- Store Invitations Policies
DROP POLICY IF EXISTS "Owners can manage invitations" ON public.store_invitations;
CREATE POLICY "Owners can manage invitations" ON public.store_invitations
    FOR ALL TO authenticated USING (public.is_business_owner_or_manager(business_id));

DROP POLICY IF EXISTS "Anyone can verify invite code" ON public.store_invitations;
CREATE POLICY "Anyone can verify invite code" ON public.store_invitations
    FOR SELECT TO authenticated USING (true);

-- Health Check Policies
DROP POLICY IF EXISTS "Anyone can read health check" ON public.health_check;
CREATE POLICY "Anyone can read health check" ON public.health_check
    FOR SELECT TO anon, authenticated USING (true);

-- 21. POSTGREST API GRANTS
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT EXECUTE ON FUNCTION public.generate_store_code TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_new_store TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_store_by_code TO authenticated;
GRANT EXECUTE ON FUNCTION public.switch_active_store TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_stock_mutation TO authenticated;
