# Koha deployment guide

Tested on: Koha 25.11, Debian 12, OpenSearch, Apache mpm_itk.  

---

## One-time setup on the Koha instance

These steps are needed once.

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

After inserting: full reindex required (`sudo koha-elasticsearch -d --instance <instance>`
or equivalent).

### 4. Record Matching Rule SEEDCOL
- Admin → Record matching rules → New matching rule
- Code: `SEEDCOL`, record type: biblio, threshold: 1000
- One matchpoint: index `seed-col-uri`, score 1000, tag 110, subfield `0`, normalizer: `none`

---

## Deploying or updating plugin files

### Standard installation (any Koha instance)

Package the plugin as a `.kpz` file and upload it via the Koha staff interface:

```bash
cd /path/to/koha-seed-cataloguing
zip -r koha-seed-cataloguing.kpz Koha/
```

Then in Koha: **Administration → Plugins → Upload plugin** → select the `.kpz` file.
After uploading, go to **View all plugins** and click **Scan plugins** if the plugin
does not appear immediately.

### MANDATORY: restart Plack after every deploy

Plack workers cache `require`d modules in `%INC` for the lifetime of the process.
Updating a file on disk has **no effect** until the workers restart.

```bash
sudo koha-plack --restart <instance>
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
https://<your-staff-host>/cgi-bin/koha/plugins/run.pl?class=Koha%3A%3APlugin%3A%3ASeedCataloguing&method=tool
```

Or via the Koha staff menu: Tools → Seed Cataloguing Tool.

