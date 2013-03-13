#!/bin/bash
# This script builds the Salesforce NetworkSDK artifacts

# Xcode build setting references: 
#   http://developer.apple.com/library/mac/#documentation/DeveloperTools/Reference/XcodeBuildSettingRef/1-Build_Setting_Reference/build_setting_ref.html

# Environment variable used in this script:
# JOB_URL : URL of the job as specified by Jenkins
# WORKSPACE : Jenkins workspace or current directory if not specified
SCRIPT_ROOT=$(dirname $0)
. $SCRIPT_ROOT/build.common


usage() {
	[ $# -eq 0 ] || error "$*" >&2
cat <<EOF >&2
usage: $0 [options] <action>...
options:
    -b=<branch>     Branch name (default: current branch name from git)
    -o=<logfile>    Log output filename (default: 'output.txt')
    -j=<jobURL>     Jenkins job URL (default: '\$JOB_URL') $(clr smul)$(clr bold)[REQUIRED]$(clr sgr0)
    -h              Help
    -v              Verbose mode

actions:
    $(clr smul)$(clr bold)all (default)$(clr sgr0)    Builds all actions
    docs             Generates documentation output
    all	             Fetch dependencis, Builds release, debug, thin
    release          Compiles the release build, with simulator and device architectures
    debug            Compiles the debug build, with simulator and device architectures
    thin			 Compiles the thin build, with only device architecture
    dependencies     Fetches and installs dependencies
    
misc:
    The below actions may only be run from a script executing in the context of an Xcode shell
    (i.e. an Xcode script build phase):
    
    public_headers  Generates import headers for Salesforce-iOS-NetworkSDK
EOF
    exit 1
}

OPT_HELP=
OPT_VERBOSE=
OPT_BRANCH=`git branch | awk '/^\* / { print $2 }'`
OPT_JOBURL=$JOB_URL
while getopts "vhs:w:o:a:b:n:j:" opt; do
	case $opt in
        h) OPT_HELP=1 ;;
        v) OPT_VERBOSE=1 ;;
        b) OPT_BRANCH=$OPTARG ;;
        j) OPT_JOBURL=$OPTARG ;;
        \?) usage "Invalid option: -$opt" ;;
        :) usage "Option -$opt requires an argument." ;;
    esac
done
shift $((OPTIND-1))

INSTALL_PATH=$WORKSPACE/artifacts
STATIC_LIB=libSalesforceNetworkSDK.a
LIBRARY_PATH=Libraries
HEADER_PATH=Headers
PROJECT_NAME=SalesforceNetworkSDK
DISTRIBUTION_PATH=$PWD/../../distribution
[ -z $INSTALL_PATH ] || INSTALL_PATH=$PWD/artifacts

PROJ=../$PROJECT_NAME.xcodeproj
declare readonly DEPENDENCIES="$SCRIPT_ROOT/../dependencies"

function build_combined() {
	local configuration="$1"; shift
	pre_build_process
	xcodebuild -project $PROJ -configuration $configuration -sdk iphoneos INSTALL_ROOT=$INSTALL_PATH/device install
	xcodebuild -project $PROJ -configuration $configuration -sdk iphonesimulator INSTALL_ROOT=$INSTALL_PATH/simulator install
	lipo -create -output $INSTALL_PATH/$LIBRARY_PATH/$STATIC_LIB $INSTALL_PATH/device/$LIBRARY_PATH/$STATIC_LIB $INSTALL_PATH/simulator/$LIBRARY_PATH/$STATIC_LIB
	
	post_build_process $configuration $configuration
}

function build_thin() {
	pre_build_process
  	xcodebuild -project $PROJ -configuration Release -sdk iphoneos INSTALL_ROOT=$INSTALL_PATH/device install
  	mv $INSTALL_PATH/device/$LIBRARY_PATH/$STATIC_LIB $INSTALL_PATH/$LIBRARY_PATH/$STATIC_LIB
  	
  	post_build_process Release Thin
}

