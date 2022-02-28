#!/bin/bash
# ********************************************************************
# (c) 2022 Skynet Consulting Ltd. 
# ********************************************************************
# Description:
#   This script audits the security of the system and optionally 
#   applies the recommended security patches and fixes.
# ********************************************************************

# ********************************************************************
# Definitions 
# ********************************************************************
export SCRIPT=`basename $0`
export LOG_DIR=${HOME}/openscap_log
export LOG=${LOG_DIR}/${SCRIPT}.log
export OPENSCAP_PROFILE_L1=xccdf_org.ssgproject.content_profile_cis_server_l1
export OPENSCAP_PROFILE_L2=xccdf_org.ssgproject.content_profile_cis
export OPENSCAP_XML=/usr/share/xml/scap/ssg/content/ssg-rhel8-ds.xml

# ********************************************************************
# Usage
# ********************************************************************
usage() {
    echo "
Usage: ${SCRIPT}

    This script is used for RHEL8 security audit and patching.
    Ref: https://www.open-scap.org/

    -f)     Fix RHEL8 / CentOS 8 package installation
    -u)     Update RHEL8 / CentOS8 O/S via 'yum update'
    -i)     Install the OpenSCAP packages
    -11)    Execute the OpenSCAP packages - Level 1
    -12)    Execute the OpenSCAP packages - Level 2
    -v)     Print the OpenSCAP version info
"
    exit 1
}

# ********************************************************************
# Fix RHEL 8 / CentOS 8 - error to update RPM packages
#
# Error: Failed to download metadata for repo 'appstream': Cannot prepare internal mirrorlist: No URLs in mirrorlist
# https://stackoverflow.com/questions/70963985/error-failed-to-download-metadata-for-repo-appstream-cannot-prepare-internal
# ********************************************************************
fix_rhel8_error() {
    echo "*** Fixing RHEL8/CentOS8 - allowing the updatings at `date` ***"
    wget 'http://mirror.centos.org/centos/8-stream/BaseOS/x86_64/os/Packages/centos-gpg-keys-8-3.el8.noarch.rpm'
    sudo rpm -i 'centos-gpg-keys-8-3.el8.noarch.rpm'
    dnf --disablerepo '*' --enablerepo=extras swap centos-linux-repos centos-stream-repos
    sudo dnf distro-sync
}

# ********************************************************************
# Register RHEL subscription
# This has already been automated in the RHEL deployment script
# ********************************************************************
rhel_subscription() {
    echo "*** RHEL subscription manager register/attach at `date` ***"
    sudo /usr/sbin/subscription-manager register
    sudo /usr/sbin/subscription-manager attach
}

# ********************************************************************
# Update RHEL
# ********************************************************************
update_rhel() {
    echo "*** Updated RHEL/CentOS 8 at `date` ***"
    sudo yum update -y
}

# ********************************************************************
# Install Openscap packages needed to assess and benchmark the server
# ********************************************************************
install_openscap() {
    echo "*** Installing Openscap at `date` ***"
    sudo yum install -y openscap openscap-scanner scap-security-guide -y
}

# ********************************************************************
# Openscap version info
# ********************************************************************
openscap_version() {
    echo "*** Openscap Version at `date` ***"
    oscap --version
}

# ********************************************************************
# Execute Openscap 
# ********************************************************************
execute_openscap() {
    echo "*** Executing Openscap at `date` ***"

    # Generate initial results
    oscap xccdf eval --fetch-remote-resources --profile ${OPENSCAP_PROFILE} --results scan_results_initial.xml \
       --report scan_report1.html ${OPENSCAP_XML}

    # Baseline System - remediate issues based on the report
    # There are some issues which cannot be remediate automatically
    # 1.  File system mounted as separate patition
    # 2.  Remediation involving Firewall zone names
    # 3.  Recommendations relating to GRUB
    oscap xccdf eval --remediate --profile ${OPENSCAP_PROFILE} --report remediate_report_baseline.html ${OPENSCAP_XML}

    # Generate the ansible and bash scripts that can be used for remediation
    oscap xccdf generate fix --fix-type ansible --output PlaybookToRemediate.yml --result-id "" scan_results_initial.xml
    oscap xccdf generate fix --fix-type bash --output PlaybookToRemediate.sh --result-id "" scan_results_initial.xml

    # report will include some false positives as the system needs to be rebooted for some of the 
    # remediation configuration to take effect
    oscap xccdf eval --fetch-remote-resources --profile ${OPENSCAP_PROFILE} --results scan_results_rem.xml \
        --report scan_report_after_remediation.html ${OPENSCAP_XML}

    echo "*** Finished Openscap at `date` ***"
}

# ********************************************************************
# Check root user
# ********************************************************************
check_root_user () {
    if [ $LOGNAME != "root" ]; then
        echo "You must be the root user to execute this script! Currently: $LOGNAME"
        exit 1
    fi
}

# ********************************************************************
# Main
# ********************************************************************
export FIX_RHEL8_ERROR=0
export UPDATE_RHEL8=0
export INSTALL_OPENSCAP=0
export EXECUTE_OPENSCAP=0
export OPENSCAP_VERSION=0

# Check the user and then process the parameters
check_root_user
if [ $# -eq 0 ]; then usage; fi
case "$1" in 
    -f)     export FIX_RHEL8_ERROR=1; shift;;
    -u)     export UPDATE_RHEL8=1; shift;;
    -i)     export INSTALL_OPENSCAP=1; shift;;
    -l1)    export OPENSCAP_PROFILE=${OPENSCAP_PROFILE_L1}; EXECUTE_OPENSCAP=1; OPENSCAP_VERSION=1; shift;;
    -l2)    export OPENSCAP_PROFILE=${OPENSCAP_PROFILE_L2}; EXECUTE_OPENSCAP=1; OPENSCAP_VERSION=1; shift;;
    -v)     export OPENSCAP_VERSION=1; shift;;
    *)      usage; shift;;
esac

mkdir -p ${LOG_DIR}
cd ${LOG_DIR}

# Use the subshell to capture the stdout and stderr output, and tee the output to the screen and file
(
    echo "*** Start ${SCRIPT} at `date` on server:`uname -n`" 

    if [ ${FIX_RHEL8_ERROR} -eq 1 ];  then fix_rhel8_error; fi
    if [ ${UPDATE_RHEL8}    -eq 1 ];  then update_rhel; fi
    if [ ${INSTALL_OPENSCAP} -eq 1 ]; then install_openscap; fi
    if [ ${OPENSCAP_VERSION} -eq 1 ]; then openscap_version; fi
    if [ ${EXECUTE_OPENSCAP} -eq 1 ]; then execute_openscap; fi

    echo "*** Finished ${SCRIPT} at `date`. Please see log files at ${LOG}"
) | tee ${LOG} 2>&1
