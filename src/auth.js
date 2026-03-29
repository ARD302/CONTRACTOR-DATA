/**
 * auth.js — Authentication module
 *
 * Wraps Supabase Auth with app-specific helpers:
 *   • signUp / signIn / signOut
 *   • password reset flow
 *   • session & user getters
 *   • auth state change listener
 *   • route guard (redirects to /login.html when unauthenticated)
 *
 * All public-facing functions return { data, error } objects mirroring
 * the Supabase SDK convention so callers can handle errors uniformly.
 */

import { supabase } from './lib/supabase.js';

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const LOGIN_PAGE = '/login.html';
const APP_PAGE   = '/index.html';

// ---------------------------------------------------------------------------
// Sign up with email + password
// Optional metadata: { full_name, company_name }
// ---------------------------------------------------------------------------
export async function signUp(email, password, meta = {}) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: {
      data: meta,              // stored in raw_user_meta_data → picked up by handle_new_user trigger
      emailRedirectTo: `${location.origin}${APP_PAGE}`,
    },
  });
  return { data, error };
}

// ---------------------------------------------------------------------------
// Sign in with email + password
// ---------------------------------------------------------------------------
export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  return { data, error };
}

// ---------------------------------------------------------------------------
// Sign out (clears local session)
// ---------------------------------------------------------------------------
export async function signOut() {
  const { error } = await supabase.auth.signOut();
  if (!error) {
    window.location.href = LOGIN_PAGE;
  }
  return { error };
}

// ---------------------------------------------------------------------------
// Get the currently active session (null if not logged in)
// ---------------------------------------------------------------------------
export async function getSession() {
  const { data, error } = await supabase.auth.getSession();
  return { session: data?.session ?? null, error };
}

// ---------------------------------------------------------------------------
// Get the currently logged-in user object (null if not logged in)
// Prefers the cached session; falls back to a network call.
// ---------------------------------------------------------------------------
export async function getUser() {
  const { data, error } = await supabase.auth.getUser();
  return { user: data?.user ?? null, error };
}

// ---------------------------------------------------------------------------
// Send a password-reset e-mail
// ---------------------------------------------------------------------------
export async function sendPasswordReset(email) {
  const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${location.origin}/reset-password.html`,
  });
  return { data, error };
}

// ---------------------------------------------------------------------------
// Update the password after the user follows the reset link
// Call this from reset-password.html once the session is confirmed.
// ---------------------------------------------------------------------------
export async function updatePassword(newPassword) {
  const { data, error } = await supabase.auth.updateUser({ password: newPassword });
  return { data, error };
}

// ---------------------------------------------------------------------------
// Auth state change listener
// callback(event, session) is called whenever the auth state changes:
//   SIGNED_IN | SIGNED_OUT | TOKEN_REFRESHED | USER_UPDATED | PASSWORD_RECOVERY
// Returns an unsubscribe function.
// ---------------------------------------------------------------------------
export function onAuthChange(callback) {
  const { data: { subscription } } = supabase.auth.onAuthStateChange(callback);
  return () => subscription.unsubscribe();
}

// ---------------------------------------------------------------------------
// Route guard — call at the top of every protected page
//
// If the user is NOT authenticated, redirects to LOGIN_PAGE immediately.
// Returns the user object so the page can skip a second getUser() call.
//
// Usage (top of index.html <script type="module">):
//   import { requireAuth } from './src/auth.js';
//   const user = await requireAuth();
//   // rest of page init …
// ---------------------------------------------------------------------------
export async function requireAuth() {
  const { session, error } = await getSession();

  if (error || !session) {
    window.location.replace(LOGIN_PAGE);
    // Halt execution — the redirect is async so throw to stop further JS.
    throw new Error('Unauthenticated — redirecting to login.');
  }

  return session.user;
}

// ---------------------------------------------------------------------------
// Redirect guard for the login page itself
// If the user IS already authenticated, send them straight to the app.
//
// Usage (top of login.html <script type="module">):
//   import { redirectIfAuthenticated } from './src/auth.js';
//   await redirectIfAuthenticated();
//   // render login form …
// ---------------------------------------------------------------------------
export async function redirectIfAuthenticated() {
  const { session } = await getSession();
  if (session) {
    window.location.replace(APP_PAGE);
  }
}
