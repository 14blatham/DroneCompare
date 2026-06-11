// supabase-config.js — single Supabase client for all pages (ES module)

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SUPABASE_URL = 'https://tsbhsputwmildvfrwmld.supabase.co';
const SUPABASE_ANON_KEY = 'sb_publishable_Zx_wQhKCTrwv2tmsNrK3eQ_fQC-QQ6k';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);


// ============================================================
// AUTH HELPERS — all return { data, error } or { user, error }
// ============================================================

export async function signUp(email, password, metadata = {}) {
  const { data, error } = await supabase.auth.signUp({
    email,
    password,
    options: { data: metadata }
  });
  return { data, error };
}

export async function signIn(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  return { data, error };
}

export async function signInWithGoogle() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'google',
    options: { redirectTo: window.location.origin + '/emailverificationlandingpage.html' }
  });
  return { data, error };
}

export async function signInWithApple() {
  const { data, error } = await supabase.auth.signInWithOAuth({
    provider: 'apple',
    options: { redirectTo: window.location.origin + '/emailverificationlandingpage.html' }
  });
  return { data, error };
}

export async function signOut() {
  const { error } = await supabase.auth.signOut();
  return { error };
}

export async function getUser() {
  const { data: { user }, error } = await supabase.auth.getUser();
  return { user, error };
}

export async function resetPassword(email) {
  const { data, error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: window.location.origin + '/loginpage.html'
  });
  return { data, error };
}

export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange((event, session) => callback(event, session));
}


// ============================================================
// SUPPLIER QUERIES
// ============================================================

export async function getSuppliersByTrade(tradeType, postcode = null) {
  let query = supabase
    .from('suppliers')
    .select(`*, supplier_postcodes (postcode_prefix)`)
    .eq('trade_type', tradeType)
    .eq('is_active', true)
    .order('rating_avg', { ascending: false });

  const { data, error } = await query;
  if (error) throw error;

  if (postcode && data) {
    const cleaned = postcode.trim().toUpperCase().replace(/\s+/g, '');
    const match = cleaned.match(/^[A-Z]{1,2}[0-9][A-Z0-9]?/);
    const outward = match ? match[0] : cleaned.split(' ')[0];
    const area = outward.replace(/[0-9].*$/, '');
    return data.filter(s =>
      s.postcode_coverage?.includes(outward) ||
      s.postcode_coverage?.includes(area) ||
      s.supplier_postcodes?.some(p => p.postcode_prefix === outward || p.postcode_prefix === area)
    );
  }
  return data;
}

// Anonymous-safe project summary (no contact details) — used by quotes.html
export async function getProjectSummary(projectId) {
  const { data, error } = await supabase
    .from('project_summary')
    .select('*')
    .eq('id', projectId)
    .single();
  if (error) throw error;
  return data;
}

export async function getSupplierById(supplierId) {
  const { data, error } = await supabase
    .from('suppliers')
    .select(`
      *,
      reviews (
        overall_rating, quality_rating, communication_rating,
        value_rating, narrative, created_at,
        profile_public:reviewer_id (full_name)
      ),
      supplier_files (file_type, storage_path, file_name),
      supplier_postcodes (postcode_prefix)
    `)
    .eq('id', supplierId)
    .single();
  if (error) throw error;
  return data;
}

