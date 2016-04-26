#!/usr/bin/awk

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

# Script to parse vwinfo output to make it chartable and graphable for analysis.
# Transposes rows to columns within a data/time-stamped block.

# Usage: awk -F '|' -f vwinfo-pivot.awk <input-data-filename> > vwinfo-out.csv
# Then import the data to Excel or similar to chart it.

# Input data looks like this:
#
#2016-04-26 10:56:23:  Start Processing : monitor_vwinfo
#+------------------------------------+--------------------------------------------+
#|stat                                |value                                       |
#+------------------------------------+--------------------------------------------+
#|memory.memcontext_allocated         |7626673992                                  |
#|memory.memcontext_maximum           |287037194240                                |
#|system.log_file_size                |9839545026                                  |
#|system.threshold_log_condense       |11694901940                                 |
#+------------------------------------+--------------------------------------------+
#2016-04-26 10:56:23:  End Processing : monitor_vwinfo
#

# and output format looks like this:

#timestamp,memcontext_allocated,log_file_size,active_sessions,committed_transactions
#2016-04-26 10:56:23,7626673992,9839545026,21,51811414
#2016-04-26 11:00:06,13600321807,7441402489,3,25461059
#2016-04-26 11:26:26,8259696240,12566530678,3,34660155


BEGIN {
	# Set up the list of fields we are interested in. Space-separate their names.
	# Field names have to be unique but not fully spelled out, since we do a regex
	# match when looking for them later.

	###################################################################
	# Edit the line below to choose which data fields to pull out from all of the ones available. 
	###################################################################

	field_list = "committed_transactions memcontext_allocated memcontext_maximum active_sessions log_file_size threshold_log_condense %memcontext %log";


	# Transform the numeric indexes from the split into an associative array so we can 
	# store the values when we find them
	no_fields = split(field_list, field_temp, " ");
	for (i = 1; i <= no_fields; i++) fields[field_temp[i]] = 0;

	# Print out the header row first, generated dynamically based on the selected fields.
	printf "timestamp";

	for (field in fields) printf ",%s", field;
	printf "\r\n";
}

# capture the date of this next block of records
/Start Processing/ {
    split($0, dates, ": Start");
	record_date = dates[1];

	# Initialise the data array to clear out old data, just in case we miss a value somewhere
	for (i = 1; i <= no_fields; i++) fields[field_temp[i]] = 0;
}

# Only pick out lines with 'proper' data in them, indicated by a "|xxxx.xxxx" sort of pattern. 
# Capture data in an array to print out at end of the block.

/^\|[[:alnum:]]*\.[[:alnum:]]*/ { 
	# Look through the set of fields to see if the current line matches one of interest. Store if so.

	# Field $2 is the data item name, and field $3 is the value.
	# Store these in an associative array for this block of time.
	# Requires that the field separator value is |, via -F '|' when calling this script

    for (field in fields) {
    	if ($2 ~ field ) {
    		# Store away the record values that match the ones we are interested in
			fields[field] = $3;
	    }
    }
}


# This is the end of the block, so print out the data record for this block
/End Processing/ {
	# Print out the date just once for every block of data, at the start of a line
	# Note that this prints all data for the previous block only at the end of a block
	# so even the last block must have an 'End' marker

	# Calculate 'special' derived fields as percentages.
	# These only get calculated properly if all 4 field names below are in the field list.

	fields["%log"]  = (fields["log_file_size"]/fields["threshold_log_condense"])*100;
	fields["%memcontext"] = (fields["memcontext_allocated"]/fields["memcontext_maximum"])*100;

	# Only print the row if there is decent data. Log condense threshold value is never really 1.
	if (fields["threshold_log_condense"] > 1 ) {
		# Start printing the output record for this block of time
		printf record_date;

		for (field in fields) printf ",%d", fields[field];

		# Cleanly terminate each line
		printf "\r\n";
	}
}