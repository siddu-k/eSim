#!/bin/bash
#==========================================================
#          FILE: install-nghdl-25.04.sh
#
#         USAGE: ./install-nghdl.sh --install   (called by the dispatcher)
#
#   DESCRIPTION: Installs NGHDL on Ubuntu 25.04:
#                GHDL 4.1.0 (LLVM backend) + Verilator 4.210 + ngspice 35.
#
#  Differences from install-nghdl-24.04.sh (each marked [FIX n]):
#
#    [FIX 1] LLVM: Ubuntu 25.04 ships LLVM/Clang 20. GHDL 4.1.0's configure
#            aborts with "Unhandled version llvm 20.1.2". Install llvm-18 and
#            build against /usr/bin/llvm-config-18.
#    [FIX 2] libcanberra-gtk-module no longer exists on 25.04; only the
#            gtk3 variant is available.
#    [FIX 3] ngspice 35 needs a complete build dependency set (the 24.04
#            script relied on a desktop image already having it). Use
#            libncurses-dev (libncurses5-dev is only a virtual alias now).
#    [FIX 4] Fail early with an actionable message if llvm-config-18 is
#            missing, instead of a confusing GHDL configure error.
#    [FIX 5] Remove the packager's stale Verilator build state before
#            configure (the shipped tarball contains config.status and a
#            Makefile with /home/avinash paths).
#    [FIX 6] `cd $pwd` in createSoftLink() is a typo (empty variable); use the
#            saved source directory instead.
#==========================================================

nghdl="nghdl-simulator"
ghdl="ghdl-4.1.0"
verilator="verilator-4.210"
llvm_config="/usr/bin/llvm-config-18"     # [FIX 1]
config_dir="$HOME/.nghdl"
config_file="config.ini"
src_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # nghdl/ root
cd "$src_dir" || exit 1

# Will be used to take backup of any file
sysdate="$(date)"
timestamp=$(echo "$sysdate" | awk '{print $3"_"$2"_"$6"_"$4 }')


# All functions go here

error_exit() {
    echo -e "\n\nError! Kindly resolve above error(s) and try again."
    echo -e "\nAborting Installation...\n"
}

on_error() {
    local rc=$?
    echo -e "\n[NGHDL] FAILED at line $LINENO: $BASH_COMMAND (exit $rc)" >&2
    error_exit
}


function installDependency
{

    echo "Installing dependencies for $ghdl LLVM............"

    echo "Installing Make..........................................."
    sudo apt-get install -y make

    echo "Installing GNAT (Ada compiler).........................."
    sudo apt-get install -y gnat

    # GHDL's LLVM backend compiles src/ortho/llvm6/llvm-cbindings.cpp with
    # clang++; llvm-18-dev does not pull a C++ compiler in.
    echo "Installing Clang (C++ compiler for the LLVM bindings)....."
    sudo apt-get install -y clang

    # [FIX 1] GHDL 4.1.0 does not support LLVM 20. Use the 18 series.
    echo "Installing LLVM 18 (GHDL-supported version)............."
    sudo apt-get install -y llvm-18 llvm-18-dev

    # [FIX 4] Fail here, with a clear message, rather than inside GHDL.
    if [ ! -x "$llvm_config" ]; then
        echo "ERROR: $llvm_config not found after installing llvm-18-dev." >&2
        echo "       GHDL 4.1.0 cannot be built without it." >&2
        return 1
    fi
    echo "Using LLVM: $("$llvm_config" --version) at $llvm_config"

    echo "Installing Zlib1g-dev....................................."
    sudo apt-get install -y zlib1g-dev

    # [FIX 2] libcanberra-gtk-module was removed in Ubuntu 25.04.
    echo "Installing Gtk Canberra modules (gtk3 only)..............."
    sudo apt-get install -y libcanberra-gtk3-module

    # Specific dependency for nvidia graphic cards
    echo "Installing graphics dependency for Ngspice source build"
    echo "Installing libxaw7........................................"
    sudo apt-get install -y libxaw7

    echo "Installing libxaw7-dev...................................."
    sudo apt-get install -y libxaw7-dev

    echo "Installing dependencies for $verilator...................."
    if command -v apt >/dev/null 2>&1; then
        sudo apt-get install -y make autoconf g++ flex bison
    else
        sudo yum install -y make autoconf flex bison which
        sudo yum groupinstall -y 'Development Tools'
    fi

    # [FIX 3] ngspice 35 build dependencies. libncurses-dev is the real
    # package on 25.04 (libncurses5-dev only resolves as a virtual alias).
    echo "Installing dependencies for ngspice (with OSDI)..........."
    sudo apt-get update
    sudo apt-get install -y \
        build-essential \
        autoconf \
        automake \
        libtool \
        pkg-config \
        flex \
        bison \
        libreadline-dev \
        libncurses-dev \
        libxaw7 \
        libxaw7-dev \
        libx11-dev
}



function installGHDL
{

    echo "Installing $ghdl LLVM................................."
    tar xf $ghdl.tar.gz
    echo "$ghdl successfully extracted"
    echo "Changing directory to $ghdl installation"
    cd $ghdl/ || return 1
    echo "Configuring $ghdl build as per requirements"
    chmod +x configure
    # [FIX 1] Explicit LLVM 18 config; GHDL 4.1.0 rejects LLVM 20.
    ./configure --with-llvm-config="$llvm_config"
    echo "Building the install file for $ghdl LLVM"
    make -j"$(nproc)"
    sudo make install
    sudo ldconfig
    hash -r

    echo "GHDL installed successfully"
    cd ../
}