function post_build_process() {
	local configuration="$1"; shift
	local outputSuffix="$1"; shift
	mv $INSTALL_PATH/device/Headers $INSTALL_PATH
	rm -rf $INSTALL_PATH/device $INSTALL_PATH/simulator
	rm -rf $configuration*
	rm -rf *.build
	(
        cd $INSTALL_PATH
        rm -rf $PROJECT_NAME-$outputSuffix $PROJECT_NAME-$outputSuffix.zip
        mkdir $PROJECT_NAME-$outputSuffix
        mv $LIBRARY_PATH $HEADER_PATH $PROJECT_NAME-$outputSuffix
        zip -r $PROJECT_NAME-$outputSuffix.zip $PROJECT_NAME-$outputSuffix
        rm -rf $PROJECT_NAME-$outputSuffix
    )
}

function pre_build_process() {
	rm -rf $INSTALL_PATH/$LIBRARY_PATH
	rm -rf $INSTALL_PATH/$HEADER_PATH
	mkdir -p $INSTALL_PATH/$LIBRARY_PATH
	mkdir -p $INSTALL_PATH/$HEADER_PATH
}

# Generates the SDK headers. This function is invoked directly from the Xcode project.
function gen_headers() {
    local mode=$1
    if [ 0$XCODE_VERSION_MINOR -lt 0400 ] ; then
        usage "Generating headers needs to be run from within an Xcode shell environment"
    fi

	inH=$CONFIGURATION_BUILD_DIR/Headers
    outH=$BUILT_PRODUCTS_DIR/Headers
    DATE=$(date +"%e/%m/%y")
    info "Generating headers $H"

    if [[ $mode = "SalesforceNetworkSDK" ]] ; then
        headers="SalesforceNetworkSDK SalesforceNetworkSDKPrivate"
    fi
 
	for target in $headers; do
        mkdir -p $outH/$target
        if [ $outH/$target/$target.h -nt $PROJECT_FILE_PATH/project.pbxproj ]; then
            warn "Skipping $target since $outH/$target/$target.h is up-to-date"
            continue
        fi
        
        cat <<EOF > $outH/$target/$target.h
        
//
//  $target.h
//  $mode
//
//  Created by Michael Nachbaur on $DATE.
//  Copyright 2012 Salesforce.com. All rights reserved.
//

EOF
    for file in $(find $inH/$target -type f); do
        filename=$(basename $file)
        if [[ $filename == "$target.h" ]]; then
            continue;
        fi
        echo "#import \"$filename\"" >> $inH/$target/$target.h
    done
    
done
    
}

# Fetches the dependencies of ChatterSDK from the build server.
# This is the only place where we absolutely need to fetch from a non-local directory.
function fetch_dependencies() {
    info "Installing dependencies"

	mkdir -p "$DEPENDENCIES"
    downloadJenkinsDependencies $OPT_JOBURL
}

# Main function of this script
function main() {
    if [ $# == 0 ]; then
    	usage "You must supply a command."
    fi

	#prep install path
	

    local args="$*"
    if [[ $args =~ all ]] ; then
        args="dependencies debug release thin"
    fi
    
    if [[ $args =~ dependencies ]]; then
        if [[ -z $OPT_JOBURL ]] ; then
            if [[ -n $OPT_BRANCH ]] ; then
            	local testURL="http://mobile-iosbuild1-1-sfm.ops.sfdc.net/jenkins/job/Salesforce-iOS-NetworkSDK-$OPT_BRANCH/"
            	info "$testURL"
                if [[ $(curl -Is -w "%{http_code}" -o/dev/null $testURL) -eq 200 ]]; then
                    info "No job URL supplied, but guessed it is $testURL"
                    OPT_JOBURL=$testURL
                else 
                	info "No job URL supplied, and $testURL calculated from branch cannot be connected"
                fi
                 
            fi
        fi

        [[ -z $OPT_JOBURL ]] && usage "You must supply a job URL when not running within Jenkins"

        fetch_dependencies
    fi
    
    if [[ $args =~ debug ]] ; then
        info "generate combined library for Debug configuration"
        build_combined Debug
    fi
    
    if [[ $args =~ release ]] ; then
        info "generate combined library for Release configuration"
        build_combined Release
    fi
    
    if [[ $args =~ thin ]] ; then
        info "generate thin library for Device Release configuration"
        build_thin
    fi
    
    if [[ $args =~ public_headers ]]; then
    	gen_headers SalesforceNetworkSDK                  # only allowed for scripts running within an Xcode shell
    fi
}


# Turn on error to stop as soon as something goes wrong
set -e

# Debug log
#set -x

# Execute the main function
main "$@"
