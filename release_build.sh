#!/bin/bash
#
# Build a bakery release of all sysexts.
#
# The release will include all sysexts from the "latest" release
# (these will be downloaded). Sysexts listed in release_build_versions.txt
# and _not_ included in the "latest" release will be built.

set -euo pipefail

: ${REPO:=jpvantelon/sysext-bakery-docker}

BUILD_ARCH="x86-64"

echo
echo "Fetching previous 'latest' release sysexts"
echo "=========================================="
curl -fsSL --retry-delay 1 --retry 60 --retry-connrefused \
         --retry-max-time 60 --connect-timeout 20  \
         https://api.github.com/repos/"${REPO}"/releases/latest \
    | jq -r '.assets[] | "\(.name)\t\(.browser_download_url)"' | { grep -E '\.raw$' || true; } | tee prev_release_sysexts.txt

while IFS=$'\t' read -r name url; do
    echo
    echo "  ## Fetching ${name} <-- ${url}"
    curl -o "${name}" -fsSL --retry-delay 1 --retry 60 --retry-connrefused --retry-max-time 60 --connect-timeout 20  "${url}"
done <prev_release_sysexts.txt

streams=()

echo
echo "Building sysexts"
echo "================"

mapfile -t images < <( awk '{ content=sub("[[:space:]]*#.*", ""); if ($0) print $0; }' \
                       release_build_versions.txt )

echo "building: ${images[@]}"

echo "# Release $(date '+%Y-%m-%d %R')" > Release.md

if [[ ${#images[@]} -gt 0 ]]; then
  images_to_build=()
  for image in "${images[@]}"; do
    component="${image%-*}"
    target="${image}-${BUILD_ARCH}.raw"
    if ! [ -f "${target}" ] ; then
        images_to_build+=("${image}")
    fi
    streams+=("${component}:-@v")
  done

  if [[ ${#images_to_build[@]} -gt 0 ]]; then
    echo "The release adds the following sysexts:" >> Release.md

    for image in "${images_to_build[@]}"; do
      component="${image%-*}"
      version="${image#*-}"
      target="${image}-${BUILD_ARCH}.raw"
      if [ -f "${target}" ] ; then
          echo "  ## Skipping ${target} because it already exists (asset from previous release)"
          continue
      fi
      echo "  ## Building ${target}."
      ARCH="${BUILD_ARCH}" "./create_${component}_sysext.sh" "${version}" "${component}"
      mv "${component}.raw" "${target}"
      echo "* ${target}" >> Release.md
    done
      
    echo "" >> Release.md
  fi
fi

echo "The release includes the following sysexts from previous releases:" >> Release.md
awk '{ print "* ["$1"]("$2")" }' prev_release_sysexts.txt >>Release.md

echo
echo "Generating systemd-sysupdate configurations and SHA256SUM."
echo "=========================================================="

for stream in "${streams[@]}"; do
  component="${stream%:*}"
  pattern="${stream#*:}"
  cat << EOF > "${component}.conf"
[Transfer]
Verify=false
[Source]
Type=url-file
Path=https://github.com/${REPO}/releases/latest/download/
MatchPattern=${component}${pattern}-%a.raw
[Target]
InstancesMax=3
Type=regular-file
Path=/opt/extensions/${component%-*}
CurrentSymlink=/etc/extensions/${component%-*}.raw
EOF
done

cat << EOF > "noop.conf"
[Source]
Type=regular-file
Path=/
MatchPattern=invalid@v.raw
[Target]
Type=regular-file
Path=/
EOF

# Generate new SHA256SUMS from all assets
sha256sum *.raw | tee SHA256SUMS
