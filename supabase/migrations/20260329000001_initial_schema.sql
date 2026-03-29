-- =============================================================================
-- Contractor Management System — Initial Schema
-- Supabase / PostgreSQL
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extensions
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "pgcrypto";   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS "pg_trgm";    -- fuzzy text search on names


-- ---------------------------------------------------------------------------
-- Helper: auto-update updated_at timestamps
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;


-- =============================================================================
-- TABLE: profiles
-- Extended metadata for each Supabase auth user.
-- =============================================================================
CREATE TABLE IF NOT EXISTS profiles (
  id            uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name     text,
  company_name  text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Auto-create a profile row whenever a new user registers
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO profiles (id, full_name)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', '')
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE TRIGGER trg_new_user_profile
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();


-- =============================================================================
-- TABLE: projects
-- Master list of construction projects.
-- =============================================================================
CREATE TABLE IF NOT EXISTS projects (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code        text        NOT NULL,          -- human-readable: P001, P002 …
  name        text        NOT NULL,
  client      text,
  location    text,
  status      text        NOT NULL DEFAULT 'Active'
                          CHECK (status IN ('Active', 'Planning', 'Completed', 'Inactive')),
  start_date  date,
  notes       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (user_id, code)
);

CREATE INDEX idx_projects_user_id ON projects (user_id);

CREATE TRIGGER trg_projects_updated_at
  BEFORE UPDATE ON projects
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =============================================================================
-- TABLE: workers
-- Roster of workers / subcontractors.
-- =============================================================================
CREATE TABLE IF NOT EXISTS workers (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code                text        NOT NULL,  -- W001, W002 …
  name                text        NOT NULL,
  role                text,
  phone               text,
  daily_rate          numeric(10,3) NOT NULL DEFAULT 0 CHECK (daily_rate >= 0),
  -- hourly_rate is always daily_rate / 8; computed by the application layer
  -- (stored separately on payroll rows as a snapshot of the rate at entry time)
  default_project_id  uuid        REFERENCES projects(id) ON DELETE SET NULL,
  status              text        NOT NULL DEFAULT 'Active'
                                  CHECK (status IN ('Active', 'Inactive')),
  hire_date           date,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),

  UNIQUE (user_id, code)
);

CREATE INDEX idx_workers_user_id ON workers (user_id);
CREATE INDEX idx_workers_default_project ON workers (default_project_id);

CREATE TRIGGER trg_workers_updated_at
  BEFORE UPDATE ON workers
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =============================================================================
-- TABLE: activities
-- Master list of work activities (Concrete, Masonry, Finishing, Steel, Other).
-- =============================================================================
CREATE TABLE IF NOT EXISTS activities (
  id          uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid  NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name        text  NOT NULL,
  group_name  text  NOT NULL
              CHECK (group_name IN ('Concrete', 'Masonry', 'Finishing', 'Steel', 'Other')),
  unit        text  NOT NULL
              CHECK (unit IN ('m³', 'm²', 'ton', 'm', 'No.', 'LS')),
  created_at  timestamptz NOT NULL DEFAULT now(),

  UNIQUE (user_id, name)
);

CREATE INDEX idx_activities_user_id ON activities (user_id);
CREATE INDEX idx_activities_group   ON activities (user_id, group_name);


