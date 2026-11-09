-- =============================================================================
-- TZIONSTOCKLY: JAWIZA STORE PRODUCTION SEED & SYNC SCRIPT FOR SUPABASE
-- Run this script in your Supabase Project SQL Editor:
-- Dashboard -> SQL Editor -> New Query -> Paste & Run
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

DO $$
DECLARE
    v_business_id UUID := '00000000-0000-0000-0000-000000000001'::UUID;
    v_admin_user_id UUID;
    v_maria_user_id UUID;
    v_cat_unga UUID;
    v_cat_poultry UUID;
    v_cat_appetizer UUID;
BEGIN
    -- -------------------------------------------------------------------------
    -- 1. ENSURE JAWIZA STORE RECORD EXISTS IN businesses & stores
    -- -------------------------------------------------------------------------
    INSERT INTO public.businesses (
        id, name, store_code, currency, phone, address, subscription_tier
    ) VALUES (
        v_business_id,
        'Jawiza',
        'TZ-JAWIZA',
        'TZS',
        '+255755123456',
        'Dar es Salaam, Tanzania',
        'active'
    )
    ON CONFLICT (id) DO UPDATE SET
        name = 'Jawiza',
        phone = '+255755123456',
        address = 'Dar es Salaam, Tanzania',
        subscription_tier = 'active',
        updated_at = NOW();

    -- Also sync with stores table (if migration 00007 is active)
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'stores') THEN
        INSERT INTO public.stores (
            id, name, owner_name, owner_phone, monthly_fee_tzs, status,
            subscription_renews_at, grace_period_days, is_locked, lock_reason
        ) VALUES (
            v_business_id,
            'Jawiza',
            'Jawiza Admin',
            '+255755123456',
            50000.00,
            'active',
            NOW() + INTERVAL '60 days',
            14,
            false,
            NULL
        )
        ON CONFLICT (id) DO UPDATE SET
            name = 'Jawiza',
            owner_name = 'Jawiza Admin',
            owner_phone = '+255755123456',
            status = 'active',
            is_locked = false,
            subscription_renews_at = NOW() + INTERVAL '60 days';
    END IF;

    -- -------------------------------------------------------------------------
    -- 2. CREATE / SYNC AUTH ACCOUNTS: Admin & Maria
    -- -------------------------------------------------------------------------
    -- Check or Insert Admin (admin@jawiza.com / Jawiza@Admin2026)
    SELECT id INTO v_admin_user_id FROM auth.users WHERE email = 'admin@jawiza.com';
    IF v_admin_user_id IS NULL THEN
        v_admin_user_id := uuid_generate_v4();
        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password,
            email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
            created_at, updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            v_admin_user_id,
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
        WHERE id = v_admin_user_id;
    END IF;

    -- Check or Insert Maria (maria@jawiza.com / Maria@Jawiza2026)
    SELECT id INTO v_maria_user_id FROM auth.users WHERE email = 'maria@jawiza.com';
    IF v_maria_user_id IS NULL THEN
        v_maria_user_id := uuid_generate_v4();
        INSERT INTO auth.users (
            instance_id, id, aud, role, email, encrypted_password,
            email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
            created_at, updated_at
        ) VALUES (
            '00000000-0000-0000-0000-000000000000',
            v_maria_user_id,
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
        WHERE id = v_maria_user_id;
    END IF;

    -- -------------------------------------------------------------------------
    -- 3. LINK USERS IN user_profiles, profiles & business_members
    -- -------------------------------------------------------------------------
    -- Admin Profile
    INSERT INTO public.user_profiles (id, email, business_id, role, full_name, created_at, updated_at)
    VALUES (v_admin_user_id, 'admin@jawiza.com', v_business_id, 'owner', 'Jawiza Admin', NOW(), NOW())
    ON CONFLICT (id) DO UPDATE SET
        business_id = v_business_id,
        role = 'owner',
        full_name = 'Jawiza Admin',
        updated_at = NOW();

    INSERT INTO public.profiles (id, full_name, role)
    VALUES (v_admin_user_id, 'Jawiza Admin', 'admin')
    ON CONFLICT (id) DO UPDATE SET
        full_name = 'Jawiza Admin',
        role = 'admin';

    INSERT INTO public.business_members (user_id, business_id, role)
    VALUES (v_admin_user_id, v_business_id, 'owner')
    ON CONFLICT (user_id, business_id) DO UPDATE SET role = 'owner';

    -- Maria Profile
    INSERT INTO public.user_profiles (id, email, business_id, role, full_name, created_at, updated_at)
    VALUES (v_maria_user_id, 'maria@jawiza.com', v_business_id, 'staff', 'Maria', NOW(), NOW())
    ON CONFLICT (id) DO UPDATE SET
        business_id = v_business_id,
        role = 'staff',
        full_name = 'Maria',
        updated_at = NOW();

    INSERT INTO public.profiles (id, full_name, role)
    VALUES (v_maria_user_id, 'Maria', 'staff')
    ON CONFLICT (id) DO UPDATE SET
        full_name = 'Maria',
        role = 'staff';

    INSERT INTO public.business_members (user_id, business_id, role)
    VALUES (v_maria_user_id, v_business_id, 'staff')
    ON CONFLICT (user_id, business_id) DO UPDATE SET role = 'staff';

    -- -------------------------------------------------------------------------
    -- 4. ENSURE CATEGORIES FOR JAWIZA (unga, poultry, appetizer)
    -- -------------------------------------------------------------------------
    INSERT INTO public.categories (id, business_id, name)
    VALUES ('c0000000-0000-0000-0000-000000000001', v_business_id, 'unga')
    ON CONFLICT (id) DO UPDATE SET name = 'unga';

    INSERT INTO public.categories (id, business_id, name)
    VALUES ('c0000000-0000-0000-0000-000000000002', v_business_id, 'poultry')
    ON CONFLICT (id) DO UPDATE SET name = 'poultry';

    INSERT INTO public.categories (id, business_id, name)
    VALUES ('c0000000-0000-0000-0000-000000000003', v_business_id, 'appetizer')
    ON CONFLICT (id) DO UPDATE SET name = 'appetizer';

    -- -------------------------------------------------------------------------
    -- 5. SEED EXACT 7 JAWIZA PRODUCTS INTO public.products
    -- -------------------------------------------------------------------------
    -- 1. mbilimbi
    INSERT INTO public.products (
        id, business_id, name, sku, category, unit,
        cost_price, selling_price, cost_price_tzs, selling_price_tzs,
        stock_quantity, reorder_level, min_threshold
    ) VALUES (
        'p0000000-0000-0000-0000-000000000001', v_business_id, 'mbilimbi', 'APP-MBI-001', 'appetizer', 'fungu',
        1000, 1500, 1000.00, 1500.00,
        50, 10, 10
    ) ON CONFLICT (id) DO UPDATE SET
        name = 'mbilimbi', category = 'appetizer', unit = 'fungu',
        cost_price = 1000, selling_price = 1500, cost_price_tzs = 1000.00, selling_price_tzs = 1500.00,
        stock_quantity = 50, updated_at = NOW();

    -- 2. kuku
    INSERT INTO public.products (
        id, business_id, name, sku, category, unit,
        cost_price, selling_price, cost_price_tzs, selling_price_tzs,
        stock_quantity, reorder_level, min_threshold
    ) VALUES (
        'p0000000-0000-0000-0000-000000000002', v_business_id, 'kuku', 'PLT-KUK-001', 'poultry', 'kuku',
        12000, 15000, 12000.00, 15000.00,
        30, 5, 5
    ) ON CONFLICT (id) DO UPDATE SET
        name = 'kuku', category = 'poultry', unit = 'kuku',
        cost_price = 12000, selling_price = 15000, cost_price_tzs = 12000.00, selling_price_tzs = 15000.00,
        stock_quantity = 30, updated_at = NOW();

    -- 3. Uji Mtamu
    INSERT INTO public.products (
        id, business_id, name, sku, category, unit,
        cost_price, selling_price, cost_price_tzs, selling_price_tzs,
        stock_quantity, reorder_level, min_threshold
    ) VALUES (
        'p0000000-0000-0000-0000-000000000003', v_business_id, 'Uji Mtamu', 'UNG-UJI-001', 'unga', 'pakiti',
        2500, 3500, 2500.00, 3500.00,
        40, 10, 10
    ) ON CONFLICT (id) DO UPDATE SET
        name = 'Uji Mtamu', category = 'unga', unit = 'pakiti',
        cost_price = 2500, selling_price = 3500, cost_price_tzs = 2500.00, selling_price_tzs = 3500.00,
        stock_quantity = 40, updated_at = NOW();

    -- 4. mayai
    INSERT INTO public.products (
        id, business_id, name, sku, category, unit,
        cost_price, selling_price, cost_price_tzs, selling_price_tzs,
        stock_quantity, reorder_level, min_threshold
    ) VALUES (
        'p0000000-0000-0000-0000-000000000004', v_business_id, 'mayai', 'PLT-MAY-001', 'poultry', 'trei',
        9000, 11000, 9000.00, 11000.00,
        25, 5, 5
    ) ON CONFLICT (id) DO UPDATE SET
        name = 'mayai', category = 'poultry', unit = 'trei',
        cost_price = 9000, selling_price = 11000, cost_price_tzs = 9000.00, selling_price_tzs = 11000.00,
        stock_quantity = 25, updated_at = NOW();

    -- 5. mtama mwekundu
    INSERT INTO public.products (
        id, business_id, name, sku, category, unit,
        cost_price, selling_price, cost_price_tzs, selling_price_tzs,
        stock_quantity, reorder_level, min_threshold
    ) VALUES (
        'p0000000-0000-0000-0000-000000000005', v_business_id, 'mtama mwekundu', 'UNG-MTM-001', 'unga', 'kg',
        1800, 2500, 1800.00, 2500.00,
        50, 10, 10
    ) ON CONFLICT (id) DO UPDATE SET
        name = 'mtama mwekundu', category = 'unga', unit = 'kg',
        cost_price = 1800, selling_price = 2500, cost_price_tzs = 1800.00, selling_price_tzs = 2500.00,
        stock_quantity = 50, updated_at = NOW();

    -- 6. mtama mweupe
    INSERT INTO public.products (
        id, business_id, name, sku, category, unit,
        cost_price, selling_price, cost_price_tzs, selling_price_tzs,
        stock_quantity, reorder_level, min_threshold
    ) VALUES (
        'p0000000-0000-0000-0000-000000000006', v_business_id, 'mtama mweupe', 'UNG-MTW-002', 'unga', 'kg',
        1800, 2500, 1800.00, 2500.00,
        50, 10, 10
    ) ON CONFLICT (id) DO UPDATE SET
        name = 'mtama mweupe', category = 'unga', unit = 'kg',
        cost_price = 1800, selling_price = 2500, cost_price_tzs = 1800.00, selling_price_tzs = 2500.00,
        stock_quantity = 50, updated_at = NOW();

    -- 7. Njano mix
    INSERT INTO public.products (
        id, business_id, name, sku, category, unit,
        cost_price, selling_price, cost_price_tzs, selling_price_tzs,
        stock_quantity, reorder_level, min_threshold
    ) VALUES (
        'p0000000-0000-0000-0000-000000000007', v_business_id, 'Njano mix', 'UNG-NJM-003', 'unga', 'pakiti',
        2500, 3500, 2500.00, 3500.00,
        40, 10, 10
    ) ON CONFLICT (id) DO UPDATE SET
        name = 'Njano mix', category = 'unga', unit = 'pakiti',
        cost_price = 2500, selling_price = 3500, cost_price_tzs = 2500.00, selling_price_tzs = 3500.00,
        stock_quantity = 40, updated_at = NOW();

    RAISE NOTICE 'SUCCESS: Jawiza store, Admin, Maria, and 7 products synchronized to Supabase!';
END $$;
