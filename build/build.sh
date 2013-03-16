#!/bin/bash
SCRIPT_ROOT=$(dirname $0)
. $SCRIPT_ROOT/build.common

usage() {
    [ $# -eq 0 ] || echo "$*" >&2
cat <<EOF >&2
usage: $0 [options] <action>...
options:
    -n=<buildnum>   Build number (default: Jenkins build number, or 1)
    -a=<artifacts>  Path to the artifacts output dir (default: <workspace>/artifacts)
    -w=<workspace>  Workspace path (default: Jenkins workspace, or the project root)
    -h              Help
    -b=<branch>     Branch name (default: current branch name from git)
    -j=<jobURL>     Jenkins job URL (default: '\$JOB_URL') $(clr smul)$(clr bold)[REQUIRED]$(clr sgr0)
	-v              Verbose mode
	
actions:
    all (default)       Builds all actions
    debug               Builds debug universal library
    release             Builds release universal library
    gen_headers Creates an updated wrapper header file
    dependencies     Fetches and installs dependencies
EOF
    exit 1
}

OPT_VERBOSE=0
OPT_HELP=
OPT_BUILDNUM=$BUILD_NUMBER; [[ -z $BUILD_NUMBER ]] && OPT_BUILDNUM=1
OPT_WORKSPACE=$WORKSPACE; [[ -z $OPT_WORKSPACE ]] && OPT_WORKSPACE=$(cd `dirname $0`/..; echo $PWD)
OPT_ARTIFACTS=$OPT_WORKSPACE/artifacts
OPT_JOBURL=$JOB_URL

while getopts "vhw:a:n:b:j:" opt; do
    case $opt in
        h) OPT_HELP=1 ;;
        n) OPT_BUILDNUM=$OPTARG ;;
        w) OPT_WORKSPACE=$OPTARG ;;
        a) OPT_ARTIFACTS=$OPTARG ;;
        b) OPT_BRANCH=$OPTARG ;;
        j) OPT_JOBURL=$OPTARG ;;
        v) OPT_VERBOSE=1 ;;
        \?) usage "Invalid option: -$opt" ;;
        :) usage "Option -$opt requires an argument." ;;
    esac
done
shift $((OPTIND-1))

[ $OPT_HELP ] && usage

cd $(dirname $0)

PROJECT_NAME=SalesforceNetworkSDK
STATIC_LIB=lib$PROJECT_NAME.a
HEADER_PATH=Headers
PROJ=$OPT_WORKSPACE/$PROJECT_NAME.xcodeproj
BUILD_SCRIPT_DIR=$OPT_WORKSPACE/build
DEPENDENCIES="$OPT_WORKSPACE/dependencies"

function build_combined() {
	local configuration="$1"; shift
	pre_build_process

	xcodebuild -project $PROJ -configuration $configuration -sdk iphoneos INSTALL_ROOT=$OPT_ARTIFACTS/device install
	xcodebuild -project $PROJ -configuration $configuration -sdk iphonesimulator INSTALL_ROOT=$OPT_ARTIFACTS/simulator install
	
	lipo -create -output $OPT_ARTIFACTS/$STATIC_LIB $OPT_ARTIFACTS/device/$STATIC_LIB $OPT_ARTIFACTS/simulator/$STATIC_LIB
	post_build_process $configuration $configuration
}


function post_build_process() {
	local configuration="$1"; shift
	local outputSuffix="$1"; shift
	mv $OPT_ARTIFACTS/device/Headers $OPT_ARTIFACTS
	rm -rf $OPT_ARTIFACTS/device $OPT_ARTIFACTS/simulator UninstalledProducts
	rm -rf $configuration*
	rm -rf *.build
	(
        cd $OPT_ARTIFACTS
        rm -rf $PROJECT_NAME-$outputSuffix $PROJECT_NAME-$outputSuffix.zip
        mkdir $PROJECT_NAME-$outputSuffix
        mv $STATIC_LIB Headers $PROJECT_NAME-$outputSuffix
        zip -r $PROJECT_NAME-$outputSuffix.zip $PROJECT_NAME-$outputSuffix
        rm -rf $PROJECT_NAME-$outputSuffix
    )
}

