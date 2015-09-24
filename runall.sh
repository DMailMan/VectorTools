#!/bin/bash
#
# Name:
#   runall
#
# Description:
#
#
# History:
#   1.0 11-Mar-2015 (mark.whalley@actian.com)
#       Throwing around some ideas to see which stick
#
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
h_prog_name=`basename ${0}`
h_prog_version="v1.8"
#------------------------------------------------------------------------------


INITIALIZE()
{

  h_pid=$$
  h_noof_errors_reported=-1
  h_sq="'"

  h_script_list="/tmp/"$h_prog_name"."$h_pid".script_list"
  touch $h_script_list

  h_log_file="/tmp/"$h_prog_name"."$h_pid".log"
  touch $h_log_file

  h_script_error_file="/tmp/"$h_prog_name"."$h_pid".script_error"
  touch $h_script_error_file

  h_profile_data_file="/tmp/"$h_prog_name"."$h_pid".profile_data"
  touch $h_profile_data_file

  h_load_profile_data="/tmp/"$h_prog_name"."$h_pid".load_profile_data.sql"
  touch $h_load_profile_data

  export II_SYSTEM=$h_clv_iisystem

  export PATH=$II_SYSTEM/ingres/bin:$II_SYSTEM/ingres/utility:$PATH

  if [ "$LD_LIBRARY_PATH" ] ; then
      LD_LIBRARY_PATH=/usr/local/lib:$II_SYSTEM/ingres/lib:$II_SYSTEM/ingres/lib/lp32:$LD_LIBRARY_PATH
  else
      LD_LIBRARY_PATH=/lib:/usr/lib:/usr/local/lib:$II_SYSTEM/ingres/lib:$II_SYSTEM/ingres/lib/lp32
  fi
  export LD_LIBRARY_PATH

  return 0
}



PRINT_USAGE()
{
   printf "%s\n" "Usage:"
   printf "%s\n" "  $h_prog_name"
   printf "%s\n" "      -d|--database      {DB Name}"
   printf "%s\n" "      -g|--profgraph     {Y|N to create x100 profile graphs}"
   printf "%s\n" "      -i|--iisystem      {II_SYSTEM}"
   printf "%s\n" "      -k|--keeplog       {Y|N to keep temporary files}"
   printf "%s\n" "      -m|--maxconcurrent {Max number of concurrent queries}"
   printf "%s\n" "      -n|--numruns       {Number of runs}"
   printf "%s\n" "      -p|--profiledata   {Y|N to generate profile data from system catalogs}"
   printf "%s\n" "      -s|--scriptdir     {Script Directory Name}"

   return 0
}



TIDYUP()
{
#------------------------------------------------------------------------------
# Several files will have been created in /tmp during the run of this script.  
# This function will remove all of these is requested (from the provided run 
# time parameter)
#
# All the files prefixed by this program name and the PID of this invocation
# are removed
#
# Note that files created by previous runs (and thus a different PID) will not
# be removed by this function.
#------------------------------------------------------------------------------

   if [ $h_clv_keep_log == "N" ]
   then
      rm /tmp/$h_prog_name.$h_pid.*
   fi

   return 0
}
# ----------------------------------------------------------------------------
# End of Function: TIDYUP
# ----------------------------------------------------------------------------


function MESSAGELOG
{
# ----------------------------------------------------------------------------
# The MESSAGELOG function takes the string of text that the function was 
# called with and appends the string to a log file.  
#
# Each line is prefixed with a date/time stamp.
#
# Currently the function also displays the same detail on the screen.
# ----------------------------------------------------------------------------


# ----------------------------------------------------------------------------
#   Assign whatever has been passed as parameters to the h_clf_message
#   variable.
# ----------------------------------------------------------------------------
   h_message=$*

# ----------------------------------------------------------------------------
#   Whatever 'message' has been passed as a parameter, write it to
#   the log file
# ----------------------------------------------------------------------------

   echo `date +"%d/%m/%Y %H:%M:%S"` "$h_message" >> $h_log_file
   echo `date +"%d/%m/%Y %H:%M:%S"` "$h_message" 

   return 0
}
# ----------------------------------------------------------------------------
# End of Function: MESSAGELOG
# ----------------------------------------------------------------------------





