#!/bin/bash

# ==============================================================================
#
# Title:        Global Proxy Manager for Ubuntu 24.04 (Hysteria Version)
# Description:  This script starts/stops a local Hysteria proxy service,
#               configures the system-wide proxy (for Docker, APT, wget, etc.),
#               and includes a test for connectivity.
# Author:       Gemini
# Version:      2.5
# Last Updated: 2025-07-26
#
# Usage:
#   sudo ./proxy.sh set
#   sudo ./proxy.sh unset
#   ./proxy.sh list
#   ./proxy.sh test
#
# Prerequisites:
#   - The 'hysteria-linux-amd64' executable must be in the same directory
#     as this script and be executable (chmod +x hysteria-linux-amd64).
#   - A 'config' file for Hysteria must be in the same directory.
#
# ==============================================================================

# --- Configuration ---
APT_PROXY_CONF="/etc/apt/apt.conf.d/99proxy.conf"
ENV_FILE="/etc/environment"
WGET_RC_FILE="/etc/wgetrc"
PID_FILE="/tmp/hysteria_proxy.pid" # Using /tmp for the PID file
PROXY_IP="127.0.0.1"
PROXY_PORT="10809"
HYSTERIA_EXEC="./hysteria-linux-amd64"
HYSTERIA_CONFIG="config.yaml"
DOCKER_PROXY_CONF_DIR="/etc/systemd/system/docker.service.d"
DOCKER_PROXY_CONF_FILE="${DOCKER_PROXY_CONF_DIR}/http-proxy.conf"

# --- Helper Functions ---

# Function to display colored messages
print_msg() {
    local color_code="$1"
    local message="$2"
    # Colors: 31=red, 32=green, 33=yellow, 34=blue
    echo -e "\n\e[${color_code}m${message}\e[0m"
}

# Function to display the script's usage instructions
show_usage() {
    print_msg 31 "Error: Invalid usage."
    echo "Please use the script as follows:"
    echo "------------------------------------------------------------"
    echo "To SET the global proxy (starts Hysteria service):"
    echo "  sudo $0 set"
    echo ""
    echo "To UNSET the global proxy (stops Hysteria service):"
    echo "  sudo $0 unset"
    echo ""
    echo "To LIST the current proxy settings:"
    echo "  $0 list"
    echo ""
    echo "To TEST the proxy connectivity:"
    echo "  $0 test"
    echo "------------------------------------------------------------"
    exit 1
}

# --- Core Functions ---

# Function to test proxy connectivity
test_proxy() {
    local PROXY_URL="http://${PROXY_IP}:${PROXY_PORT}"
    print_msg 34 "Testing proxy connectivity to https://www.google.com..."

    # Check if Hysteria service is running before testing
    if ! [ -f "${PID_FILE}" ] || ! ps -p "$(cat "${PID_FILE}")" > /dev/null; then
        print_msg 31 "FAILURE: Hysteria service is not running. Please start it with 'sudo $0 set'."
        return 1
    fi

    print_msg 33 "Note: This test may be blocked depending on your network location (Foshan, China)."

    local http_code
    # Use curl with specific options for a reliable, non-interactive test
    http_code=$(curl -x "${PROXY_URL}" -k -s -I -o /dev/null -w '%{http_code}' --max-time 10 "https://www.google.com")
    local curl_exit_code=$?

    if [ ${curl_exit_code} -ne 0 ]; then
        print_msg 31 "FAILURE: curl command failed (Exit Code: ${curl_exit_code}). The proxy server may be down or unreachable."
    elif [ "$http_code" = "200" ] || [ "$http_code" = "301" ] || [ "$http_code" = "302" ]; then
        print_msg 32 "SUCCESS: Connection via proxy successful (HTTP Status: ${http_code})."
    else
        print_msg 31 "FAILURE: Could not connect via proxy (HTTP Status: ${http_code})."
        print_msg 31 "         Check your Hysteria config, network, or firewall settings."
    fi
}

