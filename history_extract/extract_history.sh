#!/bin/bash
# ******************************************************************************
# (c) 2021 Skynet Consulting Ltd.
#
# File:    wspl_extract_history.sh
# Date:    14 May 2021
# Author:  Douglas Kruger
# Version: 1.0
#
# Description:
# This script exports out the history data.
# It creates database views that gets the appropriate data. The view
# is then used by the Sybase bcp (Bulk Copy) utility to dump into a text file
# One file per data type is created and the file is gzipped.
# ******************************************************************************
# The following was used to determine the sybase date conversion
# COUNTER=0
# while [  $COUNTER -lt 150 ]; do
#    echo "select $COUNTER as FORMAT,convert(CHAR(35),getdate(),$COUNTER) as DATE"
#    echo "go"
#    let COUNTER=COUNTER+1
# done
# ******************************************************************************
# isql useful settings
#   set rowcount 10
#   set nocount on
#   set statistics io, time on
# ******************************************************************************
export SA_PASSWD=SET_PASSWORD
export CONFIG_DB=SET_CONFIG_DB
export HISTORY_DB=SET_HISTORY_DB
# ******************************************************************************
# Define the data types of interest in the history database
# ******************************************************************************
export DATA_TYPES="boolean choice float long short peakfloat peaklong"
export EXT_TIME=`date "+%Y%m%d_%H%M%S"`
export LOG=wspl_extract_history_${EXT_TIME}.log
export WORK_DIR=$HOME/abb_extract
# ******************************************************************************
# Make the working subdir
# ******************************************************************************
mkdir -p $WORK_DIR
cd $WORK_DIR
/bin/rm -f $WORK_DIR/*
# ******************************************************************************
# Create the sql files to count the various table rows
# ******************************************************************************
isql -Usa -P${SA_PASSWD} -w300 -ocount_history.sql -b <<EOF
set nocount on
go
select 'set nocount on' || char(10) || 'go'
select 'set statistics io, time on' || char(10) || 'go'
go
select 'select '''||convert(varchar(40),name)|| ''',count(ObjectId) from ${HISTORY_DB}..' ||
  convert(varchar(40),name) || char(10) || 'go' ||char(10) history_sql from ${HISTORY_DB}..sysobjects
  where type='U' and name like 'WG_%' and name not like 'WG_edit%' and name not like 'WG_pointlist%'
  order by name
go
select 'exit'
go
exit
EOF
isql -Usa -P${SA_PASSWD} -w300 -ocount_history_pointlist.sql -b <<EOF
set nocount on
go
select 'set nocount on' || char(10) || 'go'
go
select 'select '''||convert(varchar(40),name)|| ''',count(ObjectId) from ${HISTORY_DB}..' ||
  convert(varchar(40),name) || char(10) || 'go' ||char(10) history_sql from ${HISTORY_DB}..sysobjects
  where type='U' and name like 'WG_pointlist%'
  order by name
go
select 'exit'
go
exit
EOF
isql -Usa -P${SA_PASSWD} -w300 -ocount_history_edit.sql -b <<EOF
set nocount on
go
select 'set nocount on' || char(10) || 'go'
go
select 'select '''||convert(varchar(40),name)|| ''',count(ObjectId) from ${HISTORY_DB}..' ||
  convert(varchar(40),name) || char(10) || 'go' ||char(10) history_sql from ${HISTORY_DB}..sysobjects
  where type='U' and name like 'WG_edit%'
  order by name
go
select 'exit'
go
exit
EOF
# ******************************************************************************
# Create the sql view definition file to drop the views
# ******************************************************************************
cat >drop_abb_views.sql << EOF
use ${HISTORY_DB}
go
EOF
for DATA_TYPE in ${DATA_TYPES}; do
cat >>drop_abb_views.sql << EOF
drop view ABB_WG_${DATA_TYPE}_v
go
drop view ABB_WG_${DATA_TYPE}_all_v
go
EOF
done
# Add the exit to the file
cat >>drop_abb_views.sql << EOF
exit
EOF
# ******************************************************************************
# Create the sql view definition file
# ******************************************************************************
cat >create_abb_views.sql << EOF
use ${HISTORY_DB}
go
EOF
for DATA_TYPE in ${DATA_TYPES}; do
if [ ${DATA_TYPE} == "float" ]; then
cat >>create_abb_views.sql << EOF
create view ABB_WG_${DATA_TYPE}_v as
select
  str_replace(convert(char(14),ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || str(Value,30,9) || ";1;0;"," ",NULL) ABB_row from WG_${DATA_TYPE}
go
create view ABB_WG_${DATA_TYPE}_all_v as
select
  ObjectId, convert(char(23),Time,140) Time,MicroSeconds,Value,
  str_replace(convert(char(14),ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || str(Value,30,9) || ";1;0;"," ",NULL) ABB_row from WG_${DATA_TYPE}
go
EOF
else
cat >>create_abb_views.sql << EOF
create view ABB_WG_${DATA_TYPE}_v as
select
  str_replace(convert(char(14),ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || convert(char(20),Value) || ";1;0;"," ",NULL) ABB_row from WG_${DATA_TYPE}
go
create view ABB_WG_${DATA_TYPE}_all_v as
select
  ObjectId, convert(char(23),Time,140) Time,MicroSeconds,Value,
  str_replace(convert(char(14),ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || convert(char(20),Value) || ";1;0;"," ",NULL) ABB_row from WG_${DATA_TYPE}
go
EOF
fi
done
# Add the exit to the file
cat >>create_abb_views.sql << EOF
exit
EOF
# ******************************************************************************
# Drop then create the sql views
# ******************************************************************************
isql -Usa -P${SA_PASSWD} -w300 -idrop_abb_views.sql
isql -Usa -P${SA_PASSWD} -w300 -icreate_abb_views.sql
# ******************************************************************************
# Execute the database counts
# ******************************************************************************
echo "*** Started at `date`" >>${LOG}
echo "SQL: count history at `date`" >>${LOG}
#isql -Usa -P${SA_PASSWD} -b -w300 -icount_history.sql -ocount_history.lst
echo "SQL: count history edit at `date`" >>${LOG}
isql -Usa -P${SA_PASSWD} -b -w300 -icount_history_edit.sql -ocount_history_edit.lst
echo "SQL: count history pointlist at `date`" >>${LOG}
isql -Usa -P${SA_PASSWD} -b -w300 -icount_history_pointlist.sql -ocount_history_pointlist.lst
echo "*** Finished at `date`" >>${LOG}
# ******************************************************************************
# Execute the Bulk Copy the records out of the database
# ******************************************************************************
echo "*** Started BCP at `date`" >>${LOG}
for DATA_TYPE in ${DATA_TYPES}; do
(
        echo "Extracting ABB_WG_${DATA_TYPE} at `date`" >>${LOG}
        export FILENAME="ABB_WG_${DATA_TYPE}_${EXT_TIME}"
        bcp ${HISTORY_DB}..ABB_WG_${DATA_TYPE}_v out ${FILENAME}.txt -e ${FILENAME}.err \
                -b 100000 -Usa -P${SA_PASSWD} -c -t ";" >> ${LOG} 2>&1
        echo "Gzipping ${FILENAME}.txt at `date`" >>${LOG}
        gzip ${FILENAME}.txt
) >> ${LOG}
done
echo "*** Finished at `date`" >>${LOG}
