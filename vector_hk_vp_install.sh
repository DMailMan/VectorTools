#!/bin/bash
#
# Copyright 2016 Actian Corporation
#
# Program Ownership and Restrictions.
#
# This Program/Script provided hereunder is licensed, not sold, and all
# intellectual property rights and title to the Program shall remain with Actian
# and Our suppliers and no interest or ownership therein is conveyed to you.
#
# No right to create a copyrightable work, whether joint or unitary, is granted
# or implied; this includes works that modify (even for purposes of error
# correction), adapt, or translate the Program or create derivative works, 
# compilations, or collective works therefrom, except as necessary to configure
# the Program using the options and tools provided for such purposes and
# contained in the Program. 
#
# The Program is supplied directly to you for use as defined by the controlling
# documentation e.g. a Consulting Agreement and for no other reason.  
#
# You will treat the Program as confidential information and you will treat it
# in the same manner as you would to protect your own confidential information,
# but in no event with less than reasonable care.
#
# The Program shall not be disclosed to any third party (except solely to
# employees, attorneys, and consultants, who need to know and are bound by a
# written agreement with Actian to maintain the confidentiality of the Program
# in a manner consistent with this licence or as defined in any other agreement)
# or used except as permitted under this licence or by agreement between the
# parties.
#

#----------------------------------------------------------------------------
#
# Name:
#
#   vector_hk_vp_install.sh
#
# Description:
#
#   This script installs the Vector Housekeeping and Query Performance 
#   Analysis scripts. They are configured to run and cron entries created:
#     - Housekeeping run every day at 11pm
#     - Query Performance Analsys every 2 hours except 10pm and 12pm to
#       prevent any possible interference with House keeping.  
#
# Preresquites:
#
#    For the install to succeed this script must be run as a user with access
#    to the target Vector installation configured i.e ingXXsh run.
#
#    Sudo access is required to implement the logrotate for the Vector logs.
#    If this is not available the step will be skipped.
#
#----------------------------------------------------------------------------


l_prog_name=`basename ${0}`
l_prog_version=v1.0

export l_pid=$$

l_INSTALL_DIR=${PWD}

l_package_1="vector_housekeeping"
l_package_2="VectorQueryPerformanceAnalysis"
l_package_2_db="vqat"


if [ -z ${TEMP} ]
then
    export TEMP=/tmp
    echo "Temporary directory not set so using /tmp"
fi

if [ ! -d "${TEMP}" ]
then
    echo "TEMP folder ${TEMP} is not a directory"
    exit 1
fi


#----------------------------------------------------------------------------
# Function:
#   log_message   
#     Log a message to the default log file and console for this run.
#----------------------------------------------------------------------------
function LOG_MESSAGE
{
    l_message_log=${TEMP}/${l_prog_name}_${l_pid}.log

    if [ -f ${l_message_log} ]
    then
        touch ${l_message_log}
    fi

    l_message=$*

    echo `date +"%d/%m/%Y %H:%M:%S"` "$l_message" >> $l_message_log
    echo `date +"%d/%m/%Y %H:%M:%S"` "$l_message" 

    return 0
}


#----------------------------------------------------------------------------
# Script Main Body
#----------------------------------------------------------------------------

LOG_MESSAGE Program Name: $h_prog_name Starting

l_II_SYSTEM=$II_SYSTEM

# 1. Check the environment is correctly set to run the installation - Belt and braces

if [ -z "$l_II_SYSTEM" ]
then
    if [ `ls ~/.ing??sh | wc -l` -ne "1" ]
    then
        LOG_MESSAGE "It does not appear that this user is correctly configured with a default Vector Installation."
        LOG_MESSAGE "Attempted to declare environment but 0 or multiple environments found."
        exit 9
    fi

    l_vector_setup=`ls ~/.ing??sh`

    LOG_MESSAGE "Vector environment not configured. Attempting to declare environment with ${l_vector_setup}."

    source ${l_vector_setup}
    l_II_SYSTEM=$II_SYSTEM
fi

if [ ! -d "$l_II_SYSTEM" ]
then
    LOG_MESSAGE "It does not appear that this user is correctly configured with a default Vector Installation."
    exit 9
fi

ingprenv -report > /dev/null 2>&1

if [ $? -eq 127 ]
then
    LOG_MESSAGE "It does not appear that this user is correctly configured with a default Vector Installation."
    exit 9
fi

