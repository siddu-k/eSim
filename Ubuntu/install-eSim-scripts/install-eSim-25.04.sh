#!/bin/bash
#=============================================================================
#          FILE: install-eSim-25.04.sh
#
#         USAGE: ./install-eSim.sh --install     (called by the top-level script)
#
#   DESCRIPTION: Installation script for eSim EDA Suite on Ubuntu 25.04.
#
#  This file started as the FOSSEE `installers` branch version of
#  install-eSim-25.04.sh. Every change is marked with a "[FIX n]" comment so it
#  can be reviewed against Ubuntu/REPORT.md. Summary:
#
#    [FIX 1] installKicad(): no KiCad PPA and no exact version pin on 25.04.
#            Ubuntu 25.04 "universe" already ships KiCad 8.0.8, while the
#            PPA adds 8.0.9 (built against libgit2-1.8, absent from plucky)
#            and requires `add-apt-repository`. Also `exit 0` -> `return 0`:
#            exiting from inside installKicad() aborted the whole install
#            (after KiCad) on every re-run.
#    [FIX 2] copyKicadLibrary(): the user config dir was hard-coded to
#            ~/.config/kicad/6.0 although KiCad 8 is installed, so the symbol
#            table landed where KiCad 8 never looks. The version is now
#            detected, and ${KICAD6_SYMBOL_DIR} is rewritten to
#            ${KICAD8_SYMBOL_DIR} (KiCad 8 does not define the KICAD6 name).
#    [FIX 3] createDesktopStartScript(): `cp esim.desktop $HOME/Desktop/`
#            failed with "No such file or directory" on any machine without a
#            Desktop folder (fresh WSL / server images), aborting the install
#            at the last step. mkdir -p added. Software OpenGL is exported so
#            the GUI also starts inside VirtualBox / WSL.
#    [FIX 4] installDependency(): non-interactive apt (-y), Python deps are
#            installed into the venv with `python -m pip`, heavy Qt/matplotlib
#            come from apt via --system-site-packages (no duplicate wheels),
#            and optional pip packages no longer abort the whole install.
#            pyhdlparser is pinned to a commit (its `master` branch was
#            renamed upstream).
#    [FIX 5] uninstall: only eSim's own files under /usr/share/kicad are
#            removed. The old `rm -rf /usr/share/kicad` deleted KiCad's
#            standard symbol libraries.
#    [FIX 6] Robustness: resolve the eSim root from the script path, verify
#            prerequisites, log the failing line, and skip the proxy prompt
#            when stdin is not a terminal.
#    [FIX 7] `pip install hdlparse` is fatal on Ubuntu 25.04: the only PyPI
#            release (1.0.4) still declares use_2to3, which setuptools >= 58
#            rejects. pyhdlparser (already installed) provides the same
#            `hdlparse` module, so the dead package is no longer installed.
#=============================================================================

# All variables go here
config_dir="$HOME/.esim"
config_file="config.ini"
eSim_Home=""
ngspiceFlag=0
PYHDLPARSER_REF="e1153ace8ca1e25f9fb53350c41058ef8eb8dacf"   # [FIX 4]

## All functions go here

error_exit()
{
    echo -e "\n\nError! Kindly resolve above error(s) and try again."
    echo -e "\nAborting Installation...\n"
}

on_error()
{
    local rc=$?
    echo -e "\n[eSim] FAILED at line $LINENO: $BASH_COMMAND (exit $rc)" >&2
    error_exit
}

# [FIX 6] Work from the eSim root no matter where the script was invoked from.
resolve_esim_home()
{
    local here candidate
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    candidate="$(cd "$here/.." && pwd)"

    if [ -f "$candidate/VERSION" ] && [ -d "$candidate/src" ] && [ -d "$candidate/library" ]; then
        eSim_Home="$candidate"
    elif [ -f "$(pwd)/VERSION" ] && [ -d "$(pwd)/src" ] && [ -d "$(pwd)/library" ]; then
        eSim_Home="$(pwd)"
    else
        echo "Cannot find the eSim root (needs VERSION, src/ and library/)." >&2
        echo "Run ./install-eSim.sh from the extracted eSim-2.5 directory." >&2
        exit 1
    fi
    cd "$eSim_Home" || exit 1
}

