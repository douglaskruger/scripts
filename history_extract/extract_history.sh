#!/bin/bash
# ******************************************************************************
# (c) 2021 Skynet Consulting Ltd.
#
# File:    wspl_extract_history.sh
# Date:    5 Aug 2021
# Author:  Douglas Kruger
# Version: 1.5
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
export DATA_TYPES="float boolean choice long short peakfloat peaklong"

# ******************************************************************************
# Define the data types of interest in the history database
# ******************************************************************************
export SYB_SERVER="SYBASE_`uname -n`"
export EXT_TIME=`date "+%Y%m%d_%H%M%S"`
export LOG=extract_history_${EXT_TIME}.log
export WORK_DIR=$HOME/extract_history
export BCP_LINES=10000000
export SYB_CONNECT="-Usa -P${SA_PASSWD} -w300 -S${SYB_SERVER}"

# ******************************************************************************
# Make the working subdir
# ******************************************************************************
mkdir -p $WORK_DIR
cd $WORK_DIR
/bin/rm -f $WORK_DIR/*

# ******************************************************************************
# Create the sql files to create the view of Object Attribute
# ******************************************************************************
cat > object_attribute.sql <<EOF
use ${CONFIG_DB}
go
set nocount on
go

/* Find the ObjectAttributes */
drop view ObjectAttributes_V
go
create view ObjectAttributes_V as
select substring(O.ObjectTypeName,1,30) "ObjectTypeName", OA.ObjectTypeId "ObjectTypeId",
  substring(A.AttributeTypeName,1,30) "AttributeTypeName", OA.AttributeTypeId "AttributeTypeId",
  OA.Position,
(case when OA.Scope = 0 then "Config" when OA.Scope = 1 then "Runtime" when OA.Scope = 2 then "Both" end) "Scope"
from ObjectTypes O,AttributeTypes A, ObjectAttributes OA
where O.ObjectTypeId=OA.ObjectTypeId and A.AttributeTypeId=OA.AttributeTypeId
go
exit
EOF

# ******************************************************************************
# Create the sql files to build the object view
# ******************************************************************************
isql ${SYB_CONNECT} -b -oobject_info.sql <<EOF
set nocount on
go
select 'set nocount on' || char(10) || 'go'
go
use ${CONFIG_DB}
go
select 'use ${CONFIG_DB}' || char(10) || 'go'
go
select 'select "*** Create ObjectInfo_v ***"' || char(10) || 'go'
go
select 'drop view ObjectInfo_v' || char(10) || 'go'
go
select 'create view ObjectInfo_v as' 
go
select 'select ObjectId,ObjectId/1048576 as OType, substring(Name,1,45) as Name, "' || substring(T1.name,1,45) || '" as OName' || char(10) ||
 'from ' || substring(T1.name,1,45) || ' where HouseKeeping_State<3 union '
 from sysobjects T1, syscolumns T2 where T1.type='U' and T1.id=T2.id and T2.name="HouseKeeping_State" and T1.name!="Wiring"
go
select char(10) || 'go' || char(10)
go
select 'select "*** Create PointNum_v ***"' || char(10) || 'go'
go
select 'drop view PointNum_v' || char(10) || 'go'
go
select 'create view PointNum_v as' 
go
select 'select ObjectId,ObjectId/1048576 as OType, substring(Name,1,45) as Name, "' || substring(T1.name,1,45) || '" as OName, PointNumber as P' || char(10) ||
 'from ' || substring(T1.name,1,45) || ' where HouseKeeping_State<3 union '
 from sysobjects T1, syscolumns T2 where T1.type='U' and T1.id=T2.id and T2.name="PointNumber"
go
select char(10) || 'go' || char(10)
go
select 'exit'
go
exit
EOF

# ******************************************************************************
# Create the sql files to get the vista object definitions
# ******************************************************************************
isql ${SYB_CONNECT} -b -ovista_defn.lst <<EOF
set nocount on
go
use ${CONFIG_DB}
go
drop view vista_defn_v
go
create view vista_defn_v as
select
        substring(T1.Name,1,30) as TName,
        substring(T2.Name,1,30) as GName,
        substring(T4.Name,1,30) as SName,
        T1.TemplateNumber as T,
        T2.GroupNumber as G,
        T4.SubgroupNumber as S,
        substring(T5.Name,1,30) as OTypeName,
        substring(T6.Name,1,30) as ATypeName,
        T5.ObjectId-1048576 as OType,
        T6.ObjectId-2097152 as AType
