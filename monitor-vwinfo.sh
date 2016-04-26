#!/bin/bash
# Copyright 2016 Actian Corporation
 
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
 
#      http://www.apache.org/licenses/LICENSE-2.0
 
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

#	Capture memory usage info about Vector and VectorH via vwinfo.
#	This script is intended to be run periodically, say every half-hour, via cron.
#	Depends on having the Vector environment available, so vwinfo is on the path.

# 	Usage: monitor-vwinfo.sh <database name> >> /path/monitor-vwinfo.log

echo `date +%F\ %T`: Start Processing : $0
vwinfo $1
vwinfo -M $1
echo `date +%F\ %T`: End Processing : $0
