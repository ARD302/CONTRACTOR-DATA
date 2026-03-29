-- =============================================================================
-- Seed data — migrated from data.json
-- Run AFTER the schema migration.
-- Replace '<YOUR_USER_ID>' with the auth.users.id of the account to seed.
-- Usage from Supabase CLI:
--   psql "$DATABASE_URL" -v user_id="'<uuid>'" -f supabase/seed.sql
-- Or set the variable inline:
--   \set user_id '<uuid>'
-- =============================================================================

-- Set the user id here for convenience during manual seeding.
-- When called via the CLI migration, pass it as a variable.
\set user_id '00000000-0000-0000-0000-000000000001'

-- ---------------------------------------------------------------------------
-- Projects
-- ---------------------------------------------------------------------------
INSERT INTO projects (id, user_id, code, name, client, location, status, start_date, notes)
VALUES
  (gen_random_uuid(), :'user_id', 'P001', 'Douaihy Residence',         'Private Client',     'Ehden', 'Active', '2025-05-06',  'Block B and Block A'),
  (gen_random_uuid(), :'user_id', 'P002', 'Dr. Pierre Yammine',        'Private Client',     'Ehden', 'Active', '2025-10-25',  'Block A and Block B'),
  (gen_random_uuid(), :'user_id', 'P003', 'Restaurant Renovation FERDOS', 'Hospitality Client', 'Ehden', 'Active', '2026-03-16', 'Civil works (R.C. work)'),
  (gen_random_uuid(), :'user_id', 'P004', 'Riva Kareh',                'Private Client',     'Ehden', 'Active', '2025-06-03',  'Project had basement slab torn apart')
