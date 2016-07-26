#!/bin/bash
#
# Copyright 2016 Actian Corporation
#
# Simple script to re-generate a Vector/H profile from any file with a .profile
# suffix that is saved into the /tmp folder, or into a nominated HDFS folder.
#
# Pre-requisites are that this is run as the actian user, so we can find the installation and 
# hence the x100profgraph tool.
# x100 profgraph must also work, so its dependencies of gnuplot and graphviz must have been 
# satisfied already (i.e. via 'sudo yum install gnuplot graphviz' or equivalent).
#
# This script is intended to be run via cron on a frequent interval, e.g. every minute, via:
# * * * * * ~actian/profile_gen.sh >> ~actian/profile_gen.log 2>&1


# Adjust the following line to match your installation, if you have changed the INSTALLATION_ID
source ~actian/.ingVHsh
export PROFGRAPH_PATH=$II_SYSTEM/ingres/sig/x100profgraph/x100profgraph

# Also Adjust this path according to where you want the profiles to be placed
export PROFILE_DESTINATION="/Actian/tmp"


# Just take the default PDF output, into the same folder with a .pdf suffix
# Don't try to look for only new files, meaning that you can re-use the same profile file name
# and still have the profile re-generated. Less efficient, but simpler, and profgraph is quick anyway.

for file in `ls /tmp/*.profile`
do
	cat $file | $PROFGRAPH_PATH > ${file}.pdf
	hadoop fs -copyFromLocal ${file}.pdf ${PROFILE_DESTINATION} 
done

# Need to extract just the path from the 'ls -l' output that hadoop fs -ls produces
for file in `hadoop fs -ls ${PROFILE_DESTINATION}/*profile | rev | cut -d\  -f1 |rev`
do
	hadoop fs -cat $file | $PROFGRAPH_PATH | hadoop fs -put - hdfs://${file}.pdf 
done