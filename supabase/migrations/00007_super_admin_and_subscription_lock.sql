-- =============================================================================
-- Migration: 00007_super_admin_and_subscription_lock.sql
-- Description: Super Admin Multi-Store Management, Subscription Status Enum,
--              Store Payment Locks, Grace Period Enforcement & Stock Mutation Guard.
-- =============================================================================

-- Enable uuid generator if not already active
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. Subscription status enum
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'subscription_status') THEN
        CREATE TYPE subscription_status AS ENUM ('trial', 'active', 'past_due', 'suspended');
    END IF;
END $$;

-- 2. Stores (tenants) table
CREATE TABLE IF NOT EXISTS public.stores (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    owner_name TEXT NOT NULL,
    owner_phone TEXT NOT NULL,
    monthly_fee_tzs NUMERIC(12, 2) NOT NULL DEFAULT 50000.00,
    status subscription_status NOT NULL DEFAULT 'trial',
    subscription_renews_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '30 days'),
    grace_period_days INTEGER NOT NULL DEFAULT 3,
    is_locked BOOLEAN NOT NULL DEFAULT false,
    lock_reason TEXT DEFAULT 'Monthly subscription payment overdue',
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW())
);

-- Ensure public.profiles table exists before adding foreign keys
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT,
    full_name TEXT,
    role TEXT NOT NULL DEFAULT 'staff',
    created_at TIMESTAMPTZ DEFAULT TIMEZONE('utc', NOW())
);

-- 3. Add foreign keys to existing tables
ALTER TABLE public.profiles 
    ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES public.stores(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS is_super_admin BOOLEAN DEFAULT false;

-- Support user_profiles table if present in multi-tenant setup
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_profiles') THEN
        ALTER TABLE public.user_profiles 
            ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES public.stores(id) ON DELETE CASCADE,
            ADD COLUMN IF NOT EXISTS is_super_admin BOOLEAN DEFAULT false;
    END IF;
END $$;

ALTER TABLE public.products 
    ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES public.stores(id) ON DELETE CASCADE;

ALTER TABLE public.stock_transactions 
    ADD COLUMN IF NOT EXISTS store_id UUID REFERENCES public.stores(id) ON DELETE CASCADE;

-- 4. Backfill existing store accounts with a default active store record
-- Guardrail: Ensure all existing accounts are active so no users are locked out upon deployment
DO $$
DECLARE
    default_store_id UUID;
    biz_rec RECORD;
BEGIN
    -- Check if legacy businesses exist and migrate them to stores
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'businesses') THEN
        FOR biz_rec IN SELECT id, name, phone FROM public.businesses LOOP
            IF NOT EXISTS (SELECT 1 FROM public.stores WHERE id = biz_rec.id) THEN
                INSERT INTO public.stores (
                    id, name, owner_name, owner_phone, monthly_fee_tzs, status,
                    subscription_renews_at, grace_period_days, is_locked, lock_reason
                ) VALUES (
                    biz_rec.id,
                    COALESCE(biz_rec.name, 'Tzion Main Store'),
                    'Store Owner',
                    COALESCE(biz_rec.phone, '+255755123456'),
                    50000.00,
                    'active',
                    NOW() + INTERVAL '30 days',
                    3,
                    false,
                    NULL
                );
            END IF;
        END LOOP;
    END IF;

    -- Ensure at least one flagship active store exists
    SELECT id INTO default_store_id FROM public.stores ORDER BY created_at ASC LIMIT 1;
    IF default_store_id IS NULL THEN
        INSERT INTO public.stores (
            id, name, owner_name, owner_phone, monthly_fee_tzs, status,
            subscription_renews_at, grace_period_days, is_locked, lock_reason
        ) VALUES (
            gen_random_uuid(),
            'Tzion Main Flagship Store',
            'Edward Mlowo',
            '+255755123456',
            50000.00,
            'active',
            NOW() + INTERVAL '30 days',
            3,
            false,
            NULL
        ) RETURNING id INTO default_store_id;
    END IF;

    -- Backfill products store_id
    UPDATE public.products 
    SET store_id = default_store_id
    WHERE store_id IS NULL;

    -- Backfill stock transactions store_id
    UPDATE public.stock_transactions 
    SET store_id = default_store_id
    WHERE store_id IS NULL;

    -- Backfill profiles store_id and assign Super Admin clearance
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
        UPDATE public.profiles 
        SET store_id = default_store_id 
        WHERE store_id IS NULL;

        -- Promote admin profiles to Super Admin
        UPDATE public.profiles 
        SET is_super_admin = true 
        WHERE role = 'admin' OR id IN (SELECT id FROM public.profiles LIMIT 1);
    END IF;

    -- Backfill user_profiles store_id and assign Super Admin clearance
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_profiles') THEN
        UPDATE public.user_profiles 
        SET store_id = default_store_id 
        WHERE store_id IS NULL;

        UPDATE public.user_profiles 
        SET is_super_admin = true 
        WHERE role IN ('admin', 'owner') OR id IN (SELECT id FROM public.user_profiles LIMIT 1);
    END IF;