function installVerilator
{

    echo "Installing $verilator......................."
    tar -xf $verilator.tar.xz
    echo "$verilator successfully extracted"
    echo "Changing directory to $verilator installation"
    cd $verilator || return 1

    # [FIX 5] The repacked tarball ships config.status / src/Makefile from a
    # build in /home/avinash. configure normally rewrites them, but removing
    # them makes the build deterministic on any machine.
    rm -f config.status src/Makefile src/Makefile_obj include/verilated.mk

    echo "Configuring $verilator build as per requirements"
    chmod +x configure
    ./configure
    make -j"$(nproc)"
    sudo make install
    hash -r

    echo "Removing the unessential verilator files........"
    rm -rf docs examples include test_regress bin
    ls -1 | grep -E -v 'config.status|configure.ac|Makefile.in|verilator.1|configure|Makefile|src|verilator.pc' | xargs -r rm -f

    echo "Verilator installed successfully"
    cd ../
}


function installNGHDL
{

    echo "Installing NGHDL........................................"

    # Extracting NGHDL to Home Directory
    cd "$src_dir" || return 1
    tar -xJf "$nghdl-source.tar.xz" -C "$HOME"
    mv "$HOME/$nghdl-source" "$HOME/$nghdl" 2>/dev/null || true

    echo "NGHDL extracted successfully to $HOME"
    cd "$HOME/$nghdl" || return 1
    mkdir -p install_dir
    mkdir -p release
    cd release || return 1
    echo "Configuring NGHDL..........."
    sleep 2

    chmod +x ../configure
    ../configure --enable-xspice --disable-debug \
        --prefix="$HOME/$nghdl/install_dir/" \
        --exec-prefix="$HOME/$nghdl/install_dir/"

    make -j"$(nproc)"
    make install

    sudo chmod 755 "$HOME/$nghdl/install_dir/bin/ngspice"

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    echo "Removing previously installed Ngspice (if any)"
    sudo apt-get purge -y ngspice

    echo "NGHDL installed successfully"
    echo "Adding softlink for the installed Ngspice"

    sudo rm -f /usr/bin/ngspice

    set -e      # Re-enable exit on error
    trap on_error ERR

    sudo ln -sf "$HOME/$nghdl/install_dir/bin/ngspice" /usr/bin/ngspice
    echo "Added softlink for Ngspice....."
    hash -r

}


function createConfigFile
{
    # Creating config.ini file and adding configuration information
    mkdir -p "$config_dir"
    rm -f "$config_dir/$config_file"
    touch "$config_dir/$config_file"

    echo "[NGHDL]" >> "$config_dir/$config_file"
    echo "NGHDL_HOME = $HOME/$nghdl" >> "$config_dir/$config_file"
    echo "DIGITAL_MODEL = %(NGHDL_HOME)s/src/xspice/icm" >> "$config_dir/$config_file"
    echo "RELEASE = %(NGHDL_HOME)s/release" >> "$config_dir/$config_file"
    echo "[SRC]" >> "$config_dir/$config_file"
    echo "SRC_HOME = $src_dir" >> "$config_dir/$config_file"
    echo "LICENSE = %(SRC_HOME)s/LICENSE" >> "$config_dir/$config_file"
}


function createSoftLink
{
    # Make it executable
    sudo chmod 755 "$src_dir/src/ngspice_ghdl.py"

    # Creating softlink
    if [[ -L /usr/local/bin/nghdl ]]; then
        echo "Symlink was already present"
        sudo unlink /usr/local/bin/nghdl
    fi

    sudo ln -sf "$src_dir/src/ngspice_ghdl.py" /usr/local/bin/nghdl
    echo "Added softlink for NGHDL....."
}


#####################################################################
#       Script start from here                                      #
#####################################################################

### Checking if file is passed as argument to script

if [ "$#" -eq 1 ]; then
    option=$1
else
    echo "USAGE : "
    echo "./install-nghdl.sh --install"
    exit 1
fi

## Checking flags
if [ "$option" == "--install" ]; then

    set -e  # Set exit option immediately on error
    set -E  # inherit ERR trap by shell functions

    # Trap on function error_exit before exiting on error
    trap on_error ERR

    # Calling functions
    installDependency
    installGHDL
    installVerilator
    installNGHDL
    createConfigFile
    createSoftLink

elif [ "$option" == "--uninstall" ]; then
    sudo rm -rf "$HOME/$nghdl" "$HOME/.nghdl" \
        /usr/share/kicad/library/eSim_Nghdl.lib \
        /usr/local/bin/nghdl /usr/bin/ngspice

    echo "Removing GHDL......................"
    if [ -d "$ghdl/" ]; then
        cd $ghdl/
        sudo make uninstall || true
        cd ../
        sudo rm -rf $ghdl/
    fi

    echo "Removing Verilator................."
    if [ -d "$verilator/" ]; then
        cd $verilator/
        sudo make uninstall || true
        cd ../
        sudo rm -rf $verilator/
    fi

    echo "Removing libxaw7-dev..............."
    sudo apt-get purge -y libxaw7-dev
    echo "Removing LLVM 18..................."
    sudo apt-get purge -y llvm-18 llvm-18-dev
    echo "Removing GNAT......................"
    sudo apt-get purge -y gnat
else
    echo "Please select the proper operation."
    echo "--install"
    echo "--uninstall"
fi