sql iidbdb > /dev/null 2>&1 <<EOF
\q
EOF

if [ $? -ne 0 ]; then
    LOG_MESSAGE "ERROR on start-up. The user does not appear to have access to a Vector/VectorH installation"
    exit 9
fi

l_II_INSTALLATION="`ingprenv | grep II_INSTALLATION | cut -d= -f2`"

if [ -z "$l_II_INSTALLATION" ]
then
    LOG_MESSAGE "Unable to get II_INSTALLATION"
    exit 9
fi


# 2. Download the installation packages

git clone --depth 1 -q https://github.com/ActianCorp/${l_package_1} 2>> ${l_message_log}

if [ $? -gt 0 ]
then
    LOG_MESSAGE "Unable to download the Housekeeping package."
    exit 1
fi

git clone --depth 1 -q https://github.com/ActianCorp/${l_package_2} 2>> ${l_message_log}

if [ $? -gt 0 ]
then
    LOG_MESSAGE "Unable to download the Vector Performance Analysis package."
    exit 1
fi


# 3. Install Housekeeping
#   - It is assumed that logrotate is system configured to run once daily (Linux norm)

l_dir=${l_INSTALL_DIR}/${l_package_1} 

    # Set permissions for running
chmod 755 ${l_dir}/*

    # Setup the Linux standard logrotate for the Vector logs
sudo -v 2>&1 | grep "Sorry" > /dev/null

if [ $? -eq 0 ]; then
    LOG_MESSAGE "Unable to implement Vector log rotate as it appears there is no sudo access. CONTINUING as none critical"
else
    sudo cp ${l_dir}/vectorlogs-rotate.conf /etc/logrotate.d/. &>> ${l_message_log} 

    if [ $? -gt 0 ]
    then
        LOG_MESSAGE "FAILED to implement Vector log rotate. CONTINUING as none critical"
    fi
fi

# 4. Install Vector Performance Analysis

l_dir=${l_INSTALL_DIR}/${l_package_2}

    # Set permissions for running
chmod 755 ${l_dir}/*

    # Create the analysis database
createdb ${l_package_2_db} &>> ${l_message_log} 

if [ $? -gt 0 ]
then
    LOG_MESSAGE "Unable to create analysis database ${l_package_2_db}."
    exit 1
fi

    # Set the log configuration to produce the necessary detail for analysis
cp ${l_dir}/vwlog.conf ${II_SYSTEM}/ingres/files/. &>> ${l_message_log} 

if [ $? -gt 0 ]
then
    LOG_MESSAGE "Unable to implement Vector configuration changes required for Vector Query Analysis"
    exit 1
fi

    # Dynamically tell Vector to use the new configuration 

sql ${l_package_2_db} &>> ${l_message_log} <<EOF
CALL VECTORWISE(VWLOG_RELOAD);\p\g
EOF

if [ "`grep '^E_' ${l_message_log} | wc -l`" -gt 0 ]
then
    LOG_MESSAGE "Unable to re-configure the Vector installation for log analysis"
    exit 1
fi

# 5. Setup the cron entries for both

l_vector_profile="source ~/.ing${l_II_INSTALLATION}sh"

l_cron_file=${TEMP}/${l_prog_name}_${l_pid}.cron

crontab -l > ${l_cron_file} &>> ${l_message_log} 

if [ $? -ne 0 -a "`grep 'no crontab' ${l_message_log} | wc -l`" -eq 0 ] 
then
    LOG_MESSAGE "Unable to access current cron entries. Manual completion of install required."
    exit 1
fi

echo "0 23 * * *                        ${l_vector_profile}; cd ${l_package_1}; ${l_INSTALL_DIR}/${l_package_1}/vector_housekeeping.sh ${l_II_INSTALLATION}" >> ${l_cron_file}

echo "0 2,4,6,8,10,12,14,16,18,20 * * * ${l_vector_profile}; cd ${l_package_2}; ${l_INSTALL_DIR}/${l_package_2}/load_vector_log.sh --log_db ${l_package_2_db} >/dev/null" >> ${l_cron_file}

crontab ${l_cron_file} &>> ${l_message_log} 

if [ $? -ne 0 ]
then
    LOG_MESSAGE "Unable to update cron entries. Manual completion of install required."
    exit 1
fi

LOG_MESSAGE Program Name: $h_prog_name Completed Successfully

exit 0


#------------------------------------------------------------------------------
# End of shell script
#------------------------------------------------------------------------------
