# Open questions

Design decisions not yet resolved. Each item records what is known, what is
uncertain, and what would help reach a decision.

---

## 1. Source of vernacular names — CoL API vs CoL website

**Status:** RESOLVED (2026-07-11, seba)

The `3LR` dataset genuinely lacks vernacular names; the `3LXR` (eXtended
release) dataset carries them, exposed on the `/taxon/{id}/info` endpoint under
`vernacularNames` (NOT the `/taxon/{id}/vernacularname` sub-resource, which
404s — the original bug). `Source/CoL.pm` now uses `3LXR` + `/info` and returns
35 names for *Sanguinaria canadensis*. No external fallback source (GBIF etc.)
is needed.

---

## 2. Multilingual vernacular names in MARC

**Status:** RESOLVED (2026-07-11, seba + EBo) — inline ISO 639-3 tag in `754 $d`

Chosen: multiple `$d` subfields, each with the language kept inline as an
ISO 639-3 code in parentheses — `bloodroot (eng)`, `血根草 (zho)`,
`Gatgwéhsai's (see)`. Names the API supplies with no language code go out bare.

Why 639-3 (3-letter) rather than EBo's original 2-letter sketch: the API's
`vernacularNames` already carries 639-3 codes (34/35 entries), and 639-3 is
lossless for indigenous languages that have no 2-letter (639-1) code — exactly
the names a heritage seed library most wants to keep (Seneca `see`, Ojibwe
`oji`, Mohawk `moh`, Micmac `mic`, Choctaw `cho`). Mapping down to 2-letter
would silently drop those tags.

Implementation: `Source/CoL.pm` returns two parallel lists — `common_names`
(clean, English-first; feeds the `110 $b` heading and `245 $b`) and
`common_names_tagged` (feeds `754 $d`). The rare inline `(EN)` suffix in the
source is normalised to `(eng)`. Not using 880/`$6` — overkill for a readable
catalog entry; can revisit if non-Latin display becomes a requirement.

---

## 3. Depth of taxonomic hierarchy in field 754

**Status:** raised by EBo's botanist contact (2026-07-08), not yet decided

A botanist suggested recording only family, genus, and species in 754 — not the
full hierarchy (kingdom → phylum → class → order → family → genus → species).

Arguments for **full hierarchy:**
- Complete scientific record
- Future-proofs for research use cases

Arguments for **family/genus/species only:**
- What gardeners and farmers actually care about
- What real-world seed library spreadsheets typically record
- Fewer fields = cleaner record = less confusion

Real-world data analysis (see question 5 below) may settle this.

---

## 4. Collection event identifier in field 245

**Status:** raised by EBo, not yet designed

The current 245 stub (`$a Seed collection : $b [species], [location], [year]`)
works for a single collection event but does not include an event identifier.
For commercially purchased seeds a lot number would be needed instead.

The format of a proper collection event ID and whether it goes in 245 `$b`,
a local field, or elsewhere has not been decided.

---

## 5. Real-world data analysis

**Status:** proposed by Seba (2026-07-08), EBo asked about availability

The system is being designed top-down (MARC21, CoL, controlled vocabularies)
without much real-world seed library data to test assumptions against. Many
seed communities manage perfectly well with Excel or Access files, and those
files implicitly encode what information actually matters in practice.

Proposal: obtain a few real-world seed library spreadsheets or databases and
analyse what fields they record, what they search by, and what they leave blank.
This would ground design decisions (especially questions 3 and 4 above) in
observed practice rather than theory.

EBo has been asked whether he has access to such data.

---

## 6. 910 $b JSON blob — import reliability

**Status:** bug observed, cause unknown

The JSON payload in `910 $b` does not survive MARCXML import into Koha — only
`910 $a` comes through. Likely a field length or character encoding issue in
Koha's importer. Not yet investigated.

---

## 7. Seed packet items (Koha 952)

**Status:** not yet started

The plugin currently stages species-level bibliographic records only. Seed packet
items (Koha 952 field, linked to a biblionumber) are not yet handled. The
relationship between a species record, a collection event record, and individual
seed packets needs to be designed.
