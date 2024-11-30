#!/bin/bash

# Source the details of hosts, username, and password from an external file
source host_details.sh

# Function to retry a command
retry() {
    local n=1
    local max=5
    local delay=15
    while true; do
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                echo "Command failed. Retrying $n/$max in $delay seconds..."
                sleep $delay
            else
                echo "Command failed after $n attempts. Giving up."
                return 1
            fi
        }
    done
}

# Function to check hostname for each host
check_hostname() {
    for host in "${hosts[@]}"; do
        echo "Checking hostname for $host..."
        retry sshpass -p "$password" ssh -o StrictHostKeyChecking=no \
            -o UserKnownHostsFile=/dev/null \
            -o LogLevel=ERROR \
            -o ForwardX11=no \
            "$user_name@$host" 'hostname' || echo "Failed to connect to $host after retries."
    done
}

# Main script execution
check_hostname
