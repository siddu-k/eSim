#!/bin/bash
#==========================================================
#          FILE: install-nghdl.sh
#
#         USAGE: ./install-nghdl.sh --install
#                            OR
#                ./install-nghdl.sh --uninstall
#
#   DESCRIPTION: Installation script for Ngspice, GHDL
#                and Verilator simulators (NGHDL)
#
#  Modified for Ubuntu 25.04. The only functional change in this dispatcher
#  is the added version case (and reading the version from /etc/os-release
#  instead of lsb_release). See Ubuntu/REPORT.md.
#==========================================================

# Function to detect Ubuntu version, without depending on lsb_release.
get_ubuntu_version() {
    if [ ! -r /etc/os-release ]; then
        echo "Cannot read /etc/os-release - is this Ubuntu?" >&2
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    VERSION_ID="${VERSION_ID:-}"
    FULL_VERSION="${VERSION:-$VERSION_ID}"
    FULL_VERSION="${FULL_VERSION%% *}"
    echo "Detected Ubuntu Version: ${FULL_VERSION:-unknown} (VERSION_ID=$VERSION_ID)"
}

# Function to choose and run the appropriate script
run_version_script() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-nghdl-scripts"

    case "$VERSION_ID" in
        "22.04")
            if [[ "$FULL_VERSION" == "22.04.4" ]]; then
                SCRIPT="$script_dir/install-nghdl-22.04.sh"
            else
                SCRIPT="$script_dir/install-nghdl-23.04.sh"
            fi
            ;;
        "23.04")
            SCRIPT="$script_dir/install-nghdl-23.04.sh"
            ;;
        "24.04")
            SCRIPT="$script_dir/install-nghdl-24.04.sh"
            ;;
        "25.04")
            SCRIPT="$script_dir/install-nghdl-25.04.sh"
            ;;
        "25.10")
            echo "Ubuntu 25.10 detected: using the 25.04 profile (closest tested release)."
            SCRIPT="$script_dir/install-nghdl-25.04.sh"
            ;;
        *)
            if [ -n "${ESIM_FORCE_PROFILE:-}" ]; then
                echo "Unsupported Ubuntu $VERSION_ID - forcing profile $ESIM_FORCE_PROFILE."
                SCRIPT="$script_dir/install-nghdl-${ESIM_FORCE_PROFILE}.sh"
            else
                echo "Unsupported Ubuntu version: $VERSION_ID ($FULL_VERSION)"
                echo "Supported: 22.04, 23.04, 24.04, 25.04 and 25.10."
                echo "Override with: ESIM_FORCE_PROFILE=25.04 ./install-nghdl.sh --install"
                exit 1
            fi
            ;;
    esac

    if [[ -f "$SCRIPT" ]]; then
        echo "Running script: $SCRIPT $ARGUMENT"
        bash "$SCRIPT" "$ARGUMENT"
    else
        echo "Installation script not found: $SCRIPT" >&2
        exit 1
    fi
}

# --- Main Execution Starts Here ---

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 --install | --uninstall"
    exit 1
fi

ARGUMENT=$1
if [[ "$ARGUMENT" != "--install" && "$ARGUMENT" != "--uninstall" ]]; then
    echo "Invalid argument: $ARGUMENT"
    echo "Usage: $0 --install | --uninstall"
    exit 1
fi

get_ubuntu_version
run_version_script
