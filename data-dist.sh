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

# This SQL script is intended to show the numbers of rows stored in each partition of a Vector/H table.
# Pass in the database name and table name that you want to examine as the only parameters needed.

# You can also use vwinfo -T to get the same data in terms of disk blocks, rather than rows.

if [ $# -ne 2 ]
then
	echo "Usage: data-dist.sh database-name table-name"
	exit 1
fi

sql $1 <<EOF
SELECT tid/10000000000000000 AS partition_id, COUNT(*) AS num_tuples 
FROM $2
GROUP BY 1 ORDER BY 1;\g
EOF