#!/usr/bin/env bash

set -Eeuo pipefail

ROOT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
DEB_DIRECTORY="$ROOT_DIRECTORY/debs"
SITE_DIRECTORY="$ROOT_DIRECTORY/site"
PUBLIC_DIRECTORY="$ROOT_DIRECTORY/public"

case "$PUBLIC_DIRECTORY" in
    "$ROOT_DIRECTORY/public") ;;
    *)
        echo "error: unsafe public directory: $PUBLIC_DIRECTORY" >&2
        exit 70
        ;;
esac

for command_name in dpkg-deb dpkg-scanpackages gzip xz sha256sum; do
    command -v "$command_name" >/dev/null 2>&1 || {
        echo "error: missing required command: $command_name" >&2
        exit 69
    }
done

rm -rf -- "$PUBLIC_DIRECTORY"
mkdir -p "$PUBLIC_DIRECTORY/debs"
cp -a "$SITE_DIRECTORY/." "$PUBLIC_DIRECTORY/"

declare -A package_keys=()
package_count=0

while IFS= read -r -d '' package_path; do
    dpkg-deb --info "$package_path" >/dev/null

    package_id="$(dpkg-deb --field "$package_path" Package)"
    package_version="$(dpkg-deb --field "$package_path" Version)"
    package_architecture="$(dpkg-deb --field "$package_path" Architecture)"

    if [[ -z "$package_id" || -z "$package_version" || -z "$package_architecture" ]]; then
        echo "error: missing Package, Version or Architecture: $package_path" >&2
        exit 65
    fi
    case "$package_architecture" in
        iphoneos-arm64e|all) ;;
        *)
            echo "error: unsupported architecture '$package_architecture': $package_path" >&2
            echo "Only RootHide iphoneos-arm64e and architecture-independent all packages are accepted." >&2
            exit 65
            ;;
    esac

    package_key="$package_id|$package_version|$package_architecture"
    if [[ -n "${package_keys[$package_key]:-}" ]]; then
        echo "error: duplicate package tuple: $package_key" >&2
        echo "  first: ${package_keys[$package_key]}" >&2
        echo "  again: $package_path" >&2
        exit 65
    fi
    package_keys[$package_key]="$package_path"

    relative_path="${package_path#"$DEB_DIRECTORY/"}"
    destination="$PUBLIC_DIRECTORY/debs/$relative_path"
    mkdir -p "$(dirname "$destination")"
    cp -p "$package_path" "$destination"
    package_count=$((package_count + 1))
    echo "validated: $package_id $package_version ($package_architecture)"
done < <(find "$DEB_DIRECTORY" -type f -name '*.deb' -print0 | LC_ALL=C sort -z)

(
    cd "$ROOT_DIRECTORY"
    dpkg-scanpackages --multiversion debs /dev/null >"$PUBLIC_DIRECTORY/Packages"
)

gzip -9n -c "$PUBLIC_DIRECTORY/Packages" >"$PUBLIC_DIRECTORY/Packages.gz"
xz --threads=1 -9e -c "$PUBLIC_DIRECTORY/Packages" >"$PUBLIC_DIRECTORY/Packages.xz"

release_date="$(LC_ALL=C date -Ru)"
cat >"$PUBLIC_DIRECTORY/Release" <<EOF
Origin: 154328106
Label: 154328106 RootHide Repo
Suite: stable
Version: 1.0
Codename: stable
Architectures: iphoneos-arm64e all
Components: main
Description: Personal packages tested with Relaxin and RootHide
Date: $release_date
EOF

append_hashes() {
    local algorithm="$1"
    local utility="$2"
    printf '%s:\n' "$algorithm" >>"$PUBLIC_DIRECTORY/Release"
    for filename in Packages Packages.gz Packages.xz; do
        checksum="$($utility "$PUBLIC_DIRECTORY/$filename" | awk '{print $1}')"
        size="$(wc -c <"$PUBLIC_DIRECTORY/$filename" | tr -d ' ')"
        printf ' %s %16s %s\n' "$checksum" "$size" "$filename" >>"$PUBLIC_DIRECTORY/Release"
    done
}

append_hashes MD5Sum md5sum
append_hashes SHA1 sha1sum
append_hashes SHA256 sha256sum

printf '%s\n' "$package_count" >"$PUBLIC_DIRECTORY/package-count.txt"
echo "built repository with $package_count package(s): $PUBLIC_DIRECTORY"

