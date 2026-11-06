#!/usr/bin/env bash
# Runs with no real hosts and no Datadog account: --syntax-check per OS path, a check-mode
# config render for the Debian and Windows paths, and the two negative cases (missing API key,
# bad apm_enabled type). Cannot run on the Windows machine this was written on - ansible-core
# does not run there at all (confirmed in earlier challenges: it fails importing `grp`, a
# Unix-only stdlib module) - this script is for CI (Linux) only.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
FAILED=0

check() {
  local desc="$1"
  local rc="$2"
  if [ "$rc" = "0" ]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc"
    FAILED=1
  fi
}

# --- syntax-check, one per OS path ---
for os in Debian RedHat Windows; do
  ansible-playbook site.yml --syntax-check -e "ansible_os_family=$os" -e "datadog_agent_api_key=fake-test-key" \
    >/tmp/syntax-check-"$os".log 2>&1
  check "syntax-check passes faking ansible_os_family=$os" "$?"
done

# --- check-mode config render, Debian path and Windows path ---
for os in Debian Windows; do
  OUT=$(TEST_CONFIG_PATH="/tmp/datadog-test-config-$os.yaml" \
    ansible-playbook tests/check-mode-config.yml --check --diff --tags datadog_config \
    -e "ansible_os_family=$os" 2>&1)
  echo "$OUT" | grep -q "env:test"
  check "$os path: rendered config contains the env tag" "$?"
  echo "$OUT" | grep -q "service:checkout"
  check "$os path: rendered config contains the service tag" "$?"
  echo "$OUT" | grep -q "enabled: true"
  check "$os path: rendered config contains apm enabled: true" "$?"
done

# --- negative: missing API key fails the play with the expected message ---
OUT=$(ansible-playbook tests/negative-missing-api-key.yml 2>&1)
RC=$?
[ "$RC" != "0" ]
check "missing api key fails the play" "$?"
echo "$OUT" | grep -q "datadog_agent_api_key is not set"
check "missing api key failure message is the expected one" "$?"

# --- negative: a non-boolean apm_enabled is rejected ---
OUT=$(ansible-playbook tests/negative-bad-apm-type.yml 2>&1)
RC=$?
[ "$RC" != "0" ]
check "bad apm_enabled type fails the play" "$?"
echo "$OUT" | grep -q "datadog_agent_apm_enabled must be true or false"
check "bad apm_enabled failure message is the expected one" "$?"

rm -f /tmp/datadog-test-config-*.yaml /tmp/syntax-check-*.log

exit $FAILED
