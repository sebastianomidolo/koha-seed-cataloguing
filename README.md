# koha-seed-cataloguing

A Koha staff plugin for seed libraries and seed banks. It fetches species data from
the [Catalogue of Life](https://www.catalogueoflife.org/) and generates MARC21
bibliographic records ready for review and import into Koha.

**Status:** early working prototype, tested on Koha 25.11 / OpenSearch.  
**Licence:** GPLv3 (intended)  
**Authors:** Sebastiano Midolo and John "EBo" David

---

## What it does

1. A cataloguer types a scientific name into the plugin search form.
2. The plugin queries the Catalogue of Life API and shows a list of matching taxa.
3. The cataloguer picks one and sees a full MARC preview.
4. On confirmation the record is **staged** (not immediately imported) into Koha's
   native import batch system, with duplicate detection via a matching rule on
   `110 $0` (the CoL taxon URI).
5. A librarian reviews the staged batch at Tools → Manage staged MARC records and
   commits it. Duplicates are flagged automatically — the librarian decides what to do.

---

## Files

```
Koha/Plugin/SeedCataloguing.pm          — Koha plugin shell (UI, CSRF, staging)
Koha/Plugin/SeedCataloguing/
    MARCBuilder.pm                      — normalised species hash → MARC21 record
    Source/
        CoL.pm                          — Catalogue of Life / ChecklistBank API driver
deploy-to-lecat.sh                      — development deploy script (see KOHA-deploy.md)
docs/
    MARC-decisions.md                   — MARC field choices and rationale
    ARCHITECTURE.md                     — plugin design and data flow
    API-notes.md                        — Catalogue of Life API quirks and known issues
    KOHA-deploy.md                      — how to deploy and update on a Koha instance
    OPEN-QUESTIONS.md                   — design questions not yet resolved
```

---

## Requirements

- Koha 25.11 or later with the plugin system enabled
- OpenSearch (the plugin uses the `SEEDCOL` record matching rule on an ES-indexed field)
- The following Perl modules (all present in a standard Koha installation):
  `MARC::Record`, `MARC::Field`, `C4::Biblio`, `C4::Matcher`, `C4::ImportBatch`,
  `LWP::UserAgent`, `JSON`, `URI::Escape`, `Koha::Token`
- Internet access from the Koha server to `api.checklistbank.org`

---

## One-time Koha setup (before first use)

These steps are needed once on the target Koha instance. See `docs/KOHA-deploy.md`
for full details.

1. Create bibliographic framework **SEED** (clone of Default).
2. Create item type **SEED**.
3. Add OpenSearch field `seed-col-uri` mapped to `110 $0`.
4. Create Record Matching Rule **SEEDCOL** matching on `seed-col-uri`, threshold 1000.
5. Deploy plugin files and restart Plack.

---

## Deployment

```bash
cd /path/to/koha-seed-cataloguing
bash deploy-to-lecat.sh        # copies files to the Koha plugin directory
sudo koha-plack --restart lecat
```

See `docs/KOHA-deploy.md` for the full procedure and the mandatory Plack restart rule.

---

## Known limitations

- **Vernacular name coverage**: the Catalogue of Life API (ChecklistBank dataset 3LR)
  does not return vernacular names for all species. The CoL website shows richer name
  data whose exact source is under investigation (possibly GBIF). A fallback source
  will be added once the upstream source is identified.
- **910 $b JSON blob**: a full collection-event JSON payload is planned for field 910,
  but the mechanism for importing it reliably is still under development.
- **No item creation**: the plugin stages species-level records only. Seed packet items
  (952 field) are not yet handled.
