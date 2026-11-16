# Crossplay Minecraft Server (Java & Bedrock)

A containerized, production-ready Minecraft server supporting simultaneous cross-play between **Minecraft: Java Edition** (PC, Mac, Linux) and **Minecraft: Bedrock Edition** (Windows 10/11, iOS, Android, Xbox, PlayStation, Nintendo Switch).

---

## Prerequisites

Before starting the server, ensure your machine meets the following requirements:

- **Docker & Docker Compose**:
  - **Linux**: [Docker Engine](https://docs.docker.com/engine/install/) + Docker Compose plugin (`docker compose`) or standalone `docker-compose`. Ensure the Docker daemon is running and your user has permission to run `docker` commands.
  - **Windows / macOS**: [Docker Desktop](https://www.docker.com/products/docker-desktop/) (includes Docker Engine and Docker Compose).
- **Memory (RAM)**: At least **6 GB total RAM** recommended (**4 GB** is allocated to the JVM by default via `MEMORY=4G` in `.env`, plus overhead for the OS and container).
- **Disk Space**: At least **2–5 GB** free space for the container image, PaperMC, plugins, world data, and backups.
- **Internet Access (First Run / Updates)**: Required to pull `itzg/minecraft-server:latest`, PaperMC, and the official GeyserMC & Floodgate plugins.
- **Available Ports**:
  - `25565/TCP` — Java Edition
  - `19132/UDP` & `19132/TCP` — Bedrock Edition (GeyserMC)
  - `127.0.0.1:25575/TCP` — RCON console (localhost only)
- **Shell / Runtime**:
  - **Linux / macOS**: `bash` (and `tar` for `./server.sh backup`).
  - **Windows**: Command Prompt (`server.bat`) or PowerShell (`server.ps1`).
- **Environment File (`.env`)**: Automatically created from `.env.example` on first run if missing (update `RCON_PASSWORD` before exposing the server).

---

## 1. Why this Architecture is the Most Reliable

The setup uses **PaperMC** as the base server, combined with **GeyserMC** and **Floodgate** as server-side plugins inside Docker:

```
                  +-----------------------------------+
                  |           CLIENTS                 |
                  +-----------------+-----------------+
                                    |
                 +------------------+------------------+
                 |                                     |
    [Java Edition Players]                 [Bedrock Edition Players]
         (PC / Mac)                            (Mobile / Console / PC)
                 |                                     |
         Port 25565 (TCP)                       Port 19132 (UDP)
                 |                                     |
                 +------------------+------------------+
                                    |
+-----------------------------------v-------------------------------------+
| DOCKER CONTAINER: itzg/minecraft-server                                 |
|                                                                         |
|   +-----------------------------------------------------------------+   |
|   | PaperMC Server Engine (JVM)                                     |   |
|   |                                                                 |   |
|   |  +-----------------------------------------------------------+  |   |
|   |  | GeyserMC Plugin (Real-time Protocol & Packet Translator)  |  |   |
|   |  | - Converts Bedrock packets <--> Java packets on-the-fly   |  |   |
|   |  | - Translates animations, combat, block states, inventories|  |   |
|   |  +-----------------------------------------------------------+  |   |
|   |                                                                 |   |
|   |  +-----------------------------------------------------------+  |   |
|   |  | Floodgate Plugin (Bedrock Authentication & Skin Handling) |  |   |
|   |  | - Allows Bedrock users to join without a Java account     |  |   |
|   |  | - Links Xbox Live credentials & prevents name collisions  |  |   |
|   |  +-----------------------------------------------------------+  |   |
|   +-----------------------------------------------------------------+   |
|                                                                         |
|   Persistent Volumes: ./data (Worlds, Plugins, Configs, Logs)           |
+-------------------------------------------------------------------------+
```

### Why this is the gold standard:
1. **Zero Proxy Latency**: Running Geyser directly inside Paper (as a plugin) eliminates the extra network hops and overhead required by a standalone proxy.
2. **Floodgate Authentication**: Bedrock players do not need to buy or own a Java Edition Minecraft account. They join seamlessly with their existing Microsoft/Xbox Live account.
3. **Paper Performance**: Built on top of PaperMC with Aikar's optimized Garbage Collection flags for minimal tick lag and high TPS.
4. **Data Durability**: Server worlds, player inventories, and configurations are fully persisted on the host machine inside the `./data` folder.

---

## 2. Quick Start

### On Linux or macOS

1. Make sure Docker is running on your machine.
2. Open a terminal in this directory and start the server:
   ```bash
   ./server.sh start
   ```
3. Follow the live startup logs:
   ```bash
   ./server.sh logs
   ```
4. Check server health and RAM consumption:
   ```bash
   ./server.sh status
   ```

### On Windows

You can use either **Command Prompt / Double-Click** or **PowerShell**:

- **Command Prompt (CMD) / Double-click**:
  - Simply double-click `server.bat` for an interactive menu, or run:
    ```cmd
    server.bat start
    server.bat logs
    ```
- **PowerShell**:
  ```powershell
  .\server.ps1 start
  .\server.ps1 logs
  ```

---

## 3. How Players Connect

| Edition | Default Port | Protocol | How to Connect |
|---|---|---|---|
| **Java Edition** | `25565` | TCP | Multiplayer -> Add Server -> Enter `your-server-ip:25565` |
| **Bedrock Edition** (Mobile/Win10) | `19132` | UDP | Play -> Servers -> Add Server -> Enter `your-server-ip`, Port `19132` |
| **Bedrock Edition** (Consoles: Xbox, PS, Switch) | `19132` | UDP | Consoles restrict custom server IPs. Use the free **BedrockTogether** mobile app or change DNS (e.g. BedrockConnect) to join. |

---

## 4. Script Command Reference

Both `./server.sh` (Linux) and `server.bat` / `server.ps1` (Windows) support identical commands:

| Command | Action | Description |
|---|---|---|
| `start` | `./server.sh start` | Starts the server container in the background. |
| `stop` | `./server.sh stop` | Gracefully notifies players, flushes chunk saves, and stops the container. |
| `restart` | `./server.sh restart` | Safely restarts the Minecraft server. |
| `status` | `./server.sh status` | Displays container state, healthcheck, and live RAM/CPU usage. |
| `logs` | `./server.sh logs` | Streams real-time server console output (press `Ctrl+C` to exit). |
| `console` | `./server.sh console` | Opens the interactive RCON console to execute commands (e.g. `op PlayerName`, `gamemode`). |
| `backup` | `./server.sh backup` | Freezes chunk saving and creates a compressed, timestamped archive in `backups/`. |
| `update` | `./server.sh update` | Pulls the latest base Docker image and dependencies. |

---

## 5. Configuration (`.env`)

You can modify server parameters anytime by editing [.env](file:///home/samusanc/minecraft/.env):

```env
# Server Name & Message of the Day
SERVER_NAME="Crossplay Minecraft Server"
MOTD="§aWelcome to our Server §7| §eJava & Bedrock Crossplay"

# Paper / Minecraft Version (set to LATEST or e.g. 1.21.4)
TYPE=PAPER
MC_VERSION=LATEST

# RAM Allocation (e.g. 4G, 6G, 8G)
MEMORY=4G

# Network Ports
JAVA_PORT=25565
BEDROCK_PORT=19132
RCON_PORT=25575

# RCON Admin Password
RCON_PASSWORD=ChangeThisPassword123!

# Gameplay Settings
DIFFICULTY=normal
MAX_PLAYERS=20
MODE=survival
PVP=true
VIEW_DISTANCE=10
SIMULATION_DISTANCE=8
ONLINE_MODE=TRUE
```

After changing [.env](file:///home/samusanc/minecraft/.env), apply changes with:
```bash
./server.sh restart
```

---

## 6. Port Forwarding & Router Firewall (For Public Play)

If you are hosting this server from home for friends on the internet, forward the following ports in your router's administration panel to your computer's local IP:

1. **Port 25565 (TCP)** -> For Java Edition players.
2. **Port 19132 (UDP)** -> For Bedrock Edition players.

*(Note: Do **NOT** forward port 25575 (RCON) to the internet; it is locked to localhost for security).*

---

## 7. Installing Additional Plugins

To install other Bukkit/Spigot/Paper plugins (such as EssentialsX, LuckPerms, WorldEdit, GriefPrevention):
1. Place the plugin `.jar` file directly into the `plugins/` directory.
2. Run `./server.sh restart`.
The server will automatically synchronize the plugin into the server engine on startup.
