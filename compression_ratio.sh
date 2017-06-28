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

TMPFILE="/tmp/compression_ratio.tmp"
infodb $1 >${TMPFILE}
if [ $? != 0 ]
then
        echo "Unable to run infodb command"
        exit 1
fi

while read VW_LOC
        do
        let VW_MB="`du -m -c -s --exclude=main_wal_backups ${VW_LOC}/{CBM,wal} | tail -1 | awk '{print $1}'`"
        let FILE_SYSTEM=${FILE_SYSTEM}+${VW_MB}
        done < <(cat ${TMPFILE} | grep DATA | grep '/data/vector' | awk '{print $3}')

# This command can sometimes take quite a long time on large databases
echo 'call vectorwise(total_db_size);\g' | sql $1 >/dev/null
VW_UNCOMP=`tail -250 $II_SYSTEM/ingres/files/vectorwise.log | grep total_db_size | grep " $1 " | tail -1 | awk '{print ($(NF))}'`
let VW_UNCOMP=$VW_UNCOMP/1024/1024

if [ "$VW_UNCOMP" = 0 ]
then
        echo "Vector database is 0 bytes"
else
        echo "File system (compressed): ${FILE_SYSTEM} MB"
        echo "Uncompressed projection : ${VW_UNCOMP} MB"
        COMPRESSION=`echo "scale=2; $VW_UNCOMP/$FILE_SYSTEM" | bc | sed 's/^\./0./'`
        echo "Compression ratio of database $1 is ${COMPRESSION} : 1"
fi

exit
