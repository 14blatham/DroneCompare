# SkyCompare — Drone Professional Directory & Price Comparison

A directory and price comparison platform for **commercial clients** that connects them directly with **verified drone professionals**.

## How it works (clients)
1. **Submit Your Details** — input your property details and the specific drone service you need.
2. **Instant Matching** — the system instantly generates a list of qualified local drone professionals covering your exact area, complete with price estimates, qualifications, and full contact details.
3. **Direct Communication** — you receive the operator's direct details to negotiate, ask questions, and book the job independently.
4. **Independent Hiring** — you contract and pay the operator directly. The platform takes **no commission**; operators pay a small fee to be listed.

## How it works (drone operators)
1. **Account & Control Panel** — register your company and manage your business parameters: exact postcode districts you cover, and your own price estimates per property criteria (used to show live estimates to clients).
2. **Live Lead Generation** — when a client's criteria match your profile rules, they instantly see your company name, price estimate, qualifications and contact details, while the lead is sent to you simultaneously. No middleman, no delay.
3. **No Commission Fees** — you never pay commission on jobs you win. Deal directly with the client to negotiate, finalise the price, and collect payment.
4. **Cost-Per-Lead Model** — £0 joining / monthly / annual / exit fees. You only pay a small advertising fee per lead, billed automatically via direct debit.

## Pages
- `index.html` — public landing page
- `service.html` — multi-step client intake form (main flow → quotes)
- `AerialSurveyRequirements.html`, `RoofInspectionRequirements.html`, `ThermalImagingRequirements.html`, `MappingRequirements.html` — per-service intake forms
- `quotes.html` — client results dashboard (live comparison of matched operators)
- `supplier.html` — operator onboarding portal
- `dashboard.html` — operator control panel (coverage, pricing rules, leads)
- `loginpage.html`, `signuppage.html`, `emailverificationlandingpage.html`, `reviewsubmission.html`

## Stack
- Static HTML + Tailwind CSS (CDN) — Material Design 3 token palette, Newsreader + Manrope typography
- Supabase (auth, Postgres, RLS, server-side lead-matching trigger) — see `supabase-schema-v2.sql`
- `supabase-config.js` — client + auth helpers · `trade-requirements.js` — shared intake form logic · `page-transitions.js` — page fade transitions

## Setup
1. Create a Supabase project and run `supabase-schema-v2.sql` (or the migration block at the bottom for an existing DB).
2. Update the Supabase URL/anon key in `supabase-config.js`.
3. Deploy as a static site (e.g. Vercel).
