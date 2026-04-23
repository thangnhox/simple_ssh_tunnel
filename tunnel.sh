#!/bin/sh

# Directory to store PID files
PID_DIR="$HOME/.ssh_tunnels"
mkdir -p "$PID_DIR"

usage() {
    echo "Usage:"
    echo "  tunnel start <name> <type> <port1> <host> <port2> <ssh_user> <ssh_host> [ssh_port]"
    echo ""
    echo "  Parameters:"
    echo "    <type>      : -L (Local forward) or -R (Remote forward)"
    echo "    <port1>     : Port to listen on (Src port: Local for -L, Remote for -R)"
    echo "    <host>      : Target host/IP (Dst IP: e.g., Container IP 172.17.0.5 or localhost)"
    echo "    <port2>     : Target port (Dst port)"
    echo "    [ssh_port]  : SSH port (Optional, defaults to 22)"
    echo ""
    echo "  Examples:"
    echo "    Forward container to local network (for multiple clients):"
    echo "    tunnel start myapp -L 8080 172.17.0.5 80 myuser myserver.com"
    echo ""
    echo "  tunnel stop <name>"
    echo "  tunnel status"
    exit 1
}

tunnel_start() {
    local name="$1"
    local type="$2"
    local port1="$3"
    local host="$4"
    local port2="$5"
    local user="$6"
    local sshhost="$7"
    # Default to 22 if the 8th parameter is empty or missing
    local ssh_port="${8:-22}"
    local pid_file="$PID_DIR/$name.pid"
    local log_file="$PID_DIR/$name.log"

    if [ -f "$pid_file" ]; then
        # Read the first field (PID) using colon as the delimiter
        IFS=':' read -r saved_pid _ < "$pid_file"
        
        # Check if the process is actually still running
        if ps -p "$saved_pid" > /dev/null 2>&1; then
            echo "Tunnel '$name' is already running (PID $saved_pid)."
            exit 1
        else
            echo "Removing stale PID file for '$name'..."
            rm -f "$pid_file"
        fi
    fi

    local forward_spec=""

    # Set up the forward spec based on explicit type (-L or -R)
    if [ "$type" = "-L" ] || [ "$type" = "L" ]; then
        type="-L"
        # 0.0.0.0 allows other clients on your network to connect
        forward_spec="0.0.0.0:${port1}:${host}:${port2}"
        echo "Starting LOCAL (-L) tunnel '$name' to $host:$port2..."
    elif [ "$type" = "-R" ] || [ "$type" = "R" ]; then
        type="-R"
        forward_spec="${port1}:${host}:${port2}"
        echo "Starting REMOTE (-R) tunnel '$name' to $host:$port2..."
    else
        echo "Error: Type must be -L or -R"
        usage
    fi

    # Clear previous log
    > "$log_file"

    # Start a background wrapper that acts as the parent of the ssh process.
    # It spawns ssh, saves the PID, waits for it to exit, and then cleans up.
    # This avoids polling loops.
    (
        ssh -p "$ssh_port" -N \
            "$type" "$forward_spec" \
            "${user}@${sshhost}" \
            -o ExitOnForwardFailure=yes > "$log_file" 2>&1 &
        
        local ssh_pid=$!
        
        # Save tracking details in the format: PID:TYPE:PORT1:HOST:PORT2:SSH_HOST:SSH_PORT
        echo "$ssh_pid:$type:$port1:$host:$port2:$sshhost:$ssh_port" > "$pid_file"
        
        # Wait for the child SSH process to terminate natively
        wait "$ssh_pid"
        
        # Process has terminated. Remove the PID file if it still belongs to this specific process.
        if [ -f "$pid_file" ]; then
            IFS=':' read -r current_pid _ < "$pid_file"
            if [ "$current_pid" = "$ssh_pid" ]; then
                rm -f "$pid_file"
            fi
        fi
    ) &

    # Wait up to 2 seconds for the wrapper to create the PID file
    local wait_time=0
    while [ ! -f "$pid_file" ] && [ $wait_time -lt 20 ]; do
        sleep 0.1
        wait_time=$((wait_time + 1))
    done

    # If it failed to create the file, or if it already cleaned it up due to immediate failure
    if [ ! -f "$pid_file" ]; then
        echo "Failed to start tunnel. Check your SSH connection, authentication, and ports."
        echo "See log for details: $log_file"
        tail -n 3 "$log_file" | sed 's/^/  > /'
        exit 1
    fi

    local pid
    IFS=':' read -r pid _ < "$pid_file"

    # Wait a brief moment to ensure SSH didn't immediately fail (e.g., bad port/auth)
    sleep 1
    if ! ps -p "$pid" > /dev/null 2>&1; then
        echo "Failed to start tunnel. Check your SSH connection, authentication, and ports."
        echo "See log for details: $log_file"
        # Also print out the last few lines of the log for immediate feedback
        tail -n 3 "$log_file" | sed 's/^/  > /'
        exit 1
    fi

    echo "Tunnel '$name' started successfully (PID $pid)."
}

tunnel_stop() {
    local name="$1"
    local pid_file="$PID_DIR/$name.pid"

    if [ ! -f "$pid_file" ]; then
        echo "Tunnel '$name' not found."
        exit 1
    fi

    # Extract just the PID from the saved string
    IFS=':' read -r pid _ < "$pid_file"
    
    echo "Stopping tunnel '$name' (PID $pid)..."
    kill "$pid" 2>/dev/null
    rm -f "$pid_file"
    echo "Tunnel '$name' stopped."
}

tunnel_status() {
    echo "Active tunnels:"
    local found=0
    
    for f in "$PID_DIR"/*.pid; do
        [ -e "$f" ] || continue
        local name=$(basename "$f" .pid)
        
        # Parse the saved details
        IFS=':' read -r pid type port1 host port2 sshhost ssh_port < "$f"
        
        local status_str="RUNNING"
        if ! ps -p "$pid" > /dev/null 2>&1; then
            status_str="STALE"
        fi

        if [ -z "$type" ]; then
            # Legacy format support (file only contains the PID)
            if [ "$status_str" = "RUNNING" ]; then
                echo "  $name (PID $pid) - Legacy format (run stop/start to update tracking details)"
            else
                echo "  $name (stale PID: $pid)"
            fi
        else
            # New format with tracking details
            local type_desc="Local"
            [ "$type" = "-R" ] && type_desc="Remote"

            if [ "$status_str" = "RUNNING" ]; then
                echo "  $name (PID $pid)"
            else
                echo "  $name (stale PID: $pid)"
            fi
            
            local details_str="    -> Type: $type ($type_desc), Src Port: $port1, Dst IP: $host, Dst Port: $port2"
            if [ -n "$sshhost" ] && [ -n "$ssh_port" ]; then
                details_str="$details_str, SSH: $sshhost:$ssh_port"
            fi
            echo "$details_str"
        fi
        
        found=1
    done
    
    if [ $found -eq 0 ]; then
        echo "  None"
    fi
}

# Ensure minimum arguments are provided for 'start'
if [ "$1" = "start" ] && [ "$#" -lt 8 ]; then
    usage
fi

case "$1" in
    start) tunnel_start "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" ;;
    stop) tunnel_stop "$2" ;;
    status) tunnel_status ;;
    *) usage ;;
esac
