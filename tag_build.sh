#!/bin/bash
#
# Build a bakery tag release of latest sysexts.
#
# The release will include all sysexts listed in release_build_versions.txt.

set -euo pipefail

: ${REPO:=jpvantelon/sysext-bakery-docker}

echo
echo "Building sysexts"
echo "================"

mapfile -t images < <( awk '{ content=sub("[[:space:]]*#.*", ""); if ($0) print $0; }' \
                       release_build_versions.txt )

echo "building: ${images[@]}"

echo "# Release $(date '+%Y-%m-%d %R')" > Release.md
echo "The release contains the following sysexts:" >> Release.md

for image in "${images[@]}"; do
  component="${image%-*}"
  version="${image#*-}"
  for arch in x86-64; do
    target="${image}-${arch}.raw"
    echo "  ## Building ${target}."
    ARCH="${arch}" "./create_${component}_sysext.sh" "${version}" "${component}"
    mv "${component}.raw" "${target}"
    echo "* ${target}" >> Release.md
  done
  streams+=("${component}:-@v")
  if [ "${component}" = "kubernetes" ] || [ "${component}" = "crio" ]; then
    streams+=("${component}-${version%.*}:.@v")
    # Should give, e.g., v1.28 for v1.28.2 (use ${version#*.*.} to get 2)
  fi
done
  
echo "" >> Release.md

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