END $$;

-- 5. Subscription check inside stock mutation RPC
-- Guard condition checks if the store is suspended or locked due to unpaid subscription fees.
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
    target_store_id UUID;
    prod_biz_id UUID;
    user_role TEXT;
    is_admin_user BOOLEAN := FALSE;
BEGIN
    -- 1. Identify the store associated with the product
    SELECT COALESCE(store_id, business_id) INTO target_store_id
    FROM public.products
    WHERE id = p_product_id;

    IF target_store_id IS NULL THEN
        -- Fallback to default flagship store if not linked
        SELECT id INTO target_store_id FROM public.stores ORDER BY created_at ASC LIMIT 1;
    END IF;

    -- 2. SUBSCRIPTION PAYMENT LOCK & GRACE PERIOD ENFORCEMENT
    IF target_store_id IS NOT NULL AND EXISTS (
        SELECT 1 FROM public.stores 
        WHERE id = target_store_id AND (status = 'suspended' OR is_locked = true)
    ) THEN
        RAISE EXCEPTION 'Account Suspended: Subscription payment required to record transactions.';
    END IF;

    -- 3. Verify user authorization
    IF EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND (role IN ('admin', 'owner') OR is_super_admin = true)) THEN
        is_admin_user := TRUE;
    ELSIF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_profiles') THEN
        IF EXISTS (SELECT 1 FROM public.user_profiles WHERE id = p_user_id AND (role IN ('admin', 'owner') OR is_super_admin = true)) THEN
            is_admin_user := TRUE;
        END IF;
    END IF;

    -- 4. Apply inventory adjustment
    IF p_type = 'CHECK_IN' THEN
        IF NOT is_admin_user THEN
            RAISE EXCEPTION 'Access Denied: Only Store Admins can perform stock Check-In.';
        END IF;

        UPDATE public.products
        SET stock_quantity = stock_quantity + p_quantity,
            updated_at = NOW()
        WHERE id = p_product_id;
    ELSE
        -- CHECK_OUT (Both Staff and Admin can record sales)
        IF (SELECT stock_quantity FROM public.products WHERE id = p_product_id) < p_quantity THEN
            RAISE EXCEPTION 'Insufficient stock quantity available.';
        END IF;

        UPDATE public.products
        SET stock_quantity = stock_quantity - p_quantity,
            updated_at = NOW()
        WHERE id = p_product_id;
    END IF;

    -- 5. Record immutable audit transaction
    INSERT INTO public.stock_transactions (
        product_id, store_id, performed_by, type, quantity, unit_price_tzs, notes, device_created_at
    ) VALUES (
        p_product_id, target_store_id, p_user_id, p_type, p_quantity, p_unit_price_tzs, p_notes, p_device_created_at
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Super Admin Helper Procedures
-- 6a. 1-Click Store Lock / Unlock
CREATE OR REPLACE FUNCTION public.toggle_store_lock(
    p_store_id UUID,
    p_is_locked BOOLEAN,
    p_lock_reason TEXT DEFAULT 'Monthly subscription payment overdue'
) RETURNS JSONB AS $$
DECLARE
    new_status subscription_status;
BEGIN
    IF p_is_locked THEN
        new_status := 'suspended';
    ELSE
        new_status := 'active';
    END IF;

    UPDATE public.stores
    SET is_locked = p_is_locked,
        status = new_status,
        lock_reason = CASE WHEN p_is_locked THEN p_lock_reason ELSE NULL END
    WHERE id = p_store_id;

    RETURN jsonb_build_object(
        'success', true,
        'store_id', p_store_id,
        'is_locked', p_is_locked,
        'status', new_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6b. Extend Grace Period (+3 Days / +7 Days)
CREATE OR REPLACE FUNCTION public.extend_store_grace_period(
    p_store_id UUID,
    p_days INTEGER
) RETURNS JSONB AS $$
DECLARE
    new_renewal TIMESTAMPTZ;
BEGIN
    UPDATE public.stores
    SET subscription_renews_at = GREATEST(subscription_renews_at, NOW()) + (p_days || ' days')::INTERVAL,
        is_locked = false,
        status = 'active',
        lock_reason = NULL
    WHERE id = p_store_id
    RETURNING subscription_renews_at INTO new_renewal;

    RETURN jsonb_build_object(
        'success', true,
        'store_id', p_store_id,
        'new_renewal_date', new_renewal,
        'is_locked', false,
        'status', 'active'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- 6d. Update Store Details, Owner, Phone & Monthly Fee
CREATE OR REPLACE FUNCTION public.update_store_details(
    p_store_id UUID,
    p_name TEXT,
    p_owner_name TEXT,
    p_owner_phone TEXT,
    p_monthly_fee_tzs NUMERIC,
    p_grace_period_days INTEGER DEFAULT 3,
    p_status subscription_status DEFAULT 'active',
    p_is_locked BOOLEAN DEFAULT false
) RETURNS JSONB AS $
BEGIN
    UPDATE public.stores
    SET name = p_name,
        owner_name = p_owner_name,
        owner_phone = p_owner_phone,
        monthly_fee_tzs = p_monthly_fee_tzs,
        grace_period_days = p_grace_period_days,
        status = p_status,
        is_locked = p_is_locked,
        lock_reason = CASE WHEN p_is_locked THEN 'Monthly subscription payment overdue' ELSE NULL END
    WHERE id = p_store_id;

    RETURN jsonb_build_object(
        'success', true,
        'store_id', p_store_id,
        'name', p_name,
        'monthly_fee_tzs', p_monthly_fee_tzs,
        'status', p_status
    );
END;
$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6c. Manually Set Custom Store Renewal Date
CREATE OR REPLACE FUNCTION public.set_store_renewal_date(
    p_store_id UUID,
    p_new_date TIMESTAMPTZ
) RETURNS JSONB AS $$
DECLARE
    v_is_future BOOLEAN;
    v_status subscription_status;
BEGIN
    v_is_future := (p_new_date > NOW());
    IF v_is_future THEN
        v_status := 'active';
    ELSE
        v_status := 'past_due';
    END IF;

    UPDATE public.stores
    SET subscription_renews_at = p_new_date,
        is_locked = CASE WHEN v_is_future THEN false ELSE is_locked END,
        status = v_status,
        lock_reason = CASE WHEN v_is_future THEN NULL ELSE lock_reason END
    WHERE id = p_store_id;

    RETURN jsonb_build_object(
        'success', true,
        'store_id', p_store_id,
        'new_renewal_date', p_new_date,
        'status', v_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6c. Super Admin Multi-Store Metrics
CREATE OR REPLACE FUNCTION public.get_super_admin_metrics()
RETURNS JSONB AS $$
DECLARE
    v_total INTEGER;
    v_active INTEGER;
    v_past_due INTEGER;
    v_suspended INTEGER;
    v_mrr NUMERIC(14, 2);
BEGIN
    SELECT 
        COUNT(*),
        COUNT(*) FILTER (WHERE status = 'active' AND is_locked = false),
        COUNT(*) FILTER (WHERE status = 'past_due' OR (NOW() > subscription_renews_at AND NOT is_locked)),
        COUNT(*) FILTER (WHERE status = 'suspended' OR is_locked = true),
        COALESCE(SUM(monthly_fee_tzs) FILTER (WHERE status IN ('active', 'past_due')), 0)
    INTO v_total, v_active, v_past_due, v_suspended, v_mrr
    FROM public.stores;

    RETURN jsonb_build_object(
        'total_stores', v_total,
        'active_stores', v_active,
        'past_due_stores', v_past_due,
        'suspended_stores', v_suspended,
        'mrr_tzs', v_mrr
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Row Level Security for Stores & Profiles
ALTER TABLE public.stores ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any to allow safe re-runs
DROP POLICY IF EXISTS "Super Admins have full access to stores" ON public.stores;
DROP POLICY IF EXISTS "Store members can read their assigned store" ON public.stores;
DROP POLICY IF EXISTS "Public read stores verification" ON public.stores;

-- Allow Super Admins full access to all stores
CREATE POLICY "Super Admins have full access to stores"
ON public.stores FOR ALL TO authenticated
USING (
    EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND is_super_admin = true)
    OR EXISTS (SELECT 1 FROM public.user_profiles WHERE id = auth.uid() AND is_super_admin = true)
);

-- Allow Store Users to view their assigned store
CREATE POLICY "Store members can read their assigned store"
ON public.stores FOR SELECT TO authenticated
USING (
    id IN (SELECT store_id FROM public.profiles WHERE id = auth.uid())
    OR id IN (SELECT store_id FROM public.user_profiles WHERE id = auth.uid())
);

-- Public fallback read policy for local offline bootstrapping & health checks
CREATE POLICY "Public read stores verification"
ON public.stores FOR SELECT TO anon
USING (true);

-- Grant privileges
GRANT ALL ON TABLE public.stores TO authenticated;
GRANT SELECT ON TABLE public.stores TO anon;
GRANT EXECUTE ON FUNCTION public.process_stock_mutation TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_stock_mutation TO anon;
GRANT EXECUTE ON FUNCTION public.toggle_store_lock TO authenticated;
GRANT EXECUTE ON FUNCTION public.extend_store_grace_period TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_store_renewal_date TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_store_renewal_date TO anon;
GRANT EXECUTE ON FUNCTION public.update_store_details TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_store_details TO anon;
GRANT EXECUTE ON FUNCTION public.get_super_admin_metrics TO authenticated;

