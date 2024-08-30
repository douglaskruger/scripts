#!/bin/bash
# ******************************************************************************
# (c) 2021, 2022 Skynet Consulting Ltd.
#
# File:    wspl_extract_history.sh
# Date:    2 Sept 2022
# Author:  Douglas Kruger
#
# Description:
# This script exports out the history data.
# It creates database views that gets the appropriate data. The view
# is then used by the Sybase bcp (Bulk Copy) utility to dump into a text file
# These text files then are processed further
# ******************************************************************************
# The following was used to determine the sybase date conversion
# COUNTER=0
# while [  $COUNTER -lt 150 ]; do
#    echo "select $COUNTER as FORMAT,convert(CHAR(35),getdate(),$COUNTER) as DATE"
#    echo "go"
#    let COUNTER=COUNTER+1
# done
# ******************************************************************************
# isql useful settings:
#   set rowcount 10
#   set nocount on
#   set statistics io, time on
#   update statistics abb_mapping
# ******************************************************************************
# The data file generated will have four columns and this is separated by the semi-colon
# OBE_IRN    
#    ABB Object IRN nummber    
# SYSTIME     
#    Time in this format yyyymmddhh24missff3    
# VALUE
#    The value of the object in registered time.     
# QST_NO (Quality flag)
#    1 = Normal
#    2 = Invalid
#    4 = Not updated    Not required set to 0. 
# TEST_OPERATION 
#    << do not use as per email 12-Jan-2022 from Nishad MohamedAli from ABB
# ******************************************************************************
# Sample:
#    1412271;20200113084426000;3182.815917969;1;
# ******************************************************************************
# Sorting: sort by the second field - numeric
#     sort -t\; -k 2,2n FILE 
#     grep ";${MIN_DATE}" ${SRC_FILE} | sort -t\; -k 2,2n | uniq > ${FILE_PATH}/${TMP_FILE}
# ******************************************************************************
# Timezone offset - 8 hours
# dateadd(us, MicroSeconds, convert(bigdatetime, dateadd(hour,8,Time))) 
# ******************************************************************************
export SA_PASSWD=scadacom
export BASE_DB=powergas
export INSERT_ABB_ANALOG_MAPPING_FILE="/export/sybase/extract_2022/insert_abb_analog_mapping_20220822.sql"
export INSERT_ABB_DIGITAL_MAPPING_FILE="/export/sybase/extract_2022/insert_abb_digital_mapping_20220829.sql"
export BASE_DATE="2015-09-01"  # in YYYY-MM-DD format used to determine earliest history date
                               # in this case, approximately 7 years ago

# For no offset, use
# export DATE_OFFSET=Time
# For 8 hour offset from GMT to convert to local, use (required by ABB as they use local time)
export DATE_OFFSET="dateadd(hour,8,Time)"

# ******************************************************************************
# Define the script information
# ******************************************************************************
export SCRIPT_NAME=`basename $0`
export SCRIPT_VER=3.0
export SCRIPT_DATE=2-Sept-2022

# ******************************************************************************
# Define the data types of interest in the history database
# ******************************************************************************
export SERVER=`uname -n`
export SYB_SERVER="SYBASE_`uname -n`"
export DSQUERY=SYB_SERVER
export EXT_TIME=`date "+%Y%m%d_%H%M%S"`
export WORK_DIR=${HOME}/extract_history
export SQL_DIR=${WORK_DIR}/sql
export RAW_DIR=${WORK_DIR}/raw_data
export MONTHLY_DIR=${WORK_DIR}/monthly_data
export FINAL_DIR=${WORK_DIR}/final_data
export LOG=${WORK_DIR}/extract_history_${EXT_TIME}.log
export BCP_LINES=40000000       # 40 million lines per original dump file
export BCP_ALARM_LINES=20000000 # 20 million lines per original dump file
export BCP_BUFFER=100000        # BCP Buffer size
export SYB_CONNECT="-Usa -P${SA_PASSWD} -S${SYB_SERVER}"
export SYB_CONNECT_W300="${SYB_CONNECT} -w300"
# as per discussions with ABB on 31-Aug-2022, they only want 'value' (float) and 'state' (choice)
# export DATA_TYPES="boolean choice long short peakfloat peaklong float"
export DATA_TYPES="choice float"
export CONFIG_DB=${BASE_DB}_config
export HISTORY_DB=${BASE_DB}_history
export ALARM_DB=${BASE_DB}_alarm

