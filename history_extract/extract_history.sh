#!/bin/bash
# ******************************************************************************
# (c) 2021 Skynet Consulting Ltd.
#
# File:    wspl_extract_history.sh
# Date:    6 Aug 2021
# Author:  Douglas Kruger
# Version: 1.6
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
export BASE_DB=SET_BASE_DB

# ******************************************************************************
# Define the data types of interest in the history database
# ******************************************************************************
export SYB_SERVER="SYBASE_`uname -n`"
export EXT_TIME=`date "+%Y%m%d_%H%M%S"`
export LOG=extract_history_${EXT_TIME}.log
export WORK_DIR=$HOME/extract_history
export BCP_LINES=10000000
export SYB_CONNECT="-Usa -P${SA_PASSWD} -w300 -S${SYB_SERVER}"
export DATA_TYPES="float boolean choice long short peakfloat peaklong"
export CONFIG_DB=${BASE_DB}_config
export HISTORY_DB=${BASE_DB}_history

# ******************************************************************************
# Create the sql files to create the view of Object Attribute
# ******************************************************************************
create_object_attribute_sql()
{
	echo "Creating the Object Attribute SQL and applying it to the database"
	
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
	isql ${SYB_CONNECT} -b -iobject_attribute.sql
	
	# Generate the list of object attributes
	isql ${SYB_CONNECT} -oobject_attribute.lst <<EOF
use ${CONFIG_DB}
go
select * from ObjectAttributes_v
go
exit
EOF
}

# ******************************************************************************
# Create the sql files to build the object view
# ******************************************************************************
create_object_info_sql()
{
	echo "Creating the Object Info SQL and applying it to the database"

	# Build the SQL
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
	isql ${SYB_CONNECT} -b -iobject_info.sql
	
	# Generate the list of object attributes
	isql ${SYB_CONNECT} -oobject_info.lst <<EOF
use ${CONFIG_DB}
go
select * from ObjectInfo_v order by ObjectId
go
exit
EOF

	# Generate the list of object attributes
	isql ${SYB_CONNECT} -opoint_info.lst <<EOF
use ${CONFIG_DB}
go
select * from PointNum_v order by ObjectId
go
exit
EOF
}

# ******************************************************************************
# Create the sql files to get the vista object definitions
# ******************************************************************************
create_vista_object_sql()
{
	echo "Creating the Vista Object SQL and applying it to the database"

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
	isql ${SYB_CONNECT} -b -ivista_defn.sql -ovista_defn.lst
}

# ******************************************************************************
# Create the sql files to count the various history datatype table rows
# ******************************************************************************
create_history_count_sql()
{
	echo "Creating the History SQL"

	# Build the SQL - but do not run it
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
}

