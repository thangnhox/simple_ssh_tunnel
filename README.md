# SSH Tunnel Manager (tunnel)

A lightweight, dependency-free shell script to create and manage persistent SSH tunnels in the background.

Instead of manually running complex SSH port-forwarding commands and hunting for process IDs (PIDs) to kill them later, this script wraps the process into simple start, stop, and status commands. It is especially useful for securely exposing remote Docker containers to your local network.

## Features

- Easy Management: Start and stop tunnels by a friendly <name>.
- Smart PID Tracking: Saves PIDs to \~/.ssh_tunnels/ and automatically cleans up stale files if a tunnel crashes.
- LAN Ready: Local (-L) tunnels automatically bind to 0.0.0.0, allowing other devices on your local Wi-Fi/LAN to access the forwarded ports.
- Multi-Directional: Supports both Local (-L) and Remote (-R) port forwarding.

## Installation

1. Save the script to a location in your $PATH (e.g., /usr/local/bin/ or /opt/bin/).
2. Make the script executable:

```
sudo mv tunnel.sh /usr/local/bin/tunnel
sudo chmod +x /usr/local/bin/tunnel
```

## Usage

The script accepts three main commands: start, stop, and status.

### 1. Starting a Tunnel

```
tunnel start <name> <type> <port1> <host> <port2> <ssh_user> <ssh_host> <ssh_port>
```

#### Parameters:

- name: A friendly identifier for your tunnel (e.g., web-db, docker-app).
- type: -L (Local forward) or -R (Remote forward).
- port1: The port to listen on.
- host: The target host or IP (e.g., localhost, or a Docker Container IP like 172.17.0.5).
- port2: The target port on the remote host/container.
- ssh_user: The username for the SSH connection.
- ssh_host: The IP or hostname of the SSH server acting as the gateway.
- ssh_port: The port of the SSH server (usually 22).

### 2. Stopping a Tunnel

```
tunnel stop <name>
```

### 3. Checking Tunnel Status

```
tunnel status
```

This will list all currently tracked tunnels and their active PIDs.

## Examples

### Example 1: Forwarding a Remote Docker Container (Local Forward)

You have a web app running inside a remote Docker container on 172.17.0.5:80. You want to access it on your local machine and share it with your local network on port 8080.

```
tunnel start myapp -L 8080 172.17.0.5 80 myuser myserver.com 22
```

Result: You (and anyone on your local Wi-Fi) can access the remote container by going to http://<your-local-ip>:8080.

### Example 2: Forwarding Local Dev Server to a Remote Host (Remote Forward)

You are running a local Node.js server on port 3000 and want to securely expose it on a remote VPS on port 9000.

```
tunnel start local-dev -R 9000 localhost 3000 vpsuser myvps.com 22
```

## License

This project is released under the CC0-1.0 (Creative Commons Zero v1.0 Universal) license. You can copy, modify, distribute and perform the work, even for commercial purposes, all without asking permission.