-- =============================================================================
-- TABLE: payroll_entries
-- Daily labour records: who worked, where, how long, at what rate.
-- hourly_rate is stored as a snapshot so historical records survive rate changes.
-- =============================================================================
CREATE TABLE IF NOT EXISTS payroll_entries (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        date        NOT NULL,
  project_id  uuid        NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
  activity_id uuid        NOT NULL REFERENCES activities(id) ON DELETE RESTRICT,
  worker_id   uuid        NOT NULL REFERENCES workers(id) ON DELETE RESTRICT,
  hours       numeric(5,2) NOT NULL CHECK (hours > 0),
  hourly_rate numeric(10,4) NOT NULL CHECK (hourly_rate >= 0),
  -- labor_cost = hours × hourly_rate, stored generated for query convenience
  labor_cost  numeric(10,2) GENERATED ALWAYS AS (hours * hourly_rate) STORED,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_payroll_user_date    ON payroll_entries (user_id, date DESC);
CREATE INDEX idx_payroll_project      ON payroll_entries (project_id);
CREATE INDEX idx_payroll_worker       ON payroll_entries (worker_id);
CREATE INDEX idx_payroll_activity     ON payroll_entries (activity_id);

CREATE TRIGGER trg_payroll_updated_at
  BEFORE UPDATE ON payroll_entries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =============================================================================
-- TABLE: material_entries
-- Daily material consumption records per activity.
-- =============================================================================
CREATE TABLE IF NOT EXISTS material_entries (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date            date          NOT NULL,
  project_id      uuid          NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
  activity_id     uuid          NOT NULL REFERENCES activities(id) ON DELETE RESTRICT,
  volume          numeric(10,3),                    -- quantity of work done
  unit            text CHECK (unit IN ('m³', 'm²', 'ton', 'm', 'No.', 'LS')),
  cement_bags     numeric(10,2) NOT NULL DEFAULT 0, -- number of bags
  steel_kg        numeric(10,2) NOT NULL DEFAULT 0, -- kilograms
  concrete_m3     numeric(10,3) NOT NULL DEFAULT 0, -- cubic metres
  sand_m3         numeric(10,3) NOT NULL DEFAULT 0,
  gravel_m3       numeric(10,3) NOT NULL DEFAULT 0,
  other_cost      numeric(10,2) NOT NULL DEFAULT 0, -- USD
  total_material  numeric(10,2) NOT NULL DEFAULT 0, -- USD
  created_at      timestamptz   NOT NULL DEFAULT now(),
  updated_at      timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX idx_materials_user_date ON material_entries (user_id, date DESC);
CREATE INDEX idx_materials_project   ON material_entries (project_id);
CREATE INDEX idx_materials_activity  ON material_entries (activity_id);

CREATE TRIGGER trg_materials_updated_at
  BEFORE UPDATE ON material_entries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =============================================================================
-- TABLE: cost_entries
-- Financial summary per activity execution: labour + material + other vs revenue.
-- profit and profit_per_unit are generated columns kept consistent automatically.
-- =============================================================================
CREATE TABLE IF NOT EXISTS cost_entries (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date            date          NOT NULL,
  project_id      uuid          NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
  activity_id     uuid          NOT NULL REFERENCES activities(id) ON DELETE RESTRICT,
  status          text          NOT NULL DEFAULT 'In Progress'
                                CHECK (status IN ('In Progress', 'Completed', 'On Hold')),
  volume          numeric(10,3),
  unit            text CHECK (unit IN ('m³', 'm²', 'ton', 'm', 'No.', 'LS')),
  labor           numeric(10,2) NOT NULL DEFAULT 0,
  material        numeric(10,2) NOT NULL DEFAULT 0,
  other           numeric(10,2) NOT NULL DEFAULT 0,
  total_cost      numeric(10,2) GENERATED ALWAYS AS (labor + material + other) STORED,
  revenue         numeric(10,2) NOT NULL DEFAULT 0,
  profit          numeric(10,2) GENERATED ALWAYS AS (revenue - (labor + material + other)) STORED,
  profit_per_unit numeric(10,4) GENERATED ALWAYS AS (
    CASE WHEN volume IS NOT NULL AND volume > 0
         THEN (revenue - (labor + material + other)) / volume
         ELSE 0
    END
  ) STORED,
  labor_hours     numeric(8,2)  NOT NULL DEFAULT 0,
  created_at      timestamptz   NOT NULL DEFAULT now(),
  updated_at      timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX idx_cost_user_date  ON cost_entries (user_id, date DESC);
CREATE INDEX idx_cost_project    ON cost_entries (project_id);
CREATE INDEX idx_cost_activity   ON cost_entries (activity_id);
CREATE INDEX idx_cost_status     ON cost_entries (user_id, status);

CREATE TRIGGER trg_cost_updated_at
  BEFORE UPDATE ON cost_entries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =============================================================================
-- TABLE: daily_entries
-- Per-day quality & discipline scoring for a project (6 criteria, 0–1 each).
-- total_score is auto-calculated as the mean of the six criteria.
-- =============================================================================
CREATE TABLE IF NOT EXISTS daily_entries (
  id                uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date              date          NOT NULL,
  project_id        uuid          NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
  mindset           numeric(3,2)  NOT NULL DEFAULT 0 CHECK (mindset BETWEEN 0 AND 1),
  site_control      numeric(3,2)  NOT NULL DEFAULT 0 CHECK (site_control BETWEEN 0 AND 1),
  concrete_quality  numeric(3,2)  NOT NULL DEFAULT 0 CHECK (concrete_quality BETWEEN 0 AND 1),
  cost_control      numeric(3,2)  NOT NULL DEFAULT 0 CHECK (cost_control BETWEEN 0 AND 1),
  problem_handling  numeric(3,2)  NOT NULL DEFAULT 0 CHECK (problem_handling BETWEEN 0 AND 1),
  discipline        numeric(3,2)  NOT NULL DEFAULT 0 CHECK (discipline BETWEEN 0 AND 1),
  total_score       numeric(4,3)  GENERATED ALWAYS AS (
    (mindset + site_control + concrete_quality + cost_control + problem_handling + discipline) / 6
  ) STORED,
  notes             text,
  created_at        timestamptz   NOT NULL DEFAULT now(),
  updated_at        timestamptz   NOT NULL DEFAULT now(),

  UNIQUE (user_id, date, project_id)   -- one entry per project per day
);

CREATE INDEX idx_daily_user_date ON daily_entries (user_id, date DESC);
CREATE INDEX idx_daily_project   ON daily_entries (project_id);

CREATE TRIGGER trg_daily_updated_at
  BEFORE UPDATE ON daily_entries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =============================================================================
-- TABLE: decision_entries
-- Decision log with 5-criteria quality checklist.
-- score = mean of the five binary criteria.
-- =============================================================================
CREATE TABLE IF NOT EXISTS decision_entries (
  id          uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid          NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  date        date          NOT NULL,
  project_id  uuid          NOT NULL REFERENCES projects(id) ON DELETE RESTRICT,
  activity_id uuid          REFERENCES activities(id) ON DELETE SET NULL,
  decision    text          NOT NULL,
  -- 5 binary quality criteria (0 = No, 1 = Yes)
  facts       smallint      NOT NULL DEFAULT 0 CHECK (facts IN (0,1)),
  no_ego      smallint      NOT NULL DEFAULT 0 CHECK (no_ego IN (0,1)),
  numbers_ok  smallint      NOT NULL DEFAULT 0 CHECK (numbers_ok IN (0,1)),
  worst_case  smallint      NOT NULL DEFAULT 0 CHECK (worst_case IN (0,1)),
  simple      smallint      NOT NULL DEFAULT 0 CHECK (simple IN (0,1)),
  score       numeric(4,3)  GENERATED ALWAYS AS (
    (facts + no_ego + numbers_ok + worst_case + simple)::numeric / 5
  ) STORED,
  approved    text          NOT NULL DEFAULT 'No' CHECK (approved IN ('Yes', 'No')),
  follow_up   text,
  created_at  timestamptz   NOT NULL DEFAULT now(),
  updated_at  timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX idx_decisions_user_date ON decision_entries (user_id, date DESC);
CREATE INDEX idx_decisions_project   ON decision_entries (project_id);
CREATE INDEX idx_decisions_approved  ON decision_entries (user_id, approved);

CREATE TRIGGER trg_decisions_updated_at
  BEFORE UPDATE ON decision_entries
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();


-- =============================================================================
-- VIEWS
-- =============================================================================

-- Project-level financial summary (mirrors the Project Summary module)
CREATE OR REPLACE VIEW project_summary AS
SELECT
  p.id                                              AS project_id,
  p.user_id,
  p.code,
  p.name,
  p.client,
  p.location,
  p.status,
  p.start_date,
  COALESCE(SUM(c.revenue),       0)::numeric(12,2)  AS total_revenue,
  COALESCE(SUM(c.total_cost),    0)::numeric(12,2)  AS total_cost,
  COALESCE(SUM(c.profit),        0)::numeric(12,2)  AS total_profit,
  COALESCE(SUM(c.volume),        0)::numeric(12,3)  AS total_volume,
  CASE WHEN COALESCE(SUM(c.volume), 0) > 0
       THEN (COALESCE(SUM(c.profit), 0) / SUM(c.volume))::numeric(10,4)
       ELSE 0
  END                                               AS profit_per_unit,
  COALESCE(SUM(pe.hours),        0)::numeric(10,2)  AS total_labor_hours,
  COALESCE(AVG(d.total_score),   0)::numeric(4,3)   AS avg_daily_score,
  COUNT(DISTINCT pe.id)                             AS payroll_count,
  COUNT(DISTINCT c.id)                              AS cost_entry_count
FROM  projects       p
LEFT JOIN cost_entries    c  ON c.project_id = p.id
LEFT JOIN payroll_entries pe ON pe.project_id = p.id
LEFT JOIN daily_entries   d  ON d.project_id = p.id
GROUP BY p.id, p.user_id, p.code, p.name, p.client, p.location, p.status, p.start_date;

-- Dashboard KPI roll-up across all projects for the current user
CREATE OR REPLACE VIEW dashboard_kpi AS
SELECT
  user_id,
  COALESCE(SUM(revenue),       0)::numeric(12,2) AS total_revenue,
  COALESCE(SUM(total_cost),    0)::numeric(12,2) AS total_cost,
  COALESCE(SUM(profit),        0)::numeric(12,2) AS total_profit,
  COALESCE(SUM(labor_hours),   0)::numeric(10,2) AS total_labor_hours,
  COUNT(*)                                        AS cost_entry_count
FROM cost_entries
GROUP BY user_id;


-- =============================================================================
-- ROW-LEVEL SECURITY
-- Each user can only see and modify their own rows.
-- =============================================================================

ALTER TABLE profiles         ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects         ENABLE ROW LEVEL SECURITY;
ALTER TABLE workers          ENABLE ROW LEVEL SECURITY;
ALTER TABLE activities       ENABLE ROW LEVEL SECURITY;
ALTER TABLE payroll_entries  ENABLE ROW LEVEL SECURITY;
ALTER TABLE material_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE cost_entries     ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_entries    ENABLE ROW LEVEL SECURITY;
ALTER TABLE decision_entries ENABLE ROW LEVEL SECURITY;

-- ── profiles ──────────────────────────────────────────────────────────────────
CREATE POLICY "profiles: own row only"
  ON profiles FOR ALL
  USING      (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ── projects ──────────────────────────────────────────────────────────────────
CREATE POLICY "projects: own rows only"
  ON projects FOR ALL
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── workers ───────────────────────────────────────────────────────────────────
CREATE POLICY "workers: own rows only"
  ON workers FOR ALL
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── activities ────────────────────────────────────────────────────────────────
CREATE POLICY "activities: own rows only"
  ON activities FOR ALL
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── payroll_entries ───────────────────────────────────────────────────────────
CREATE POLICY "payroll: own rows only"
  ON payroll_entries FOR ALL
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── material_entries ──────────────────────────────────────────────────────────
CREATE POLICY "materials: own rows only"
  ON material_entries FOR ALL
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── cost_entries ──────────────────────────────────────────────────────────────
CREATE POLICY "cost: own rows only"
  ON cost_entries FOR ALL
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── daily_entries ─────────────────────────────────────────────────────────────
CREATE POLICY "daily: own rows only"
  ON daily_entries FOR ALL
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── decision_entries ──────────────────────────────────────────────────────────
CREATE POLICY "decisions: own rows only"
  ON decision_entries FOR ALL
  USING      (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());


-- =============================================================================
-- COMMENTS (documentation inside the DB)
-- =============================================================================
COMMENT ON TABLE profiles         IS 'Extended user profile, 1-to-1 with auth.users';
COMMENT ON TABLE projects         IS 'Construction project master list';
COMMENT ON TABLE workers          IS 'Worker/subcontractor roster';
COMMENT ON TABLE activities       IS 'Activity master list (Concrete, Masonry, etc.)';
COMMENT ON TABLE payroll_entries  IS 'Daily labour records per worker per activity';
COMMENT ON TABLE material_entries IS 'Daily material consumption per activity';
COMMENT ON TABLE cost_entries     IS 'Financial summary: labour + material + other vs revenue';
COMMENT ON TABLE daily_entries    IS '6-criteria quality scoring per project per day';
COMMENT ON TABLE decision_entries IS '5-criteria decision quality log';

COMMENT ON COLUMN workers.daily_rate      IS 'USD per standard 8-hour day';
COMMENT ON COLUMN payroll_entries.hourly_rate IS 'Snapshot of rate at time of entry — survives future rate changes';
COMMENT ON COLUMN payroll_entries.labor_cost  IS 'Generated: hours × hourly_rate';
COMMENT ON COLUMN cost_entries.total_cost     IS 'Generated: labor + material + other';
COMMENT ON COLUMN cost_entries.profit         IS 'Generated: revenue − total_cost';
COMMENT ON COLUMN cost_entries.profit_per_unit IS 'Generated: profit / volume (0 when volume is null or 0)';
COMMENT ON COLUMN daily_entries.total_score   IS 'Generated: mean of 6 criteria (0–1)';
COMMENT ON COLUMN decision_entries.score      IS 'Generated: mean of 5 binary criteria (0–1)';