# ******************************************************************************
# Create the sql to count the history support tables - point and edit lists
# ******************************************************************************
create_history_support_count_sql()
{
	echo "Creating the History Support SQL"
	
	# Build the SQL - but do not run it
	isql ${SYB_CONNECT} -ocount_history_support.sql -b <<EOF
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
# ******************************************************************************
create_abb_mapping_sql()
{
	echo "Creating the ABB_Mapping table and populating the table in the database"
	
	# Build the SQL - but do not run it
	isql ${SYB_CONNECT} <<EOF
set nocount on
go

use ${HISTORY_DB}
go

drop table abb_mapping
go

select 0 as "ABB_NM_IRN",0 as "ObjectId" into abb_mapping
go

create unique clustered index abb_mapping_I on abb_mapping (ObjectId asc)
go

insert abb_mapping (ABB_NM_IRN,ObjectId) values (42846211,83362446)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42758211,83362306)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42768211,83362307)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42767211,83362308)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42845211,83362444)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42769211,83362309)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40323211,83362339)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40804211,83362340)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40803211,83362456)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40805211,83362344)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40665211,83362317)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40663211,83362316)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40458211,83362314)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40664211,83362315)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40698211,83362247)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40697211,83362246)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40351211,83362245)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41112211,83362249)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41113211,83362250)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41107211,83362248)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42103211,83362231)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42104211,83362232)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42135211,83362453)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42098211,83362230)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42478211,83362463)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42476211,83362234)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42460211,83362233)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42532211,83362464)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42475211,83362235)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42477211,83362462)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42014211,83361806)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42009211,83361805)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42015211,83361807)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41909211,83362302)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41942211,83362450)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41903211,83362300)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41908211,83362301)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42853211,83362218)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42862211,83362220)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42864211,83362448)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42863211,83362219)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42905211,83362449)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42550211,83362430)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42663211,83362223)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42553211,83362442)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42535211,83362221)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42551211,83362222)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42552211,83362443)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42664211,83362434)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41041211,83362224)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41047211,83362226)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41046211,83362225)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42293211,83362229)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42277211,83362227)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42292211,83362228)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31813211,83361966)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31806211,83361965)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31814211,82837702)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31798211,83361967)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31815211,82837706)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31826211,83361968)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31816211,82837705)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42075211,83361846)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42076211,83361847)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42078211,83361843)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41062211,83361852)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41068211,83361854)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41067211,83361853)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42221211,83362254)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42226211,83362255)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42227211,83362256)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41989211,83362258)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41984211,83362257)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41990211,83362259)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31649211,83362252)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (30986211,83362486)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31642211,83362346)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31629211,82837644)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31628211,82837645)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31630211,83362487)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (31631211,82837646)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36665211,83362265)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36598211,83362253)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36607211,82837670)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36609211,82837669)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36610211,82837668)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36617211,83362261)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36625211,83362262)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36668211,82837666)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36667211,83362348)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36666211,83362351)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (36608211,83362260)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (99809211,83362264)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (99800211,83362263)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (99808211,83362437)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (99722211,83362458)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (99717211,83362438)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (99691211,83362489)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (99709211,83362488)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42685211,83362319)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42669211,83362318)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42684211,83362320)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108396211,171444392)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108397211,171444393)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108398211,171444394)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108173211,171442574)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108174211,171442575)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108193211,171442594)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108395211,171444391)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108401211,171444397)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108402211,171444398)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108403211,171444399)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108243211,171442589)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108383211,171444386)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108359211,171444372)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108360211,171444373)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108361211,171444374)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108250211,171442590)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108270211,171444351)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108354211,171444367)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108355211,171444368)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108356211,171444369)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108394211,171444390)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108272211,171444352)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108340211,171444353)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108341211,171444354)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136740211,163053973)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108235211,171442582)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108236211,171442583)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108343211,171444356)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108344211,171444357)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108345211,171444358)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108348211,171444361)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108349211,171444362)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108238211,171442585)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108240211,171442586)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108346211,171444359)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108367211,171444376)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108368211,171444377)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108369211,171444378)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108350211,171444363)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108351211,171444364)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108382211,171444385)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85691211,83362267)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85378211,83362739)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85690211,83362740)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85590211,83362467)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85372211,83362640)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85696211,83362461)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85692211,83362745)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85693211,83362268)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85694211,83362746)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85695211,83362747)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85538211,83362466)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85434211,83362738)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85553211,83362469)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85582211,83362468)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108194211,171442595)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108358211,171444371)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108357211,171444370)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108362211,171444375)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108377211,171444382)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108264211,171442592)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108266211,171442593)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108267211,171444349)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108353211,171444366)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108231211,171442578)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108342211,171444355)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108241211,171442587)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108380211,171444383)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108347211,171444360)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108242211,171442588)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108381211,171444384)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108352211,171444365)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108376211,171444379)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108233211,171442580)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108234211,171442581)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108195211,171442596)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108196211,171442576)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108230211,171442577)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108237211,171442584)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108378211,171444380)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108379211,171444381)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108400211,171444396)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108251211,171442591)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108269211,171444350)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108384211,171444387)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108385211,171444388)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108389211,171444389)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108399211,171444395)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42053211,83362304)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42058211,83362322)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42059211,83362323)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85972211,83362474)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85969211,83362327)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86150211,83362481)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86190211,83362482)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108661211,171442679)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108518211,171442656)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108462211,171442649)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108463211,171442621)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108464211,171442666)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108608211,171442644)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108677211,171442631)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108523211,171442635)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108522211,171442624)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108596211,171442642)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108606211,171442678)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108607211,171442661)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108461211,171442654)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108525211,171442669)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108659211,171442662)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108660211,171442696)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85970211,83362470)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86191211,83362483)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85913211,83362476)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85968211,83362326)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86137211,83362480)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85882211,83362514)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85900211,83362477)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86189211,83362472)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85971211,83362473)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86095211,83362479)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86187211,83362475)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86192211,83362484)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86188211,83362471)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (86082211,83362478)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (85967211,83362328)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108593211,171442676)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108594211,171442659)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108595211,171442660)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108526211,171442703)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108517211,171442639)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108598211,171442643)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108605211,171442627)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108473211,171442689)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108474211,171442672)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108475211,171442650)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108534211,171442625)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108580211,171442641)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108467211,171442638)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108468211,171442683)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108662211,171442646)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108460211,171442632)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108471211,171442684)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108679211,171442665)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108678211,171442682)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108477211,171442688)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108478211,171442673)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108479211,171442701)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108465211,171442671)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108519211,171442653)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108520211,171442692)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108521211,171442623)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108469211,171442667)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108470211,171442633)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108466211,171442622)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108592211,171442626)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108666211,171442698)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108673211,171442664)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108669211,171442680)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108597211,171442693)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108458211,171442620)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108459211,171442637)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108670211,171442697)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108658211,171442645)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108667211,171442647)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108668211,171442699)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108527211,171442640)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108671211,171442681)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108680211,171442648)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108609211,171442695)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108652211,171442663)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108653211,171442629)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108533211,171442686)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108528211,171442658)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108532211,171442691)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108476211,171442655)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108529211,171442674)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108530211,171442652)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108531211,171442675)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108472211,171442700)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108524211,171442657)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (108581211,171442636)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (131860211,171442628)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (131769211,171442630)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136127211,171442694)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136128211,171442704)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136130211,171442634)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136131211,171442651)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136132211,171442668)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136133211,171442685)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136134211,171442702)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136124211,171442670)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136125211,171442677)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136741211,171442690)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (136126211,171442687)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (57502211,83362329)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (57499211,83362330)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40555211,83362269)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40850211,83362270)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40849211,83362251)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40848211,83362271)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40851211,83362436)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41865211,83362274)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41868211,83362272)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41864211,83362273)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41901211,83362435)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41083211,83362275)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41089211,83362277)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41088211,83362276)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41002211,83362278)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41008211,83362280)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41020211,83362567)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41007211,83362279)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41949211,83362282)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41944211,83362281)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (41950211,83362283)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40908211,83362285)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40398211,83362284)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (40907211,83362286)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42032211,83362290)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42038211,83362292)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (42037211,83362291)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (56862211,83362146)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (56864211,83362143)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (56863211,83362145)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (56861211,83362144)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (56805211,83362157)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (56806211,83362155)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (56803211,83362156)
insert abb_mapping (ABB_NM_IRN,ObjectId) values (56804211,83362158)
go

