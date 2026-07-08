# MARC field decisions

This document records the MARC21 field choices made for seed-library records,
with the reasoning behind each. It is a living document — decisions may change
as the project matures.

---

## The core analogy

A seed collection event is treated as a **bibliographic record**, exactly as a
library book is. The species plays the role of **corporate body** (the "author"
of the seed), and the collection event is the "publication".

| Seed-bank concept    | Library/MARC analogy                  |
|----------------------|---------------------------------------|
| Species              | Corporate body (MARC field 110)       |
| Collection event     | Bibliographic record (the "book")     |
| Seed packet          | Copy/item (Koha 952)                  |

This analogy was proposed by EBo and validated against the Kew Gardens MSBP
field manual, which splits data cleanly into species-level (biographic) and
collection-event (bibliographic) layers.

---

## Field 110 — Species identity (Corporate Name)

**Indicators:** `2 _` (ind1=2: name in direct order; ind2=blank)

| Subfield | Content | Notes |
|---|---|---|
| `$a` | Scientific name with authority, e.g. *Sanguinaria canadensis* L. | Main entry |
| `$b` | Primary vernacular/common name, e.g. "bloodroot" | Not a perfect semantic fit ($b = subordinate unit in standard MARC) but best available subfield |
| `$0` | Authority URI, e.g. `https://www.catalogueoflife.org/data/taxon/79HDB` | External identifier; used as the duplicate-detection key |
| `$1` | Real-world object URI (POWO, GBIF, etc.) if available | Correct subfield for a URI per MARC21 standard |
| `$2` | Source code, e.g. `catl` | Registered LoC taxonomic source codes: `catl`, `plantsdb`, `itis`, `iucnrl`, `grintp`, `inatur` |

**Why 110 and not 100?** Field 100 (Personal Name) must be kept free for real people
— collectors, farm owners, researchers. Species are entities, not persons; 110 is
correct. Confirmed after discussion between Seba and EBo.

**Why ind1=2?** "Name in direct order" is appropriate for a scientific binomial
(*Sanguinaria canadensis*), which is not inverted. Corrected from the original `##`
by EBo on 2026-06-28.

**Note on $6:** EBo originally used `$6` for the authority URI. This is wrong —
in MARC21, `$6` is reserved for linkage between fields in the same record. The
correct subfield for a URI is `$1`. Fixed in seed_SPF.csv (2026-06-28).

---

## Field 245 — Title (Collection event description)

`245 10 $a Seed collection : $b [Species], [Location], [Year]`

Example: `245 10 $a Seed collection : $b Sanguinaria canadensis, Shenandoah Valley, Virginia, 2025`

A stub title. For real collection event records, an event identifier should be
incorporated. For commercially purchased seeds, a lot number. Design not yet finalised.

---

## Field 251 — Version tag

`251 __ $a 0.1 $2 Koha_Seed`

EBo's local extension to tag records with the schema version. Allows future
migration when the data model evolves.

---

## Field 700 — Collector (Added Entry — Personal Name)

`700 1_ $a [Surname, Forename] $e collector`

For secondary collectors (multiple per collection event). Ind1=1 (surname first).

---

## Field 754 — Taxonomic Identification

`754 __ $c [rank] $a [name] ... $d [common name] $0 [authority URI] $2 [source code]`

The `$c`/`$a` pair is repeatable, in hierarchical order from family down to species.

Example:
```
754 __ $c family $a Papaveraceae $c genus $a Sanguinaria $c species $a canadensis
        $d bloodroot $0 https://www.catalogueoflife.org/data/taxon/79HDB $2 catl
```

**Key points:**
- Field 754 exists **only in bibliographic format** — not in authority records.
- `$d` carries vernacular/common names (repeatable). No language subfield exists
  within 754 — multilingual names are an open question (see OPEN-QUESTIONS.md).
- `$0` here is a URI — correct per MARC21 (unlike `$6` which was used erroneously
  by EBo before correction).
- The depth of the taxonomic hierarchy (full kingdom→species vs family→species only)
  is an open question — see OPEN-QUESTIONS.md.

**Why not 650 (subject entry) for vernacular names?**
A 650 with ind2=3 (NAL authority) was proposed by EBo but rejected. Reasons:
- The vernacular name is an alternative identity of the species, not a subject heading.
- NAL authority requires NALT URIs, which CoL does not provide.
- 110 $b and 754 $d already carry the information more naturally.

---

## Field 910 — JSON payload (local field)

`910 __ $a collection_event $b {...JSON...}`

A local field carrying the full collection-event data as a JSON blob: coordinates,
altitude, habitat, soil, sampling statistics, permit references, germination data, etc.

**Rationale:** MARC handles species identity and taxonomy for discovery; the JSON blob
carries full domain-specific richness and travels with the record. It can evolve
independently of the MARC schema.

**Known issue:** the JSON blob in `$b` is silently dropped on MARCXML import in
Koha (cause under investigation — possibly field length or character encoding).

---

## Field 942 — Koha item type

`942 __ $c SEED`

Koha-specific field for item type. Framework: SEED (cloned from Default on lecat).

---

## Registered LoC taxonomic source codes ($2 values)

| Code | Source |
|---|---|
| `catl` | Catalogue of Life |
| `plantsdb` | USDA PLANTS Database |
| `itis` | Integrated Taxonomic Information System |
| `iucnrl` | IUCN Red List |
| `grintp` | GRIN Taxonomy for Plants |
| `inatur` | iNaturalist |
| `plantl` | The Plant List (Kew + Missouri Botanical Garden) |

Note: **GBIF is not registered** as a LoC taxonomic source code.
