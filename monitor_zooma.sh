#!/bin/bash
# @author: rpetry
# @date:   11 Nov 2011

# This script provides Nagios-like monitoring of http://www.ebi.ac.uk/spot/zooma

if [ $# -lt 2 ]; then
        echo "Usage: $0 ZOOMA_URLS NOTIFICATION_EMAILADDRESS"
        exit 1;
fi

ZOOMA_URLS=$1
NOTIFICATION_EMAILADDRESS=$2
# query="v2/api/server/metadata"
query="v2/api/services/annotate?propertyValue=heart"
for server in $(echo $ZOOMA_URLS | tr "," "\n"); do
    host=`echo $server | awk -F"." '{print $1}' | sed 's|http://||'`
    # Make sure the output file exists - so that mailx doesn't complain 
    touch ~/tmp/zooma_${host}_output
    httpCode=`curl -o ~/tmp/zooma_${host}_output -X GET -s -w %{http_code} "$server/$query"`
    echo $httpCode | grep -P '000|200' > /dev/null
    if [ $? -ne 0 ]; then
	if [ ! -f ~/tmp/zooma_${host}_down ]; then
	    now=`eval date "+%Y-%m-%d\ %H:%M"`
	    mailx -s "[zooma/cron]: $now: $server unresponsive (HTTP return code: $httpCode)" ${NOTIFICATION_EMAILADDRESS} < ~/tmp/zooma_${host}_output
	    touch ~/tmp/zooma_${host}_down
	fi	   	   
    else
	if [ -f ~/tmp/zooma_${host}_down ]; then
	    now=`eval date "+%Y-%m-%d\ %H:%M"`
	    mailx -s "[zooma/cron]: $now: $server back to life" ${NOTIFICATION_EMAILADDRESS} < /dev/null
	    rm -rf ~/tmp/zooma_${host}_down
	fi	  
fi      
done
