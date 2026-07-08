#!/bin/bash
# Deploy SeedCataloguing plugin to lecat.
# Run from /home/seba/ebo-seed-library/SeedCataloguing/
# Requires sudo.

set -e
DEST=/var/lib/koha/lecat/plugins

sudo mkdir -p "$DEST/Koha/Plugin/SeedCataloguing/Source"

sudo cp Koha/Plugin/SeedCataloguing.pm          "$DEST/Koha/Plugin/SeedCataloguing.pm"
sudo cp Koha/Plugin/SeedCataloguing/MARCBuilder.pm  "$DEST/Koha/Plugin/SeedCataloguing/MARCBuilder.pm"
sudo cp Koha/Plugin/SeedCataloguing/Source/CoL.pm   "$DEST/Koha/Plugin/SeedCataloguing/Source/CoL.pm"

echo "Done. Now go to Koha admin > Tools > Plugins and click 'Scan plugins'."