function pre_build_process() {
	rm -rf $OPT_ARTIFACTS/$STATIC_LIB $OPT_ARTIFACTS/$HEADER_PATH
	mkdir -p $OPT_ARTIFACTS/$HEADER_PATH
}

# Generates the SDK headers. This function is invoked directly from the Xcode project.
function gen_headers() {
    if [ 0$XCODE_VERSION_MINOR -lt 0400 ] ; then
        usage "Generating headers needs to be run from within an Xcode shell environment"
    fi

    # 'DerivedData' in the BUILT_PRODUCTS_DIR path probably indicates that we're building from within the Xcode IDE 
    # (as opposed to from the command line via xcodebuild), therefore output the combined headers to the DerivedData
    # path (such as the example below); otherwise output the combined headers to the 'artifacts' path.
    if [[ "$BUILT_PRODUCTS_DIR" =~ '/DerivedData/' ]]; then
        H=$BUILT_PRODUCTS_DIR
    else
        H=$INSTALL_ROOT                    # i.e. build/artifacts/$configuration-$sdk/Headers
    fi
    
    
    H=$H/Headers
    
    headers="SalesforceNetworkSDK"
    
	for target in $headers; do
        mkdir -p $H/$target
        if [ $H/$target/$target.h -nt $PROJECT_FILE_PATH/project.pbxproj ]; then
            echo "Skipping $target since it is up-to-date"
            continue
        fi
        
        echo "Generating headers $H/$target/$target.h"
        
        cat <<EOF > $H/$target/$target.h
//
//  $target.h
//  $PROJECT_NAME
//
//  Created by Michael Nachbaur on $DATE.
//  Copyright 2012 Salesforce.com. All rights reserved.
//

EOF
    for file in $(find $H/$target -type f); do
        if [[ $file =~ "/$target.h" ]]; then
            continue;
        fi
        echo $file | sed -E "s%$H/$target/%#import \"%" | sed -E 's/$/"/' >> $H/$target/$target.h
    done
done
    
}

# Fetches the dependencies of ChatterSDK from the build server.
# This is the only place where we absolutely need to fetch from a non-local directory.
function fetch_dependencies() {
    echo "Installing dependencies"

	mkdir -p "$DEPENDENCIES"
    downloadJenkinsDependencies $OPT_JOBURL
}

# Main function of this script
function main() {
    if [ $# == 0 ]; then
        usage
    fi

	#prep install path
	

    local args="$*"
    if [[ $args =~ all ]] ; then
        args="dependencies debug release"
    fi
    
    if [[ $args =~ dependencies ]]; then
    	if [[ -z $OPT_JOBURL ]] ; then
            if [[ -n $OPT_BRANCH ]] ; then
            	local testURL="http://mobile-iosbuild1-1-sfm.ops.sfdc.net/jenkins/job/Salesforce-iOS-NetworkSDK-$OPT_BRANCH/"
            	echo "$testURL"
                if [[ $(curl -Is -w "%{http_code}" -o/dev/null $testURL) -eq 200 ]]; then
                    echo "No job URL supplied, but guessed it is $testURL"
                    OPT_JOBURL=$testURL
                else 
                	echo "No job URL supplied, and $testURL calculated from branch cannot be connected"
                fi
                 
            fi
        fi

        [[ -z $OPT_JOBURL ]] && usage "You must supply a job URL when not running within Jenkins"

        fetch_dependencies
    fi
    
    if [[ $args =~ debug ]] ; then
        echo "generate combined library for Debug configuration"
        build_combined Debug
    fi
    
    if [[ $args =~ release ]] ; then
        echo "generate combined library for Release configuration"
        build_combined Release
    fi
    
   
    if [[ $args =~ gen_headers ]]; then
        gen_headers                   # only allowed for scripts running within an Xcode shell
    fi

    rm -rf $OPT_ARTIFACTS/$STATIC_LIB $OPT_ARTIFACTS/$HEADER_PATH
}

# Turn on error to stop as soon as something goes wrong
set -e

# Debug log
#set -x

# Execute the main function
main "$@"