function createConfigFile
{
    # Creating config.ini file and adding configuration information
    mkdir -p "$config_dir"
    rm -f "$config_dir/$config_file"
    touch "$config_dir/$config_file"

    echo "[eSim]" >> "$config_dir/$config_file"
    echo "eSim_HOME = $eSim_Home" >> "$config_dir/$config_file"
    echo "LICENSE = %(eSim_HOME)s/LICENSE" >> "$config_dir/$config_file"
    echo "KicadLib = %(eSim_HOME)s/library/kicadLibrary.tar.xz" >> "$config_dir/$config_file"
    echo "IMAGES = %(eSim_HOME)s/images" >> "$config_dir/$config_file"
    echo "VERSION = %(eSim_HOME)s/VERSION" >> "$config_dir/$config_file"
    echo "MODELICA_MAP_JSON = %(eSim_HOME)s/library/ngspicetoModelica/Mapping.json" >> "$config_dir/$config_file"
}


function installNghdl
{
    echo "Installing NGHDL..........................."
    if [ ! -d nghdl ]; then
        unzip -o nghdl.zip
    fi
    cd nghdl/ || return 1
    chmod +x install-nghdl.sh

    # Do not trap on error of any command. Let the NGHDL script handle its
    # own errors, then fail this step explicitly.
    trap "" ERR
    ./install-nghdl.sh --install
    local rc=$?
    trap on_error ERR

    if [ "$rc" -ne 0 ]; then
        echo "NGHDL installation failed (exit $rc)." >&2
        echo "NGHDL provides ngspice; eSim cannot simulate without it." >&2
        return "$rc"
    fi

    ngspiceFlag=1
    cd ../
}


function installSky130Pdk
{
    echo "Installing SKY130 PDK......................"

    if [ ! -f library/sky130_fd_pr.tar.xz ]; then
        echo "library/sky130_fd_pr.tar.xz is missing; skipping SKY130 PDK." >&2
        return 0
    fi

    # Extract the PDK
    tar -xJf library/sky130_fd_pr.tar.xz -C library

    # Remove any previous sky130-fd-pdr instance, if any
    sudo rm -rf /usr/share/local/sky130_fd_pr

    # Copy SKY130 library (eSim looks in /usr/share/local - see
    # src/kicadtoNgspice/DeviceModel.py, so keep this path)
    echo "Copying SKY130 PDK........................."
    sudo mkdir -p /usr/share/local/
    sudo mv library/sky130_fd_pr /usr/share/local/

    # Change ownership from root to the user
    sudo chown -R "$USER:$USER" /usr/share/local/sky130_fd_pr/
}


function installKicad
{
    echo "Installing KiCad..........................."
    echo "Ubuntu 25.04 detected: using the KiCad 8 packages from 'universe'."
    echo "(No PPA: its 8.0.9 build needs libgit2-1.8, which plucky does not ship.)"

    # [FIX 1] Already installed and new enough? Keep it and CONTINUE the
    # install. The old code called `exit 0` here, which silently stopped the
    # installer before NGHDL/PDK/launcher were set up.
    if dpkg -s kicad &>/dev/null; then
        local installed_version installed_major
        installed_version=$(dpkg-query -W -f='${Version}' kicad)
        installed_major=$(printf '%s' "$installed_version" | cut -d'.' -f1)
        if [ "$installed_major" -ge 8 ] 2>/dev/null; then
            echo "KiCad $installed_version is already installed (>= 8) - keeping it."
            return 0
        fi
        echo "KiCad $installed_version is older than 8; it will be upgraded."
    fi

    sudo add-apt-repository -y universe >/dev/null 2>&1 || true
    sudo apt-get update

    # [FIX 1] No version pin. kicad-libraries is a metapackage, so a failure
    # there must not abort the install of the actual application.
    if ! sudo apt-get install -y --no-install-recommends \
            kicad kicad-symbols kicad-footprints kicad-templates; then
        echo "KiCad is not available from 'universe' on this release." >&2
        echo "Falling back to the KiCad 8 PPA..." >&2
        sudo add-apt-repository -y ppa:kicad/kicad-8.0-releases
        sudo apt-get update
        sudo apt-get install -y --no-install-recommends \
            kicad kicad-symbols kicad-footprints kicad-templates
    fi
    sudo apt-get install -y --no-install-recommends kicad-libraries \
        || echo "Note: kicad-libraries metapackage unavailable; continuing."

    echo "KiCad installation completed successfully!"
}


