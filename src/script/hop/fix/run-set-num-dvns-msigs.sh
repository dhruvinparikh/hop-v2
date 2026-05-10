#!/usr/bin/env bash
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

OUTPUT_DIR="src/script/hop/fix/generated/set-num-dvns"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120s}"
NUM_DVNS="${NUM_DVNS:-5}"
BLOCK_TIMESTAMP="${BLOCK_TIMESTAMP:-$(date +%s)}"
START_CHAIN="${START_CHAIN:-}"
START_CHAIN_SEEN=0

usage() {
  echo "Usage: $0 [fresh]"
  echo
  echo "Generate direct local Safe JSON batches for HopV2.setNumDVNs(${NUM_DVNS}) into ${OUTPUT_DIR}."
  echo
  echo "Environment:"
  echo "  NUM_DVNS=5            target HopV2 numDVNs"
  echo "  BLOCK_TIMESTAMP=...   block timestamp used for Safe JSON createdAt"
  echo "  START_CHAIN=8453      skip earlier chains and resume generation at this chain id"
  echo "  TIMEOUT_SECONDS=120s  per-forge-script timeout"
  echo
  echo "  fresh                 remove generated JSON from ${OUTPUT_DIR} before regenerating"
}

mkdir -p "${OUTPUT_DIR}"

case "${1:-}" in
  "")
    ;;
  "fresh")
    echo "Removing stale Safe JSON from ${OUTPUT_DIR}"
    find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "*.json" -delete
    ;;
  "-h"|"--help")
    usage
    exit 0
    ;;
  *)
    usage
    exit 2
    ;;
esac

clean_chain() {
  local chain_id="$1"
  find "${OUTPUT_DIR}" -maxdepth 1 -type f -name "${chain_id}-HopV2-*.json" -delete
}

should_run_chain() {
  local chain_id="$1"

  if [[ -z "${START_CHAIN}" || "${START_CHAIN_SEEN}" == "1" ]]; then
    return 0
  fi

  if [[ "${chain_id}" == "${START_CHAIN}" ]]; then
    START_CHAIN_SEEN=1
    return 0
  fi

  return 1
}

run_chain() {
  local chain_id="$1"

  if ! should_run_chain "${chain_id}"; then
    return 0
  fi

  echo "SetNumDVNsDirect: ${chain_id}"
  clean_chain "${chain_id}"

  OUTPUT_DIR="${OUTPUT_DIR}" \
  NUM_DVNS="${NUM_DVNS}" \
  RUST_LOG=error \
  timeout "${TIMEOUT_SECONDS}" \
    forge script src/script/hop/fix/SetNumDVNsDirect.s.sol \
      --chain "${chain_id}" \
      --block-timestamp "${BLOCK_TIMESTAMP}" \
      --ffi \
      --quiet \
      --disable-labels
}

CHAIN_IDS=(
  1
  10
  56
  130
  146
  196
  252
  324
  480
  999
  1329
  2741
  4217
  5031
  8453
  34443
  42161
  43114
  57073
  59144
  747474
  80094
  534352
  1313161554
)

for chain_id in "${CHAIN_IDS[@]}"; do
  run_chain "${chain_id}"
done

if [[ -n "${START_CHAIN}" && "${START_CHAIN_SEEN}" == "0" ]]; then
  echo "START_CHAIN ${START_CHAIN} was not found" >&2
  exit 1
fi
