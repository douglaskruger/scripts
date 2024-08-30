#!/bin/ksh
# ***************************************
# Execute this script as the sybase UNIX user
# ***************************************
export NAME=`uname -n`
gather_info() {
    echo "*** Gathering Server Information for ${NAME} on "`date`
    echo "*** Solaris info"
    cat /etc/release
    echo "*** Package info"
    pkginfo -l
    echo "*** Sybase License info"
    ls -l /export/sybase/SYSAM-2_0/licenses/*.lic
    cat /export/sybase/SYSAM-2_0/licenses/*.lic
    echo "*** Sybase Property info"
    ls -l /export/sybase/ASE-15_0/sysam/*.properties
    cat /export/sybase/ASE-15_0/sysam/*.properties
    echo "*** Sybase Sysamcap - Machine"
    /export/sybase/SYSAM-2_0/bin/sysamcap -v MACHINE
    echo "*** Sybase Sysamcap - Partition"
    /export/sybase/SYSAM-2_0/bin/sysamcap -v PARTITION
    echo "*** Unix env"
    env
    echo "*** Unix zoneadm"
    zoneadm list -cv
    echo "*** iSQL"
    isql -Usa -Pscadacom -w300 << EOF
sp_helpdb
go
sp_helpdevice
go
EOF
    echo "*** Finished Gathering Server Information for ${NAME} on "`date`
}

# Main 
echo "*** Gathering Server Information for ${NAME} on "`date`
gather_info >/tmp/${NAME}_info.txt 2>&1
gzip /tmp/${NAME}_info.txt
echo "*** Finished Gathering Server Information for ${NAME} on "`date`
echo "Please pass the /tmp/${NAME}_info.txt.gz" 