function installDependency
{
    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    # Update apt repository
    echo "Updating apt index files..................."
    sudo apt-get update

    set -e      # Re-enable exit on error
    trap on_error ERR

    # [FIX 4] -y everywhere (the old line prompted in the middle of an
    # otherwise unattended install) and the archive helpers we rely on.
    echo "Installing virtualenv and archive tools....."
    sudo apt-get install -y \
        python3-virtualenv python3-venv python3-pip python3-full \
        unzip xz-utils rsync ca-certificates

    echo "Creating virtual environment to isolate packages "
    rm -rf "$config_dir/env"
    if command -v virtualenv >/dev/null 2>&1; then
        # [FIX 4] system site packages: use the distro's PyQt5/matplotlib
        # instead of compiling/pulling duplicate wheels into the venv.
        virtualenv --system-site-packages "$config_dir/env"
    else
        python3 -m venv --system-site-packages "$config_dir/env"
    fi

    echo "Starting the virtual env..................."
    # shellcheck disable=SC1091
    source "$config_dir/env/bin/activate"

    echo "Upgrading Pip.............................."
    python -m pip install --disable-pip-version-check --upgrade pip setuptools wheel

    echo "Installing Xterm..........................."
    sudo apt-get install -y xterm

    echo "Installing Psutil.........................."
    sudo apt-get install -y python3-psutil

    echo "Installing PyQt5..........................."
    sudo apt-get install -y python3-pyqt5

    echo "Installing Matplotlib......................"
    sudo apt-get install -y python3-matplotlib

    echo "Installing Setuptools..................."
    sudo apt-get install -y python3-setuptools

    # [FIX 4] These two are imported by the GUI (src/maker/Maker.py), so they
    # must be present; install into the venv explicitly.
    echo "Installing Watchdog........................"
    python -m pip install --disable-pip-version-check watchdog

    # [FIX 7] Do NOT `pip install hdlparse`. The only PyPI release (1.0.4,
    # 2018) has `use_2to3 = True` in setup.py, which setuptools >= 58
    # rejects: "error in hdlparse setup command: use_2to3 is invalid".
    # Ubuntu 25.04's venv seeds setuptools 75, so the old script aborted here.
    # pyhdlparser IS the maintained hdlparse: it installs the same
    # `hdlparse` module (1.0.7) that eSim imports.
    echo "Installing Pyhdlparser (provides the hdlparse module)..."
    python -m pip install --disable-pip-version-check \
        "https://github.com/hdl/pyhdlparser/tarball/$PYHDLPARSER_REF"

    # [FIX 4] CLI tools for the Makerchip/NgVeri flow. They are optional at
    # runtime: if PyPI is unreachable the GUI still installs and starts, so
    # warn instead of aborting the whole installation.
    echo "Installing Makerchip (optional)............"
    python -m pip install --disable-pip-version-check makerchip-app \
        || echo "WARNING: makerchip-app could not be installed; Makerchip tab will not work."

    echo "Installing SandPiper Saas (optional)......."
    python -m pip install --disable-pip-version-check sandpiper-saas \
        || echo "WARNING: sandpiper-saas could not be installed; TLV-to-SV conversion will not work."

    # [FIX 4] Verify what the GUI actually imports, and say so clearly.
    echo "Verifying Python modules used by the GUI..."
    python - <<'PY'
import importlib, sys
mods = ["PyQt5.QtWidgets", "PyQt5.uic", "matplotlib", "watchdog.events", "hdlparse.verilog_parser"]
bad = []
for m in mods:
    try:
        importlib.import_module(m)
        print("  OK      ", m)
    except Exception as exc:
        print("  MISSING ", m, "->", exc)
        bad.append(m)
if bad:
    print("WARNING: missing modules:", ", ".join(bad), file=sys.stderr)
PY
}