export async function registerSupplier(supplierData) {
  const { data, error } = await supabase
    .from('suppliers')
    .insert([supplierData])
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function updateSupplier(supplierId, updates) {
  const { data, error } = await supabase
    .from('suppliers')
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq('id', supplierId)
    .select()
    .single();
  if (error) throw error;
  return data;
}


// ============================================================
// LEADS (supplier dashboard)
// ============================================================

export async function getLeadsForSupplier(supplierId) {
  const { data, error } = await supabase
    .from('leads')
    .select(`
      *,
      projects:project_id (
        trade_type, property_postcode, property_type,
        contact_name, contact_email, contact_phone,
        scope_notes, budget_range, created_at
      )
    `)
    .eq('supplier_id', supplierId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

export async function respondToLead(leadId, accepted, declineReason = null) {
  const updates = accepted
    ? { status: 'accepted' }
    : { status: 'declined', decline_reason: declineReason };

  const { data, error } = await supabase
    .from('leads')
    .update(updates)
    .eq('id', leadId)
    .select()
    .single();
  if (error) throw error;
  return data;
}


// ============================================================
// QUOTES
// ============================================================

export async function submitQuote(quoteData) {
  const { data, error } = await supabase
    .from('quotes')
    .insert([{
      project_id: quoteData.project_id,
      supplier_id: quoteData.supplier_id,
      price_min: quoteData.price_min,
      price_max: quoteData.price_max,
      message: quoteData.message || null,
      status: 'pending'
    }])
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function getQuotesForProject(projectId) {
  const { data, error } = await supabase
    .from('quotes')
    .select(`*, suppliers (company_name, trade_type, rating_avg, review_count, is_verified)`)
    .eq('project_id', projectId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}


// ============================================================
// REVIEWS
// ============================================================

export async function submitReview(reviewData) {
  const { data, error } = await supabase
    .from('reviews')
    .insert([{
      supplier_id: reviewData.supplier_id,
      reviewer_id: reviewData.reviewer_id || null,
      project_id: reviewData.project_id || null,
      overall_rating: reviewData.overall_rating,
      quality_rating: reviewData.quality_rating || null,
      communication_rating: reviewData.communication_rating || null,
      value_rating: reviewData.value_rating || null,
      narrative: reviewData.narrative || null
    }])
    .select()
    .single();
  if (error) throw error;
  return data;
}

export async function getReviewsForSupplier(supplierId) {
  const { data, error } = await supabase
    .from('reviews')
    .select(`*, profile_public:reviewer_id (full_name)`)
    .eq('supplier_id', supplierId)
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}


// ============================================================
// PROFILE
// ============================================================

export async function getProfile(userId) {
  const { data, error } = await supabase
    .from('profiles')
    .select('*')
    .eq('id', userId)
    .single();
  if (error) throw error;
  return data;
}


// ============================================================
// UI HELPERS
// ============================================================

export function renderStars(rating, maxStars = 5) {
  let html = '';
  for (let i = 1; i <= maxStars; i++) {
    if (i <= Math.floor(rating)) {
      html += '<span class="material-symbols-outlined text-amber-500" style="font-variation-settings: \'FILL\' 1">star</span>';
    } else if (i - 0.5 <= rating) {
      html += '<span class="material-symbols-outlined text-amber-500" style="font-variation-settings: \'FILL\' 1">star_half</span>';
    } else {
      html += '<span class="material-symbols-outlined text-slate-300">star</span>';
    }
  }
  return html;
}

export function showToast(message, type = 'success') {
  const toast = document.createElement('div');
  const bg = type === 'success' ? 'bg-green-600' : type === 'error' ? 'bg-red-600' : 'bg-blue-600';
  toast.className = `fixed bottom-6 right-6 ${bg} text-white px-6 py-3 rounded-lg shadow-lg z-[9999] transition-opacity duration-300`;
  toast.textContent = message;
  document.body.appendChild(toast);
  setTimeout(() => { toast.style.opacity = '0'; setTimeout(() => toast.remove(), 300); }, 3000);
}

export function setLoading(button, loading) {
  if (loading) {
    button.dataset.originalText = button.textContent;
    button.textContent = 'Loading...';
    button.disabled = true;
    button.style.opacity = '0.6';
  } else {
    button.textContent = button.dataset.originalText || 'Submit';
    button.disabled = false;
    button.style.opacity = '1';
  }
}


// ============================================================
// AUTH NAV — update nav on every page that uses data-auth attrs
// ============================================================

async function updateNavForAuth() {
  try {
    const { user } = await getUser();
    const signUpBtn = document.querySelector('[data-auth="signup-btn"]');
    const authMenu = document.querySelector('[data-auth="user-menu"]');

    if (user && signUpBtn) {
      const profile = await getProfile(user.id).catch(() => null);
      signUpBtn.style.display = 'none';
      if (authMenu) {
        authMenu.style.display = 'flex';
        const nameEl = authMenu.querySelector('[data-auth="user-name"]');
        if (nameEl) nameEl.textContent = profile?.full_name || user.email;
      }
    }
  } catch {
    // No active session — nav stays in logged-out state
  }
}

document.addEventListener('DOMContentLoaded', updateNavForAuth);
