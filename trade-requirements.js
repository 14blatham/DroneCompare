// trade-requirements.js
// Shared logic for all drone service requirement forms (Aerial Survey, Roof Inspection, Thermal Imaging, Mapping & 3D Models)

import { supabase, getUser } from './supabase-config.js';

export function initTradeRequirementForm(tradeType) {
  const form = document.querySelector('form') || document.querySelector('[type="submit"]')?.closest('form') || document.body;
  const submitBtn = document.querySelector('button[type="submit"]');
  if (!submitBtn) return;

  // Find form fields by label text (works across all requirement pages)
  function findInputByLabel(labelText) {
    const labels = document.querySelectorAll('label');
    for (const label of labels) {
      if (label.textContent.toLowerCase().includes(labelText.toLowerCase())) {
        const parent = label.closest('div') || label.parentElement;
        return parent.querySelector('input, select, textarea');
      }
    }
    return null;
  }

  // Get selected service category from radio buttons
  function getServiceCategory() {
    const checked = document.querySelector('input[name="service_type"]:checked');
    if (checked) {
      const label = checked.closest('label');
      const text = label?.querySelector('.font-label')?.textContent?.trim();
      return text || '';
    }
    return '';
  }

  submitBtn.addEventListener('click', async (e) => {
    e.preventDefault();

    const postcode = findInputByLabel('postcode')?.value || findInputByLabel('location')?.value || '';
    const budget = findInputByLabel('budget')?.value || '';
    const scope = findInputByLabel('scope')?.value || findInputByLabel('notes')?.value || '';
    const name = findInputByLabel('name')?.value || '';
    const phone = findInputByLabel('contact')?.value || findInputByLabel('phone')?.value || '';
    const serviceCategory = getServiceCategory();

    if (!postcode || !name) {
      alert('Please fill in at least your postcode and name.');
      return;
    }

    submitBtn.innerHTML = '<span class="inline-block w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin align-middle mr-2"></span>Submitting...';
    submitBtn.disabled = true;

    try {
      const { user } = await getUser();

      // 1. Create the project
      const { data: project, error: projErr } = await supabase.from('projects').insert({
        homeowner_id: user?.id || null,
        trade_type: tradeType,
        survey_type: serviceCategory,
        property_postcode: postcode,
        contact_name: name,
        contact_phone: phone,
        contact_email: user?.email || null,
        scope_notes: scope,
        budget_range: budget,
        status: 'open'
      }).select().single();

      if (projErr) throw projErr;

      // 2. Create detailed trade requirement
      await supabase.from('trade_requirements').insert({
        project_id: project.id,
        trade_type: tradeType,
        service_category: serviceCategory,
        budget_range: budget,
        scope_notes: scope,
        postcode: postcode,
        contact_name: name,
        contact_number: phone
      });

      // Lead matching to suppliers happens server-side via a database
      // trigger on `projects` insert — no client-side step needed here.

      // 3. Redirect to quotes
      window.location.href = 'quotes.html?project=' + project.id;
    } catch (err) {
      submitBtn.textContent = 'Request Expert Consultation';
      submitBtn.disabled = false;
      alert('Something went wrong: ' + (err.message || 'Please try again.'));
    }
  });
}
