# Catalogue of Life API — notes and known issues

Base URL: `https://api.checklistbank.org/dataset/3LR`  
Dataset: `3LR` = Catalogue of Life latest release  
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

The endpoint `GET /taxon/{id}/vernacularname` returns **404** for all taxa in the
3LR dataset. It is not a valid endpoint for this dataset. The correct endpoint for
vernacular names is `/taxon/{id}/info`, which returns a `vernacularNames` array.

---

## Known issue: language encoding in vernacular names

The `/info` endpoint does **not** provide a structured `language` field for vernacular
names. Instead, language is embedded inline in the `name` string as a two-letter
suffix in parentheses:

```json
{ "name": "Bloodroot (EN)" }
{ "name": "カクトラノオ (JA)" }
{ "name": "Фізостегія віргінська (UK)" }
```

The plugin strips the suffix via `_strip_lang_suffix()` and selects English names
first by matching `\(EN\)`.

---

## Known issue: uneven vernacular name coverage

The CoL API (3LR dataset) has vernacular names for some species but not others.
For example:
- *Sanguinaria canadensis*: "Bloodroot (EN)" — present
- *Physostegia virginiana*: no vernacular names in 3LR

However, the CoL **website** (`catalogueoflife.org/data/taxon/…`) shows 35+
vernacular names for the same taxa. The source of those names is under investigation
— likely GBIF or a separate ChecklistBank dataset. A fallback source will be added
once identified. Do not implement iNaturalist or GBIF fallback until EBo's
investigation is complete.

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