ON CONFLICT (user_id, code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Workers  (daily_rate stored; hourly_rate = daily_rate / 8 in the app)
-- ---------------------------------------------------------------------------
INSERT INTO workers (id, user_id, code, name, role, phone, daily_rate, default_project_id, status, hire_date)
SELECT
  gen_random_uuid(),
  :'user_id',
  w.code,
  w.name,
  w.role,
  w.phone,
  w.daily_rate,
  p.id,
  w.status,
  w.hire_date::date
FROM (VALUES
  ('W001', 'Kenan Sabra',   'Foremen',            '81-846701', 33, 'P001', 'Active', '2025-01-01'),
  ('W002', 'Yael Talje',    'Skilled Labor',       '',          30, 'P001', 'Active', '2025-01-01'),
  ('W003', 'Fady Sabra',    'Semi Skilled Labor',  '71-494865', 27, 'P001', 'Active', '2025-01-02'),
  ('W004', 'Nayrouz Talje', 'Skilled Labor',       '03-541615', 30, 'P002', 'Active', '2025-01-02'),
  ('W005', 'Nidal',         'Labor',               '',          22, 'P001', 'Active', '2025-01-01'),
  ('W006', 'Issa',          'Labor',               '',          22, 'P001', 'Active', '2025-01-02'),
  ('W007', 'Hamze',         'Labor',               '',          21, 'P001', 'Active', '2025-01-05'),
  ('W008', 'Raghed',        'Labor',               '',          22, 'P001', 'Active', '2025-01-09'),
  ('W009', 'Yamen',         'Semi Skilled Labor',  '',          24, 'P002', 'Active', '2025-01-09'),
  ('W010', 'Mohamad',       'Semi Skilled Labor',  '70-995687', 24, 'P002', 'Active', '2025-01-09'),
  ('W011', 'Aghyad',        'Labor',               '',          18, 'P001', 'Active', '2025-01-09'),
  ('W012', 'Haydar',        'Labor',               '',          20, 'P002', 'Active', '2025-01-09'),
  ('W013', 'Mouhtassem',    'Labor',               '',          18, 'P001', 'Active', '2025-01-09'),
  ('W014', 'Lilane',        'Labor',               '',          20, 'P001', 'Active', '2025-01-09'),
  ('W015', 'Fakhem',        'Labor',               '',          16, 'P001', 'Active', '2025-01-09'),
  ('W016', 'Hamoudeh',      'Labor',               '',          17, 'P001', 'Active', '2025-01-09')
) AS w(code, name, role, phone, daily_rate, proj_code, status, hire_date)
JOIN projects p ON p.code = w.proj_code AND p.user_id = :'user_id'
ON CONFLICT (user_id, code) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Activities
-- ---------------------------------------------------------------------------
INSERT INTO activities (user_id, name, group_name, unit)
VALUES
  (:'user_id', 'Footing',         'Concrete',  'm³'),
  (:'user_id', 'Tie Beam',        'Concrete',  'm³'),
  (:'user_id', 'Column',          'Concrete',  'm³'),
  (:'user_id', 'Beam',            'Concrete',  'm³'),
  (:'user_id', 'Slab',            'Concrete',  'm³'),
  (:'user_id', 'Retaining Wall',  'Concrete',  'm³'),
  (:'user_id', 'Blockwork',       'Masonry',   'm²'),
  (:'user_id', 'Plaster',         'Finishing', 'm²'),
  (:'user_id', 'Waterproofing',   'Finishing', 'm²'),
  (:'user_id', 'Steel Erection',  'Steel',     'ton')
ON CONFLICT (user_id, name) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Payroll entries
-- ---------------------------------------------------------------------------
INSERT INTO payroll_entries (user_id, date, project_id, activity_id, worker_id, hours, hourly_rate)
SELECT
  :'user_id',
  pe.date::date,
  p.id,
  a.id,
  w.id,
  pe.hours,
  pe.hourly_rate
FROM (VALUES
  ('2026-03-20', 'P001', 'Slab',   'W001', 10, 4.125),
  ('2026-03-20', 'P001', 'Slab',   'W002',  9, 3.75),
  ('2026-03-20', 'P001', 'Slab',   'W004',  8, 3.75),
  ('2026-03-20', 'P002', 'Column', 'W003',  8, 3.375),
  ('2026-03-21', 'P001', 'Beam',   'W001',  4, 4.125),
  ('2026-03-21', 'P002', 'Column', 'W001',  4, 4.125),
  ('2026-03-21', 'P001', 'Beam',   'W002',  8, 3.75)
) AS pe(date, proj_code, act_name, worker_code, hours, hourly_rate)
JOIN projects   p ON p.code = pe.proj_code   AND p.user_id = :'user_id'
JOIN activities a ON a.name = pe.act_name    AND a.user_id = :'user_id'
JOIN workers    w ON w.code = pe.worker_code AND w.user_id = :'user_id';

-- ---------------------------------------------------------------------------
-- Cost entries  (profit & total_cost are generated columns — omit them)
-- ---------------------------------------------------------------------------
INSERT INTO cost_entries (user_id, date, project_id, activity_id, status, volume, unit, labor, material, other, revenue, labor_hours)
SELECT
  :'user_id',
  ce.date::date,
  p.id,
  a.id,
  ce.status,
  ce.volume,
  ce.unit,
  ce.labor,
  ce.material,
  ce.other,
  ce.revenue,
  ce.labor_hours
FROM (VALUES
  ('2026-03-20', 'P001', 'Slab',   'Completed', 45,  'm³',  93,    3200, 150, 4500, 27),
  ('2026-03-20', 'P002', 'Column', 'Completed',  8,  'm³',  20,     850, 100, 1350,  8),
  ('2026-03-21', 'P001', 'Beam',   'Completed', 12,  'm³',  42.5,  1100,  60, 1500, 12)
) AS ce(date, proj_code, act_name, status, volume, unit, labor, material, other, revenue, labor_hours)
JOIN projects   p ON p.code = ce.proj_code AND p.user_id = :'user_id'
JOIN activities a ON a.name = ce.act_name  AND a.user_id = :'user_id';

-- ---------------------------------------------------------------------------
-- Daily entries  (total_score is a generated column — omit it)
-- ---------------------------------------------------------------------------
INSERT INTO daily_entries (user_id, date, project_id, mindset, site_control, concrete_quality, cost_control, problem_handling, discipline, notes)
SELECT
  :'user_id',
  de.date::date,
  p.id,
  de.mindset,
  de.site_control,
  de.concrete_quality,
  de.cost_control,
  de.problem_handling,
  de.discipline,
  de.notes
FROM (VALUES
  ('2026-03-20', 'P001', 1.0, 0.9, 0.9, 0.8, 1.0, 0.9, 'Slab pour well controlled'),
  ('2026-03-20', 'P002', 0.9, 0.8, 0.8, 0.8, 0.9, 0.9, 'Column work acceptable'),
  ('2026-03-21', 'P001', 0.9, 0.9, 0.8, 0.9, 0.9, 0.9, 'Beam activity on track')
) AS de(date, proj_code, mindset, site_control, concrete_quality, cost_control, problem_handling, discipline, notes)
JOIN projects p ON p.code = de.proj_code AND p.user_id = :'user_id'
ON CONFLICT (user_id, date, project_id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- Decision entries  (score is a generated column — omit it)
-- ---------------------------------------------------------------------------
INSERT INTO decision_entries (user_id, date, project_id, activity_id, decision, facts, no_ego, numbers_ok, worst_case, simple, approved, follow_up)
SELECT
  :'user_id',
  de.date::date,
  p.id,
  a.id,
  de.decision,
  de.facts,
  de.no_ego,
  de.numbers_ok,
  de.worst_case,
  de.simple,
  de.approved,
  de.follow_up
FROM (VALUES
  ('2026-03-20', 'P001', 'Slab',   'Accepted slightly higher slump after verifying pumpability and finish risk', 1,1,1,1,1, 'Yes', ''),
  ('2026-03-21', 'P002', 'Column', 'Split Ali between 2 projects due to priority',                               1,1,1,1,1, 'Yes', '')
) AS de(date, proj_code, act_name, decision, facts, no_ego, numbers_ok, worst_case, simple, approved, follow_up)
JOIN projects   p ON p.code = de.proj_code AND p.user_id = :'user_id'
JOIN activities a ON a.name = de.act_name  AND a.user_id = :'user_id';
