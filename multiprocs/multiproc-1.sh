#!/bin/bash
# ********************************************************************
# (c) 2022 Skynet Consulting Ltd.
# ********************************************************************
# Description:
#   This script demonstrates simple multitasking in bash
# ********************************************************************

task(){
   ((i=$RANDOM%20))
   echo "*** Task Start - $1 ($2) - Sleep $i at "`date "+%Y%m%d_%H%M%S"`
   sleep $i
   echo "*** Task Finish - $1 ($2) - Sleep $i at "`date "+%Y%m%d_%H%M%S"`
}

N=4
(
   for thing in a b c d e f g h i j k l; do
   echo "*** loop **"
      ((i=i%N)); export CPU=$i;((i++==0)) && wait
      task "$thing" $CPU &
   done
   sleep 1
   jobs -p

   echo "** Waiting"
   wait < <(jobs -p)
   echo "** Finish"
)

