#!/bin/bash
################################################################################
# SPDX-License-Identifier: Apache-2.0
# Copyright 2017 Massachusetts Institute of Technology.
################################################################################

# Configure the installer here
KEYLIME_GIT=https://github.com/keylime/keylime.git
TPM2TSS_GIT=https://github.com/tpm2-software/tpm2-tss.git
TPM2TOOLS_GIT=https://github.com/tpm2-software/tpm2-tools.git
TPM2SIM_SRC=http://sourceforge.net/projects/ibmswtpm2/files/ibmtpm1119.tar.gz/download
KEYLIME_VER="master"
TPM4720_VER="master"
TPM2TSS_VER="3.2.x"
TPM2TOOLS_VER="5.1.X"

# Minimum version requirements
MIN_PYTHON_VERSION="3.6.7"
MIN_PYSETUPTOOLS_VERSION="0.7"
MIN_PYTORNADO_VERSION="4.3"
MIN_PYZMQ_VERSION="14.4"
MIN_PYCRYPTOGRAPHY_VERSION="2.1.4"

# default variables
CENTOS7_TSS_FLAGS=
NEED_BUILD_TOOLS=0
NEED_PYTHON_DIR=0
PYTHON_PIPS=
TPM2_TOOLS_PKGS=
NEED_EPEL=0
POWERTOOLS=

# Check to ensure version is at least minversion
version_checker () {
    newest=$( printf "$1\n$2" | sort -V | tail -n1 )
    [[ "$1" == "$2" || "$1" != "$newest" ]]
}

confirm_force_install () {
    echo $1
    read -r -p "This may introduce security issues, instability or an incomplete install!  Continue? [y/N] " resp
    case "$resp" in
        [yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# Determine distibution (using systemd standard `os-release`):
if [ -f /etc/os-release ]; then
        . /etc/os-release
    else
        echo "Not able to determine your OS or Distribution"
        exit 1
fi

case "$ID" in
    debian | ubuntu)
        echo "${ID} selected."
        PACKAGE_MGR=$(command -v apt-get)
        PYTHON_PREIN="git patch"
        PYTHON_DEPS="python3 python3-pip python3-dev python3-setuptools python3-zmq python3-tornado python3-cryptography python3-requests python3-psutil gcc g++ libssl-dev swig python3-yaml python3-gnupg python3-lark wget python3-alembic" 
        if [ "$(uname -m)" = "x86_64" ]; then
            PYTHON_DEPS+=" libefivar-dev"
        fi
        BUILD_TOOLS="build-essential libtool automake pkg-config m4 libgcrypt20-dev uthash-dev autoconf autoconf-archive libcurl4-gnutls-dev gnulib doxygen libdbus-1-dev uuid-dev libjson-c-dev"
        $PACKAGE_MGR update
        case "${VERSION_ID}" in
          # Ubuntu 18.04, Debian 9 and 10 don't ship with a new enough version of tpm2-tools/tpm2-tss
          18.04 | 9 | 10 )
            NEED_BUILD_TOOLS=1
          ;;
          *)
            TPM2_TOOLS_PKGS="tpm2-tools tss2"
            NEED_BUILD_TOOLS=0
          ;;
        esac
    ;;

    rhel | centos)
        case "${VERSION_ID}" in
            7*)
                echo "${ID} ${VERSION_ID} selected."
                PACKAGE_MGR=$(command -v yum)
                NEED_EPEL=1
                PYTHON_PREIN="python36 python36-devel python36-setuptools python36-pip git wget patch openssl"
                PYTHON_DEPS="gcc gcc-c++ openssl-devel swig python36-PyYAML python36-tornado python36-cryptography python36-requests python36-zmq yaml-cpp-devel python3-psutil python3-alembic"
                if [ "$(uname -m)" = "x86_64" ]; then
                    PYTHON_DEPS+=" efivar-libs"
                fi
                BUILD_TOOLS="openssl-devel file libtool make automake m4 libgcrypt-devel autoconf autoconf-archive libcurl-devel libstdc++-devel uriparser-devel dbus-devel gnulib-devel doxygen libuuid-devel json-c-devel"
                NEED_BUILD_TOOLS=1
                CENTOS7_TSS_FLAGS="--enable-esapi=no --disable-doxygen-doc"
            ;;
            8*)
                echo "${ID} ${VERSION_ID} selected."
                PACKAGE_MGR=$(command -v dnf)
                NEED_EPEL=1
                PYTHON_PREIN="python3 python3-devel python3-setuptools python3-pip"
                PYTHON_DEPS="gcc gcc-c++ openssl-devel python3-yaml python3-requests swig python3-cryptography wget git python3-tornado python3-zmq python3-gnupg python3-psutil"
                if [ "$(uname -m)" = "x86_64" ]; then
                    PYTHON_DEPS+=" efivar-libs"
                fi
                BUILD_TOOLS="git wget patch libyaml openssl-devel libtool make automake m4 libgcrypt-devel autoconf libcurl-devel libstdc++-devel dbus-devel libuuid-devel json-c-devel"
                #TPM2_TOOLS_PKGS="tpm2-tss tpm2-tools" TODO: still on 3.1.1 tpm2_tools
                NEED_BUILD_TOOLS=1
                NEED_PYTHON_DIR=1
                POWERTOOLS="--enablerepo=PowerTools install autoconf-archive"
            ;;
            *)
                echo "Version ${VERSION_ID} of ${ID} not supported"
                exit 1
        esac
    ;;

    fedora)
        echo "${ID} selected."
        PACKAGE_MGR=$(command -v dnf)
        PYTHON_PREIN="python3 python3-devel python3-setuptools git wget patch"
        PYTHON_DEPS="python3-pip gcc gcc-c++ openssl-devel swig python3-pyyaml python3-zmq python3-cryptography python3-tornado python3-requests python3-gnupg yaml-cpp-devel procps-ng python3-psutil python3-lark-parser python3-alembic"
        if [ "$(uname -m)" = "x86_64" ]; then
            PYTHON_DEPS+=" efivar-devel"
        fi
        BUILD_TOOLS="openssl-devel libtool make automake pkg-config m4 libgcrypt-devel autoconf autoconf-archive libcurl-devel libstdc++-devel uriparser-devel dbus-devel gnulib-devel doxygen libuuid-devel json-c-devel"
        if [[ ${VERSION_ID} -ge 30 ]] ; then
        # if fedora 30 or greater, then using TPM2 tool packages
            TPM2_TOOLS_PKGS="tpm2-tools tpm2-tss tss2"
            NEED_BUILD_TOOLS=0
        else
            NEED_BUILD_TOOLS=1
        fi
    ;;

    *)
        echo "${ID} is not currently supported."
        exit 1
