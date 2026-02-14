-- ============================================
-- ENABLE EXTENSIONS
-- ============================================
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements";

-- ============================================
-- CUSTOM TYPES
-- ============================================
CREATE TYPE organization_type AS ENUM ('household', 'business');
CREATE TYPE organization_status AS ENUM ('active', 'suspended', 'deleted');
CREATE TYPE membership_role AS ENUM ('owner', 'admin', 'member', 'viewer');
CREATE TYPE membership_status AS ENUM ('active', 'invited', 'inactive');
CREATE TYPE subscription_tier AS ENUM ('free', 'premium', 'family', 'business');
CREATE TYPE subscription_status AS ENUM ('active', 'past_due', 'canceled', 'trialing');
CREATE TYPE category_type AS ENUM ('expense', 'income');
CREATE TYPE budget_period AS ENUM ('monthly', 'quarterly', 'yearly');
CREATE TYPE trip_status AS ENUM ('planning', 'ongoing', 'completed', 'canceled');
CREATE TYPE transaction_type AS ENUM ('expense', 'income', 'transfer');

-- ============================================
-- PROFILES (extends auth.users)
-- ============================================
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  locale TEXT DEFAULT 'sv-SE',
  timezone TEXT DEFAULT 'Europe/Stockholm',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Automatically create profile on user signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data->>'full_name'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- ============================================
-- ORGANIZATIONS
-- ============================================
CREATE TABLE organizations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name TEXT NOT NULL,
  type organization_type NOT NULL DEFAULT 'household',
  status organization_status NOT NULL DEFAULT 'active',
  
  -- Business-specific (nullable for households)
  business_registration_number TEXT,
  vat_number TEXT,
  
  -- Settings
  currency TEXT DEFAULT 'SEK',
  fiscal_year_start_month INTEGER DEFAULT 1,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  
  CONSTRAINT valid_fiscal_month CHECK (fiscal_year_start_month BETWEEN 1 AND 12)
);

CREATE INDEX idx_organizations_status ON organizations(status) WHERE status = 'active';

-- ============================================
-- ORGANIZATION MEMBERSHIPS
-- ============================================
CREATE TABLE organization_memberships (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  
  role membership_role NOT NULL DEFAULT 'member',
  status membership_status NOT NULL DEFAULT 'invited',
  
  invited_by UUID REFERENCES profiles(id),
  invited_at TIMESTAMPTZ DEFAULT NOW(),
  accepted_at TIMESTAMPTZ,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(organization_id, user_id)
);

CREATE INDEX idx_memberships_user ON organization_memberships(user_id, status);
CREATE INDEX idx_memberships_org ON organization_memberships(organization_id, status);

-- Automatically create first organization for new user
CREATE OR REPLACE FUNCTION public.create_default_organization()
RETURNS TRIGGER AS $$
DECLARE
  new_org_id UUID;
BEGIN
  -- Create organization
  INSERT INTO organizations (name, type)
  VALUES (
    COALESCE(NEW.full_name, 'Mitt Hushåll') || 's Budget',
    'household'
  )
  RETURNING id INTO new_org_id;
  
  -- Add user as owner
  INSERT INTO organization_memberships (organization_id, user_id, role, status, accepted_at)
  VALUES (new_org_id, NEW.id, 'owner', 'active', NOW());
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_profile_created
  AFTER INSERT ON profiles
  FOR EACH ROW EXECUTE FUNCTION public.create_default_organization();

-- ============================================
-- SUBSCRIPTIONS
-- ============================================
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  
  tier subscription_tier NOT NULL DEFAULT 'free',
  status subscription_status NOT NULL DEFAULT 'active',
  
  stripe_subscription_id TEXT UNIQUE,
  stripe_customer_id TEXT,
  
  current_period_start TIMESTAMPTZ,
  current_period_end TIMESTAMPTZ,
  trial_end TIMESTAMPTZ,
  
  -- Free tier limits
  max_transactions_per_month INTEGER DEFAULT 50,
  max_members INTEGER DEFAULT 2,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  canceled_at TIMESTAMPTZ,
  
  UNIQUE(organization_id)
);

-- Auto-create free subscription for new org
CREATE OR REPLACE FUNCTION public.create_default_subscription()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO subscriptions (organization_id, tier, status)
  VALUES (NEW.id, 'free', 'active');
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_organization_created
  AFTER INSERT ON organizations
  FOR EACH ROW EXECUTE FUNCTION public.create_default_subscription();

