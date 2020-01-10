#!/bin/bash

# This script provides Nagios-like monitoring of http://www.ebi.ac.uk/microarray-srv/otrs/index.pl

if [ $# -lt 2 ]; then
        echo "Usage: $0 OTRS_URL NOTIFICATION_EMAILADDRESS"
        exit 1;
fi

OTRS_URL=$1
NOTIFICATION_EMAILADDRESS=$2

httpCode=`curl -o /dev/null -X GET -s -w %{http_code} "$OTRS_URL"`
if [ $httpCode -ne 200 ]; then
   if [ ! -f ~/tmp/otrs_down ]; then
	now=`eval date "+%Y-%m-%d\ %H:%M"`
	echo "HTTP return code: $httpCode" | mailx -s "[otrs/cron]: $now: $OTRS_URL unresponsive" ${NOTIFICATION_EMAILADDRESS}
	touch ~/tmp/otrs_down
   fi	   	   
else
   if [ -f ~/tmp/otrs_down ]; then
	now=`eval date "+%Y-%m-%d\ %H:%M"`
	mailx -s "[otrs/cron]: $now: $OTRS_URL back to life" ${NOTIFICATION_EMAILADDRESS} < /dev/null
	rm -rf ~/tmp/otrs_down
   fi	  
fi      
