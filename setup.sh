#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
STATE_FILE="${STATE_FILE:-$SCRIPT_DIR/.setup-state.env}"

for file in "$SCRIPT_DIR"/setup.d/*.sh; do
    # shellcheck source=/dev/null
    source "$file"
done

if [ "${HERMES_SINGLE_TEST_MODE:-false}" != "1" ]; then
    main "$@"
fi