function copyKicadLibrary
{
    # Extract custom KiCad Library
    tar -xJf library/kicadLibrary.tar.xz

    # [FIX 2] Detect the KiCad config directory that actually exists instead
    # of hard-coding 6.0 while installing KiCad 8.
    local kicad_cfg="$HOME/.config/kicad" kicad_ver kicad_major
    kicad_ver=$(ls "$kicad_cfg" 2>/dev/null | grep -E '^[0-9]+\.[0-9]+$' | sort -V | tail -n 1)
    if [ -z "$kicad_ver" ]; then
        kicad_major=$(dpkg-query -W -f='${Version}' kicad 2>/dev/null | cut -d'.' -f1)
        kicad_ver="${kicad_major:-8}.0"
    fi
    kicad_major="${kicad_ver%%.*}"

    mkdir -p "$kicad_cfg/$kicad_ver"
    echo "Using KiCad config directory: $kicad_cfg/$kicad_ver"

    # Back up an existing table, then rewrite the KiCad-6 variable name to the
    # one this KiCad release defines (KICAD8_SYMBOL_DIR, KICAD9_SYMBOL_DIR...).
    if [ -f "$kicad_cfg/$kicad_ver/sym-lib-table" ]; then
        cp -f "$kicad_cfg/$kicad_ver/sym-lib-table" \
              "$kicad_cfg/$kicad_ver/sym-lib-table.bak-$(date +%Y%m%d-%H%M%S)"
    fi
    sed "s|\${KICAD6_SYMBOL_DIR}|\${KICAD${kicad_major}_SYMBOL_DIR}|g" \
        kicadLibrary/template/sym-lib-table \
        > "$kicad_cfg/$kicad_ver/sym-lib-table"
    echo "Symbol table copied to $kicad_cfg/$kicad_ver/sym-lib-table"

    # Copy KiCad symbols made for eSim
    sudo mkdir -p /usr/share/kicad/symbols
    if command -v rsync >/dev/null 2>&1; then
        sudo rsync -a kicadLibrary/eSim-symbols/ /usr/share/kicad/symbols/
    else
        sudo cp -r kicadLibrary/eSim-symbols/* /usr/share/kicad/symbols/
    fi

    # [FIX 2] Drop table entries whose file does not exist on this KiCad
    # install (the template still lists KiCad-6 era .lib files). KiCad 8
    # otherwise reports a wall of "library not found" errors at startup.
    if command -v python3 >/dev/null 2>&1; then
        python3 - "$kicad_cfg/$kicad_ver/sym-lib-table" "$kicad_major" <<'PY'
import os, re, sys
table, major = sys.argv[1], sys.argv[2]
symbols_dir = "/usr/share/kicad/symbols"
kept, dropped = [], 0
for line in open(table, encoding="utf-8"):
    m = re.search(r'\(uri "\$\{KICAD%s_SYMBOL_DIR\}/([^"]+)"\)' % major, line)
    if m and not os.path.exists(os.path.join(symbols_dir, m.group(1))):
        dropped += 1
        continue
    kept.append(line)
open(table, "w", encoding="utf-8").writelines(kept)
print("  sym-lib-table: %d stale entries removed" % dropped)
PY
    fi

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    # Remove extracted KiCad Library - not needed anymore
    rm -rf kicadLibrary

    set -e      # Re-enable exit on error
    trap on_error ERR

    # [FIX 2] Only eSim's own files are chowned; /usr/share/kicad stays owned
    # by the kicad packages. eSim rewrites its Ngveri/Nghdl libraries at
    # runtime, so the user needs write access to those files specifically.
    sudo chown "$USER:$USER" /usr/share/kicad/symbols/eSim_* 2>/dev/null || true
}


function createDesktopStartScript
{
    # Generating new esim-start.sh
    echo '#!/bin/bash' > esim-start.sh
    # [FIX 3] Software OpenGL: eSim is Qt Widgets + matplotlib and needs no
    # GPU; this removes Mesa/Zink failures in VirtualBox and WSL.
    echo ': "${LIBGL_ALWAYS_SOFTWARE:=1}"; export LIBGL_ALWAYS_SOFTWARE' >> esim-start.sh
    echo "cd \"$eSim_Home/src/frontEnd\"" >> esim-start.sh
    echo "source \"$config_dir/env/bin/activate\"" >> esim-start.sh
    echo 'exec python3 Application.py "$@"' >> esim-start.sh

    # Make it executable
    chmod 755 esim-start.sh
    # Copy esim start script
    sudo cp -vp esim-start.sh /usr/bin/esim
    # Remove local copy of esim start script
    rm esim-start.sh

    # Generating esim.desktop file
    echo "[Desktop Entry]" > esim.desktop
    echo "Version=1.0" >> esim.desktop
    echo "Name=eSim" >> esim.desktop
    echo "Comment=EDA Tool" >> esim.desktop
    echo "GenericName=eSim" >> esim.desktop
    echo "Keywords=eda-tools" >> esim.desktop
    echo "Exec=esim %u" >> esim.desktop
    echo "Terminal=true" >> esim.desktop
    echo "X-MultipleArgs=false" >> esim.desktop
    echo "Type=Application" >> esim.desktop
    getIcon="$config_dir/logo.png"
    echo "Icon=$getIcon" >> esim.desktop
    echo "Categories=Development;" >> esim.desktop
    echo "MimeType=text/html;text/xml;application/xhtml+xml;application/xml;text/plain;" >> esim.desktop
    echo "StartupNotify=true" >> esim.desktop

    # Make esim.desktop file executable
    chmod 755 esim.desktop
    # Copy desktop icon file to share applications
    sudo cp -vp esim.desktop /usr/share/applications/
    # [FIX 3] Fresh WSL/server images have no ~/Desktop.
    mkdir -p "$HOME/Desktop"
    cp -vp esim.desktop "$HOME/Desktop/"

    set +e      # Temporary disable exit on error
    trap "" ERR # Do not trap on error of any command

    # Make esim.desktop file as trusted application
    gio set "$HOME/Desktop/esim.desktop" "metadata::trusted" true 2>/dev/null || true
    # Set Permission and Execution bit
    chmod a+x "$HOME/Desktop/esim.desktop"

    # Remove local copy of esim.desktop file
    rm esim.desktop

    set -e      # Re-enable exit on error
    trap on_error ERR

    # Copying logo.png to .esim directory to access as icon
    cp -vp images/logo.png "$config_dir"
}


function uninstall_eSim
{
    echo "Removing eSim application files..........."
    sudo rm -rf "$HOME/.esim" "$HOME/Desktop/esim.desktop" \
        /usr/bin/esim /usr/share/applications/esim.desktop

    echo "Removing KiCad + eSim symbols............"
    # [FIX 5] Only eSim's own symbols. The old script ran
    # `sudo rm -rf /usr/share/kicad`, deleting KiCad's standard libraries
    # while the kicad packages still owned them.
    sudo rm -f /usr/share/kicad/symbols/eSim_*.kicad_sym \
                /usr/share/kicad/symbols/eSim_*.lib 2>/dev/null || true
    sudo apt-get purge -y kicad kicad-footprints kicad-libraries \
        kicad-symbols kicad-templates 2>/dev/null || true

    # Remove the eSim entries from each KiCad version's user symbol table.
    local d table
    for d in "$HOME"/.config/kicad/*/; do
        table="${d}sym-lib-table"
        [ -f "$table" ] || continue
        if grep -q 'eSim_' "$table"; then
            rm -f "$table"
            echo "Removed $table (it contained eSim symbol entries)"
        fi
    done

    echo "Removing Virtual env......................."
    sudo rm -rf "$config_dir/env"

    echo "Removing SKY130 PDK......................"
    sudo rm -R /usr/share/local/sky130_fd_pr 2>/dev/null || true

    echo "Removing NGHDL..........................."
    rm -rf library/modelParamXML/Nghdl/*
    rm -rf library/modelParamXML/Ngveri/*
    if [ -d nghdl/ ]; then
        cd nghdl/ || return
        chmod +x install-nghdl.sh
        ./install-nghdl.sh --uninstall || true
        cd ../
        rm -rf nghdl
    else
        echo "Cannot find \"nghdl\" directory. Please remove it manually."
    fi
}


####################################################################
#                   MAIN START FROM HERE                           #
####################################################################

### Checking if file is passed as argument to script

if [ "$#" -eq 1 ]; then
    option=$1
else
    echo "USAGE : "
    echo "./install-eSim.sh --install"
    echo "./install-eSim.sh --uninstall"
    exit 1
fi

resolve_esim_home

## Checking flags

if [ "$option" == "--install" ]; then

    set -e  # Set exit option immediately on error
    set -E  # inherit ERR trap by shell functions

    # Trap on function error_exit before exiting on error
    trap on_error ERR

    # [FIX 6] No hanging prompt when the script is driven by a wrapper,
    # CI or `ssh host './install-eSim.sh --install' < /dev/null`.
    if [ -t 0 ]; then
        echo "Enter proxy details if you are connected to internet through proxy"
        echo -n "Is your internet connection behind proxy? (y/n): "
        # Under `script` stdin is a PTY but may already be at EOF: treat EOF
        # as "no proxy" instead of tripping the ERR trap.
        read -r getProxy || getProxy="n"
    else
        echo "Non-interactive shell: assuming no proxy."
        getProxy="n"
    fi

    if [ "$getProxy" == "y" -o "$getProxy" == "Y" ]; then
        echo -n 'Proxy Hostname :'
        read -r proxyHostname
        echo -n 'Proxy Port :'
        read -r proxyPort
        echo -n "username@$proxyHostname:$proxyPort :"
        read -r username
        echo -n 'Password :'
        read -rs passwd
        echo

        unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ftp_proxy FTP_PROXY

        export http_proxy="http://$username:$passwd@$proxyHostname:$proxyPort"
        export https_proxy="$http_proxy"
        export HTTP_PROXY="$http_proxy"
        export HTTPS_PROXY="$http_proxy"
        export ftp_proxy="$http_proxy"
        export FTP_PROXY="$http_proxy"
        echo "Install with proxy"
    elif [ "$getProxy" == "n" -o "$getProxy" == "N" ]; then
        echo "Install without proxy"
    else
        echo "Please select the right option"
        exit 0
    fi

    # Calling functions
    createConfigFile
    installDependency
    installKicad
    copyKicadLibrary
    installNghdl
    installSky130Pdk
    createDesktopStartScript

    echo "-----------------eSim Installed Successfully-----------------"
    echo "Type \"esim\" in Terminal to launch it"
    echo "or double click on the \"eSim\" icon placed on the Desktop"

elif [ "$option" == "--uninstall" ]; then
    echo -n "Are you sure? It will remove eSim completely including KiCad, Makerchip, NGHDL and SKY130 PDK (y/n):"
    read -r getConfirmation
    if [ "$getConfirmation" == "y" -o "$getConfirmation" == "Y" ]; then
        uninstall_eSim
        echo -e "----------------eSim Uninstalled Successfully----------------"
    elif [ "$getConfirmation" == "n" -o "$getConfirmation" == "N" ]; then
        exit 0
    else
        echo "Please select the right option."
        exit 0
    fi
else
    echo "Please select the proper operation."
    echo "--install"
    echo "--uninstall"
fi
