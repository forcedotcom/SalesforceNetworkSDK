#generate appledoc
HELPDOC_PATH=helpdocs
DISTRIBUTION_PATH=../../distribution
DOC_NAME=SalesforceNetworkSDKHelpDocs
FINAL_DOCSET_NAME=com.salesforce.networksdk.1_0.docset
mkdir -p $HELPDOC_PATH;
appledoc ./AppledocSettings.plist ../SalesforceNetworkSDK
(cd $HELPDOC_PATH; mkdir -p $DISTRIBUTION_PATH; mv docset $FINAL_DOCSET_NAME; zip -r ${DISTRIBUTION_PATH}/$DOC_NAME.zip $FINAL_DOCSET_NAME html; rm -rf $FINAL_DOCSET_NAME; rm -rf html)
rm -rf $HELPDOC_PATH

