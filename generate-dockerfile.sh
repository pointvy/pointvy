#!/bin/bash

curl -sSL \
    -H "Accept: application/vnd.github.v3+json" \
    https://api.github.com/repos/aquasecurity/trivy/releases/latest > release.json

CS_URL=$(jq -r '.assets[] | select(.name | contains("checksums.txt")) .browser_download_url' release.json)

TRIVY_VERSION=$(jq -r '.name' release.json | sed 's/v//1')

curl -sSL \
    -H "Accept: application/vnd.github.v3+json" \
    "$CS_URL" > trivy_latest_checksums.txt

TRIVY_CHECKSUM=$(grep -E 'trivy_[0-9]+\.[0-9]+\.[0-9]+_Linux-64bit.tar.gz' "trivy_latest_checksums.txt" \
    | awk -F '  ' '{print $1}')

echo "$TRIVY_CS"

sed "s/%%TRIVY_VERSION%%/$TRIVY_VERSION/1" Dockerfile.template > Dockerfile.tmp
sed "s/%%TRIVY_CHECKSUM%%/$TRIVY_CHECKSUM/1" Dockerfile.tmp > Dockerfile.latest

rm release.json trivy_latest_checksums.txt Dockerfile.tmp
