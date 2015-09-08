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
if [ $# -ne 4 ]
then
	echo 'Usage: $0 databasename table-owner table-name column-name'
	exit 1
fi

DBNAME=${1}
TOWNER=${2}
TNAME=${3}
CNAME=${4}

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


TNAMEX100="_${TOWNER}S${TNAME}"
CNAMEX100="_${CNAME}"
DATAFILE="/tmp/${0}.dat"
DATATABLE="minmax_deleteme"

echo "Database: ${DBNAME}, Owner: ${TOWNER}, Table: ${TNAME} [ ${TNAMEX100} ], Column: ${CNAME} [ ${CNAMEX100} ]"
if [ -d "$II_SYSTEM/ingres/data/vectorwise/$DBNAME/CBM" ]
then
	# Vector
	LOCKDIR="$II_SYSTEM/ingres/data/vectorwise/$DBNAME/CBM"
else
	# Vector-H
	LOCKDIR="$II_SYSTEM/ingres/data/vectorwise/$DBNAME"
fi

# Get the datatype for the column, so we can store the values later in the temp table
# Dumps the table schema to a file in /tmp then grabs the column datatype from that
copydb -u${TOWNER} ${DBNAME} ${TNAME} >copydb.log 2>&1
ERRORS=$(grep E_ copydb.log)

if [ "${ERRORS}" != "" ]
then
	echo "Problems accessing database ${DBNAME} and table ${TNAME} owned by ${TOWNER} - please check details and permissions"
	exit 1
fi

CTYPE=$(grep ${CNAME} copy.in |cut -d' ' -f2|head -1)

rm copy.out copy.in copydb.log

# Provide a default if the above didn't work for some reason
if [ "${CTYPE}" = "" ]
then
	CTYPE="integer8"
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
			,==(table_name, '${TNAMEX100}')
		 )
			,[ table_id ] [ table_name ]
	 )
		,[ table_name, column_offset ] [ table_name, column_name ]
)
;

EOF


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

copy table ${DATATABLE} (
	 RowId		= 'c0|'
	,MinValue	= 'c0|'
	,MaxValue	= 'c0|'
	,TableName	= 'c0|'
	,ColName	= 'c0nl'
)
from '${DATAFILE}'
;\g

select top 1
	 TableName
	,ColName
  from ${DATATABLE}
;\g

with MinMaxData as (
	select
--		 row_number() over (order by MinValue) as LineNum
		 row_number() over (order by RowId) as LineNum
		,RowId
		,MinValue
		,MaxValue
	  from
		 ${DATATABLE}
)
select
	 mm1.LineNum
	,mm1.MinValue
	,mm1.MaxValue
	,mm2.MinValue
	,mm2.MaxValue
	,mm2.RowId - mm1.RowId as rows
	,case
		when mm1.MaxValue > mm2.MinValue then 1
		else 0
	 end as OverLap
  from
	 MinMaxData mm1
	,MinMaxData mm2
 where
	mm1.LineNum = mm2.LineNum - 1
order by
	 mm1.LineNum
;\g

EOF

#cat ${DATAFILE}
rm -f ${DATAFILE}
