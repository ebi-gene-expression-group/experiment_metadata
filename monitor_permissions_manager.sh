#!/bin/bash

# This script provides Nagios-like monitoring of https://www.ebi.ac.uk/fg/acext/api/test

if [ $# -lt 2 ]; then
        echo "Usage: $0 ACEXT_URL NOTIFICATION_EMAILADDRESS"
        exit 1;
fi

ACEXT_URL=$1
NOTIFICATION_EMAILADDRESS=$2

httpCode=`curl -o /dev/null -X GET -s -w %{http_code} "$ACEXT_URL"`
if [ $httpCode -ne 200 ]; then
   if [ ! -f ~/tmp/acext_down ]; then
	now=`eval date "+%Y-%m-%d\ %H:%M"`
	echo "HTTP return code: $httpCode" | mailx -s "[acext/cron]: $now: $ACEXT_URL unresponsive" ${NOTIFICATION_EMAILADDRESS}
	touch ~/tmp/acext_down
   fi	   	   
else
   if [ -f ~/tmp/acext_down ]; then
	now=`eval date "+%Y-%m-%d\ %H:%M"`
	mailx -s "[acext/cron]: $now: $ACEXT_URL back to life" ${NOTIFICATION_EMAILADDRESS} < /dev/null
	rm -rf ~/tmp/acext_down
   fi	  
fi      