# ******************************************************************************
# Usage
# ******************************************************************************
usage()
{
    cat << EOF
    
${SCRIPT_NAME} Ver:${SCRIPT_VER} Date:${SCRIPT_DATE}

Usage: `basename $0` [-create_sql] [-create_abb] [-count] [-count_supp] [-bcp_lines {BCP_LINEES}] [-purge] 
       [-extract_alarm] [-extract_s1] [-extract_s2] [-extract_s3]

This script prepares the history database to export the data from the key tables to be used by the
client in the CSV format. Most of the options are used to setup the database with the -extract doing the
sybase BCP action. While this is an efficient model, it still requires significant time to run and
depending on the dataset available, can generate GB of data files. The default is ${BCP_LINES} lines
(rows) per file.

The parameters are:
    -create_sql           Creates the supporting tables and views
    -create_abb           Creates the abb supporting tables and views
    -create_abb_distinct  Creates the abb tables and abb views with distinct clause
                          Option provided - caution may be slow or use too many Sybase resources
    -insert_abb           Inserts test ABB mapping data
    -count                Counts the history table rows - NOTE: This can take significant time.
    -count_supp           Counts the history support tables
    -bcp_lines LINES      Override the number of lines (rows) per file. Default: ${BCP_LINES}
    -purge                Purge files in work directory
    -extract_alarm        Extract the alarm data to CSV text files using Sybase BCP 
    -extract_s1           Extract the data to CSV text files using Sybase BCP 
    -extract_s2           Extract the data to monthly files for efficiency for stage 3
    -extract_s3           Extract daily files from csv files using unix commands

Preparation:
  ./extract_history.sh -create_sql -create_abb -insert_abb 
Stage 1: Extract data from Sybase to Unix Files
  ./extract_history.sh -extract_s1
Stage 2: Gather data into correct months
  ./extract_history.sh -extract_s2
Stage 3: Sort the data chronologically and ensure uniq and restrict to 1 million lines max
  ./extract_history.sh -extract_s3

Alarms: Extract the alarm data from Sybase to Unix Files
  ./extract_history.sh -extract_alarm

EOF
    exit
}

# ******************************************************************************
# Create the header for the data file 
# ******************************************************************************
create_abb_header()
{
    export ABB_TYPE=$1
    cat << EOF
OPTIONS(rows=100000,bindsize=1048576,readsize=1048576)
LOAD DATA
INFILE *
APPEND
INTO TABLE HIS.${ABB_TYPE}
FIELDS TERMINATED BY ';'
("OBE_IRN","SYSTIME" TIMESTAMP "yyyymmddhh24missff3","VALUE","QST_NO")
BEGINDATA
EOF
}

# ******************************************************************************
# Create the footer for the data file
# ******************************************************************************
create_abb_footer()
{
    cat << EOF 
ENDDATA
EOF
}


# ******************************************************************************
# Create the header for the script log
# ******************************************************************************
create_log_header()
{
    cat << EOF > ${LOG}
*******************************************************************************
Executing ${SCRIPT_NAME} Ver:${SCRIPT_VER} Date:${SCRIPT_DATE}
Server ${SERVER} at ${EXT_TIME}
Connecting to Sybase:${SYB_SERVER}
Logging to ${LOG}
DataTypes: ${DATA_TYPES}
ConfigDB: ${CONFIG_DB}
HistoryDB: ${HISTORY_DB}
*******************************************************************************
EOF
}