exit
EOF
}

# ******************************************************************************
# Create the abb_mapping table
# ******************************************************************************
create_abb_mapping_sql-old()
{
	# Build the SQL - but do not run it
	isql ${SYB_CONNECT} -ocreate_abb_mapping.sql -b <<EOF
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
select 'select ObjectId,0 as ABB_NM_IRN, ObjectId/1048576 as OType, AttributeId as AType, ' || char(10) ||
  '0 as A,0 as U, 0 as T, 0 as M, 0 as G, 0 as S, 0 as P into abb_mapping ' || char(10) ||
  'from WG_pointlist_float where 1=2' || char(10) || 'go'
go
select 'insert abb_mapping select ObjectId, 0 as ABB_NM_IRN, ObjectId/1048576 as OType, AttributeId as AType,' || char(10) ||
  '0 as A,0 as U, 0 as T, 0 as M, 0 as G, 0 as S, 0 as P from ${HISTORY_DB}..' || convert(varchar(40),name) || char(10) ||
  'go' || char(10) history_sql from sysobjects
  where type='U' and name like 'WG_pointlist%'
go
select 'update abb_mapping set T=T1.T, G=T1.G, S=T1.S' || char(10) ||
  'from ${CONFIG_DB}..vista_defn_v T1, abb_mapping T2' || char(10) ||
  'where T1.OType=T2.OType and T1.AType=T2.AType' || char(10) ||
  'go' || char(10)
go
select 'update abb_mapping set U=T1.UnitNumber, A=T1.Address, M=T1.MemberNumber' || char(10) ||
  'from ${CONFIG_DB}..RTU T1, abb_mapping T3,' || char(10) ||
  '${CONFIG_DB}..Wiring W1, ${CONFIG_DB}..Wiring W2 where' || char(10) ||
  'T1.ObjectId=W1.ObjectId and W1.AttributeTypeId=8 and' || char(10) ||
  'W1.WiredObjectId=W2.ObjectId and W2.AttributeTypeId=8 and W2.WiredObjectId=T3.ObjectId' || char(10) ||
  'go' || char(10)
go
select 'update abb_mapping set P=T2.P from abb_mapping T1, ${CONFIG_DB}..PointNum_v T2 where ' || 
  'T1.ObjectId=T2.ObjectId' || char(10) || 'go' || char(10)
go
/*
  HARD CODED based on ABB information
*/
select 'update abb_mapping set ABB_NM_IRN=40941211 where ObjectId=83362813' || char(10) || 'go'
select 'update abb_mapping set ABB_NM_IRN=40946211 where ObjectId=83362814' || char(10) || 'go'
select 'update abb_mapping set ABB_NM_IRN=40947211 where ObjectId=83362815' || char(10) || 'go'
go
select 'exit'
go
exit
EOF

	isql ${SYB_CONNECT} -icreate_abb_mapping.sql
}

