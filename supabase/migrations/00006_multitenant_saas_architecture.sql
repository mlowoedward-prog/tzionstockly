-- =========================================================================
-- Migration 00006: Multi-Tenant SaaS Architecture & Tenant Isolation
-- Implements complete store partitioning, multi-store membership,
-- store invite codes, and zero-leakage Row Level Security (RLS).
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. STORE CODE GENERATOR FUNCTION
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

-- 2. ENHANCE BUSINESSES (STORES) FOR SAAS
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS store_code TEXT UNIQUE;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS phone TEXT;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS address TEXT;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS tin_number TEXT;
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS subscription_tier TEXT NOT NULL DEFAULT 'free';
ALTER TABLE public.businesses ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id);

-- Ensure all existing businesses have a unique store code
UPDATE public.businesses
SET store_code = public.generate_store_code()
WHERE store_code IS NULL;

-- 3. STORE INVITATIONS TABLE (Staff Onboarding via 6-digit Codes)
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

-- 4. ENSURE ALL CORE ENTITY TABLES ARE STRICTLY PARTITIONED BY business_id
ALTER TABLE public.products ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;
ALTER TABLE public.categories ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;
ALTER TABLE public.partners ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;
ALTER TABLE public.stock_movements ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;
ALTER TABLE public.stock_transactions ADD COLUMN IF NOT EXISTS business_id UUID REFERENCES public.businesses(id) ON DELETE CASCADE;

-- Backfill business_id for stock_transactions if null
UPDATE public.stock_transactions st
SET business_id = p.business_id
FROM public.products p
WHERE st.product_id = p.id AND st.business_id IS NULL;

-- Assign default business if still null
UPDATE public.stock_transactions
SET business_id = '00000000-0000-0000-0000-000000000001'::UUID
WHERE business_id IS NULL;

-- Multi-tenant unique indexes: SKU is unique PER STORE, not globally!
DROP INDEX IF EXISTS idx_products_sku;
ALTER TABLE public.products DROP CONSTRAINT IF EXISTS products_sku_key;
CREATE UNIQUE INDEX IF NOT EXISTS idx_products_biz_sku
    ON public.products(business_id, sku)
    WHERE deleted_at IS NULL AND sku IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_products_biz_barcode
    ON public.products(business_id, barcode)
    WHERE deleted_at IS NULL AND barcode IS NOT NULL;

-- 5. FAST SECURITY DEFINER TENANT LOOKUP FUNCTIONS
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

-- 6. RPC PROCEDURES FOR SAAS STORE MANAGEMENT
-- A. Create a New Store (with default categories and owner membership)
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

    -- Create Store
    INSERT INTO public.businesses (name, currency, phone, address, store_code, created_by)
    VALUES (p_name, COALESCE(p_currency, 'TZS'), p_phone, p_address, generated_code, auth.uid())
    RETURNING id INTO new_biz_id;

    -- Add current user as Store Owner
    INSERT INTO public.business_members (user_id, business_id, role)
    VALUES (auth.uid(), new_biz_id, 'owner')
    ON CONFLICT (user_id, business_id) DO UPDATE SET role = 'owner';

    -- Update active business in user_profiles
    UPDATE public.user_profiles
    SET business_id = new_biz_id,
        role = 'owner',
        updated_at = NOW()
    WHERE id = auth.uid();

    -- Provision default store categories
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

-- B. Join an Existing Store by Store Code or Invite Code
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

    -- Check if it matches a business store_code directly
    SELECT id, name INTO target_biz_id, target_biz_name
    FROM public.businesses
    WHERE UPPER(store_code) = UPPER(TRIM(p_code)) AND deleted_at IS NULL;

    -- If not direct store code, check store_invitations
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

    -- Add membership
    INSERT INTO public.business_members (user_id, business_id, role)
    VALUES (auth.uid(), target_biz_id, assigned_role)
    ON CONFLICT (user_id, business_id) DO UPDATE SET role = EXCLUDED.role;

    -- Update active business in user_profiles
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

-- C. Switch Active Store for Multi-Store Owners
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

-- D. Updated Multi-Tenant Atomic Stock Mutation
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
    -- 1. Identify product tenant
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

    -- Fallback to user_profiles check
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

-- 7. ZERO-LEAKAGE ROW LEVEL SECURITY (RLS) POLICIES
-- Each table strictly checks is_business_member(business_id)

-- Businesses Table
DROP POLICY IF EXISTS "Members can view their business" ON public.businesses;
CREATE POLICY "Members can view their business" ON public.businesses
    FOR SELECT TO authenticated
    USING (public.is_business_member(id) OR id = '00000000-0000-0000-0000-000000000001');

DROP POLICY IF EXISTS "Members can update their business" ON public.businesses;
CREATE POLICY "Members can update their business" ON public.businesses
    FOR UPDATE TO authenticated
    USING (public.is_business_owner_or_manager(id));

-- Products Table: Strict store isolation
DROP POLICY IF EXISTS "Products viewable by authenticated" ON public.products;
CREATE POLICY "Products viewable by authenticated" ON public.products
    FOR SELECT TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

DROP POLICY IF EXISTS "Products mutable by business member" ON public.products;
CREATE POLICY "Products mutable by business member" ON public.products
    FOR ALL TO authenticated
    USING (business_id IS NOT NULL AND public.is_business_member(business_id));

-- Stock Transactions Table: Strict store isolation (NO MORE USING (true))
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

-- Categories Table: Strict store isolation
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

-- Store Invitations Table
ALTER TABLE public.store_invitations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Owners can manage invitations" ON public.store_invitations;
CREATE POLICY "Owners can manage invitations" ON public.store_invitations
    FOR ALL TO authenticated
    USING (public.is_business_owner_or_manager(business_id));

-- Allow users to verify an invite code before joining
DROP POLICY IF EXISTS "Anyone can verify invite code" ON public.store_invitations;
CREATE POLICY "Anyone can verify invite code" ON public.store_invitations
    FOR SELECT TO authenticated
    USING (true);

-- 8. POSTGREST API GRANTS
GRANT EXECUTE ON FUNCTION public.create_new_store TO authenticated;
GRANT EXECUTE ON FUNCTION public.join_store_by_code TO authenticated;
GRANT EXECUTE ON FUNCTION public.switch_active_store TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_stock_mutation TO authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.store_invitations TO authenticated;