GETSCRIPTLIST()
{
# ----------------------------------------------------------------------------
# Using the supplied parameter which provides a directory in which a list of
# SQL scripts has been created, this GETSCRIPTLIST function gets the list of
# scripts and loads them into an array.
#
# The scripts will be used to run against the database.
#
# Currently this function only handles SQL scripts, and these MUST have a 
# suffix of ".sql".
#
# The list of scripts will be automatically sorted, and it is in this order
# that they will be executed.
#
# If scripts are required to be run in a particular order, then the scripts
# need to be named alphabetically (or numerically) when placed in this
# script directory.
#
# Note that depending on the number of runs requested (as another run-time
# parameter), some of these scripts may be run several times (if there are
# more runs than scripts supplied) or some scripts may not be run at all
# (if there are more scripts supplied than runs requested).
#
# Thus if every script is required to be run just once, then then number of
# scripts must match the number of runs.
# ----------------------------------------------------------------------------

   MESSAGELOG Getting a list of SQL scripts from $h_clv_script_dir

   cd $h_clv_script_dir

   ls -1 *.sql | sort > $h_script_list

   h_noof_scripts=`cat $h_script_list | wc -l`

   MESSAGELOG Number of SQL scripts found: $h_noof_scripts

   h_script_idx=0

   while read h_script_name
   do

      (( h_script_idx+=1 ))

      MESSAGELOG Script $h_script_idx : $h_script_name

      ha_script_name[$h_script_idx]=$h_script_name

   done < $h_script_list

   return 0
}
# ----------------------------------------------------------------------------
# End of Function: GETSCRIPTLIST
# ----------------------------------------------------------------------------


ANYERRORS()
{
# ----------------------------------------------------------------------------
# ANYERRORS periodically checks for the existence of any errors being reported
# in the global script error file.
#
# Each independent execution of a script, on completion will have its own
# output examined for errors.  If any errors are found, a 1-liner is written
# to the global script error file and thus picked up here.
#
# Where a script does not report an error, then nothing for that script is
# written to the global script file.
# ----------------------------------------------------------------------------

      h_noof_previous_errors_reported=$h_noof_errors_reported

      h_noof_errors_reported=`cat $h_script_error_file | wc -l`


      if [ $h_noof_errors_reported -gt 0 ]
      then
         if [ $h_noof_errors_reported -gt $h_noof_previous_errors_reported ]
         then
            MESSAGELOG "========================================"
            MESSAGELOG "NOTE: Errors are being reported $h_noof_errors_reported!!!!!"
            MESSAGELOG "========================================"
         fi
      fi

}
# ----------------------------------------------------------------------------
# End of Function: ANYERRORS
# ----------------------------------------------------------------------------