esac

# Command line params
STUB=0
KEYLIME_DIR=
TARBALL=0
TPM_SOCKET=0
while getopts ":shctkmp:" opt; do
    case $opt in
        k) STUB=1 ;;
        p)
            KEYLIME_DIR=$OPTARG
            # Ensure absolute path
            if [[ "$KEYLIME_DIR" != "/"* ]] ; then
                KEYLIME_DIR=`pwd`"/$KEYLIME_DIR"
            fi
            ;;
        t) TARBALL=1 ;;
        m) ;;
        s) TPM_SOCKET=1 NEED_BUILD_TOOLS=1 ;;
        h)
            echo "Usage: $0 [option...]"
            echo "Options:"
            echo $'-k \t\t\t\t Download Keylime (stub installer mode)'
            echo $'-t \t\t\t\t Create tarball with keylime_agent'
            echo $'-m \t\t\t\t Use modern TPM 2.0 libraries; this is the default'
            echo $'-s \t\t\t\t Install & use a Software TPM emulator (development only)'
            echo $'-p PATH \t\t\t Use PATH as Keylime path'
            echo $'-h \t\t\t\t This help info'
            exit
            ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
   echo -e "This script must be run as root in order to install keylime and its dependencies" 1>&2
   exit 1
fi


# Keylime python-related dependencies
echo
echo "=================================================================================="
echo $'\t\t\tInstalling python & crypto libs'
echo "=================================================================================="
if [[ "$NEED_EPEL" -eq "1" ]] ; then
	$PACKAGE_MGR -y install epel-release
	if [[ $? > 0 ]] ; then
    	echo "ERROR: EPEL package failed to install properly!"
    	exit 1
	fi
fi

$PACKAGE_MGR install -y $PYTHON_PREIN
if [[ $? > 0 ]] ; then
    echo "ERROR: Package(s) failed to install properly!"
    exit 1
fi
$PACKAGE_MGR install -y $PYTHON_DEPS
if [[ $? > 0 ]] ; then
    echo "ERROR: Package(s) failed to install properly!"
    exit 1
fi
if [[ ! -z $PYTHON_PIPS ]] ; then
    pip3 install $PYTHON_PIPS
fi


# Ensure Python is installed
if [[ ! `command -v python3` ]] ; then
    echo "ERROR: Python failed to install properly!"
    exit 1