from
        VISTATemplate T1,
        VISTAGroup T2,
        ObjectAttribute T3,
        VISTASubgroup T4,
        ObjectType T5,
        AttributeType T6,
        Wiring W1,                              -- Link VISTATemplate to VISTAGroup
        Wiring W2,                              -- Retrieve VISTAGroup ParentLink
        Wiring W3,                              -- Retrive the ObjectType childlist
        Wiring W4,                              -- Retrive the ObjectAttribute childlist
        Wiring W5                               -- Retrive the ObjectAttribute childlist
where
        T1.ObjectId=W1.ObjectId and W1.AttributeTypeId=815 and W1.WiredObjectId=T2.ObjectId and
        T2.ObjectId=W2.ObjectId and W2.AttributeTypeId=9 and W2.WiredObjectId=W3.ObjectId and
        T3.ObjectId=W3.WiredObjectId and W3.AttributeTypeId=8 and
        T4.ObjectId=W4.WiredObjectId and W4.AttributeTypeId=8 and W4.ObjectId=W3.WiredObjectId and
        T5.ObjectId=W2.WiredObjectId and
        T6.ObjectId=W5.WiredObjectId and W5.AttributeTypeId=16 and W5.ObjectId=T3.ObjectId
go
select * from vista_defn_v order by T,G,S
go
exit
EOF

# ******************************************************************************
# Create the sql files to count the various table rows
# ******************************************************************************
isql ${SYB_CONNECT} -ocount_history.sql -b <<EOF
set nocount on
go
use ${HISTORY_DB}
go
select 'use ${HISTORY_DB}' || char(10) || 'go'
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

# ******************************************************************************
# Create the abb_mapping table
# ******************************************************************************
isql ${SYB_CONNECT} -ocreate_mapping.sql -b <<EOF
set nocount on
go
select 'set nocount on' || char(10) || 'go'
go
use ${HISTORY_DB}
go
select 'use ${HISTORY_DB}' || char(10) || 'go'
go
select 'select "*** Create abb_mapping ***"' || char(10) || 'go'
go
select 'drop table abb_mapping' || char(10) || 'go'
go
select 'select ObjectId,0 as OBE_IRN, ObjectId/1048576 as OType, AttributeId as AType, ' || char(10) ||
  '0 as A,0 as U, 0 as T, 0 as M, 0 as G, 0 as S, 0 as P into abb_mapping ' || char(10) ||
  'from WG_pointlist_float where 1=2' || char(10) || 'go'
go
select 'insert abb_mapping select ObjectId, 0 as OBE_IRN, ObjectId/1048576 as OType, AttributeId as AType,' || char(10) ||
  '0 as A,0 as U, 0 as T, 0 as M, 0 as G, 0 as S, 0 as P from ${HISTORY_DB}..' || convert(varchar(40),name) || char(10) ||
  'go' || char(10) history_sql from sysobjects
  where type='U' and name like 'WG_pointlist%'
go
select 'update abb_mapping set T=T1.T, G=T1.G, S=T1.S' || char(10) ||
  'from ${CONFIG_DB}..vista_defn_v T1, abb_mapping T2' || char(10) ||
  'where T1.OType=T2.OType and T1.AType=T2.AType' || char(10) ||
  'go' || char(10)
go
/*
select 'update abb_mapping set U=T1.UnitNumber, A=T1.Address, M=T1.MemberNumber' || char(10) ||
  'from ${CONFIG_DB}..RTU T1, ${CONFIG_DB}..RTULogical T2, abb_mapping T3,' || char(10) ||
  '${CONFIG_DB}..Wiring W1, ${CONFIG_DB}..Wiring W2 where' || char(10) ||
  'T1.ObjectId=W1.ObjectId and W1.AttributeTypeId=8 and W1.WiredObjectId=T2.ObjectId and' || char(10) ||
  'W1.WiredObjectId=W2.ObjectId and W2.AttributeTypeId=8 and W2.WiredObjectId=T3.ObjectId' || char(10) ||
  'go' || char(10)
go
*/
select 'update abb_mapping set U=T1.UnitNumber, A=T1.Address, M=T1.MemberNumber' || char(10) ||
  'from ${CONFIG_DB}..RTU T1, abb_mapping T3,' || char(10) ||
  '${CONFIG_DB}..Wiring W1, ${CONFIG_DB}..Wiring W2 where' || char(10) ||
  'T1.ObjectId=W1.ObjectId and W1.AttributeTypeId=8 and' || char(10) ||
  'W1.WiredObjectId=W2.ObjectId and W2.AttributeTypeId=8 and W2.WiredObjectId=T3.ObjectId' || char(10) ||
  'go' || char(10)
