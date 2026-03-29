/**
 * env.js — Injected by Vercel Edge Middleware or a build step.
 *
 * This file is served from /public/env.js and sets window.__ENV__
 * so that src/lib/supabase.js can read the keys without a bundler.
 *
 * In production, Vercel replaces the placeholder strings at deploy time
 * using the environment variables configured in the project dashboard.
 *
 * During local development, replace the empty strings with your
 * values from .env.local (never commit real keys).
 */
window.__ENV__ = {
  SUPABASE_URL:      process.env.SUPABASE_URL      || '',
  SUPABASE_ANON_KEY: process.env.SUPABASE_ANON_KEY || '',
};
