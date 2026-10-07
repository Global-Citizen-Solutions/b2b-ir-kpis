# B2B Intermediary-Referral KPI Report Generator

Pulls deal, meeting and contact data from HubSpot and tracks five
year-to-date stages (Retained Clients, Referred Clients, Presentations,
Calls/Meetings, New Intermediaries) for the Institutional Relations BDMs
(João Pacheco Gonçalves and Rohan Harris).

The primary output today is the **[web dashboard](#web-dashboard)**
(`dashboard/data/kpi-data.json`, refreshed twice daily via GitHub Actions and
published on Azure Container Apps). An Excel-workbook output also exists in this file
(`build_workbook()` and its styling helpers) but is currently **dormant**
- not run automatically, not wired into `main()` - kept in case it's
needed again later; see [Excel workbook (dormant)](#excel-workbook-dormant)
below if you want to regenerate one manually.

## Setup

1. **Create a virtual environment and install dependencies:**

   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   pip install -r requirements.txt
   ```

2. **Get a HubSpot token.**

   Preferred: a **Service Key** - Settings → Integrations → Service Keys
   (or Development → Keys → Service Keys, currently in public beta). This
   is HubSpot's recommended credential for a scheduled, data-only script
   with no webhooks or UI extensions.

   Fallback: a legacy-style **Private App** access token (Settings →
   Integrations → Private Apps) works as a drop-in replacement with zero
   code changes - both are used identically as an `Authorization: Bearer`
   header.

   Grant exactly these scopes, no more:

   | Scope | Used for |
   |---|---|
   | `crm.objects.contacts.read` | Contact search/associations, meetings retrieval |
   | `crm.objects.deals.read` | Deal search, batch-read, pipelines/stages, meeting↔deal associations |
   | `crm.objects.owners.read` | Owner list |
   | `crm.schemas.contacts.read` | Contact property metadata |
   | `crm.schemas.deals.read` | Deal property metadata |

3. **Configure the token:**

   ```bash
   cp .env.example .env
   # edit .env and paste the token as HUBSPOT_ACCESS_TOKEN=...
   ```

   `.env` is gitignored and must never be committed.

## Running it

```bash
python generate_report.py
```

The script is idempotent - safe to re-run any time. It overwrites
`dashboard/data/kpi-data.json` cleanly on every run and leaves no state
behind between runs. It prints, in order:

1. **Step 0** - every ID/value it resolved from the portal (association
   labels, the lead-source property, pipeline/stage IDs, the
   `lifecyclestage` "Customer" value, and the two BDMs' owner IDs) so you
   can sanity-check them against your portal before trusting the numbers
   below.
2. Each stage's own diagnostics as it's computed - counts, and any
   anomalies it found along the way (referred contacts with no recorded
   introducer, contacts with multiple qualifying deals, meetings already
   booked for a future date, etc.), so a data-quality gap is visible
   immediately rather than buried in a final total.
3. A final **Year-to-Date Summary** - one line per stage with its current
   grand total.

On any failure (missing token, a HubSpot API error, rate-limiting
exhausted after retries) the script exits non-zero with a clear message
on stderr.

### Reading the numbers

Every stage is scoped to **this calendar year, through today** - a
meeting already booked for next week, or a deal signed last year, is
excluded from the current total (the script tells you when it excludes
something like that, and why). Because of this, the totals move day to
day, and don't chase a single fixed "expected" figure the way an
all-time report would. Two things worth knowing if a number looks lower
than you expected:

- **Retained Clients** in particular can look small this early in the
  year - it only counts deals actually signed within the current year, so
  a deal signed last year for a client referred last year won't show up
  even though that client is genuinely retained.
- Any KPI-population gap the script finds (e.g. a Partner-Referral
  contact with no recorded introducer association) is logged with the
  specific contact/deal IDs responsible, not silently dropped.

### Terminology note

HubSpot's underlying property is genuinely called **Deal Owner**
(`hubspot_owner_id`) and the code, API calls and variable names all use
that name throughout, since that's what the field actually is in the CRM.
Both outputs rename this: every user-facing label says **"BDM"** instead
- a display-only substitution.

## Excel workbook (dormant)

`build_workbook()` and its GCS-styled sheet-builder helpers are still in
`generate_report.py`, fully working, just not called from `main()` any
more and not run by any workflow - the dashboard replaced the workbook as
the primary deliverable, and the two were never dependent on each other
(the dashboard reads `dashboard/data/kpi-data.json` only). To regenerate
`reports/reports.xlsx` manually, call `build_workbook(kpi_data_list,
retained_program_breakdown, ref, today)` yourself (see the git history
before this change, or `main()`'s old structure, for how the pieces fit
together) - one tab per Stage with a Month→Week→Day column drill-down via
Excel's native outline grouping, a Retained Clients row-level drill-down
by Country/Program of Interest, a Calls-Meetings "% of Target" column,
and a static KPI Targets reference tab.

## Web dashboard

`generate_report.py` writes `dashboard/data/kpi-data.json` - the computed
numbers, reshaped for a live web dashboard published on Azure Container
Apps. This is the primary output today (the Excel workbook above is
dormant).

The dashboard follows the same pattern as the sibling
`gcs-hubspot-funnel-reporting` project: no framework, no server. A small
Python build step inlines the JSON dataset and the GCS logos into three
HTML templates (`dashboard/template_head.html`, `template_body.html`,
`template_js.html`), producing one self-contained, plaintext
`outputs/index.html`. Access control is company Microsoft (Entra ID)
sign-in in front of the app; the page itself is no longer encrypted, so
it, and the dataset behind it, are never committed (see below).

### Building it locally

```bash
python generate_report.py                                    # writes dashboard/data/kpi-data.json
python3 dashboard/build_dashboard.py                          # -> outputs/index.html
```

Open `outputs/index.html` directly in a browser to preview the dashboard -
no server needed. (`dashboard/build_locked.py`, the old client-side password
lock, is kept but no longer part of the pipeline.)

### Automation and deployment (Azure)

`.github/workflows/dashboard-data.yml` runs twice daily (08:00 and 15:00
Europe/Lisbon local time), on `workflow_dispatch`, and on pushes to `main`
that touch the code behind the page. Each run: fetches from HubSpot
(`generate_report.py`, `HUBSPOT_ACCESS_TOKEN`), builds the plaintext
`outputs/index.html`, bakes it into a small nginx image (`Dockerfile`),
pushes that to GHCR (`ghcr.io/global-citizen-solutions/b2b-ir-kpis`) and
calls
[`gcs-azure-infrastructure`](https://github.com/Global-Citizen-Solutions/gcs-azure-infrastructure)'s
reusable `deploy-container-app.yml` with Entra ID sign-in on. **Nothing is
committed back**: the page and `dashboard/data/kpi-data.json` hold real
client and intermediary names, so they only live in the run's workspace and
in the image (both are gitignored).

```
HubSpot API
    │  generate_report.py (HUBSPOT_ACCESS_TOKEN secret)
    ▼
dashboard/data/kpi-data.json         (gitignored, CI workspace only)
    │  dashboard/build_dashboard.py
    ▼
outputs/index.html                   (gitignored, plaintext)
    │  Dockerfile (nginx) -> ghcr.io/global-citizen-solutions/b2b-ir-kpis
    ▼
Azure Container App 'b2b-ir-kpis' in cae-prod, behind Entra ID sign-in
```

Same guard as before: the cron fires at both possible UTC offsets and a
tolerant Lisbon-hour check skips a scheduled firing that is outside the
06:00-21:59 window (a manual run always proceeds); a skipped firing also
skips the deploy.

**Scheduled runs only run from the repository's default branch**, and the
push trigger watches `main`, so `main` must be the GitHub default branch
(until the move it was `claude/b2b-ir-kpi-report-generator-3e46eq`).

**Who can open it**: the Entra app registration `easyauth-b2b-ir-kpis` must
have "assignment required" with a user group (the tenant convention is
`eid_<app>_users`) before the URL is shared. The page is plaintext, so that
is its only lock.

#### One-time setup (not triggered by pushing code)

Lives outside this repo, see `gcs-azure-infrastructure`'s
`docs/getting-started.md`:

- `./scripts/onboard-app-repo.sh b2b-ir-kpis --dedicated-identity`
- GitHub Environment `production` (deployments from `main` only), variables
  `AZURE_CLIENT_ID` / `AZURE_TENANT_ID` / `AZURE_SUBSCRIPTION_ID`, secret
  `GHCR_PULL_TOKEN` (classic PAT, `read:packages`).
- `./scripts/create-entra-auth-app.sh b2b-ir-kpis --github-repo b2b-ir-kpis`
  (sets `ENTRA_CLIENT_ID` / `ENTRA_CLIENT_SECRET`); run it once more after the
  first deploy to register the app's callback URL.
- Repository secret `HUBSPOT_ACCESS_TOKEN` (already there). `DASHBOARD_PASSWORD`
  is no longer used and can be deleted.

If a run fails at Azure login, image pull or the sign-in check, suspect that
setup before the workflow.

**Adapting this for another project**: the reusable idea is the
JSON-in-the-middle handoff - decoupling "fetch your data" from "build the
page" means either half can change independently, and the page-build step
never needs credentials for whatever you're fetching from. For data that is
not public, keep the page and dataset out of git and put real sign-in in
front of it, as here.

### What's on the dashboard

Stage order throughout the dashboard: **Retained, Referred,
Presentations, Calls/Meetings, New Intermediaries** - independent of the
(dormant) Excel workbook's own tab order, via `DASHBOARD_STAGE_ORDER` in
`generate_report.py`.

- **KPI cards** for all 5 stages, split by BDM, for the selected period
  (Year to Date or any individual month); the Calls/Meetings card shows
  each BDM's percentage of their 440/year target alongside the raw count.
- **Funnel by BDM**: a stacked bar per stage showing each BDM's share.
- **Trend**: a line chart, one line per stage, with a **Both / João /
  Rohan** filter above it. Year to Date shows monthly totals across the
  year; selecting a specific month switches the x-axis to that month's
  weeks instead.
- **Stage performance by BDM**: BDM rows (João, Rohan, Grand Total) x
  stage columns, in this order - Retained, Retained Target (`n/12` per
  BDM, `n/24` combined - a pacing indicator, not a formula), Referred,
  Presentations, Calls/Meetings, Calls/Meetings Target (actual/440 with
  a percentage, `x/880` combined), New Intermediaries, Total (the sum of
  the 5 raw count columns for the selected period).
- **Click-through to HubSpot**: every populated Retained or Referred
  number, in the KPI cards, the Funnel bars, and the table, is clickable
  - exactly one matching record opens directly in HubSpot; more than one
  opens a small modal listing each by name, linked to its own record.
  Retained Clients links to the underlying **deal** (a retained client
  always has one); Referred Clients links to the **contact** (a referred
  contact doesn't need a deal to count, so there isn't always one to
  link to).

Numbers refresh once a day.

### Keeping this on-brand and accessible

Any future change to `dashboard/` should be checked against
**`.claude/skills/web-design-guidelines`** (interaction/accessibility
rules - focus states, semantic HTML, `prefers-reduced-motion`, etc.) and
the **`gcs-design-system`** skill's tokens (colors, fonts, spacing) before
being considered done - both were applied deliberately throughout this
dashboard and should stay that way as it evolves.
