#!/bin/bash
# Create Package.
# Run locally to create the package.
# Does not require sudo.

set -e

zip -R koha-seed-cataloging.kpz *.pm

echo "Done. Now you can load the seed cataloging plugin'."