RUNALL()
{
# ----------------------------------------------------------------------------
# The RUNALL function is the main component of this application.
#
# It main purpose is to control and manage the execution of scripts and call
# other functions to check for errors etc.
# ----------------------------------------------------------------------------

   MESSAGELOG Starting to run all scripts

   h_script_idx=0
   h_runno=0

   h_noof_script_running=0

# ----------------------------------------------------------------------------
# The "Num Runs" parameter which was provided at the run-time of the
# application will determine how many separate runs are to be peformed.
#
# This section controls the execution of these runs.
# ----------------------------------------------------------------------------
   while [ $h_runno -lt $h_clv_num_runs ]
   do

# ----------------------------------------------------------------------------
# The function keeps a track of how many concurrent scripts are running by
# checking for running processes.
#
# NOTE: There are plans to convert this checking to checking for specific PIDs
# ----------------------------------------------------------------------------
      h_noof_script_running=`ps -fale | grep $h_prog_name'.'$h_pid | grep -v grep |  awk '{print $16}' | sort -u | wc -l`

# ----------------------------------------------------------------------------
# Check to see if any of the current/previously running scripts have reported
# any errors to the global error file
# ----------------------------------------------------------------------------
      ANYERRORS

# ----------------------------------------------------------------------------
# If we have reached the maximum number of concurrently running scripts
# (as defined by the start up paramater), then print out a log message and
# go to sleep for a second before continuing around the loop
# ----------------------------------------------------------------------------
      if [ $h_noof_script_running -eq $h_clv_max_concurrent ]
      then
         if [ $h_noof_script_running_nochange == "N" ]
         then
            MESSAGELOG Number of scripts running has reached the max concurrent allowed of $h_clv_max_concurrent
            h_noof_script_running_nochange="Y"
         fi
         sleep 1
         continue
      else
         h_noof_script_running_nochange="N"
      fi

# ----------------------------------------------------------------------------
# If we are not at the limit of concurrently runnings scripts, report a log
# message and prepare to start running the next one
# ----------------------------------------------------------------------------
      MESSAGELOG Number of scripts running: $h_noof_script_running of $h_clv_max_concurrent

      ((h_runno+=1))

# ----------------------------------------------------------------------------
# If we are at the end of the list of available scripts (stored in the array)
# we need to start again at the beginning of the array (and thus start running
# scripts that have already been submitted)
# ----------------------------------------------------------------------------
      if [ $h_script_idx -eq $h_noof_scripts ]
      then
         h_script_idx=0
      fi

      ((h_script_idx+=1))

      h_script_name=${ha_script_name[$h_script_idx]}

# ----------------------------------------------------------------------------
# Define some files:
#    "script"        : the controlling script
#    "run_sql_script": the script that will run the SQL script (called from
#                      "script"
#    "sql_script"    : a copy of the supplied SQL script and any additional
#                      SQL this script may have added (e.g. profile stuff)
#    "check_script"  : a shell script that gets called by "script" after the
#                      "run_sql_script" to check for errors
# ----------------------------------------------------------------------------
      h_runall_script="/tmp/$h_prog_name."$h_pid"."$h_runno
      h_runall_run_sql_script="/tmp/$h_prog_name."$h_pid".runsql."$h_runno
      h_runall_sql_script="/tmp/$h_prog_name."$h_pid"."$h_script_name"."$h_runno
      h_runall_check_script="/tmp/$h_prog_name."$h_pid".check."$h_runno


# ----------------------------------------------------------------------------
# If we want x100 profile graphs to be created (as defined from the run-time
# parameter "profgraph", then turn on profiling to create the profile file.
#
# The call to x100profgraph will be included later
# ----------------------------------------------------------------------------
      if [ $h_clv_profgraph == "Y" ]
      then

         h_runall_profgraph_text="/tmp/$h_prog_name."$h_pid"."$h_script_name".profilegraphtext."$h_runno

         echo "call vectorwise (setconf 'server, profiling, ''true''')            " >> $h_runall_sql_script
         echo "\p\g                                                              " >> $h_runall_sql_script
         echo "call vectorwise (setconf 'server, profile_file, ''"$h_runall_profgraph_text"''')" >> $h_runall_sql_script
         echo "\p\g                                                              " >> $h_runall_sql_script

      fi

# ----------------------------------------------------------------------------
# Populate the temporary "sql_script" with the contents of the supplied SQL
# script
# ----------------------------------------------------------------------------
      cat $h_clv_script_dir/$h_script_name >> $h_runall_sql_script



# ----------------------------------------------------------------------------
# ... and if we turned profiling on, better turn it off
# ----------------------------------------------------------------------------
      if [ $h_clv_profgraph == "Y" ]
      then

         h_runall_profgraph_text="/tmp/$h_prog_name."$h_pid"."$h_script_name".profilegraphtext."$h_runno

         echo "call vectorwise(setconf 'server, profiling, ''false''')           " >> $h_runall_sql_script
         echo "\p\g                                                              " >> $h_runall_sql_script

      fi



# ----------------------------------------------------------------------------
# If we want profile data captured from running the script, add the SQL to
# extract it to the end of the temporary "sql_script"
#
# This will be done by putting the profile data into a session temporary table
# then copying that out to a text file.
#
# This profile data in the text file will subsequently be combined with all the
# other profile data from other scripts to be loaded into a single table for
# subsequent analysis
# ----------------------------------------------------------------------------
      if [ $h_clv_profile_data == "Y" ]
      then

         h_runall_sql_profile_data="/tmp/$h_prog_name."$h_pid"."$h_script_name".profile_data."$h_runno

         echo "declare global temporary table session.maw_iivwprof_query as      " >> $h_runall_sql_script
         echo "select                                                            " >> $h_runall_sql_script
         echo "  '$h_script_name'    as script_name,                             " >> $h_runall_sql_script
         echo "  '$h_runno'          as run_no,                                  " >> $h_runall_sql_script
         echo "  session_id,                                                     " >> $h_runall_sql_script
         echo "  query_id,                                                       " >> $h_runall_sql_script
         echo "  start_time,                                                     " >> $h_runall_sql_script
         echo "  execution_time,                                                 " >> $h_runall_sql_script
         echo "  mem,                                                            " >> $h_runall_sql_script
         echo "  mem_tot,                                                        " >> $h_runall_sql_script
         echo "  mem_vm,                                                         " >> $h_runall_sql_script
         echo "  mem_tot_vm                                                      " >> $h_runall_sql_script
         echo "from                                                              " >> $h_runall_sql_script
         echo "  iivwprof_query                                                  " >> $h_runall_sql_script
         echo "where                                                             " >> $h_runall_sql_script
         echo "  query_text not like '%maw_iivwprof_query%'                      " >> $h_runall_sql_script
         echo "on commit preserve rows with norecovery                           " >> $h_runall_sql_script
         echo "\p\g                                                              " >> $h_runall_sql_script

         echo "copy session.maw_iivwprof_query(                                  " >> $h_runall_sql_script
         echo "  script_name      = c0tab,                                       " >> $h_runall_sql_script
         echo "  run_no           = c0tab,                                       " >> $h_runall_sql_script
         echo "  session_id       = c0tab,                                       " >> $h_runall_sql_script
         echo "  query_id         = c0tab,                                       " >> $h_runall_sql_script
         echo "  start_time       = c0tab,                                       " >> $h_runall_sql_script
         echo "  execution_time   = c0tab,                                       " >> $h_runall_sql_script
         echo "  mem              = c0tab,                                       " >> $h_runall_sql_script
         echo "  mem_tot          = c0tab,                                       " >> $h_runall_sql_script
         echo "  mem_vm           = c0tab,                                       " >> $h_runall_sql_script
         echo "  mem_tot_vm       = c0nl)                                        " >> $h_runall_sql_script
         echo "into '$h_runall_sql_profile_data'\p\g                             " >> $h_runall_sql_script


      fi



      MESSAGELOG Starting to run Script No: $h_script_idx - $h_script_name as Run No: $h_runno

# ----------------------------------------------------------------------------
# Write an SQL command line call for the above sql script into the "run_sql_script"
# ----------------------------------------------------------------------------
      echo "sql $h_clv_db_name < $h_runall_sql_script 1>$h_runall_script.log 2>&1" > $h_runall_run_sql_script

# ----------------------------------------------------------------------------
# ... and prepare the "check_script" to check for errors in the above SQL 
# run (when it runs!)
#
# This simply looks for an E_ in the output of the above SQL, and if it finds
# any writes a 1-liner to the global check script to indicate which run 
# number had errors and how many E_ it found
# ----------------------------------------------------------------------------
      echo 'h_noof_errors=`grep E_ '$h_runall_script'.log | wc -l`'          > $h_runall_check_script
      echo 'if [ $h_noof_errors -gt 0 ]'                                    >> $h_runall_check_script
      echo 'then'                                                           >> $h_runall_check_script
      echo '  echo Run No '$h_script_idx' has reported $h_noof_errors errors >> '$h_script_error_file  >> $h_runall_check_script
      echo 'fi'                                                             >> $h_runall_check_script


# ----------------------------------------------------------------------------
# ... and finally build the "script" file to call the two other scripts:
#     1. The SQL script
#     2. The check script
# ----------------------------------------------------------------------------

      echo "$h_runall_run_sql_script 1>/dev/null 2>/dev/null"                > $h_runall_script
      echo "$h_runall_check_script 1>/dev/null 2>/dev/null"                 >> $h_runall_script


# ----------------------------------------------------------------------------
# Make all the scripts executable
# ----------------------------------------------------------------------------
      chmod 777 $h_runall_script
      chmod 777 $h_runall_run_sql_script
      chmod 777 $h_runall_check_script


# ----------------------------------------------------------------------------
# ... and run the main "script" in background
# ----------------------------------------------------------------------------
      nohup $h_runall_script 1>/dev/null 2>/dev/null &

# ----------------------------------------------------------------------------
# Before cycling round to see if there are any more runs to be done
# ----------------------------------------------------------------------------
   done


# ----------------------------------------------------------------------------
# To make life a little easier, create an SQL script that will create a
# physical table for this run (PID) and a copy statement to load in all
# the profile data from each of the accumulated profiles
# ----------------------------------------------------------------------------

   if [ $h_clv_profile_data == "Y" ]
   then

      echo "cat $h_runall_sql_profile_data >> $h_profile_data_file"      >> $h_runall_check_script

      echo "create table "$h_prog_name"_"$h_pid"_prof_query (                 "  > $h_load_profile_data
      echo "  script_name         char(20)      not null,                     " >> $h_load_profile_data
      echo "  run_no              integer       not null,                     " >> $h_load_profile_data
      echo "  session_id          integer8      not null,                     " >> $h_load_profile_data
      echo "  query_id            integer8      not null,                     " >> $h_load_profile_data
      echo "  start_time          timestamp(6)  not null,                     " >> $h_load_profile_data
      echo "  execution_time      interval day to second(6),                  " >> $h_load_profile_data
      echo "  mem                 integer8      not null,                     " >> $h_load_profile_data
      echo "  mem_tot             integer8      not null,                     " >> $h_load_profile_data
      echo "  mem_vm              integer8      not null,                     " >> $h_load_profile_data
      echo "  mem_tot_vm          integer8      not null) \p\g                " >> $h_load_profile_data
      echo "\p\g                                                              " >> $h_load_profile_data

      echo "copy "$h_prog_name"_"$h_pid"_prof_query (                         " >> $h_load_profile_data
      echo "  script_name      = c0tab,                                       " >> $h_load_profile_data
      echo "  run_no           = c0tab,                                       " >> $h_load_profile_data
      echo "  session_id       = c0tab,                                       " >> $h_load_profile_data
      echo "  query_id         = c0tab,                                       " >> $h_load_profile_data
      echo "  start_time       = c0tab,                                       " >> $h_load_profile_data
      echo "  execution_time   = c0tab,                                       " >> $h_load_profile_data
      echo "  mem              = c0tab,                                       " >> $h_load_profile_data
      echo "  mem_tot          = c0tab,                                       " >> $h_load_profile_data
      echo "  mem_vm           = c0tab,                                       " >> $h_load_profile_data
      echo "  mem_tot_vm       = c0nl)                                        " >> $h_load_profile_data
      echo "from '$h_profile_data_file'      \p\g                             " >> $h_load_profile_data


   fi

#------------------------------------------------------------------------------
# No that we have fired off the last run, we now need to wait until all the
# outstanding scripts have finished
#------------------------------------------------------------------------------

   h_noof_script_running=999

   MESSAGELOG "Waiting until all remaining scripts have finished running"

#------------------------------------------------------------------------------
# Keep looping round until there are no more scripts running
#------------------------------------------------------------------------------
   while [ $h_noof_script_running -gt 0 ]
   do

#------------------------------------------------------------------------------
# Check how many processes are running
#------------------------------------------------------------------------------
      h_noof_script_running=`ps -fale | grep $h_prog_name'.'$h_pid | grep -v grep |  awk '{print $16}' | sort -u | wc -l`

#------------------------------------------------------------------------------
# Better check if there have been any further errros
#------------------------------------------------------------------------------
      ANYERRORS

#------------------------------------------------------------------------------
# If there are still scripts running, pause for a second before checking again
#------------------------------------------------------------------------------
      if [ $h_noof_script_running -gt 0 ]
      then
         sleep 1
         continue
      fi

   done



   return 0
}
# ----------------------------------------------------------------------------
# End of Function: RUNALL
# ----------------------------------------------------------------------------





