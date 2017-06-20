#!/bin/bash
# Copyright 2017 Actian Corporation
 
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
  
#      http://www.apache.org/licenses/LICENSE-2.0
   
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.


# What compression ratio is my Vector database achieving ?
# Pass in the database name that you want to examine as the only parameter needed.

if [ $# -ne 1 ]
then
    echo "Usage: $0 <database name>"
    exit 1
fi

FILE_SYSTEM=`du -s -h $II_SYSTEM/ingres/data/vectorwise/$1 | tr -d 'M' | cut -f 1`

echo '\\s call vectorwise(total_db_size);\g' | sql $1 >/dev/null
COMPRESSION=`tail $II_SYSTEM/ingres/files/vectorwise.log | grep total_db_size| head -1| awk '{print $FILE_SYSTEM/($13/1024/1024)}'`

echo Compression ratio of database $1 is ${COMPRESSION}:1
