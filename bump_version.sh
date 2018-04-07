#!/usr/bin/env bash
# ------------------
# bump-version.sh - update the versions in our project
#
# usage:
#   ./bump-version.sh major          : x.y.z -> x+1.0.0 ; use for breaking changes
#   ./bump-version.sh minor          : x.y.z -> x.y+1.0 ; use for new backward compatible features
#   ./bump-version.sh <no arguments> : x.y.z -> x.y.z+1 ; use for bugfixes or minor updates
# ------------------

PWD=`pwd`
FILE_NAME=( funtoo-report lib/Funtoo/Report.pm README.md)
VERSION=""
MAJOR=0
MINOR=0
PACKAGE=0

function read_version {
	# Using the latest git tag here as the last release number
	VERSION=`git tag |sort -rV|head -1|sed -e 's/v//'`
	MAJOR=`echo $VERSION | perl -ne 'if (m/(\d+)\.(\d+)\.(\d+)/) { print "$1" }'`
	MINOR=`echo $VERSION | perl -ne 'if (m/(\d+)\.(\d+)\.(\d+)/) { print "$2" }'`
	PACKAGE=`echo $VERSION | perl -ne 'if (m/(\d+)\.(\d+)\.(\d+)/) { print "$3" }'`
}

function write_version {
	for f in ${FILE_NAME[@]}
	do
		echo "Bumping $f ..."

		# This line searches for our $VERSION in funtoo-report and in Report.pm
		# FIXME: This line currently doesn't work, please correct it so it searches for our $VERSION and replaces it.
		perl -pi -e "s/^our[ ]\$VERSION[ ]=[ ]'\d+[.]\d+[.]\d+(-.*)?'/our \$VERSION = '$MAJOR.$MINOR.$PACKAGE'/xms" $PWD/$f

		# The rest works
		# This line searches for Version x.y.z found in Report.pm in POD
		perl -pi -e "s/^Version(\s?)+\d+\.\d+\.\d+(-?)+(\w?)*/Version $MAJOR.$MINOR.$PACKAGE/" $PWD/$f
		# This line searches for version number in README.md
		perl -pi -e "s/^# Funtoo-Report - v(\s?)+\d+\.\d+\.\d+(-?)+(\w?)*/# Funtoo-Report - v$MAJOR.$MINOR.$PACKAGE/" $PWD/$f

		# Here are all the version strings we need to bump with their file names.
		#./funtoo-report:our $VERSION = '3.0.0-beta';
		#./lib/Funtoo/Report.pm:our $VERSION = '3.0.0-beta';
		#./lib/Funtoo/Report.pm:Version 3.0.0-beta
		#./README.md:# Funtoo-Report - v3.0.0-beta ![CI build test badge](https://api.travis-ci.org/haxmeister/funtoo-reporter.svg?branch=develop "Build test badge")

	done

}

read_version

if [ "$VERSION" == "" ]
then
	echo "ERROR: couldn't parse version string from git tags."
	exit 1
fi

if [ "$1" == "major" ]
then
	let MAJOR+=1
	MINOR=0
	PACKAGE=0
elif [ "$1" == "minor" ]
then
	let MINOR+=1
	PACKAGE=0
else
	let PACKAGE+=1
fi

echo "Funtoo::Report updating $VERSION -> $MAJOR.$MINOR.$PACKAGE"
echo "**************************************"

write_version

echo "--------------------------------------"
echo "done"
