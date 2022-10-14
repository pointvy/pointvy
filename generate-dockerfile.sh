#!/bin/bash

active_branch=$(git branch --show-current)

echo "Active branch: $active_branch"

validate="^[0-9]+.[0-9]+.[0-9]+$"

if [[ $active_branch =~ $validate ]]; then
    echo "Branch format is ok."
else
    echo "Branch format must be semver (ex: 1.2.3)."
    exit 1
fi

curl -sSL \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/aquasecurity/trivy/releases/latest > release.json

CS_URL=$(jq -r '.assets[] | select(.name | endswith("checksums.txt")) .browser_download_url' release.json)

TRIVY_VERSION=$(jq -r '.name' release.json | sed 's/v//1')

curl -sSL \
    -H "Accept: application/vnd.github.v3+json" \
    "$CS_URL" > trivy_latest_checksums.txt

TRIVY_CHECKSUM=$(grep -E 'trivy_[0-9]+\.[0-9]+\.[0-9]+_Linux-64bit.tar.gz' "trivy_latest_checksums.txt" \
    | awk -F '  ' '{print $1}')

cp Dockerfile Dockerfile.bak

sed "s/%%TRIVY_VERSION%%/$TRIVY_VERSION/1" Dockerfile.template > Dockerfile.tmp0
sed "s/%%TRIVY_CHECKSUM%%/$TRIVY_CHECKSUM/1" Dockerfile.tmp0 > Dockerfile.tmp1
sed "s/%%POINTVY_VERSION%%/$active_branch/1" Dockerfile.tmp1 > Dockerfile

rm release.json trivy_latest_checksums.txt Dockerfile.tmp0 Dockerfile.tmp1

echo "Dockerfile updated."
