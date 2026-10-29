# Catalogue of Life API — notes and known issues

Base URL: `https://api.checklistbank.org/dataset/3LXR`  
Dataset: `3LXR` = Catalogue of Life eXtended release (recommended by CoL; includes full vernacular name data)  
Note: `3LR` (without X) is the standard release and lacks vernacular names for many species — do not use it.  
Authentication: none required (open API)

---

## Endpoints used

| Purpose | Endpoint |
|---|---|
| Search by name | `GET /nameusage/search?q={name}&limit=15&type=EXACT` |
| Taxon details | `GET /taxon/{id}` |
| Classification | `GET /taxon/{id}/classification` |
| Vernacular names + extra data | `GET /taxon/{id}/info` |
| Synonyms | `GET /taxon/{id}/synonym` |

---

## Known issue: `/vernacularname` does not exist

The endpoint `GET /taxon/{id}/vernacularname` returns **404** (it does not exist
in this API, on either `3LR` or `3LXR`) — this was the original cause of the
missing vernacular names. The correct endpoint is `/taxon/{id}/info`, which
returns a `vernacularNames` array.

---

## Language encoding in vernacular names

The `/info` endpoint returns language **two** ways. The dominant form is a
structured `language` field holding an ISO 639-3 code (verified on taxon
`79HDB`: 34 of 35 entries):

```json
{ "name": "Blodrot",  "language": "swe" }
{ "name": "血根草",    "language": "zho" }
{ "name": "Gatgwéhsai's", "language": "see" }
```

Rarely, an entry has no `language` key and encodes it inline as a two-letter
suffix instead (1 of 35 on `79HDB`):

```json
{ "name": "Bloodroot (EN)" }
```

`Source/CoL.pm` handles both: it reads the structured `language` when present,
else parses the inline `(XX)` suffix and maps it to ISO 639-3 (`en` → `eng`).
Names are normalised to `{ name, lang }`, English first. `fetch()` returns two
parallel lists — `common_names` (clean, for `110$b`/`245$b`) and
`common_names_tagged` (`name (iso639-3)`, for `754$d`). See MARC-decisions.md.

---

## Vernacular name coverage — resolved (2026-07-08)

The original `3LR` dataset had uneven vernacular name coverage (zero for many species).
Switching to `3LXR` (eXtended release) resolves this — it includes full multilingual
vernacular name data for all species, with structured `language` fields.

The `3LXR` dataset returns vernacular names in two formats (both handled by the driver):
- Structured: `{"name": "bloodroot", "language": "eng"}`
- Inline suffix: `{"name": "Bloodroot (EN)"}`

---

## Known issue: mixed classification shapes

For some infrafamilial ranks (e.g. the tribe *Chelidonieae* in *Sanguinaria
canadensis*'s classification), the CoL API returns the `name` field of a
classification level as a **bare string** rather than a nested hash object.

The driver (`Source/CoL.pm`) handles both shapes:
```perl
my $ln = (ref $name_field eq 'HASH') ? $name_field : undef;
```

---

## Search strategy

The driver tries an exact-match search first (`type=EXACT`). If that returns no
results, it falls back to a plain search without the type constraint. Both the URL
used and the raw JSON response are returned to the plugin shell for display on the
results page, so the cataloguer can see exactly what the API returned.

---

## Taxon IDs

CoL taxon IDs are short alphanumeric strings (e.g. `79HDB` for *Sanguinaria
canadensis*). They are stable within a CoL release but may change between annual
releases. The authority URI format is:

```
https://www.catalogueoflife.org/data/taxon/{id}
```

This URI is used as the duplicate-detection key in `110 $0` and in the SEEDCOL
matching rule.
