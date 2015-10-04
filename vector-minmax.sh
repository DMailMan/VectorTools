#!/bin/bash
# Copyright 2015 Actian Corporation
 
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
 
#      http://www.apache.org/licenses/LICENSE-2.0
 
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# This script is designed to report information about the Vector (or Vector-H) Mix Max indexes.
# These indexes indicate the order in which data is stored on disk, and are important to query
# performance.


# Check we have all the necessary parameters
# Now have optional 5th parameer 
if [ $# -lt 4 ]
then
	echo 'Usage: $0 databasename table-owner table-name column-name [partition number]'
	exit 1
fi

DBNAME=${1}
TOWNER=${2}
TNAME=${3}
CNAME=${4}
PTN=${5}

# Provide some defaults. Change these if you want to increase convenience.
if [ "${DBNAME}" = "" ]
then
	DBNAME="risk"
fi

if [ "${TOWNER}" = "" ]
then
	TOWNER="actian"
fi

if [ "${TNAME}" = "" ]
then
	TNAME="fact_risk"
fi

if [ "${CNAME}" = "" ]
then
	CNAME="cobid"
fi

# Default the partiton to all partitions (for both partitioned and non partitioned tables) or add the "@" character if a partition is specified
# Tidy test for partitioning and forming the x100 name
if [ "${PTN}" = "" ]
then
	PTN="%"
fi

# Move getting the DDL higher up so that we can test if table is partitioned.
# Get the datatype for the column, so we can store the values later in the temp table
# Dumps the table schema to a file in /tmp then grabs the column datatype from that
copydb -u${TOWNER} ${DBNAME} ${TNAME} >copydb.log 2>&1
ERRORS=$(grep E_ copydb.log)
if [ "${ERRORS}" != "" ]
then
	echo "Problems accessing database ${DBNAME} and table ${TNAME} owned by ${TOWNER} - please check details and permissions."
	exit 1
fi

# Provide a default if the above didn't work for some reason

# Add a space to differentiate beween say col1 and col10
# Treat timestamps and dates as integers
CTYPE=$(grep "${CNAME} " copy.in |cut -d' ' -f2|head -1)
CTYPETRUNC=$(echo "${CTYPE}" | cut -d "(" -f1 )

if [ "${CTYPETRUNC}" = "" ] || [ "${CTYPETRUNC}" = "ansidate" ] || [ "${CTYPETRUNC}" = "timestamp" ]
then
	CTYPE="integer8"
fi

#echo ${CTYPE}
#exit

rm copy.out copy.in copydb.log

# Check if table is partitioned
if [ -z "`grep 'partition = (HASH' copy.in`" ]
then
	# Not Partitioned
	MATCHFUNC="=="
	TNAMEX100="_${TOWNER}S${TNAME}"
else
	# Partitioned
	MATCHFUNC="like"
	TNAMEX100="_${TOWNER}S${TNAME}@${PTN}"
fi

# Include the partition spec in the x100 table name
CNAMEX100="_${CNAME}"
DATAFILE="/tmp/${0}.dat"
DATATABLE="minmax_deleteme"
# LHS R4 - TWO NEW TABLES
DATATABLE2="minmax2_deleteme"
DATATABLE3="minmax3_deleteme"

#  Include partition spec
echo "Database: ${DBNAME}, Owner: ${TOWNER}, Table/Partition: ${TNAME}/${PTN} [ ${TNAMEX100} ], Column: ${CNAME} [ ${CNAMEX100} Datatype: ${CTYPE} ]"

if [ -d "$II_SYSTEM/ingres/data/vectorwise/$DBNAME/CBM" ]
then
	# Vector
	LOCKDIR="$II_SYSTEM/ingres/data/vectorwise/$DBNAME/CBM"
else
	# Vector-H
	LOCKDIR="$II_SYSTEM/ingres/data/vectorwise/$DBNAME"
fi

# For Vector
x100_client --port `cat ${LOCKDIR}/lock | head -1` --passfile $II_SYSTEM/ingres/data/vectorwise/$DBNAME/authpass -o raw << EOF > ${DATAFILE}

# Join to the minax table (restict to 1 column)
HashJoin01 (
	 SysScan('minmax', [ 'table_name', 'column_nr', 'minmax_row', 'minmax_minval', 'minmax_maxval' ] )
		,[ table_name, column_nr ] [ minmax_row, minmax_minval, minmax_maxval ]
	,HashJoin01 (
		 Select(
			 SysScan('columns', ['column_name', 'table_id', 'column_offset'])
			,==(column_name, '${CNAMEX100}')
		 )
		 	, [ table_id ] [ column_name, column_offset ]
		,Select(
		 	 SysScan('tables', ['table_name', 'table_id'])
#  Change the condition to a like
# Matching function depends if table is partitioned
#			,==(table_name, '${TNAMEX100}')
#			,like(table_name, '${TNAMEX100}')
			,${MATCHFUNC}(table_name, '${TNAMEX100}')
		 )
			,[ table_id ] [ table_name ]
	 )
		,[ table_name, column_offset ] [ table_name, column_name ]
)
;

EOF

#  Debug
#cat ${DATAFILE}
#exit

sql ${DBNAME} << EOF

drop table if exists ${DATATABLE}; \g


create table ${DATATABLE} (
	 RowId		integer8	not null
	,MinValue	${CTYPE}	not null
	,MaxValue	${CTYPE}	not null
	,TableName	varchar(30)	not null
	,ColName	varchar(30)	not null
)
;\g

--  Fix order of table name and column name
copy table ${DATATABLE} (
	 RowId		= 'c0|'
	,MinValue	= 'c0|'
	,MaxValue	= 'c0|'
	,ColName	= 'c0|'
	,TableName	= 'c0nl'
)
from '${DATAFILE}'
;\g

--  No longer applies for partitioned tables
--select top 1
--	 TableName
--	,ColName
--  from ${DATATABLE}
--;\g

--  Include basic output
select
         row_number() over (partition by TableName order by RowId) as LineNum
        ,RowId
        ,MinValue
        ,MaxValue
        ,TableName
  from
         ${DATATABLE}
order by
	 TableName
	,LineNum
;\g

- LHS R4 - EVERYTHING BELOW HERE IS NEW
drop table if exists ${DATATABLE2};
drop table if exists ${DATATABLE3};
;\g


create table ${DATATABLE2} as
	select
		 row_number() over (partition by TableName order by RowId) as LineNum
		,RowId
		,MinValue
		,MaxValue
		,TableName
	  from
		 ${DATATABLE}
;\g

create table ${DATATABLE3} as
select
	 mm1.TableName
	,mm1.LineNum
	,mm1.MinValue as mm1_MinValue
	,mm1.MaxValue as mm1_MaxValue
	,mm2.MinValue as mm2_MinValue
	,mm2.MaxValue as mm2_MaxValue
	,mm2.RowId - mm1.RowId as rows
	,case
		when mm1.MaxValue > mm2.MinValue then 1
		else 0
	 end as OverLap
  from
	 ${DATATABLE2} mm1
	,${DATATABLE2} mm2
 where
	mm1.TableName = mm2.TableName
   and	mm1.LineNum = mm2.LineNum - 1
;\g

select * from ${DATATABLE3}
order by
	 TableName
	,LineNum
;\g

select
	 TableName
	,sum(OverLap) as OverLaps
	,count(*) as Total
	,100.0 - decimal((decimal(sum(OverLap))/decimal(count(*)))*100.0,5,2) as SortedPct
  from
	 ${DATATABLE3}
group by
	 TableName
;\g

drop table ${DATATABLE};
drop table ${DATATABLE2};
drop table ${DATATABLE3};
\g

EOF

#cat ${DATAFILE}
rm -f ${DATAFILE}
