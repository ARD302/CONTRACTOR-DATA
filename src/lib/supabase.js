/**
 * supabase.js — Supabase client singleton
 *
 * Reads SUPABASE_URL and SUPABASE_ANON_KEY from:
 *   • Vercel environment variables injected at build time (window.__ENV__)
 *   • Or directly from the module-level constants below for local dev
 *
 * Usage:
 *   import { supabase } from './lib/supabase.js';
 *   const { data, error } = await supabase.from('projects').select('*');
 */

import { createClient } from 'https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/+esm';

// ---------------------------------------------------------------------------
// Environment resolution
// Vercel injects a <script> tag that sets window.__ENV__ at build time.
// Fall back to empty strings so the app fails loudly instead of silently.
// ---------------------------------------------------------------------------
const env = (typeof window !== 'undefined' && window.__ENV__) || {};

const SUPABASE_URL      = env.SUPABASE_URL      || '';
const SUPABASE_ANON_KEY = env.SUPABASE_ANON_KEY || '';

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error(
    '[supabase] Missing environment variables. ' +
    'Ensure SUPABASE_URL and SUPABASE_ANON_KEY are set in Vercel.'
  );
}

// ---------------------------------------------------------------------------
// Client options
// ---------------------------------------------------------------------------
const clientOptions = {
  auth: {
    // Persist session in localStorage so the user stays logged in across reloads.
    persistSession: true,
    autoRefreshToken: true,
    // Detect OAuth/magic-link callbacks from the URL hash.
    detectSessionInUrl: true,
    // Use PKCE flow for improved security with SPA.
    flowType: 'pkce',
  },
  global: {
    headers: {
      // Add a custom header so requests are identifiable in Supabase logs.
      'x-application-name': 'contractor-mgmt',
    },
  },
};

// ---------------------------------------------------------------------------
// Singleton export
// ---------------------------------------------------------------------------
export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, clientOptions);

// ---------------------------------------------------------------------------
// Convenience: typed table helpers (avoids typo'd table names)
// ---------------------------------------------------------------------------
export const DB = {
  profiles:   () => supabase.from('profiles'),
  projects:   () => supabase.from('projects'),
  workers:    () => supabase.from('workers'),
  activities: () => supabase.from('activities'),
  payroll:    () => supabase.from('payroll_entries'),
  materials:  () => supabase.from('material_entries'),
  cost:       () => supabase.from('cost_entries'),
  daily:      () => supabase.from('daily_entries'),
  decisions:  () => supabase.from('decision_entries'),
};

// ---------------------------------------------------------------------------
// Convenience: view helpers
// ---------------------------------------------------------------------------
export const VIEWS = {
  projectSummary: () => supabase.from('project_summary'),
  dashboardKpi:   () => supabase.from('dashboard_kpi'),
};