# ******************************************************************************
# Create the sql view definition file for the history datatypes
# ******************************************************************************
create_abb_views_sql()
{
	echo "Creating the ABB_Mapping views for the BCP"
	
	# Build the SQL - but do not run it
	cat >create_abb_views.sql << EOF
use ${HISTORY_DB}
go

EOF

	for DATA_TYPE in ${DATA_TYPES}; do
		cat >>create_abb_views.sql << EOF
drop view ABB_WG_${DATA_TYPE}_v
go
drop view ABB_WG_${DATA_TYPE}_all_v
go
EOF
	done	

	for DATA_TYPE in ${DATA_TYPES}; do
		if [ ${DATA_TYPE} == "float" ]; then
			cat >>create_abb_views.sql << EOF
create view ABB_WG_${DATA_TYPE}_v as
select
  str_replace(convert(char(14),T2.ABB_NM_IRN) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || str(Value,30,9) || ";1;0;"," ",NULL) ABB_row
  from WG_float T1,abb_mapping T2 where T1.ObjectId=T2.ObjectId and T2.ABB_NM_IRN>0 and T1.AttributeId=630
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
  str_replace(convert(char(14),T2.ABB_NM_IRN) || ";" ||
    str_replace(str_replace(str_replace(convert(CHAR(23),dateadd(us, MicroSeconds, convert(bigdatetime, Time)),140),
      ":",NULL),"-",NULL),".",NULL) || ";" || convert(char(20),Value) || ";1;0;"," ",NULL) ABB_row 
	  from WG_${DATA_TYPE} T1,abb_mapping T2 where T1.ObjectId=T2.ObjectId and T2.ABB_NM_IRN>0
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

	isql ${SYB_CONNECT} -icreate_abb_views.sql
}

