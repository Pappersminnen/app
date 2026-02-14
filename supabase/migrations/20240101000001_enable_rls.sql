-- ============================================
-- ENABLE ROW LEVEL SECURITY
-- ============================================
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE organization_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE budgets ENABLE ROW LEVEL SECURITY;
ALTER TABLE budget_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE trips ENABLE ROW LEVEL SECURITY;
ALTER TABLE transactions ENABLE ROW LEVEL SECURITY;

-- ============================================
-- HELPER FUNCTIONS
-- ============================================

-- Check if user is member of organization
CREATE OR REPLACE FUNCTION is_organization_member(org_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM organization_memberships
    WHERE organization_id = org_id
    AND user_id = auth.uid()
    AND status = 'active'
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Check if user has specific role in organization
CREATE OR REPLACE FUNCTION has_organization_role(org_id UUID, required_role membership_role)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM organization_memberships
    WHERE organization_id = org_id
    AND user_id = auth.uid()
    AND status = 'active'
    AND role = required_role
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- Get user's role in organization
CREATE OR REPLACE FUNCTION get_user_role(org_id UUID)
RETURNS membership_role AS $$
DECLARE
  user_role membership_role;
BEGIN
  SELECT role INTO user_role
  FROM organization_memberships
  WHERE organization_id = org_id
  AND user_id = auth.uid()
  AND status = 'active';
  
  RETURN user_role;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- ============================================
-- PROFILES POLICIES
-- ============================================

-- Users can view their own profile
CREATE POLICY "Users can view own profile"
  ON profiles FOR SELECT
  USING (auth.uid() = id);

-- Users can update their own profile
CREATE POLICY "Users can update own profile"
  ON profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- ============================================
-- ORGANIZATIONS POLICIES
-- ============================================

-- Users can view organizations they're members of
CREATE POLICY "Users can view own organizations"
  ON organizations FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM organization_memberships
      WHERE organization_id = organizations.id
      AND user_id = auth.uid()
      AND status = 'active'
    )
  );

-- Owners can update their organization
CREATE POLICY "Owners can update organization"
  ON organizations FOR UPDATE
  USING (has_organization_role(id, 'owner'))
  WITH CHECK (has_organization_role(id, 'owner'));

-- Owners can delete their organization
CREATE POLICY "Owners can delete organization"
  ON organizations FOR DELETE
  USING (has_organization_role(id, 'owner'));

-- ============================================
-- MEMBERSHIPS POLICIES
-- ============================================

-- Users can view memberships in their organizations
CREATE POLICY "Users can view organization memberships"
  ON organization_memberships FOR SELECT
  USING (is_organization_member(organization_id));

-- Owners and admins can invite members
CREATE POLICY "Owners and admins can invite members"
  ON organization_memberships FOR INSERT
  WITH CHECK (
    get_user_role(organization_id) IN ('owner', 'admin')
  );

-- Owners and admins can update memberships
CREATE POLICY "Owners and admins can update memberships"
  ON organization_memberships FOR UPDATE
  USING (get_user_role(organization_id) IN ('owner', 'admin'))
  WITH CHECK (get_user_role(organization_id) IN ('owner', 'admin'));

-- Owners can delete memberships
CREATE POLICY "Owners can delete memberships"
  ON organization_memberships FOR DELETE
  USING (has_organization_role(organization_id, 'owner'));

-- Users can update their own membership (e.g., accept invitation)
CREATE POLICY "Users can update own membership"
  ON organization_memberships FOR UPDATE
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ============================================
-- SUBSCRIPTIONS POLICIES
-- ============================================

-- Users can view subscription for their organizations
CREATE POLICY "Users can view organization subscription"
  ON subscriptions FOR SELECT
  USING (is_organization_member(organization_id));

-- Owners can update subscription
CREATE POLICY "Owners can update subscription"
  ON subscriptions FOR UPDATE
  USING (has_organization_role(organization_id, 'owner'))
  WITH CHECK (has_organization_role(organization_id, 'owner'));

-- ============================================
-- CATEGORIES POLICIES
-- ============================================

-- Users can view system defaults + their org categories
CREATE POLICY "Users can view categories"
  ON categories FOR SELECT
  USING (
    is_system_default = true
    OR is_organization_member(organization_id)
  );

-- Members can create categories in their org
CREATE POLICY "Members can create categories"
  ON categories FOR INSERT
  WITH CHECK (is_organization_member(organization_id));

-- Members can update their org categories
CREATE POLICY "Members can update categories"
  ON categories FOR UPDATE
  USING (is_organization_member(organization_id))
  WITH CHECK (is_organization_member(organization_id));

-- Admins and owners can delete categories
CREATE POLICY "Admins can delete categories"
  ON categories FOR DELETE
  USING (get_user_role(organization_id) IN ('owner', 'admin'));

-- ============================================
-- BUDGETS POLICIES
-- ============================================

-- Users can view budgets in their organizations
CREATE POLICY "Users can view organization budgets"
  ON budgets FOR SELECT
  USING (is_organization_member(organization_id));

-- Members can create budgets
CREATE POLICY "Members can create budgets"
  ON budgets FOR INSERT
  WITH CHECK (is_organization_member(organization_id));

-- Members can update budgets
CREATE POLICY "Members can update budgets"
  ON budgets FOR UPDATE
  USING (is_organization_member(organization_id))
  WITH CHECK (is_organization_member(organization_id));

-- Admins can delete budgets
CREATE POLICY "Admins can delete budgets"
  ON budgets FOR DELETE
  USING (get_user_role(organization_id) IN ('owner', 'admin'));

-- ============================================
-- BUDGET ALLOCATIONS POLICIES
-- ============================================

CREATE POLICY "Users can view budget allocations"
  ON budget_allocations FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM budgets
      WHERE budgets.id = budget_allocations.budget_id
      AND is_organization_member(budgets.organization_id)
    )
  );

CREATE POLICY "Members can manage budget allocations"
  ON budget_allocations FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM budgets
      WHERE budgets.id = budget_allocations.budget_id
      AND is_organization_member(budgets.organization_id)
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM budgets
      WHERE budgets.id = budget_allocations.budget_id
      AND is_organization_member(budgets.organization_id)
    )
  );

-- ============================================
-- TRIPS POLICIES
-- ============================================

CREATE POLICY "Users can view organization trips"
  ON trips FOR SELECT
  USING (is_organization_member(organization_id));

CREATE POLICY "Members can create trips"
  ON trips FOR INSERT
  WITH CHECK (is_organization_member(organization_id));

CREATE POLICY "Members can update trips"
  ON trips FOR UPDATE
  USING (is_organization_member(organization_id))
  WITH CHECK (is_organization_member(organization_id));

CREATE POLICY "Admins can delete trips"
  ON trips FOR DELETE
  USING (get_user_role(organization_id) IN ('owner', 'admin'));

-- ============================================
-- TRANSACTIONS POLICIES
-- ============================================

CREATE POLICY "Users can view organization transactions"
  ON transactions FOR SELECT
  USING (is_organization_member(organization_id));

CREATE POLICY "Members can create transactions"
  ON transactions FOR INSERT
  WITH CHECK (is_organization_member(organization_id));

CREATE POLICY "Members can update transactions"
  ON transactions FOR UPDATE
  USING (is_organization_member(organization_id))
  WITH CHECK (is_organization_member(organization_id));

CREATE POLICY "Members can delete transactions"
  ON transactions FOR DELETE
  USING (is_organization_member(organization_id));