else
    # Ensure Python installed meets min requirements
    py_ver=$(python3 -c 'import platform; print(platform.python_version())')
    if ! $(version_checker "$MIN_PYTHON_VERSION" "$py_ver"); then
        confirm_force_install "ERROR: Minimum Python version is $MIN_PYTHON_VERSION, but $py_ver is installed!" || exit 1
    fi

    # Ensure Python setuptools installed meets min requirements
    pyset_ver=$(python3 -c 'import setuptools; print(setuptools.__version__)')
    if ! $(version_checker "$MIN_PYSETUPTOOLS_VERSION" "$pyset_ver"); then
        confirm_force_install "ERROR: Minimum python-setuptools version is $MIN_PYSETUPTOOLS_VERSION, but $pyset_ver is installed!" || exit 1
    fi

    # Ensure Python tornado installed meets min requirements
    pynado_ver=$(python3 -c 'import tornado; print(tornado.version)')
    if ! $(version_checker "$MIN_PYTORNADO_VERSION" "$pynado_ver"); then
        confirm_force_install "ERROR: Minimum python-tornado version is $MIN_PYTORNADO_VERSION, but $pynado_ver is installed!" || exit 1
    fi

    # Ensure Python ZeroMQ installed meets min requirements
    pyzmq_ver=$(python3 -c 'import zmq; print(zmq.__version__)')
    if ! $(version_checker "$MIN_PYZMQ_VERSION" "$pyzmq_ver"); then
        confirm_force_install "ERROR: Minimum python-zmq version is $MIN_PYZMQ_VERSION, but $pyzmq_ver is installed!" || exit 1
    fi

    # Ensure Python cryptography installed meets min requirements
    pycrypto_ver=$(python3 -c 'import cryptography; print(cryptography.__version__)')
    if ! $(version_checker "$MIN_PYCRYPTOGRAPHY_VERSION" "$pycrypto_ver"); then
        confirm_force_install "ERROR: Minimum python-cryptography version is $MIN_PYCRYPTOGRAPHY_VERSION, but $pycrypto_ver is installed!" || exit 1
    fi

fi


# Download Keylime (if necessary)
if [[ "$STUB" -eq "1" ]] ; then
    if [[ -z "$KEYLIME_DIR" ]] ; then
        KEYLIME_DIR=`pwd`
        KEYLIME_DIR+="/keylime"
        if [[ ! -d "$KEYLIME_DIR" ]] ; then
            mkdir -p $KEYLIME_DIR
        fi
    fi

    echo
    echo "=================================================================================="
    echo $'\t\t\t\tDownloading Keylime'
    echo "=================================================================================="
    git clone $KEYLIME_GIT $KEYLIME_DIR
    pushd $KEYLIME_DIR
    git checkout $KEYLIME_VER
    popd
fi


# If all else fails, assume they already have Keylime (we're in it!)
if [[ -z "$KEYLIME_DIR" ]] ; then
    KEYLIME_DIR=`pwd`
fi


# Sanity check
if [[ ! -d "$KEYLIME_DIR/scripts" || ! -d "$KEYLIME_DIR/keylime" ]] ; then
    echo "ERROR: Invalid keylime directory at $KEYLIME_DIR"
    exit 1
fi


echo "INFO: Using Keylime directory: $KEYLIME_DIR"

# Prepare to build TPM libraries
if [[ "$NEED_BUILD_TOOLS" -eq "1" ]] ; then
    echo
    echo "=================================================================================="
    echo $'\t\t\tInstalling TPM libraries and build tools'
    echo "=================================================================================="
    # Create temp dir for building tpm
    TMPDIR=`mktemp -d` || exit 1
    echo "INFO: Using temp tpm directory: $TMPDIR"

    $PACKAGE_MGR -y install $BUILD_TOOLS
    if [[ $? > 0 ]] ; then
        echo "ERROR: Package(s) failed to install properly!"
        exit 1
    fi

    if [[ -n "${POWERTOOLS}" ]] ; then
    	$PACKAGE_MGR -y $POWERTOOLS
    	if [[ $? > 0 ]] ; then
        	echo "ERROR: Package(s) failed to install properly!"
        	exit 1
    	fi
    fi

    mkdir -p $TMPDIR/tpm
    cd $TMPDIR/tpm
fi

if [[ ! -z $TPM2_TOOLS_PKGS ]] ; then
    echo
    echo "=================================================================================="
    echo $'\t\t\t\tInstall tpm2-tools packages'
    echo "=================================================================================="
    $PACKAGE_MGR install -y $TPM2_TOOLS_PKGS
    if [[ $? > 0 ]] ; then
        echo "ERROR: Package(s) failed to install properly!"
        exit 1
    fi
else
    echo
    echo "=================================================================================="
    echo $'\t\t\t\tBuild and install tpm2-tss'
    echo "=================================================================================="
    git clone $TPM2TSS_GIT tpm2-tss
    pushd tpm2-tss
    git checkout $TPM2TSS_VER
    ./bootstrap
    if [[ -n $CENTOS7_TSS_FLAGS ]] ; then
        export PKG_CONFIG_PATH=/usr/lib/pkgconfig/
    fi
    ./configure --prefix=/usr $CENTOS7_TSS_FLAGS
    make
    make install
    ldconfig
    popd # tpm

