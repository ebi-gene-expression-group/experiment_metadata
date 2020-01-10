#!/bin/bash
# @author: rpetry
# @date:   11 Nov 2011

# This script provides Nagios-like monitoring of http://www.ebi.ac.uk/ontology-lookup/term.view

if [ $# -lt 2 ]; then
        echo "Usage: $0 OLS_URL NOTIFICATION_EMAILADDRESS"
        exit 1;
fi

OLS_URL=$1
NOTIFICATION_EMAILADDRESS=$2

httpCode=`curl -o /dev/null -X GET -s -w %{http_code} "$OLS_URL"`
if [ $httpCode -ne 200 ]; then
   if [ ! -f ~/tmp/ols_down ]; then
	now=`eval date "+%Y-%m-%d\ %H:%M"`
	echo "HTTP return code: $httpCode" | mailx -s "[ols/cron]: $now: $OLS_URL unresponsive" ${NOTIFICATION_EMAILADDRESS}
	touch ~/tmp/ols_down
   fi	   	   
else
   if [ -f ~/tmp/ols_down ]; then
	now=`eval date "+%Y-%m-%d\ %H:%M"`
	mailx -s "[ols/cron]: $now: $OLS_URL back to life" ${NOTIFICATION_EMAILADDRESS} < /dev/null
	rm -rf ~/tmp/ols_down
   fi	  
fi      