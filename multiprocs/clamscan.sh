#!/bin/bash
# ********************************************************************
# (c) 2022 Skynet Consulting Ltd.
# ********************************************************************
# Description:
#   Updated for the ClamAV v0.100.2 in new location
#
#   Wrapper script for the clamav scanner - to be run once per day
#
#   Due to the nature of some files such as internal O/S files,
#   removalable media, or Sybase database files - these are excluded
#   from being scanned.
#
#   In addition, the Codemeter software may hold system resources
#   locked, so this is restarted first before the scan is started.
#
#   The ClamAV Virus scanner is supported on  multiple O/S
#   and used on the SCADACOM Server and Workstations
#
#   More Info at: http://www.clamav.net/ (Original) and
#   https://www.opencsw.org/packages/CSWclamav/ (New)
#
#  Additional configuration can be found at (v0.98):
#      /usr/local/clamav/etc/clamd.conf
#
# ClamAV - usage
#     /opt/csw/bin/clamscan --help
#
# This script lives in
#     /var/lib/clamav/wg_clamscan.sh
# ********************************************************************

# ********************************************************************
# Definitions
# ********************************************************************
# Default ClamAV V0.100.2 db at /var/opt/csw/clamav/db
# Using the existing ClamAV database directory
export CLAM_WRAPPER=/var/lib/clamav/wg_clamscan.sh
export CLAM_WRAPPER_VER=1.2
export CLAM_WRAPPER_DATE="28-February-2022"
export CLAM_DB=/var/lib/clamav/clam_db
export LD_LIBRARY_PATH=/usr/sfw/lib
export CLAMSCAN=/opt/csw/bin/clamscan
export NICE=/usr/bin/nice
export NUM_CPU=6
export LOG=/var/log/clamscan.log

# ********************************************************************
# ClamAV V0.98 overrides
# ********************************************************************
#export CLAM_DB=/var/lib/clamav/old_clam_db
#export CLAMSCAN=/usr/local/clamav/bin/clamscan
#export LOG=/var/log/clamscan-098.log

# ********************************************************************
# Use the following to find out what file is being scanned
# ********************************************************************
#while [ 1 ];do;/usr/local/bin/lsof -p `ps -ef|grep clam|grep max-file|awk '{print $2}'`|grep -v clamav|tail -1;sleep 5;done

# ********************************************************************
# Configuration
#    Use -i to show only infected files
#    Use -o to suppress ok files
# ********************************************************************
export EXCLUDE_DIR="--exclude-dir=\"^/dev/|^/devices/|^/mnt/|^/kernel/|^/platform/|^/rmdisk/|^/export/sybase/data/|^/cdrom/|^/proc/|^/system/object/|^/var/tmp/|^/var/run|^/var/tmp/clamav-*|^/vol/\""
export EXCLUDE_DIR="--exclude-dir=\"^/dev/\" --exclude-dir=\"^/devices/\" --exclude-dir=\"^/mnt/\" --exclude-dir=\"^/kernel/\" --exclude-dir=\"^/platform/\" --exclude-dir=\"^/rmdisk/\" --exclude-dir=\"^/export/sybase/data/\" --exclude-dir=\"^/cdrom/\" --exclude-dir=\"^/proc/\" --exclude-dir=\"^/system/object/\" --exclude-dir=\"^/var/tmp/\" --exclude-dir=\"^/var/run/\" --exclude-dir=\"^/var/tmp/clamav-\" --exclude-dir=\"^/vol/\""
export DATABASE="--database ${CLAM_DB}"
export SIZE="--max-filesize=268435456"   # 256MB
export SIZE="--max-filesize=99999999"    # 99MB
export SYMLINKS="--follow-dir-symlinks=0 --follow-file-symlinks=0"
export BYTECODE_TO="--bytecode-timeout=180000" # 180 seconds - default 60 seconds
export CLAM_OUT="--suppress-ok-results --stdout"
export OPTIONS="${SIZE} --scan-swf=no ${CLAM_OUT} ${DATABASE} ${EXCLUDE_DIR} ${SYMLINKS} ${BYTECODE_TO}"

# Test Scan - uncomment to use
#export EXCLUDE_DIR="--exclude-dir=\"^/dev/|^/devices/|^/mnt/|^/kernel/|^/platform/|^/rmdisk/|^/export/sybase/data/|^/cdrom/|^/proc/|^/system/object/|^/var/tmp/|^/vol/\" --exclude-dir=\"^/export/sybase/test_clam/exclude_dir/\""
#export SIZE="--max-filesize=1048576"     #   1MB
#export OPTIONS="${SIZE} --scan-swf=no --stdout ${DATABASE} ${EXCLUDE_DIR} --follow-dir-symlinks=0 --follow-file-symlinks=0"