#------------------------------------------------------------------------------
# Main program
#------------------------------------------------------------------------------

#------------------------------------------------------------------------------
# Process Command Line Variables (clv)
#------------------------------------------------------------------------------

h_clv_db_name=""


while [ -n "$1" ]
do

   case "$1" in

   "-d"|"--database")
      h_clv_db_name=$2
      shift
      ;;

   "-g"|"--profgraph")
      h_clv_profgraph=$2
      shift
      ;;

   "-i"|"--iisystem")
      h_clv_iisystem=$2
      shift
      ;;

   "-k"|"--keeplog")
      h_clv_keep_log=$2
      shift
      ;;

   "-m"|"--maxconcurrent")
      h_clv_max_concurrent=$2
      shift
      ;;

   "-n"|"--numruns")
      h_clv_num_runs=$2
      shift
      ;;

   "-p"|"--profiledata")
      h_clv_profile_data=$2
      shift
      ;;

   "-s"|"--scriptdir")
      h_clv_script_dir=$2
      shift
      ;;

   *)
      printf "%s\n" "Invalid parameter: $1"
      PRINT_USAGE
      exit 1
      ;;

   esac

   shift

done


#------------------------------------------------------------------------------
# Validate parameters
#------------------------------------------------------------------------------


if [ -z "$h_clv_db_name" ]
then
   printf "%s\n" "CRITICAL no database name has been specified"
   PRINT_USAGE
   exit 1