go
select 'update abb_mapping set P=T2.P from abb_mapping T1, ${CONFIG_DB}..PointNum_v T2 where' || 
  'T1.ObjectId=T2.ObjectId' || char(10) || 'go' || char(10)
go
/*
  HARD CODED based on ABB information
*/
select 'update abb_mapping set OBE_IRN=40941211 where ObjectId=83362813' || char(10) || 'go'
select 'update abb_mapping set OBE_IRN=40946211 where ObjectId=83362814' || char(10) || 'go'
select 'update abb_mapping set OBE_IRN=40947211 where ObjectId=83362815' || char(10) || 'go'
go
select 'exit'
go
exit
EOF

# ******************************************************************************
# Create the sql to count the history point lists
# ******************************************************************************
isql ${SYB_CONNECT} -ocount_history_pointlist.sql -b <<EOF
set nocount on
go
select 'set nocount on' || char(10) || 'go'
go
use ${HISTORY_DB}
go
select 'use ${HISTORY_DB}' || char(10) || 'go'
go
select 'select "*** ObjectTypes and AttributeTypes ***"' || char(10) || 'go'
go
select 'select T1.ObjectId/1048576 as ObjectTypeId, substring(T2.Name,1,35) as ObjecTypeName,' || char(10) ||
  'T1.AttributeId, substring(T3.Name,1,35) as AttributeTypeName, count(*) as ' || convert(varchar(40),name) || char(10) ||
  'from ${HISTORY_DB}..' || convert(varchar(40),name) || ' T1,' || char(10) ||
  '${CONFIG_DB}..ObjectType T2, ${CONFIG_DB}..AttributeType T3 where ' || char(10) ||
  'T1.ObjectId/1048576 = T2.ObjectId-1048576 and T1.AttributeId = T3.ObjectId-2097152' || char(10) ||
  'group by T1.ObjectId/1048576,T2.Name,T1.AttributeId,T3.Name' || char(10) ||
  'order by T1.ObjectId/1048576,T1.AttributeId' || char(10) ||
  'go' || char(10) history_sql from ${HISTORY_DB}..sysobjects
  where type='U' and name like 'WG_pointlist%'
  order by name
go
select 'select char(10)' || char(10)|| 'go'
go

