#!/bin/bash
# This script builds the Salesforce NetworkSDK artifacts

# Xcode build setting references: 
#   http://developer.apple.com/library/mac/#documentation/DeveloperTools/Reference/XcodeBuildSettingRef/1-Build_Setting_Reference/build_setting_ref.html

# Environment variable used in this script:
# JOB_URL : URL of the job as specified by Jenkins
# WORKSPACE : Jenkins workspace or current directory if not specified
SCRIPT_ROOT=$(dirname $0)
. $SCRIPT_ROOT/build.common

INSTALL_PATH=$WORKSPACE/artifacts
STATIC_LIB=libSalesforceNetworkSDK.a
LIBRARY_PATH=Libraries
HEADER_PATH=Headers
PROJECT_NAME=SalesforceNetworkSDK
DISTRIBUTION_PATH=$PWD/../../distribution
[ -z $INSTALL_PATH ] || INSTALL_PATH=$PWD/artifacts

PROJ=../$PROJECT_NAME.xcodeproj
OPT_JOBURL="http://mobile-iosbuild1-1-sfm.ops.sfdc.net/jenkins/job/Salesforce-iOS-NetworkSDK"
OPT_VERBOSE=1
declare readonly DEPENDENCIES="$SCRIPT_ROOT/dependencies"

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

    # 'DerivedData' in the BUILT_PRODUCTS_DIR path probably indicates that we're building from within the Xcode IDE 
    # (as opposed to from the command line via xcodebuild), therefore output the combined headers to the DerivedData
    # path (such as the example below); otherwise output the combined headers to the 'artifacts' path.
     
    if [[ "$BUILT_PRODUCTS_DIR" =~ '/DerivedData/' ]]; then
        H=$BUILT_PRODUCTS_DIR
        H=`(cd $H/..; echo $PWD)`
    else
        H=$INSTALL_ROOT                    # i.e. ChatterSDK/build/artifacts/$configuration-$sdk/Headers
    fi
    
    
    H=$H/Headers
    
    headers=$mode
    
	for target in $headers; do
        if [ $H/$target.h -nt $PROJECT_FILE_PATH/project.pbxproj ]; then
            echo "Skipping $target since it is up-to-date"
            continue
        fi
        
        echo "Generating headers $H/$target.h"
        
        cat <<EOF > $H/$target.h
        
//
//  $target.h
//  $mode
//
//  Created by Michael Nachbaur on $DATE.
//  Copyright 2012 Salesforce.com. All rights reserved.
//

EOF
    for file in $(find $H/$target -type f); do
        echo $file | sed -E "s%$H/%#import \"%" | sed -E 's/$/"/' >> $H/$target.h
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
        help
    fi

	#prep install path
	

    local args="$*"
    if [[ $args =~ all ]] ; then
        args="dependencies debug release thin"
    fi
    
    if [[ $args =~ dependencies ]]; then
        if [[ -z $OPT_JOBURL ]] ; then
            if [[ -n $OPT_BRANCH ]] ; then
                local testURL="http://mobile-iosbuild1-1-sfm.ops.sfdc.net/jenkins/job/Salesforce-iOS-NetworkSDK"
                if [[ $(curl -Is -w "%{http_code}" -o/dev/null $testURL) -eq 200 ]]; then
                    info "No job URL supplied, but guessed it is $testURL"
                    OPT_JOBURL=$testURL
                fi
            fi
        fi

        [[ -z $OPT_JOBURL ]] && help "You must supply a job URL when not running within Jenkins"

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
    
    if [[ $args =~ thin ]] ; then
        echo "generate thin library for Device Release configuration"
        build_thin
    fi
    
    if [[ $args =~ public_headers ]]; then
    	gen_headers SalesforceNetworkSDK                  # only allowed for scripts running within an Xcode shell
    fi
}

#==================================================================================
# Print out Help for this build script
function help () {
	echo "Usage: ./build.sh all - Creates SalesforceNetworkSDK for Debug, Release configuration with a combined library. Also creates a thin library for release on device only"
	echo "Usage: ./build.sh debug - Creates SalesforceNetworkSDK for Debug configuration with a combined library"
	echo "Usage: ./build.sh release - Creates SalesforceNetworkSDKileSDK for Release configuration with a combined library"
	echo "Usage: ./build.sh thin - Creates SalesforceNetworkSDK for Release configuration and device only library"
}

# Turn on error to stop as soon as something goes wrong
set -e

# Debug log
#set -x

# Execute the main function
main "$@"
