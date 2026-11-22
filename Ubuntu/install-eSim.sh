#!/bin/bash
#=============================================================================
#          FILE: install-eSim.sh
#
#         USAGE: ./install-eSim.sh --install
#                            OR
#                ./install-eSim.sh --uninstall
#
#   DESCRIPTION: Installation script for eSim EDA Suite
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#       AUTHORS: Fahim Khan, Rahul Paknikar, Saurabh Bansode,
#                Sumanto Kar, Partha Singha Roy, Jayanth Tatineni,
#                Anshul Verma, Shiva Krishna Sangati, Harsha Narayana P
#  ORGANIZATION: eSim Team, FOSSEE, IIT Bombay
#       CREATED: Wednesday 15 July 2015 15:26
#      REVISION: Ubuntu 25.04 support added (see Ubuntu/REPORT.md)
#=============================================================================
#
# Changes for Ubuntu 25.04+ (documented in Ubuntu/REPORT.md):
#   * VERSION_ID is read from /etc/os-release only. The old code shelled out
#     to `lsb_release -d` and grep'd for "X.Y.Z"; on a .0 release such as
#     25.04 that string is "Ubuntu 25.04" (two components), so FULL_VERSION
#     came out empty ("Detected Ubuntu Version: ").
#   * 25.04 dispatches to install-eSim-scripts/install-eSim-25.04.sh.
#     25.10 uses the same profile (closest tested release).
#   * The path is resolved from the script location, not $PWD, so the
#     installer also works when called as `bash Ubuntu/install-eSim.sh`.
#   * No stray config.ini writes here (the 2.5 `installers` branch had them
#     duplicated inside run_version_script(), where $config_dir is unset, so
#     they tried to append to /config.ini and failed with "Permission denied").
#=============================================================================

# Function to detect Ubuntu version, without depending on lsb_release.
get_ubuntu_version() {
    if [ ! -r /etc/os-release ]; then
        echo "Cannot read /etc/os-release - is this Ubuntu?" >&2
        exit 1
    fi
    # shellcheck disable=SC1091
    . /etc/os-release
    VERSION_ID="${VERSION_ID:-}"
    # VERSION looks like "25.04 (Plucky Puffin)" or "24.04.1 LTS"
    FULL_VERSION="${VERSION:-$VERSION_ID}"
    FULL_VERSION="${FULL_VERSION%% *}"
    echo "Detected Ubuntu Version: ${FULL_VERSION:-unknown} (VERSION_ID=$VERSION_ID)"
}

# Function to choose and run the appropriate script
run_version_script() {
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-eSim-scripts"

    case "$VERSION_ID" in
        "22.04")
            if [[ "$FULL_VERSION" == "22.04.4" ]]; then
                SCRIPT="$script_dir/install-eSim-22.04.sh"
            else
                SCRIPT="$script_dir/install-eSim-23.04.sh"
            fi
            ;;
        "23.04")
            SCRIPT="$script_dir/install-eSim-23.04.sh"
            ;;
        "24.04")
            SCRIPT="$script_dir/install-eSim-24.04.sh"
            ;;
        "25.04")
            SCRIPT="$script_dir/install-eSim-25.04.sh"
            ;;
        "25.10")
            echo "Ubuntu 25.10 detected: using the 25.04 profile (closest tested release)."
            SCRIPT="$script_dir/install-eSim-25.04.sh"
            ;;
        *)
            if [ -n "${ESIM_FORCE_PROFILE:-}" ]; then
                echo "Unsupported Ubuntu $VERSION_ID - forcing profile $ESIM_FORCE_PROFILE as requested."
                SCRIPT="$script_dir/install-eSim-${ESIM_FORCE_PROFILE}.sh"
            else
                echo "Unsupported Ubuntu version: $VERSION_ID ($FULL_VERSION)"
                echo "Supported: 22.04, 23.04, 24.04, 25.04 and 25.10."
                echo "To try the 25.04 profile on a newer release anyway, run:"
                echo "    ESIM_FORCE_PROFILE=25.04 ./install-eSim.sh --install"
                exit 1
            fi
            ;;
    esac

    if [[ -f "$SCRIPT" ]]; then
        echo "Running script: $SCRIPT $ARGUMENT"
        bash "$SCRIPT" "$ARGUMENT"
    else
        echo "Installation script not found: $SCRIPT" >&2
        echo "Make sure install-eSim-scripts/ came with this archive." >&2
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