#        if [[ ! -f /usr/lib/libtss.so ]] ; then
#            echo "ERROR: tpm2-tss failed to build and install properly!"
#            exit 1
#        fi

    echo
    echo "=================================================================================="
    echo $'\t\t\t\tBuild and install tpm2-tools'
    echo "=================================================================================="
    git clone $TPM2TOOLS_GIT tpm2-tools
    pushd tpm2-tools
    git checkout $TPM2TOOLS_VER
    ./bootstrap
    if [[ -n $CENTOS7_TSS_FLAGS ]] ; then
        export SAPI_CFLAGS=' '
        export SAPI_LIBS='-ltss2-sys -L/usr/lib/'
    fi
    ./configure --prefix=/usr/local
    make
    make install
    popd # tpm
fi

if [[ -z "$(command -v tpm2_getrandom)" ]] ; then
    echo "ERROR: Failed to build tpm2_tss/tools!"
    exit 1
fi

if [[ "$TPM_SOCKET" -eq "1" ]] ; then
    echo
    echo "=================================================================================="
    echo $'\t\t\t\tBuild and install TPM2 simulator'
    echo "=================================================================================="

    # Download and unpack swtpm2
    TMPFILE=`mktemp -t swtpm2.XXXXXXXXXX.tar.gz` || exit 1
    wget "$TPM2SIM_SRC" -O $TMPFILE
    if [[ $? -ne 0 ]] ; then
        echo "ERROR: Failed to download TPM2 simulator!"
        exit 1
    fi
    mkdir swtpm2
    tar -C ./swtpm2 -xzf $TMPFILE
    pushd swtpm2

    # Begin building and installing swtpm2
    pushd src
    make
    install -c tpm_server /usr/local/bin/tpm_server

    popd # tpm/swtpm2
fi


# Install keylime
echo
echo "=================================================================================="
echo $'\t\t\t\tInstall Keylime'
echo "=================================================================================="
cd $KEYLIME_DIR
if [[ "$NEED_PYTHON_DIR" -eq "1" ]] ; then
    mkdir -p /usr/local/lib/python3.6/site-packages/
fi
python3 -m pip install . -r requirements.txt

if [[ -f "/etc/keylime.conf" ]] ; then
    if [[ $(diff -N "/etc/keylime.conf" "keylime.conf") ]] ; then
        echo "Modified keylime.conf found in /etc/, creating /etc/keylime.conf.new instead"
        cp keylime.conf /etc/keylime.conf.new
        chmod 600 /etc/keylime.conf.new
    fi
else
    echo "Installing keylime.conf to /etc/"
    cp -n keylime.conf /etc/
    chmod 600 /etc/keylime.conf
fi

echo
echo "=================================================================================="
echo $'\t\t\t\tCheck for tpm_cert_store'
echo "=================================================================================="
if [ ! -d "/var/lib/keylime/tpm_cert_store" ]; then
  echo "Creating new tpm_cert_store"
  mkdir -p /var/lib/keylime
  cp -r $KEYLIME_DIR/tpm_cert_store /var/lib/keylime/tpm_cert_store
else
  echo "Updating existing cert store"
  cp -n $KEYLIME_DIR/tpm_cert_store/* /var/lib/keylime/tpm_cert_store/
fi

# Run agent packager (tarball)
if [[ "$TARBALL" -eq "1" ]] ; then
    echo
    echo "=================================================================================="
    echo $'\t\t\t\tGenerate agent tarball'
    echo "=================================================================================="
    cd $KEYLIME_DIR/keylime
    ./make_agent_bundle_tarball.sh ""
fi

# don't start the emulator until after keylime is installed
if [[ "$TPM_SOCKET" -eq "1" ]] ; then
    echo
    echo "=================================================================================="
    echo $'\t\t\t\tStart TPM emulator'
    echo "=================================================================================="
    # starts emulator and IMA stub at boot
    cd $KEYLIME_DIR/ima_stub_service
    ./installer.sh

    echo "=================================================================================="
    echo $'\tWARNING: Please set the env var for accessing the TPM:'
    echo $'\tTPM2TOOLS_TCTI="mssim:port=2321"'
    echo "=================================================================================="

    # disable ek cert checking
    sed -i 's/require_ek_cert = True/require_ek_cert = False/' /etc/keylime.conf
else
    # Warn that we don't use abrmd anymore.
    echo "=================================================================================="
    echo $'\tWARNING: Keylime uses /dev/tpmrm0 by default.'
    echo $'\t         If you want to use abrmd set:'
    echo $'\tTPM2TOOLS_TCTI=="tabrmd:bus_name=com.intel.tss2.Tabrmd"'
    echo "=================================================================================="
fi