# Build the command to use
export CMD="${NICE} ${CLAMSCAN} ${OPTIONS} -r"

# ********************************************************************
# Usage
# ********************************************************************
usage() {
echo "
Usage: wg_clamscan

    wg_clamscan is a simple clamscan wrapper used to scan the SCADACOM server for viruses.
    There are no parameters for this wrapper script.

    Script: ${CLAM_WRAPPER} Ver:${CLAM_WRAPPER_VER} Date:${CLAM_WRAPPER_DATE}
    ClamAV Engine: `${CLAMSCAN} --version`
    ClamAV Databases: ${CLAM_DB}
`ls -l ${CLAM_DB}`

    The ClamAV databases can be updated from:
      http://database.clamav.net/main.cvd
      http://database.clamav.net/daily.cvd
      http://database.clamav.net/bytecode.cvd

    Options Set:
    ${OPTIONS}

    Typical crontab for root user:

0 3 * * * /var/lib/clamav/wg_clamscan.sh

    The following command can be used to determine which file is being scanned
    while [ 1 ];do;/usr/local/bin/lsof -p `ps -ef|grep clam|grep max-file|awk '{print $2}'`|grep -v clamav|tail -1;sleep 5;done

"
   exit 1;
}

start_logs() {
    echo "*********************************************************************************"
    echo "*** Start clamscan: "`date`
    echo "*** Server: "`uname -n`" Using CPUs: ${NUM_CPU}"
    echo "*** Script: ${CLAM_WRAPPER}"
    echo "*** ScriptVer: ${CLAM_WRAPPER_VER} Date: ${CLAM_WRAPPER_DATE} Sum: "`sum ${CLAM_WRAPPER}|awk '{print($1" "$2)}'`
    echo "*** Engine: "`$CLAMSCAN --version`
    echo "*** ClamAV Databases: ${CLAM_DB}"
    ls -l ${CLAM_DB}
}

scan() {
    # Add the directory to the command
    export CMD="${CMD} ${1}"

    # ********************************************************************
    # Execute the virus scan
    # ********************************************************************
    echo "*********************************************************************************"
    echo "*** Processing Directory: ${1} using CPU(${2}) at "`date "+%Y.%m.%d_%H:%M:%S"`
    echo "*** Command: ${CMD}"
    echo "*********************************************************************************"
    ${CMD} 2>&1 |egrep -v "Empty file|Symbolic link|RFC2047|submit it to www.clamav.net|: Excluded"
    echo "*********************************************************************************"
    echo "*** Finished Directory: ${1} using CPU(${2}) at "`date "+%Y.%m.%d_%H:%M:%S"`
    echo "*********************************************************************************"
}

stop_logs() {
    echo "*********************************************************************************"
    echo "*** Finishing clamscan at :"`date`" on Server:"`uname -n`
    echo "*********************************************************************************"
}

check_cpu() { 
    while :; do
        # echo "Processes remaining: $*"
        for pid in "$@"; do
            shift
            if kill -0 "$pid" 2>/dev/null; then
                set -- "$@" "$pid"
            elif wait "$pid"; then
                echo "$pid exited with zero exit status."
            else
                echo "$pid exited with non-zero exit status."
            fi
        done
        PIDS=$@
        (("$#" >= "${NUM_CPU}" )) || break
        sleep 5
    done
}

# ********************************************************************
# Main
# ********************************************************************
if [ $# -gt 0 ]; then usage; fi

# ********************************************************************
# Kill the CodeMeter software - it will restart in less than a minute
# via crontab. This is done to ensure system resources are freed for
# the clamscan.
# ********************************************************************
(
    echo ""
    echo "*********************************************************************************"
    echo "*** Restarting CodeMeter at: "`date`
    echo "*********************************************************************************"
    pkill CodeMeter
    start_logs
    echo "*** Directories to be processed" 
    export DIRS=`ls -d /*|egrep -v "^/cdrom|^/boot|^/dev|^/devices|^/rmdisk|^/lost\+found|^/platform|^/proc|^/vol|^/mnt|^/net"`
    export SORT_DIRS=`du -s ${DIRS}| sort -rn |sed -e 's/^[0-9]*//' -e 's/^ *//g'`
    for DIR in ${SORT_DIRS}
    do
        echo "${DIR}"
    done
    for DIR in ${SORT_DIRS}
    do
        # start a virus scan and check CPUs versus existing processes running
        ((i=i%NUM_CPU)); export CPU=$i; ((i++==0))
        scan ${DIR} ${CPU} &
        PIDS="${PIDS} $!"
        check_cpu ${PIDS}
        sleep 10
    done
    # Wait until all forks (jobs) are done
    echo "*** No new jobs - waiting for existing ones to finish"
    wait < <(jobs -p)
    stop_logs
) >> ${LOG} 2>&1