# ******************************************************************************
# Create the sql files to create the view of Object Attribute
# This is used mainly for debugging and general information
# ******************************************************************************
create_object_attribute_sql()
{
    echo "Creating the Object Attribute SQL and applying it to the database"

    cd ${SQL_DIR}
    
    # Build the SQL
    cat > object_attribute.sql <<EOF
use ${CONFIG_DB}
go
set nocount on
go

/* Find the ObjectAttributes */
drop view ObjectAttributes_v
go

create view ObjectAttributes_v as
select substring(O.ObjectTypeName,1,30) "ObjectTypeName", OA.ObjectTypeId "ObjectTypeId",
  substring(A.AttributeTypeName,1,30) "AttributeTypeName", OA.AttributeTypeId "AttributeTypeId",
  OA.Position,
(case when OA.Scope = 0 then "Config" when OA.Scope = 1 then "Runtime" when OA.Scope = 2 then "Both" end) "Scope"
from ObjectTypes O,AttributeTypes A, ObjectAttributes OA
where O.ObjectTypeId=OA.ObjectTypeId and A.AttributeTypeId=OA.AttributeTypeId
go
exit
EOF

    # Run the SQL
    isql ${SYB_CONNECT_W300} -b -iobject_attribute.sql
    
    # Generate the list of object attributes
    isql ${SYB_CONNECT_W300} -oobject_attribute.lst <<EOF
use ${CONFIG_DB}
go
select * from ObjectAttributes_v
go
exit
EOF
}

# ******************************************************************************
# Create the sql files to build the object view
# This is used mainly for debugging and general information
# ******************************************************************************
create_object_info_sql()
{
    echo "Creating the Object Info SQL and applying it to the database at "`date "+%Y%m%d_%H%M%S"`

    cd ${SQL_DIR}

    # Build the SQL
    isql ${SYB_CONNECT_W300} -b -oobject_info.sql <<EOF
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
select 'select 0,0,"Blank", "Blank" where 1=2' 
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
select 'select 0,0,"Blank", "Blank",0 where 1=2'
go
select char(10) || 'go' || char(10)
go
select 'exit'
go
exit
EOF
    # Run the SQL
    isql ${SYB_CONNECT_W300} -b -iobject_info.sql
    
    # Generate the list of object attributes
    isql ${SYB_CONNECT_W300} -oobject_info.lst <<EOF
use ${CONFIG_DB}
go
select * from ObjectInfo_v order by ObjectId
go
exit
EOF

    # Generate the list of object attributes
    isql ${SYB_CONNECT_W300} -opoint_info.lst <<EOF
use ${CONFIG_DB}
go
select * from PointNum_v order by ObjectId
go
exit
EOF
}

# ******************************************************************************
# Create the sql files to get the vista object definitions
# This is used mainly for debugging and general information
# ******************************************************************************
create_vista_object_sql()
{
    echo "Creating the Vista Object SQL and applying it to the database at "`date "+%Y%m%d_%H%M%S"`

    cd ${SQL_DIR}

    # Build the SQL
    cat > vista_defn.sql <<EOF
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

    # Run the SQL
    isql ${SYB_CONNECT_W300} -b -ivista_defn.sql -ovista_defn.lst
}

# ******************************************************************************
# Create the sql files to count the various history datatype table rows
# This is used mainly for debugging and general information
# ******************************************************************************
create_history_count_sql()
{
    echo "Creating the History SQL at "`date "+%Y%m%d_%H%M%S"` 

    cd ${SQL_DIR}

    # Build the SQL - but do not run it
    isql ${SYB_CONNECT_W300} -ocount_history.sql -b <<EOF
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
}

