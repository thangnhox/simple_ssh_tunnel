#!/bin/sh

# Directory to store PID files
PID_DIR="$HOME/.ssh_tunnels"
mkdir -p "$PID_DIR"

usage() {
    echo "Usage:"
    echo "  tunnel start <name> <type> <port1> <host> <port2> <ssh_user> <ssh_host> <ssh_port>"
    echo ""
    echo "  Parameters:"
    echo "    <type>      : -L (Local forward) or -R (Remote forward)"
    echo "    <port1>     : Port to listen on (Local for -L, Remote for -R)"
    echo "    <host>      : Target host/IP (e.g., Container IP 172.17.0.5 or localhost)"
    echo "    <port2>     : Target port"
    echo ""
    echo "  Examples:"
    echo "    Forward container to local network (for multiple clients):"
    echo "    tunnel start myapp -L 8080 172.17.0.5 80 myuser myserver.com 22"
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
    local ssh_port="$8"
    local pid_file="$PID_DIR/$name.pid"

    if [ -f "$pid_file" ]; then
        # Check if the process is actually still running
        if ps -p "$(cat "$pid_file")" > /dev/null 2>&1; then
            echo "Tunnel '$name' is already running (PID $(cat "$pid_file"))."
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

    # Run SSH in the background using '&' instead of '-f' 
    # This allows us to reliably capture the exact PID using '$!'
    ssh -p "$ssh_port" -N \
        "$type" "$forward_spec" \
        "${user}@${sshhost}" \
        -o ExitOnForwardFailure=yes &
    
    local pid=$!

    # Wait a brief moment to ensure SSH didn't immediately fail (e.g., bad port/auth)
    sleep 1
    if ! ps -p "$pid" > /dev/null 2>&1; then
        echo "Failed to start tunnel. Check your SSH connection, authentication, and ports."
        exit 1
    fi

    echo "$pid" > "$pid_file"
    echo "Tunnel '$name' started successfully (PID $pid)."
}

tunnel_stop() {
    local name="$1"
    local pid_file="$PID_DIR/$name.pid"

    if [ ! -f "$pid_file" ]; then
        echo "Tunnel '$name' not found."
        exit 1
    fi

    local pid=$(cat "$pid_file")
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
        local pid=$(cat "$f")
        
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "  $name (PID $pid)"
        else
            echo "  $name (stale PID: $pid)"
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
