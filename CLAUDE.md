# CLAUDE.md

Guardrails for working in this repo. Full setup/architecture docs live in
[`README.md`](./README.md) - this file is what to check *before* acting,
not a duplicate of it.

**Project**: pulls KPI data from HubSpot and publishes it as a web
dashboard on Azure Container Apps behind Entra ID sign-in, refreshed twice
daily via GitHub Actions. See README for the full pipeline
("Automation and deployment (Azure)").

## Rule: check both skills before any `dashboard/` change

Before considering **any** change to `dashboard/` done - the three
`template_*.html` files, `build_dashboard.py`, or `build_locked.py` -
check it against **both**:

- **`.claude/skills/web-design-guidelines`** - interaction/accessibility
  rules (focus states, semantic HTML, `prefers-reduced-motion`, touch
  targets, keyboard support, ARIA).
- **`gcs-design-system`** - brand tokens (colors, fonts, spacing: Night
  Blue `#000957`, Electric Blue `#3F8CFF`, Yrsa/Heebo, the `--chart-1..5`
  categorical palette).

This is a hard requirement, not a nicety: a change that skips this check
is not finished, even if it looks right.

## Things that will bite you if you don't know them

- **Credentials never get hardcoded or committed.** `HUBSPOT_ACCESS_TOKEN`
  comes from `.env` locally (gitignored) or the repo secret of the same
  name in CI. Never print or log a token value. (`DASHBOARD_PASSWORD` is
  no longer used.)
- **Retained Clients links to a deal; Referred Clients links to a
  contact** - not interchangeable, and not just a UI choice. A retained
  client always has a closed deal, so it click-throughs to the **deal**
  record (`meta.deal_url_base`); a referred contact doesn't need one, so
  it click-throughs to the **contact** record (`meta.contact_url_base`).
  Respect this asymmetry if a future stage gets click-through added.
- **The page and the dataset are never committed.** The dashboard holds
  real client and intermediary names. `dashboard/data/kpi-data.json` and
  `outputs/` are gitignored; CI regenerates them and bakes `outputs/index.html`
  into the Azure image. Don't "fix" the `.gitignore` to track them, and don't
  re-add a step that commits them. The page is plaintext, so Entra sign-in
  with "assignment required" (a user group) is its only lock: don't share the
  URL before that is set.
- **Scheduled runs only run from the GitHub default branch**, and the push
  trigger watches `main`: `main` must be the default branch or the schedule
  and the redeploy-on-push never fire.
- **Azure setup is outside this repo** (identity, `production` Environment,
  `AZURE_*` variables, `GHCR_PULL_TOKEN`, the Entra sign-in app). A failing
  Azure login, image pull or sign-in check is a setup problem before it is a
  workflow bug; see README.
- **`dashboard/data/kpi-data.json` is generated, not hand-edited.** It exists
  only locally (run `generate_report.py`) and in the CI workspace.
- **The Excel workbook is dormant, not deleted.** `build_workbook()` and
  its styling helpers still exist in `generate_report.py` but aren't
  called from `main()` any more (see README's "Excel workbook (dormant)"
  section). Don't resurrect it into the pipeline without confirming
  that's actually wanted.
- **`reports/reports.xlsx` and `outputs/vercel/index.html` are git-tracked
  leftovers, not source.** `reports.xlsx` is the dormant Excel output (it
  holds real KPI rows: keep the repo private). `outputs/vercel/index.html` is
  the old password-locked build, no longer updated, there only until the
  Vercel project is retired; delete it then. Never hand-edit them, and never
  `rm -rf` a directory that might contain one without checking `git status`
  first.
- **If replicating this pattern in another project**, confirm which
  branch is actually set as that repo's GitHub default branch - scheduled
  workflows only run from it.