# ******************************************************************************
# Create the sql to count the history support tables - point and edit lists
# This is used mainly for debugging and general information
# ******************************************************************************
create_history_support_count_sql()
{
    echo "Creating the History Support SQL at "`date "+%Y%m%d_%H%M%S"`
    
    cd ${SQL_DIR}

    # Build the SQL - but do not run it
    isql ${SYB_CONNECT_W300} -ocount_history_support.sql -b <<EOF
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

select 'select "*** Table Row Counts for WG_pointlist_XXX ***"' || char(10)|| 'go'
go
select 'select '''||convert(varchar(40),name)|| ''',count(ObjectId) from ${HISTORY_DB}..' ||
  convert(varchar(40),name) || char(10) || 'go' ||char(10) history_sql from ${HISTORY_DB}..sysobjects
  where type='U' and name like 'WG_pointlist%'
  order by name
go
select 'select char(10)' || char(10)|| 'go'
go

select 'select "*** Table Row Counts for WG_edit_XXX ***"' || char(10)|| 'go'
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
}

# ******************************************************************************
# Create the abb_mapping table
# This is required to map the ABB IRN to the SCADACOM ObjectIds
# ******************************************************************************
create_abb_mapping_sql()
{
    echo "Creating the ABB_Mapping table in the database at "`date "+%Y%m%d_%H%M%S"` 
    
    cd ${SQL_DIR}

    # Build the abb_mapping table 
    isql ${SYB_CONNECT_W300} <<EOF
set nocount on
go

use ${HISTORY_DB}
go

drop table abb_mapping
go

create table abb_mapping (ObjectId int not null, ABB_NM_IRN int not null)
go

create unique clustered index abb_mapping_I on abb_mapping (ObjectId asc, ABB_NM_IRN)
go

exit
EOF
}

# ******************************************************************************
# Populate the abb_mapping table
# This is required to map the ABB IRN to the SCADACOM ObjectIds for testing at WSI
# ******************************************************************************
insert_abb_mapping_sql()
{
    echo "Inserting analog data into the ABB_Mapping table at "`date "+%Y%m%d_%H%M%S"`

    # Load the table with analog mapping
    isql ${SYB_CONNECT_W300} -i ${INSERT_ABB_ANALOG_MAPPING_FILE}

    echo "Inserting digital data into the ABB_Mapping table at "`date "+%Y%m%d_%H%M%S"`

    # Load the table with digital mapping
    isql ${SYB_CONNECT_W300} -i ${INSERT_ABB_DIGITAL_MAPPING_FILE}

    echo "Updating the ABB_Mapping table statistics at "`date "+%Y%m%d_%H%M%S"`
    # Update the table statistics after it was loaded
    isql ${SYB_CONNECT_W300} <<EOF
use ${HISTORY_DB}
go

update statistics abb_mapping
go

exit
EOF
}

# ******************************************************************************
# Populate the abb_mapping table with test data only
# ******************************************************************************
insert_abb_mapping_sql_sample()
{
    echo "Inserting test data into the ABB_Mapping table at "`date "+%Y%m%d_%H%M%S"` 

    # Build the SQL 
    isql ${SYB_CONNECT_W300} <<EOF
set nocount on
go

use ${HISTORY_DB}
go

insert abb_mapping (ABB_NM_IRN,ObjectId) values (42846211,83362446)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42758211,83362306)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42768211,83362307)
go

exit
EOF
}

# ******************************************************************************
# Create the sql view definition file for the history datatypes
# This is a key routine that is used by the Sybase Bulk Copy Program (BCP)
# ******************************************************************************
create_abb_views_sql()
{
    cd ${SQL_DIR}

    # Pass in parameters
    export MIN_DATE=$1
    export MAX_DATE=$2

    # configuration of Time Range (Min_Date or Min+Max Date)
    if [ ${MAX_DATE} == "NOT_USED" ]; then
        export TIME_RANGE="Time >= '${MIN_DATE}'"
    else
        export TIME_RANGE="Time >= '${MIN_DATE}' and Time < '${MAX_DATE}'"
    fi
    echo "Creating the ABB_Mapping views for the Sybase Bulk Copy Program (BCP) at "`date "+%Y%m%d_%H%M%S"`
    
    # Build the SQL - but do not run it
    cat >create_abb_views.sql << EOF
use ${ALARM_DB}
go
drop view ABB_WG_Events_v
go
create view ABB_WG_Events_v as
select str_replace(convert(char(14),T2.ABB_NM_IRN) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),
          dateadd(us, MicroSeconds, convert(bigdatetime, ${DATE_OFFSET})),140),
      ":",NULL),"-",NULL),".",NULL) || ";"," ",NULL) || Text || ";1;" ABB_row
  from Events T1,${HISTORY_DB}..abb_mapping T2 where T1.ObjectId=T2.ObjectId
  and ${TIME_RANGE}
go

use ${HISTORY_DB}
go

EOF

    # **********************************************************************
    # Process each data type and create the appropriate views
    # **********************************************************************
    for DATA_TYPE in ${DATA_TYPES}; do
        # **************************************************************
        # float
        # **************************************************************
        if [ ${DATA_TYPE} == "float" ]; then
            cat >>create_abb_views.sql << EOF
drop view ABB_WG_${DATA_TYPE}_v
go
drop view ABB_WG_${DATA_TYPE}_all_v
go

create view ABB_WG_${DATA_TYPE}_v as
select str_replace(convert(char(14),T2.ABB_NM_IRN) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),
          dateadd(us, MicroSeconds, convert(bigdatetime, ${DATE_OFFSET})),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || str(Value,30,9) || ";1;"," ",NULL) ABB_row
  from WG_float T1,abb_mapping T2 where T1.ObjectId=T2.ObjectId  and T1.AttributeId=630
  and ${TIME_RANGE}
go

create view ABB_WG_${DATA_TYPE}_all_v as
select ObjectId, AttributeId, convert(char(23),Time,140) Time,MicroSeconds,Value,
  str_replace(convert(char(14),ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),
          dateadd(us, MicroSeconds, convert(bigdatetime, ${DATE_OFFSET})),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || str(Value,30,9) || ";1;"," ",NULL) ABB_row 
      from WG_${DATA_TYPE} where ${TIME_RANGE}
go

EOF
        # **************************************************************
                # remaining datatypes
        # **************************************************************
        else
        cat >>create_abb_views.sql << EOF
drop view ABB_WG_${DATA_TYPE}_v
go
drop view ABB_WG_${DATA_TYPE}_all_v
go

create view ABB_WG_${DATA_TYPE}_v as
select str_replace(convert(char(14),T2.ABB_NM_IRN) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),
          dateadd(us, MicroSeconds, convert(bigdatetime, ${DATE_OFFSET})),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || convert(char(20),Value) || ";1;"," ",NULL) ABB_row 
      from WG_${DATA_TYPE} T1,abb_mapping T2 where T1.ObjectId=T2.ObjectId and T1.AttributeId=564
      and ${TIME_RANGE}
go

create view ABB_WG_${DATA_TYPE}_all_v as
select ObjectId, convert(char(23),Time,140) Time,MicroSeconds,Value,
  str_replace(convert(char(14),ObjectId) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),
          dateadd(us, MicroSeconds, convert(bigdatetime, ${DATE_OFFSET})),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || convert(char(20),Value) || ";1;"," ",NULL) ABB_row 
      from WG_${DATA_TYPE} where ${TIME_RANGE}
go

EOF
        fi
    done

    # Add the exit to the file
    cat >>create_abb_views.sql << EOF
exit
EOF

    isql ${SYB_CONNECT_W300} -icreate_abb_views.sql
}

# ******************************************************************************
# Execute the database counts for the history tables
# ******************************************************************************
count_history_tables()
{
    echo "Counting the rows in the history database - this can take a long time!!! at "`date "+%Y%m%d_%H%M%S"`
    
    # Use a subshell to record the output separately
    (
        cd ${SQL_DIR}

        echo "*******************************************************************************"
        echo "*** Started at "`date "+%Y%m%d_%H%M%S"`
        echo "SQL: count history at "`date "+%Y%m%d_%H%M%S"`
        isql -b ${SYB_CONNECT_W300} -icount_history.sql -ocount_history.lst
        echo "*** Finished at "`date "+%Y%m%d_%H%M%S"`
        echo "*******************************************************************************"
        echo ""
    ) >>${LOG}
}

# ******************************************************************************
# Execute the database counts for the history support tables
# ******************************************************************************
count_history_support_tables()
{
    echo "Counting the rows in the history support database at "`date "+%Y%m%d_%H%M%S"`
    
    # Use a subshell to record the output separately
    (
        cd ${SQL_DIR}

        echo "*******************************************************************************"
        echo "*** Started at "`date "+%Y%m%d_%H%M%S"`
        echo "SQL: count history support - edit and pointlist at "`date "+%Y%m%d_%H%M%S"`
        isql ${SYB_CONNECT_W300} -icount_history_support.sql -ocount_history_support.lst
        echo "*** Finished at "`date "+%Y%m%d_%H%M%S"`
        echo "*******************************************************************************"
        echo ""
    ) >>${LOG}
}

# ******************************************************************************
# Execute the Bulk Copy the alarm records out of the database
# ******************************************************************************
extract_alarm()
{
    export FILENAME=${RAW_DIR}/ABB_WG_events_${EXT_TIME}

    # Create a special pipe file
    /bin/rm -f bcp_alarm_pipe_file
    mknod bcp_alarm_pipe_file p

    echo "*******************************************************************************"
    echo "*** Started Extracting ABB_WG_${DATA_TYPE} for MIN_DATE:${MIN_DATE} at "`date "+%Y%m%d_%H%M%S"`
    echo "Executing: bcp ${ALARM_DB}..ABB_WG_Events_v out bcp_alarm_pipe_file -e ${FILENAME}.err \
            -b ${BCP_BUFFER} ${SYB_CONNECT} -c -t \";\""
    echo "*******************************************************************************"
    # Put the BCP in the backgroup and then start the split command
    bcp ${ALARM_DB}..ABB_WG_Events_v out bcp_alarm_pipe_file -e ${FILENAME}.err \
            -b ${BCP_BUFFER} ${SYB_CONNECT} -c -t ";" &
    split -l ${BCP_ALARM_LINES} -a 3 bcp_alarm_pipe_file ${FILENAME}-

    # Sleep for 2 seconds to ensure file completion
    sleep 2

    echo "*******************************************************************************"
    echo "*** Finished Extracting ABB_WG_Events at "`date "+%Y%m%d_%H%M%S"`
    echo "*******************************************************************************"

    # Clean up
    /bin/rm -f bcp_alarm_pipe_file
}

# ******************************************************************************
# Execute the Bulk Copy the records out of the database
# ******************************************************************************
bcp_file()
{
    export FILENAME=${RAW_DIR}/$1
    export DATA_TYPE=$2

    cd ${RAW_DIR}

    # Create a special pipe file
    /bin/rm -f bcp_pipe_file
    mknod bcp_pipe_file p

    echo "*******************************************************************************"
    echo "*** Started Extracting ABB_WG_${DATA_TYPE} for MIN_DATE:${MIN_DATE} at "`date "+%Y%m%d_%H%M%S"`
    echo "Executing: bcp ${HISTORY_DB}..ABB_WG_${DATA_TYPE}_v out bcp_pipe_file -e ${FILENAME}.err \
            -b ${BCP_BUFFER} ${SYB_CONNECT} -c -t \";\""
    echo "*******************************************************************************"
    # Put the BCP in the backgroup and then start the split command
    bcp ${HISTORY_DB}..ABB_WG_${DATA_TYPE}_v out bcp_pipe_file -e ${FILENAME}.err \
            -b ${BCP_BUFFER} ${SYB_CONNECT} -c -t ";" &
    split -l ${BCP_LINES} -a 3 bcp_pipe_file ${FILENAME}-

    # Sleep for 2 seconds to ensure file completion
    sleep 2

    echo "*******************************************************************************"
    echo "*** Finished Extracting ABB_WG_${DATA_TYPE} at "`date "+%Y%m%d_%H%M%S"`
    echo "*******************************************************************************"

    # Clean up
    /bin/rm -f bcp_pipe_file
}

# ******************************************************************************
# Stage 1: Execute the Bulk Copy the records out of the database
# ******************************************************************************
extract_history()
{
    echo "Extracting the history data using Sybase BCP at "`date "+%Y%m%d_%H%M%S"`

    for DATA_TYPE in ${DATA_TYPES}; do
    (
        export FILENAME="ABB_WG_${DATA_TYPE}_${EXT_TIME}"
        bcp_file ${FILENAME} ${DATA_TYPE}
    ) >> ${LOG}
    done
    echo "Finished Extracting the history data using Sybase BCP"
}

# ******************************************************************************
# Stage 2: Slice the extract files
# ******************************************************************************
extract_monthly_files()
{
    /bin/rm -rf ${MONTHLY_DIR}
    mkdir -p ${MONTHLY_DIR}

    cd ${RAW_DIR}
    for filename in `ls ABB_WG_choice* 2>/dev/null`;
    do
        echo "Processing file: "`pwd`"/${filename} at "`date "+%Y%m%d_%H%M%S"`
        gunzip ${filename} 2>/dev/null
        cat ${filename} | ${HOME}/extract_2022/split_file wg_choice ${MONTHLY_DIR}
        gzip ${filename} &
    done
    for filename in `ls ABB_WG_float* 2>/dev/null`;
    do
        echo "Processing file: "`pwd`"/${filename} at "`date "+%Y%m%d_%H%M%S"`
        gunzip ${filename} 2>/dev/null
        cat ${filename} | ${HOME}/extract_2022/split_file wg_float ${MONTHLY_DIR}
        #gzip ${filename} &
    done
}

# ******************************************************************************
# Stage 3: Slice the monthly extract files
# ******************************************************************************
extract_history_files()
{
    echo "Extracting the history data at "`date "+%Y%m%d_%H%M%S"`
    for DATA_TYPE in ${DATA_TYPES}
    do
        export SRC_FILE=${RAW_DIR}/ABB_WG_${DATA_TYPE}*
        case ${DATA_TYPE} in
            float|peakfloat|peaklong|long|short)    export ABB_TYPE=LMEATWOMINUTE;;
            choice|boolean)                         export ABB_TYPE=LINDONESECOND;;
            *)                                      export ABB_TYPE=LMEATWOMINUTE;;
        esac

        mkdir -p ${FINAL_DIR}/${DATA_TYPE}
        for year in {2015..2022}
        do
            export FILE_PATH="${year}"
            mkdir -p ${FINAL_DIR}/${DATA_TYPE}/${FILE_PATH}
        done

        cd ${MONTHLY_DIR}
        for filename in `ls *${DATA_TYPE}* 2>/dev/null`;
        do
            echo "Process file:"`pwd`"/${filename} at "`date "+%Y%m%d_%H%M%S"`
            cat ${filename}|sort -t\; -k 2,2n |uniq | split -l 1000000

            for FILENAME2 in `ls x* 2>/dev/null`;
            do
                export YEAR=`head -1 ${FILENAME2} | awk -F\; '{print $2}'|cut -b 1-4`
                export MIN_DATE=`head -1 ${FILENAME2} | awk -F\; '{print $2}'|cut -b 1-8`
                export MIN_TIME=`head -1 ${FILENAME2} | awk -F\; '{print $2}'|cut -b 9-14`
                export MAX_DATE=`tail -1 ${FILENAME2} | awk -F\; '{print $2}'|cut -b 1-8`
                export MAX_TIME=`tail -1 ${FILENAME2} | awk -F\; '{print $2}'|cut -b 9-14`
                export TMP_PATH="${FINAL_DIR}/${DATA_TYPE}/${YEAR}"
                export TMP_FILE="${TMP_PATH}/${ABB_TYPE}_${MIN_DATE}_${MIN_TIME}_${MAX_DATE}_${MAX_TIME}.ldr"
                export META_FILE="${TMP_PATH}/meta_data.txt"

                echo "create_abb_header > ${TMP_FILE}"
                create_abb_header ${ABB_TYPE} > ${TMP_FILE}

                cat ${FILENAME2} >> ${TMP_FILE}

                echo "create_abb_footer >> ${TMP_FILE}"
                create_abb_footer >> ${TMP_FILE}

                echo "${TMP_FILE}" >> ${META_FILE}
                ls -l ${TMP_FILE} >> ${META_FILE}
                wc -l ${FILENAME2} >> ${META_FILE}

                echo "gzip ${TMP_FILE}"
                gzip ${TMP_FILE} &
            done
            # Remove the temporary files from split
            /bin/rm -f x*
            echo ""
        done
    done
}

# ******************************************************************************
# Main Program
# ******************************************************************************

# ---  Print usage and exit if there are no parameters set
if [ $# -eq 0 ]; then usage; fi

export CREATE_SQL=0
export CREATE_ABB_IN_DB=0
export INSERT_ABB_IN_DB=0
export COUNT_HISTORY=0
export COUNT_HISTORY_SUPPORT=0
export EXTRACT_HISTORY=0
export EXTRACT_ALARM=0
export PURGE=0
export EXTRACT_FILES=0
export EXTRACT_MTH_FILES=0

# ---  Process the command line
while [ $# -gt 0 ];do
    case $1 in
        -create_sql)           export CREATE_SQL=1;;
        -create_abb)           export CREATE_ABB_IN_DB=1;;
        -insert_abb)           export INSERT_ABB_IN_DB=1;;
        -count)                export COUNT_HISTORY=1;;
        -count_supp)           export COUNT_HISTORY_SUPPORT=1;;
        -bcp_lines)            shift; export BCP_LINES=$1;;
        -purge)                export PURGE=1;;
        -extract_s1)           export EXTRACT_HISTORY=1;;
        -extract_alarm)        export EXTRACT_ALARM=1;;
        -extract_s2)           export EXTRACT_MTH_FILES=1;;
        -extract_s3)           export EXTRACT_FILES=1;;
        *)                     usage;;
    esac
    shift
done

echo "Started at "`date "+%Y%m%d_%H%M%S"`

# ---  Set the default action
# Purge the work directory - if selected
if [ ${PURGE} -eq 1 ]; then
    echo "Purging the work directory: ${WORK_DIR}"
    /bin/rm -rf ${WORK_DIR}
fi

# Make the work directory and supporting directories
mkdir -p ${WORK_DIR}
mkdir -p ${RAW_DIR}
mkdir -p ${SQL_DIR}
mkdir -p ${FINAL_DIR}
cd $WORK_DIR

# Create the log header
create_log_header

# Create the various database views - but do not executed them
if [ ${CREATE_SQL} -eq 1 ]; then
    create_object_attribute_sql
    create_object_info_sql
    create_vista_object_sql
    create_history_count_sql
    create_history_support_count_sql
    create_abb_views_sql ${BASE_DATE} NOT_USED
fi

# Create the ABB mapping of the IRN to SCADACOM ObjectId mapping
if [ ${CREATE_ABB_IN_DB} -eq 1 ]; then
    create_abb_mapping_sql
fi

# Create the ABB mapping of the IRN to SCADACOM ObjectId mapping
if [ ${INSERT_ABB_IN_DB} -eq 1 ]; then
    insert_abb_mapping_sql
fi

# Optional - count history table rows - this can take a while
if [ ${COUNT_HISTORY} -eq 1 ]; then
    count_history_tables
fi

# Optional - count history support table rows - this can take a while
if [ ${COUNT_HISTORY_SUPPORT} -eq 1 ]; then
    count_history_support_tables
fi

# Extract the alarms from Sybase
if [ ${EXTRACT_ALARM} -eq 1 ]; then
    extract_alarm
fi

# Extract the history from Sybase
if [ ${EXTRACT_HISTORY} -eq 1 ]; then
    extract_history
fi

# Stage 2 - extract monthly files from Sybase export files
if [ ${EXTRACT_MTH_FILES} -eq 1 ]; then
    extract_monthly_files
fi

# Extract files individual ABB files from the monthly files
if [ ${EXTRACT_FILES} -eq 1 ]; then
    extract_history_files
fi

echo "Finished at "`date "+%Y%m%d_%H%M%S"`
