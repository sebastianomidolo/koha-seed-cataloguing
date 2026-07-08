# Koha deployment guide

Tested on: Koha 25.11, Debian 12, OpenSearch, Apache mpm_itk.  
Server: `alke.mooo.com` (same box as `ilcentro.crabdance.com` and `lecat.crabdance.com`).  
Test instance: `lecat` (throwaway — no real users).

---

## One-time setup on the Koha instance

These steps are needed once. They have already been done on `lecat`.

### 1. Bibliographic framework SEED
- Admin → MARC bibliographic frameworks → New framework
- Code: `SEED`, Name: "EBo's seed bank"
- Clone from Default
- Field 754: present with all subfields (most set to hidden=-6 for import-only workflow)

### 2. Item type SEED
- Admin → Item types → New item type
- Code: `SEED`, Description: "Seed bank item type"

### 3. OpenSearch field for duplicate detection
Add to `search_field` and `search_marc_map` tables:

```sql
INSERT INTO search_field (name, label, type) VALUES ('seed-col-uri', 'CoL taxon URI', 'string');

INSERT INTO search_marc_map (index_name, marc_type, marc_field)
VALUES ('biblios', 'marc21', '1100');   -- 110 $0

INSERT INTO search_marc_to_field (search_field_id, search_marc_map_id, facet, suggestible, sort)
VALUES (
  (SELECT id FROM search_field WHERE name='seed-col-uri'),
  (SELECT id FROM search_marc_map WHERE marc_field='1100' AND index_name='biblios'),
  0, 0, NULL
);
```

After inserting: full reindex required (`sudo koha-elasticsearch -d --instance lecat`
or equivalent).

### 4. Record Matching Rule SEEDCOL
- Admin → Record matching rules → New matching rule
- Code: `SEEDCOL`, record type: biblio, threshold: 1000
- One matchpoint: index `seed-col-uri`, score 1000, tag 110, subfield `0`, normalizer: `none`

---

## Deploying or updating plugin files

### Source of truth
All edits go to the source tree on seba's machine:
```
/home/seba/ebo-seed-library/SeedCataloguing/Koha/Plugin/
```
Changes flow **source → deployed**, never the other direction.
The lecat-koha agent must NOT edit deployed files directly.

### Deploy script
Run as `seba` (requires sudo to write to the lecat-owned plugin directory):

```bash
cd /home/seba/ebo-seed-library/SeedCataloguing
bash deploy-to-lecat.sh
```

The script copies all three plugin files to:
```
/var/lib/koha/lecat/plugins/Koha/Plugin/
```

### MANDATORY: restart Plack after every deploy

Plack workers cache `require`d modules in `%INC` for the lifetime of the process.
Updating a file on disk has **no effect** until the workers restart.

```bash
sudo koha-plack --restart lecat
```

This applies even if `perl -c` or `require` checks pass in a standalone process —
those run in a fresh interpreter and do not reflect the live worker's state.

**Rule:** any time a plugin file is updated on disk, restart Plack. No exceptions.

### Optionally flush Memcached
Rarely the actual cause of stale behaviour, but harmless:
```bash
echo 'flush_all' | nc 127.0.0.1 11211
```

---

## Accessing the plugin (staff interface)

```
https://lecat.crabdance.com:8443/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ASeedCataloguing&method=tool
```

Or via the Koha staff menu: Tools → Seed Cataloguing Tool.

Test credentials on lecat: `ebo / Seeds123!` (superlibrarian).

---

## Shared airlock for multi-agent coordination

`/srv/kohadev/` is a shared directory (group `kohadev`, mode 2775) readable and
writable by `seba`, `lecat-koha`, and `ilcentro-koha`. Use it to pass scripts,
SQL, notes, and task instructions between sessions. Always write with `umask 002`.

Memory conventions: see `/srv/kohadev/MEMORY-CONVENTION.md`.