select 'select "*** Table Row Counts ***"' || char(10)|| 'go'
go
select 'select '''||convert(varchar(40),name)|| ''',count(ObjectId) from ${HISTORY_DB}..' ||
  convert(varchar(40),name) || char(10) || 'go' ||char(10) history_sql from ${HISTORY_DB}..sysobjects
  where type='U' and name like 'WG_pointlist%'
  order by name
go
select 'select char(10)' || char(10)|| 'go'
go
select 'select "*** Table History AttributeTypeId and AttributeTypeName ***"' || char(10)|| 'go'
go
select 'select distinct '''||convert(varchar(40),name)||''' '|| convert(varchar(40),name) || char(10) ||
  ',T2.AttributeTypeId,substring(T2.AttributeTypeName,1,35) AttributeTypeName ' || char(10) ||
  'from ${CONFIG_DB}..AttributeTypes T2,${HISTORY_DB}..' ||
  convert(varchar(40),name) || ' T1 ' || char(10) ||
  'where T1.AttributeId=T2.AttributeTypeId' || char(10) || 'go'
  ||char(10) history_sql from ${HISTORY_DB}..sysobjects
  where type='U' and name like 'WG_pointlist%'
  order by name
go
select 'exit'
go
exit
EOF

# ******************************************************************************
# Create the sql to count the history edited tables
# ******************************************************************************
isql ${SYB_CONNECT} -ocount_history_edit.sql -b <<EOF
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
# Create the sql view definition file to drop the views for the history datatypes
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
# Create the sql view definition file for the history datatypes
# ******************************************************************************
cat >create_abb_views.sql << EOF
use ${HISTORY_DB}
go

EOF

for DATA_TYPE in ${DATA_TYPES}; do
if [ ${DATA_TYPE} == "float" ]; then
cat >>create_abb_views.sql << EOF
create view ABB_WG_${DATA_TYPE}_v as
/**********************************************************************************
 New SQL for data lists using the abb_map table
select
  str_replace(convert(char(14),T2.OBE_IRN) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || str(Value,30,9) || ";1;0;"," ",NULL) ABB_row
  from WG_float T1,abb_map T2 where T1.ObjectId=T2.ObjectId and T2.OBE_IRN>0 and T1.AttributeId=630
***********************************************************************************/
select
  str_replace(convert(char(14),ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || str(Value,30,9) || ";1;0;"," ",NULL) ABB_row 
	  from WG_${DATA_TYPE}
go

create view ABB_WG_${DATA_TYPE}_all_v as
select
  ObjectId, convert(char(23),Time,140) Time,MicroSeconds,Value,
  str_replace(convert(char(14),ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || str(Value,30,9) || ";1;0;"," ",NULL) ABB_row 
	  from WG_${DATA_TYPE}
go

EOF

else
cat >>create_abb_views.sql << EOF
create view ABB_WG_${DATA_TYPE}_v as
select
  str_replace(convert(char(14),T1.ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || convert(char(20),Value) || ";1;0;"," ",NULL) ABB_row 
	  from WG_${DATA_TYPE} T1,abb_map T2 where T1.ObjectId=T2.ObjectId and T2.OBE_IRN>0
go

create view ABB_WG_${DATA_TYPE}_all_v as
select
  ObjectId, convert(char(23),Time,140) Time,MicroSeconds,Value,
  str_replace(convert(char(14),ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || convert(char(20),Value) || ";1;0;"," ",NULL) ABB_row 
	  from WG_${DATA_TYPE}
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
isql ${SYB_CONNECT} -idrop_abb_views.sql
isql ${SYB_CONNECT} -icreate_abb_views.sql

# ******************************************************************************
# Execute the database counts
# ******************************************************************************
(
        echo "*******************************************************************************"
        echo "*** Started at `date`"
        echo "SQL: count history at `date`"
        #isql -b ${SYB_CONNECT} -icount_history.sql -ocount_history.lst
        echo "SQL: count history edit at `date`"
        isql -b ${SYB_CONNECT} -icount_history_edit.sql -ocount_history_edit.lst
        echo "SQL: count history pointlist at `date`"
        isql -b ${SYB_CONNECT} -icount_history_pointlist.sql -ocount_history_pointlist.lst
        echo "*** Finished at `date`"
        echo "*******************************************************************************"
        echo ""
) >>${LOG}

# ******************************************************************************
# Execute the Bulk Copy the records out of the database
# ******************************************************************************
mknod bcp_pipe_file p
for DATA_TYPE in ${DATA_TYPES}; do
(
        echo "*******************************************************************************"
        echo "*** Stated Extracting ABB_WG_${DATA_TYPE} at `date`"
        export FILENAME="ABB_WG_${DATA_TYPE}_${EXT_TIME}"
        echo "Executing: bcp ${HISTORY_DB}..ABB_WG_${DATA_TYPE}_v out bcp_pipe_file -e ${FILENAME}.err \
                -b 100000 -Usa -P${SA_PASSWD} -c -t \";\""
        # Put the BCP in the backgroup and then start the split command
        bcp ${HISTORY_DB}..ABB_WG_${DATA_TYPE}_v out bcp_pipe_file -e ${FILENAME}.err \
                -b 100000 -Usa -P${SA_PASSWD} -c -t ";" &
        split -l ${BCP_LINES} -a 3 bcp_pipe_file ${FILENAME}-

        # Sleep for 2 seconds to ensure file completion
        sleep 2
        echo "Gzipping ${FILENAME}-* at `date`"
        gzip ${FILENAME}-*
        echo "*** Finished at `date`"
        echo "*******************************************************************************"
) >> ${LOG}
done
rm bcp_pipe_file