-- ============================================
-- CATEGORIES
-- ============================================
CREATE TABLE categories (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID REFERENCES organizations(id) ON DELETE CASCADE,
  
  name TEXT NOT NULL,
  type category_type NOT NULL DEFAULT 'expense',
  color TEXT DEFAULT '#6B7280',
  icon TEXT DEFAULT 'tag',
  
  parent_category_id UUID REFERENCES categories(id),
  is_system_default BOOLEAN DEFAULT FALSE,
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  CONSTRAINT unique_org_category UNIQUE(organization_id, name)
);

CREATE INDEX idx_categories_org ON categories(organization_id);

-- Insert default categories (shared across all orgs)
INSERT INTO categories (name, type, color, icon, is_system_default, organization_id) VALUES
  ('Mat & Dryck', 'expense', '#EF4444', 'utensils', true, NULL),
  ('Boende', 'expense', '#3B82F6', 'home', true, NULL),
  ('Transport', 'expense', '#10B981', 'car', true, NULL),
  ('Shopping', 'expense', '#F59E0B', 'shopping-cart', true, NULL),
  ('Nöje', 'expense', '#8B5CF6', 'film', true, NULL),
  ('Hälsa', 'expense', '#EC4899', 'heart', true, NULL),
  ('Lön', 'income', '#059669', 'briefcase', true, NULL),
  ('Övrigt', 'expense', '#6B7280', 'more-horizontal', true, NULL);

-- ============================================
-- BUDGETS
-- ============================================
CREATE TABLE budgets (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  
  name TEXT NOT NULL,
  period budget_period NOT NULL DEFAULT 'monthly',
  
  start_date DATE NOT NULL,
  end_date DATE NOT NULL,
  total_amount DECIMAL(15,2) NOT NULL CHECK (total_amount >= 0),
  
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  CONSTRAINT valid_date_range CHECK (end_date >= start_date)
);

CREATE INDEX idx_budgets_org_date ON budgets(organization_id, start_date DESC);

CREATE TABLE budget_allocations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  budget_id UUID NOT NULL REFERENCES budgets(id) ON DELETE CASCADE,
  category_id UUID NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
  
  allocated_amount DECIMAL(15,2) NOT NULL CHECK (allocated_amount >= 0),
  
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  
  UNIQUE(budget_id, category_id)
);

-- ============================================
-- TRIPS
-- ============================================
CREATE TABLE trips (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  
  name TEXT NOT NULL,
  description TEXT,
  destination TEXT,
  
  start_date DATE,
  end_date DATE,
  budget_amount DECIMAL(15,2),
  status trip_status DEFAULT 'planning',
  
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_trips_org_date ON trips(organization_id, start_date DESC);

-- ============================================
-- TRANSACTIONS
-- ============================================
CREATE TABLE transactions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  organization_id UUID NOT NULL REFERENCES organizations(id) ON DELETE CASCADE,
  
  description TEXT NOT NULL,
  amount DECIMAL(15,2) NOT NULL,
  currency TEXT DEFAULT 'SEK',
  type transaction_type NOT NULL DEFAULT 'expense',
  
  category_id UUID REFERENCES categories(id),
  trip_id UUID REFERENCES trips(id),
  
  transaction_date DATE NOT NULL DEFAULT CURRENT_DATE,
  
  receipt_url TEXT,
  notes TEXT,
  tags TEXT[],
  
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_transactions_org_date ON transactions(organization_id, transaction_date DESC);
CREATE INDEX idx_transactions_category ON transactions(category_id);
CREATE INDEX idx_transactions_created_at ON transactions(created_at DESC);

-- ============================================
-- UPDATED_AT TRIGGERS
-- ============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_organizations_updated_at BEFORE UPDATE ON organizations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_memberships_updated_at BEFORE UPDATE ON organization_memberships
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_subscriptions_updated_at BEFORE UPDATE ON subscriptions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_categories_updated_at BEFORE UPDATE ON categories
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_budgets_updated_at BEFORE UPDATE ON budgets
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_budget_allocations_updated_at BEFORE UPDATE ON budget_allocations
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_trips_updated_at BEFORE UPDATE ON trips
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_transactions_updated_at BEFORE UPDATE ON transactions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();