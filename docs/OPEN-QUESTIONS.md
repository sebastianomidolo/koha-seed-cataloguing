# Open questions

Design decisions not yet resolved. Each item records what is known, what is
uncertain, and what would help reach a decision.

---

## 1. Source of vernacular names — CoL API vs CoL website

**Status:** under investigation by EBo (2026-07-08)

The CoL website shows 35+ vernacular names for taxa that the ChecklistBank API
(3LR dataset) returns zero for. EBo is checking the CoL/ChecklistBank code
repository to find the actual upstream source (likely GBIF).

**Do not implement any fallback until EBo's investigation is complete.**

Once the source is identified, add it as a new `Source/XYZ.pm` driver or as a
secondary lookup within `Source/CoL.pm`.

---

## 2. Multilingual vernacular names in MARC

**Status:** raised by EBo (2026-07-08), not yet discussed

*Physostegia virginiana* has vernacular names in 10–20 languages: Japanese
(カクトラノオ), Ukrainian (Фізостегія віргінська), etc. MARC 754 `$d` has no
language qualifier subfield.

Options:
- Store only the primary English name in `754 $d` and `110 $b`; put the full
  multilingual table in the `910 $b` JSON blob
- Use multiple `$d` subfields with the language suffix kept in the string
  (e.g. "obedient plant (EN)", "カクトラノオ (JA)") — readable but not structured
- Use MARC 880 (Alternate Graphic Representation) linked via `$6` for non-Latin
  scripts — standard but adds significant complexity

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
