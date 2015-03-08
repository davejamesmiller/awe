#!/bin/bash
set -o nounset -o pipefail -o errexit
cd "$(dirname "$0")"

# Make sure 'when-changed' is installed
source bash/require-when-changed.bash

# Run initial test - ignore failures
./test-javascript.sh "$@" || true

# Watch for further changes
exec when-changed -r javascript -c "./test-javascript.sh $*"
