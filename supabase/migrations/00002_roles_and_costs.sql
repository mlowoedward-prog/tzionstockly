-- ==========================================
-- Migration 00002: Roles and Cost Data Protection
-- ==========================================

-- Helper function: Check if current auth user is Owner or Manager of business
CREATE OR REPLACE FUNCTION is_owner_or_manager(biz_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM public.business_members
        WHERE business_id = biz_id
          AND user_id = auth.uid()
          AND role IN ('owner', 'manager')
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 1. PRODUCT COSTS TABLE (Restricted to Owner & Manager)
CREATE TABLE IF NOT EXISTS public.product_costs (
    product_id UUID PRIMARY KEY REFERENCES public.products(id) ON DELETE CASCADE,
    business_id UUID NOT NULL REFERENCES public.businesses(id) ON DELETE CASCADE,
    cost_price INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Trigger for server updated_at timestamp
DROP TRIGGER IF EXISTS set_product_costs_updated_at ON public.product_costs;
CREATE TRIGGER set_product_costs_updated_at
    BEFORE UPDATE ON public.product_costs
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Enable RLS
ALTER TABLE public.product_costs ENABLE ROW LEVEL SECURITY;

-- Product Costs RLS Policies: Restricted strictly to Owners and Managers!
CREATE POLICY "Owners and Managers can read product costs"
    ON public.product_costs FOR SELECT
    USING (is_owner_or_manager(business_id));

CREATE POLICY "Owners and Managers can modify product costs"
    ON public.product_costs FOR ALL
    USING (is_owner_or_manager(business_id));

-- 2. BUSINESS MEMBERS INVITATION & ROLE MANAGEMENT POLICIES
CREATE POLICY "Owners can invite or update business members"
    ON public.business_members FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM public.business_members bm
            WHERE bm.business_id = business_members.business_id
              AND bm.user_id = auth.uid()
              AND bm.role = 'owner'
        )
    );
