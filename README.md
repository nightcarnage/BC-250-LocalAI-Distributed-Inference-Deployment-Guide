LocalAI BC-250 Manager
A LocalAI AIO launcher for Podman-based systems.
This project provides a single-entrypoint script that builds a host-matched LocalAI container image and orchestrates Master, Federated, and Worker roles in a peer-to-peer (P2P) inference cluster.

The command parser intentionally supports multiple roles in a single invocation, allowing any combination of services to be launched on the same host.

Key Design Principle
Every argument is processed in order.

The script uses a while loop over all CLI arguments.
Each recognized command (master, fed, worker, etc.) is executed independently, not exclusively.

This means:

There is no “mode”
There is no mutual exclusion
You can launch multiple roles at once
Order does not matter
Requirements
Fedora 43+ or Bazzite 42
Podman
ASUS BC-250
/dev/dri access
Host networking allowed
Installation
chmod +x localai.sh
./localai.sh install
This applies:

Network tuning for P2P RPC
Firewall rules
SELinux device permissions
Builds the LocalAI container image (once)

Command Syntax:

./localai.sh [command] [command] [command] ...

There is no limit to combinations of commands you pass.

Available Commands
Command	Description
install	        Apply host tuning and build image
master	        Run LocalAI API + P2P coordinator (port 8080)
fed	                Run federated API participant (port 8081)
worker	        Run P2P execution worker (no API)
status	        Show running LocalAI containers
debug <role>	Stream logs for a role
shell <role>	Open a shell inside a running container
stop [role]	Stop a role or all roles
uninstall	        Stop everything and remove artifacts

Role Definitions
Master:
Runs LocalAI API server
Acts as P2P coordinator
Listens on 0.0.0.0:8080

Fed:
Runs LocalAI Federated server
Participates in federation
Listens on 0.0.0.0:8081

Worker:
Runs p2p-llama-cpp-rpc
Executes inference only
No HTTP API


Multi-Role Execution (IMPORTANT)
Because arguments are processed sequentially, you can start multiple roles in one command.

Examples
Run all roles on one host
./localai.sh master fed worker
Federated + Worker node


./localai.sh fed worker
Master + Worker (common single-node setup)

./localai.sh master worker
Start roles incrementally

./localai.sh master
./localai.sh worker

All of these are valid and equivalent.
What Actually Happens Internally

Each role:
Builds the image if missing
Uses a fixed container name:

localai

localai-fed

localai-worker

Uses podman run --replace
Runs independently of other roles
Launching multiple roles:
Does not share a container
Does not override other roles
Does not require coordination

Debugging Stream logs:

./localai.sh debug master
./localai.sh debug fed
./localai.sh debug worker

Opens an interactive shell

Status:

./localai.sh status

Shows all running LocalAI-related containers.

Stopping Services:

./localai.sh stop master
./localai.sh stop fed
./localai.sh stop worker

Stop everything:

./localai.sh stop

Uninstall:

./localai.sh uninstall

Stops all LocalAI containers
Removes the container image
Deletes stored node IDs
Removes the generated Containerfile

**Full Changelog**: https://github.com/nightcarnage/BC-250-LocalAI-Distributed-Inference-Deployment-Guide/compare/beta...BC-250
