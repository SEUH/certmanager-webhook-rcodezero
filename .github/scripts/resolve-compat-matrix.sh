#!/usr/bin/env bash
set -euo pipefail
# Resolves the compatibility test matrix:
#   - latest patch of the two newest cert-manager minor releases
#   - kind node images for the three Kubernetes minors currently supported upstream
# Writes cert_manager, kind_version and nodes to $GITHUB_OUTPUT when run in Actions.

gh_api() {
  curl -fsSL ${GH_TOKEN:+-H "Authorization: Bearer $GH_TOKEN"} \
    -H "Accept: application/vnd.github+json" "https://api.github.com/$1"
}

# cert-manager: newest patch of each of the two newest stable minors
cert_manager=$(
  for page in 1 2 3; do gh_api "repos/cert-manager/cert-manager/releases?per_page=100&page=$page"; done \
    | jq -r '.[] | select(.prerelease == false and .draft == false) | .tag_name' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V \
    | awk -F. '{ last[$1"."$2] = $0 } END { for (m in last) print last[m] }' \
    | sort -V | tail -n 2 | jq -R . | jq -sc .
)

# Kubernetes supports the three newest minor releases
stable=$(curl -fsSL https://dl.k8s.io/release/stable.txt)        # e.g. v1.37.2
major=$(echo "${stable#v}" | cut -d. -f1)
minor=$(echo "${stable#v}" | cut -d. -f2)
supported="$major.$minor $major.$((minor - 1)) $major.$((minor - 2))"

# kind: node images (pinned by digest) published with the latest kind release
kind_release=$(gh_api repos/kubernetes-sigs/kind/releases/latest)
kind_version=$(jq -r .tag_name <<<"$kind_release")
images=$(jq -r .body <<<"$kind_release" \
  | grep -oE 'kindest/node:v[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}' | sort -uV)

nodes='[]'
for m in $supported; do
  image=$(grep -E "^kindest/node:v${m//./\\.}\.[0-9]+@" <<<"$images" | sort -V | tail -n 1 || true)
  if [ -z "$image" ]; then
    echo "::warning::kind $kind_version has no node image for Kubernetes $m, skipping it"
    continue
  fi
  version=$(sed -E 's/^kindest\/node:(v[^@]+)@.*/\1/' <<<"$image")
  nodes=$(jq -c --arg v "$version" --arg i "$image" '. + [{k8s: $v, image: $i}]' <<<"$nodes")
done

[ "$(jq length <<<"$cert_manager")" -gt 0 ] || { echo "::error::no cert-manager releases found"; exit 1; }
[ "$(jq length <<<"$nodes")" -gt 0 ]        || { echo "::error::no usable kind node images found"; exit 1; }

echo "cert-manager: $cert_manager"
echo "kubernetes:   $supported (stable $stable)"
echo "kind:         $kind_version"
echo "nodes:        $nodes"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  {
    echo "cert_manager=$cert_manager"
    echo "kind_version=$kind_version"
    echo "nodes=$nodes"
  } >> "$GITHUB_OUTPUT"
fi
