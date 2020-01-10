#!/bin/bash
# @author: rpetry
# @date:   16 Jun 2014

if [ $# -lt 1 ]; then
        echo "Usage: $0 NOTIFICATION_EMAILADDRESS"
        exit 1;
fi

NOTIFICATION_EMAILADDRESS=$1

time=`eval date +%H:%M:%S`


# This script reports any new files in $ATLAS_PROD/conan_incoming
pushd $ATLAS_PROD/conan_incoming
find . -type d -newerct 'yesterday' -print | grep E- | sed 's|./||g' | sort | uniq > latest.todays.exps
if [ -s "todays.exps" ]; then
   comm -13 todays.exps latest.todays.exps > report.today.exps
else
   cp latest.todays.exps report.today.exps
fi
mv latest.todays.exps todays.exps
if [ -s "report.today.exps" ]; then
   mailx -s "[atlas3/cron]: $time: New experiment(s) need loading into Atlas" ${NOTIFICATION_EMAILADDRESS} < report.today.exps
fi
popd
