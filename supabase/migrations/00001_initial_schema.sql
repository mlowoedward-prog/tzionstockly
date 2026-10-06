-- Initial Schema Migration for Tzion Stockly

-- Enable UUID extension if needed
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 1. TABLES
CREATE TABLE IF NOT EXISTS businesses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    currency TEXT NOT NULL DEFAULT 'TZS',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS business_members (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('owner', 'manager', 'staff')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ,
    UNIQUE (user_id, business_id)
);

CREATE TABLE IF NOT EXISTS categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS products (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    sku TEXT,
    barcode TEXT,
    unit TEXT NOT NULL DEFAULT 'pcs',
    cost_price BIGINT NOT NULL DEFAULT 0,
    selling_price BIGINT NOT NULL DEFAULT 0,
    reorder_level INT NOT NULL DEFAULT 5,
    category_id UUID REFERENCES categories(id) ON DELETE SET NULL,
    image_path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS partners (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    phone TEXT,
    email TEXT,
    type TEXT NOT NULL CHECK (type IN ('supplier', 'customer')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS stock_movements (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    business_id UUID NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    product_id UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('purchase', 'sale', 'adjustment', 'return', 'damage')),
    quantity INT NOT NULL,
    unit_cost BIGINT NOT NULL DEFAULT 0,
    unit_price BIGINT NOT NULL DEFAULT 0,
    partner_id UUID REFERENCES partners(id) ON DELETE SET NULL,
    note TEXT,
    created_by TEXT NOT NULL DEFAULT 'local_user',
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    deleted_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS health_check (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    status TEXT NOT NULL DEFAULT 'ok',
    checked_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed health check row
INSERT INTO health_check (id, status) VALUES ('00000000-0000-0000-0000-000000000001', 'ok') ON CONFLICT (id) DO NOTHING;

-- 2. SERVER TIMESTAMP TRIGGER FUNCTION
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_businesses_updated_at BEFORE INSERT OR UPDATE ON businesses FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_business_members_updated_at BEFORE INSERT OR UPDATE ON business_members FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_categories_updated_at BEFORE INSERT OR UPDATE ON categories FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_products_updated_at BEFORE INSERT OR UPDATE ON products FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_partners_updated_at BEFORE INSERT OR UPDATE ON partners FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_stock_movements_updated_at BEFORE INSERT OR UPDATE ON stock_movements FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- 3. INDEXES
CREATE INDEX IF NOT EXISTS idx_businesses_updated ON businesses(updated_at);
CREATE INDEX IF NOT EXISTS idx_business_members_user ON business_members(user_id, business_id);
CREATE INDEX IF NOT EXISTS idx_categories_biz_updated ON categories(business_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_products_biz_updated ON products(business_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode);
CREATE INDEX IF NOT EXISTS idx_products_sku ON products(sku);
CREATE INDEX IF NOT EXISTS idx_partners_biz_updated ON partners(business_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_biz_updated ON stock_movements(business_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_stock_movements_prod_time ON stock_movements(product_id, occurred_at);

-- 4. ROW LEVEL SECURITY (RLS) & POLICIES
ALTER TABLE businesses ENABLE ROW LEVEL SECURITY;
ALTER TABLE business_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE partners ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;
ALTER TABLE health_check ENABLE ROW LEVEL SECURITY;

-- Helper RLS function
CREATE OR REPLACE FUNCTION is_business_member(biz_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM business_members
        WHERE business_id = biz_id
          AND user_id = auth.uid()
          AND deleted_at IS NULL
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Policies: business_members
CREATE POLICY "Users can view their business memberships" ON business_members
    FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can insert business membership" ON business_members
    FOR INSERT WITH CHECK (user_id = auth.uid());

-- Policies: businesses
CREATE POLICY "Members can view their business" ON businesses
    FOR SELECT USING (is_business_member(id));

CREATE POLICY "Members can update their business" ON businesses
    FOR UPDATE USING (is_business_member(id));

-- Policies: categories
CREATE POLICY "Members can view categories" ON categories
    FOR SELECT USING (is_business_member(business_id));

CREATE POLICY "Members can insert categories" ON categories
    FOR INSERT WITH CHECK (is_business_member(business_id));

CREATE POLICY "Members can update categories" ON categories
    FOR UPDATE USING (is_business_member(business_id));

-- Policies: products
CREATE POLICY "Members can view products" ON products
    FOR SELECT USING (is_business_member(business_id));

CREATE POLICY "Members can insert products" ON products
    FOR INSERT WITH CHECK (is_business_member(business_id));

CREATE POLICY "Members can update products" ON products
    FOR UPDATE USING (is_business_member(business_id));

-- Policies: partners
CREATE POLICY "Members can view partners" ON partners
    FOR SELECT USING (is_business_member(business_id));

CREATE POLICY "Members can insert partners" ON partners
    FOR INSERT WITH CHECK (is_business_member(business_id));

CREATE POLICY "Members can update partners" ON partners
    FOR UPDATE USING (is_business_member(business_id));

-- Policies: stock_movements (APPEND-ONLY: SELECT & INSERT ONLY)
CREATE POLICY "Members can view stock movements" ON stock_movements
    FOR SELECT USING (is_business_member(business_id));

CREATE POLICY "Members can insert stock movements" ON stock_movements
    FOR INSERT WITH CHECK (is_business_member(business_id));

-- Policies: health_check
CREATE POLICY "Anon can view health_check" ON health_check
    FOR SELECT TO anon, authenticated USING (true);
