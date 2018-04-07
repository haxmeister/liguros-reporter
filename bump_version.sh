#!/bin/sh

# bump-version.sh - update the versions in our project

path=$(cd "$(dirname "$0")" && pwd)
file_names="funtoo-report
lib/Funtoo/Report.pm
README.md"
version=""
major=0
minor=0
patch=0

usage() {
    echo "\
Usage: $0 type

major : x.y.z -> x+1.0.0 ; use for breaking changes
minor : x.y.z -> x.y+1.0 ; use for new backward compatible features
patch : x.y.z -> x.y.z+1 ; use for bugfixes or minor updates
    "
    exit
}

read_version() {
    # Using the latest git tag here as the last release number
    version=$(git tag | sort -rV | head -1 | sed -e 's/v//')
    major=$(echo "$version" | sed -n -e 's/\([0-9]\+\)[.]\([0-9]\+\)[.]\([0-9]\+\)/\1/p')
    minor=$(echo "$version" | sed -n -e 's/\([0-9]\+\)[.]\([0-9]\+\)[.]\([0-9]\+\)/\2/p')
    patch=$(echo "$version" | sed -n -e 's/\([0-9]\+\)[.]\([0-9]\+\)[.]\([0-9]\+\)/\3/p')

}

write_version() {
    echo "$file_names" | awk -F/ '{if (!seen[$NF]++) print }' | \
        while IFS="$'\n'" read -r file;
        do
            echo "Bumping $file ..."

            # This line searches for our $VERSION in funtoo-report and in Report.pm
            sed -i -e "s/^our \$VERSION = '\([0-9]\+[.]\)\{2\}[0-9].*/our \$VERSION = '$major.$minor.$patch';/" "$path/$file"
            # This line searches for Version x.y.z found in Report.pm in POD
            sed -i -e "s/^Version \([0-9]\+[.]\)\{2\}[0-9].*/Version $major.$minor.$patch/" "$path/$file"
            # This line searches for version number in README.md
            sed -i -e "s/^# Funtoo-Report - v\([0-9]\+[.]\)\{2\}[0-9].*!/# Funtoo-Report - v$major.$minor.$patch !/" "$path/$file"

        done
    }

    read_version

    if [ "$version" = "" ]
    then
        echo "ERROR: couldn't parse version string from git tags."
        exit 1
    fi

    case "$1" in
        major)
            major=$((major+1))
            minor=0
            patch=0
            ;;
        minor)
            minor=$((minor+1))
            patch=0
            ;;
        patch)
            patch=$((patch+1))
            ;;
        *)
            usage
            ;;
    esac

    echo "Funtoo::Report updating $version -> $major.$minor.$patch"
    echo "**************************************"

    write_version

    echo "--------------------------------------"
    echo "done"