# Function to set the global proxy
set_proxy() {
    local PROXY_URL_WITH_SLASH="http://${PROXY_IP}:${PROXY_PORT}/"
    local NO_PROXY_LIST="localhost,127.0.0.1,::1"

    # 1. Start Hysteria Service
    print_msg 34 "Starting Hysteria proxy service..."
    if [ -f "${PID_FILE}" ] && ps -p "$(cat "${PID_FILE}")" > /dev/null; then
        print_msg 33 "Hysteria service is already running (PID: $(cat "${PID_FILE}"))."
    else
        if ! [ -x "${HYSTERIA_EXEC}" ]; then
            print_msg 31 "Error: Hysteria executable not found or not executable at ${HYSTERIA_EXEC}"
            exit 1
        fi
        if ! [ -f "${HYSTERIA_CONFIG}" ]; then
            print_msg 31 "Error: Hysteria config file not found at ${HYSTERIA_CONFIG}"
            exit 1
        fi

        nohup "${HYSTERIA_EXEC}" -c "${HYSTERIA_CONFIG}" > /dev/null 2>&1 &
        local pid=$!
        sleep 2

        if ps -p "${pid}" > /dev/null; then
            echo "${pid}" > "${PID_FILE}"
            print_msg 32 "Hysteria service started successfully (PID: ${pid})."
        else
            print_msg 31 "Error: Failed to start Hysteria service."
            [ -f "${PID_FILE}" ] && rm -f "${PID_FILE}"
            exit 1
        fi
    fi

    print_msg 34 "Setting global proxy to ${PROXY_IP}:${PROXY_PORT}..."

    # 2. Configure APT proxy
    print_msg 32 "Configuring APT proxy..."
    {
        echo "Acquire::http::Proxy \"${PROXY_URL_WITH_SLASH}\";"
        echo "Acquire::https::Proxy \"${PROXY_URL_WITH_SLASH}\";"
        echo "Acquire::ftp::Proxy \"${PROXY_URL_WITH_SLASH}\";"
    } | sudo tee "${APT_PROXY_CONF}" > /dev/null
    echo "APT proxy configuration written to ${APT_PROXY_CONF}"

    # 3. Configure wget proxy
    print_msg 32 "Configuring wget proxy..."
    # Clean up any previous settings added by this script to make it idempotent
    sudo sed -i -e '/^# --- Added by proxy.sh script ---/d' -e '/^use_proxy = on/d' -e "/^http_proxy =/d" -e "/^https_proxy =/d" "${WGET_RC_FILE}"
    # Add the new settings
    {
        echo "" # Add a newline for separation
        echo "# --- Added by proxy.sh script ---"
        echo "use_proxy = on"
        echo "http_proxy = ${PROXY_URL_WITH_SLASH}"
        echo "https_proxy = ${PROXY_URL_WITH_SLASH}"
    } | sudo tee -a "${WGET_RC_FILE}" > /dev/null
    echo "wget proxy configured in ${WGET_RC_FILE}"

    # 4. Configure environment variables
    print_msg 32 "Configuring system-wide environment variables..."
    sudo sed -i -e '/http_proxy/d' -e '/https_proxy/d' -e '/ftp_proxy/d' -e '/no_proxy/d' -e '/HTTP_PROXY/d' -e '/HTTPS_PROXY/d' -e '/FTP_PROXY/d' -e '/NO_PROXY/d' "${ENV_FILE}"
    {
        echo "http_proxy=\"${PROXY_URL_WITH_SLASH}\""
        echo "https_proxy=\"${PROXY_URL_WITH_SLASH}\""
        echo "ftp_proxy=\"${PROXY_URL_WITH_SLASH}\""
        echo "no_proxy=\"${NO_PROXY_LIST}\""
        echo "HTTP_PROXY=\"${PROXY_URL_WITH_SLASH}\""
        echo "HTTPS_PROXY=\"${PROXY_URL_WITH_SLASH}\""
        echo "FTP_PROXY=\"${PROXY_URL_WITH_SLASH}\""
        echo "NO_PROXY=\"${NO_PROXY_LIST}\""
    } | sudo tee -a "${ENV_FILE}" > /dev/null
    echo "Environment variables set in ${ENV_FILE}"

    # 5. Configure Docker Daemon Proxy
    if command -v docker &> /dev/null; then
        print_msg 32 "Docker detected. Configuring proxy for Docker daemon..."
        sudo mkdir -p "${DOCKER_PROXY_CONF_DIR}"
        {
            echo "[Service]"
            echo "Environment=\"HTTP_PROXY=${PROXY_URL_WITH_SLASH}\""
            echo "Environment=\"HTTPS_PROXY=${PROXY_URL_WITH_SLASH}\""
            echo "Environment=\"NO_PROXY=localhost,127.0.0.1\""
        } | sudo tee "${DOCKER_PROXY_CONF_FILE}" > /dev/null
        
        print_msg 32 "Reloading systemd and restarting Docker service..."
        sudo systemctl daemon-reload
        sudo systemctl restart docker
        echo "Docker proxy configured."
    else
        print_msg 33 "Docker not found, skipping Docker proxy configuration."
    fi

    # 6. Configure GNOME (desktop) proxy
    if [ -n "$DISPLAY" ]; then
        print_msg 32 "Configuring GNOME desktop proxy settings..."
        gsettings set org.gnome.system.proxy mode 'manual'
        gsettings set org.gnome.system.proxy.http host "${PROXY_IP}"
        gsettings set org.gnome.system.proxy.http port "${PROXY_PORT}"
        gsettings set org.gnome.system.proxy.https host "${PROXY_IP}"
        gsettings set org.gnome.system.proxy.https port "${PROXY_PORT}"
        gsettings set org.gnome.system.proxy.ftp host "${PROXY_IP}"
        gsettings set org.gnome.system.proxy.ftp port "${PROXY_PORT}"
        gsettings set org.gnome.system.proxy ignore-hosts "['localhost', '127.0.0.0/8', '::1']"
        echo "GNOME proxy settings updated."
    fi

    # 7. Run connectivity test automatically after setting proxy
    test_proxy

    print_msg 32 "Proxy setup complete!"
    print_msg 33 "NOTE: You may need to log out and log back in for shell changes to take full effect."
}