# ******************************************************************************
# Execute the database counts for the history tables
# ******************************************************************************
count_history_tables()
{
	echo "Counting the rows in the history database - this can take a long time!!!"
	
	# Use a subshell to record the output separately
	(
			echo "*******************************************************************************"
			echo "*** Started at `date`"
			echo "SQL: count history at `date`"
			isql -b ${SYB_CONNECT} -icount_history.sql -ocount_history.lst
			echo "*** Finished at `date`"
			echo "*******************************************************************************"
			echo ""
	) >>${LOG}
}

# ******************************************************************************
# Execute the database counts for the history support tables
# ******************************************************************************
count_history_support_tables()
{
	echo "Counting the rows in the history support database"
	
	# Use a subshell to record the output separately
	(
			echo "*******************************************************************************"
			echo "*** Started at `date`"
			echo "SQL: count history support - edit and pointlist at `date`"
			isql ${SYB_CONNECT} -icount_history_support.sql -ocount_history_support.lst
			echo "*** Finished at `date`"
			echo "*******************************************************************************"
			echo ""
	) >>${LOG}
}

# ******************************************************************************
# Execute the Bulk Copy the records out of the database
# ******************************************************************************
extract_history()
{
	echo "Extracting the history data using Sybase BCP"
	
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
	echo "Finished Extracting the history data using Sybase BCP"
}

# ******************************************************************************
# Usage
# ******************************************************************************
usage()
{
	cat << EOF
	
Usage: `basename $0` [-create_sql] [-create_abb] [-count] [-count_supp] [-extract] [-bcp_lines 200000] [-purge]

This script prepares the history database to export the data from the key tables to be used by the
client in the CSV format. Most of the options are used to setup the database with the -extract doing the
sybase BCP action. While this is an efficient model, it still requires significant time to run and
depending on the dataset available, can generate GB of data files. The default is ${BCP_LINES} rows per file.

	-create_sql		Creates the supporting tables and views
	-create_abb		Creates the abb supporting tables and views
	-count			Counts the history table rows - NOTE: This can take significan time.
	-count_supp		Counts the history support tables
	-extract		Extract the data to CSV text files using Sybase BCP
	-bcp_rows ROWS	Override the number of rows per file. Default: ${BCP_LINES}
	-purge			Purge files in WORK_HISTORY
	
EOF
	exit
}
	
# ******************************************************************************
# Main Program
# ******************************************************************************

# ---  Print usage and exit if there are no parameters set
if [ $# -eq 0 ]; then usage; fi

# ---  Set the default action
export CREATE_SQL=0
export CREATE_ABB_IN_DB=0
export COUNT_HISTORY=0
export COUNT_HISTORY_SUPPORT=0
export EXTRACT_HISTORY=0
export PURGE=0

# ---  Process the command line
while [ $# -gt 0 ];do
    case $1 in
		-create_sql)	export CREATE_SQL=1;;
		-create_abb)	export CREATE_ABB_IN_DB=1;;
		-count)			export COUNT_HISTORY=1;;
		-count_supp)	export COUNT_HISTORY_SUPPORT=1;;
		-extract)		export EXTRACT_HISTORY=1;;
		-bcp_lines)		shift; export BCP_LINES=$1;;
		-purge)			export PURGE=1;;
		*)				usage;;
	esac
	shift
done

# Make the working subdir
mkdir -p $WORK_DIR
cd $WORK_DIR

if [ ${PURGE} -eq 1 ]; then
	echo "Purging the work directory: ${WORK_DIR}"
	/bin/rm -f ${WORK_DIR}/*
fi

if [ ${CREATE_SQL} -eq 1 ]; then
	create_object_attribute_sql
	create_object_info_sql
	create_vista_object_sql
	create_history_count_sql
	create_history_support_count_sql

fi

if [ ${CREATE_ABB_IN_DB} -eq 1 ]; then
	create_abb_mapping_sql
	create_abb_views_sql
fi

if [ ${COUNT_HISTORY} -eq 1 ]; then
	count_history_tables
fi

if [ ${COUNT_HISTORY_SUPPORT} -eq 1 ]; then
	count_history_support_tables
fi

if [ ${EXTRACT_HISTORY} -eq 1 ]; then
	extract_history
fi