fi


if [ -z "$h_clv_script_dir" ]
then
   printf "%s\n" "CRITICAL no script directory has been specified"
   PRINT_USAGE
   exit 1
fi



if [ -z "$h_clv_keep_log" ]
then
   printf "%s\n" "CRITICAL keep log requires a Y or N response"
   PRINT_USAGE
   exit 1
fi


if [ -z "$h_clv_profile_data" ]
then
   printf "%s\n" "CRITICAL generate profile data requires a Y or N response"
   PRINT_USAGE
   exit 1
fi

if [ -z "$h_clv_profgraph" ]
then
   printf "%s\n" "CRITICAL generate profile graph requires a Y or N response"
   PRINT_USAGE
   exit 1
fi



if [ -z "$h_clv_max_concurrent" ]
then
   printf "%s\n" "CRITICAL number of maximum concurrent queries not supplied"
   PRINT_USAGE
   exit 1
fi

if [ -z "$h_clv_num_runs" ]
then
   printf "%s\n" "CRITICAL number of runs not supplied"
   PRINT_USAGE
   exit 1
fi


if [ -z "$h_clv_iisystem" ]
then
   printf "%s\n" "CRITICAL II_SYSTEM has not supplied"
   PRINT_USAGE
   exit 1
fi



INITIALIZE

GETSCRIPTLIST

RUNALL



#------------------------------------------------------------------------------
# remove this eventually
#------------------------------------------------------------------------------
cat $h_log_file

TIDYUP

exit



#------------------------------------------------------------------------------
# End of Script
#------------------------------------------------------------------------------