# Function to unset the global proxy
unset_proxy() {
    print_msg 34 "Unsetting global proxy..."

    # 1. Stop Hysteria Service
    print_msg 34 "Stopping Hysteria proxy service..."
    if [ -f "${PID_FILE}" ]; then
        local pid
        pid=$(cat "${PID_FILE}")
        if [ -n "${pid}" ] && ps -p "${pid}" > /dev/null; then
            kill "${pid}"
            sleep 1
            if ! ps -p "${pid}" > /dev/null; then
                print_msg 32 "Hysteria service (PID: ${pid}) stopped successfully."
                rm -f "${PID_FILE}"
            else
                print_msg 31 "Error: Failed to stop Hysteria service (PID: ${pid})."
            fi
        else
            print_msg 33 "Stale PID file found. Cleaning up."
            rm -f "${PID_FILE}"
        fi
    else
        print_msg 33 "Hysteria service was not running."
    fi

    # 2. Remove Docker Daemon Proxy
    if [ -f "${DOCKER_PROXY_CONF_FILE}" ]; then
        print_msg 32 "Removing Docker daemon proxy configuration..."
        sudo rm -f "${DOCKER_PROXY_CONF_FILE}"
        sudo rmdir --ignore-fail-on-non-empty "${DOCKER_PROXY_CONF_DIR}"
        print_msg 32 "Reloading systemd and restarting Docker service..."
        sudo systemctl daemon-reload
        sudo systemctl restart docker
        echo "Docker proxy removed."
    fi

    # 3. Remove wget proxy configuration
    if [ -f "${WGET_RC_FILE}" ]; then
        print_msg 32 "Removing wget proxy configuration..."
        sudo sed -i -e '/^# --- Added by proxy.sh script ---/d' -e '/^use_proxy = on/d' -e "/^http_proxy =/d" -e "/^https_proxy =/d" "${WGET_RC_FILE}"
        echo "wget proxy settings removed from ${WGET_RC_FILE}"
    fi

    # 4. Remove APT proxy configuration
    print_msg 32 "Removing APT proxy configuration..."
    [ -f "${APT_PROXY_CONF}" ] && sudo rm -f "${APT_PROXY_CONF}" && echo "Removed ${APT_PROXY_CONF}"

    # 5. Remove environment variables
    print_msg 32 "Removing proxy settings from environment variables..."
    sudo sed -i -e '/http_proxy/d' -e '/https_proxy/d' -e '/ftp_proxy/d' -e '/no_proxy/d' -e '/HTTP_PROXY/d' -e '/HTTPS_PROXY/d' -e '/FTP_PROXY/d' -e '/NO_PROXY/d' "${ENV_FILE}"
    echo "Proxy environment variables removed from ${ENV_FILE}"

    # 6. Unset GNOME (desktop) proxy
    if [ -n "$DISPLAY" ]; then
        print_msg 32 "Resetting GNOME desktop proxy settings..."
        gsettings set org.gnome.system.proxy mode 'none'
    fi

    print_msg 32 "Proxy unset complete!"
    print_msg 33 "NOTE: You may need to log out and log back in for changes to take full effect."
}

# Function to list current proxy settings
list_proxy() {
    print_msg 34 "--- Current Proxy Settings ---"

    # 1. Check Hysteria service status
    print_msg 33 "1. Hysteria Service Status:"
    if [ -f "${PID_FILE}" ] && ps -p "$(cat "${PID_FILE}")" > /dev/null; then
        print_msg 32 "  Hysteria service is RUNNING (PID: $(cat "${PID_FILE}"))."
    else
        echo "  Hysteria service is NOT running."
    fi

    # 2. Check Docker Proxy Configuration
    print_msg 33 "\n2. Docker Daemon Proxy Configuration:"
    if [ -f "${DOCKER_PROXY_CONF_FILE}" ]; then
        print_msg 32 "  Docker proxy is ACTIVE. Contents of ${DOCKER_PROXY_CONF_FILE}:"
        cat "${DOCKER_PROXY_CONF_FILE}"
    else
        echo "  No Docker proxy configuration found."
    fi

    # 3. Check wget Proxy Configuration
    print_msg 33 "\n3. wget Proxy Configuration:"
    if grep -q "# --- Added by proxy.sh script ---" "${WGET_RC_FILE}" 2>/dev/null; then
        print_msg 32 "  wget proxy is ACTIVE. Contents from ${WGET_RC_FILE}:"
        grep -A 3 "# --- Added by proxy.sh script ---" "${WGET_RC_FILE}"
    else
        echo "  No active wget proxy configuration found in ${WGET_RC_FILE}."
    fi

    # 4. Check system-wide environment file
    print_msg 33 "\n4. System-Wide Environment File (${ENV_FILE}):"
    grep --color=never -i "proxy" "${ENV_FILE}" || echo "  No proxy settings found in ${ENV_FILE}."

    # 5. Check APT configuration
    print_msg 33 "\n5. APT Proxy Configuration:"
    if [ -f "${APT_PROXY_CONF}" ]; then
        cat "${APT_PROXY_CONF}"
    else
        echo "  No APT proxy file found at ${APT_PROXY_CONF}."
    fi

    # 6. Check GNOME settings
    if [ -n "$DISPLAY" ]; then
        print_msg 33 "\n6. GNOME Desktop Proxy Settings:"
        local gsettings_mode
        gsettings_mode=$(gsettings get org.gnome.system.proxy mode)
        echo "  Mode: ${gsettings_mode}"
        if [ "${gsettings_mode}" = "'manual'" ]; then
            echo "  HTTP Host:  $(gsettings get org.gnome.system.proxy.http host)"
            echo "  HTTP Port:  $(gsettings get org.gnome.system.proxy.http port)"
        fi
    fi

    echo "----------------------------------"
}

# --- Main Script Logic ---

# Check for root privileges for set/unset actions
if [[ "$1" == "set" || "$1" == "unset" ]]; then
    if [ "$(id -u)" -ne 0 ]; then
        print_msg 31 "Error: This action requires root privileges. Please run with sudo."
        exit 1
    fi
fi

# Parse command-line arguments
case "$1" in
    set)
        set_proxy
        ;;
    unset)
        unset_proxy
        ;;
    list)
        list_proxy
        ;;
    test)
        test_proxy
        ;;
    *)
        show_usage
        ;;
esac

exit 0
