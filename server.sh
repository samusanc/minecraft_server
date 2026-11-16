#!/usr/bin/env bash
# ==============================================================================
# Minecraft Crossplay Server Controller (Linux / macOS)
# ==============================================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

CONTAINER_NAME="minecraft-server"
BACKUP_DIR="$SCRIPT_DIR/backups"

# ANSI Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Determine compose command
if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then
    COMPOSE_CMD="docker-compose"
else
    echo -e "${RED}[ERROR] Neither 'docker compose' nor 'docker-compose' was found.${NC}"
    echo "Please install Docker and the Docker Compose plugin: https://docs.docker.com/engine/install/"
    exit 1
fi

check_docker() {
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}[ERROR] Docker daemon is not running or current user lacks permissions.${NC}"
        echo "Make sure Docker is running: 'sudo systemctl start docker' or add your user to the docker group."
        exit 1
    fi
}

check_env() {
    if [ ! -f "$SCRIPT_DIR/.env" ]; then
        if [ -f "$SCRIPT_DIR/.env.example" ]; then
            echo -e "${YELLOW}[!] .env not found. Creating from .env.example with sensible defaults...${NC}"
            cp "$SCRIPT_DIR/.env.example" "$SCRIPT_DIR/.env"
        else
            echo -e "${RED}[ERROR] .env and .env.example missing!${NC}"
            exit 1
        fi
    fi
}

start_server() {
    check_docker
    check_env
    echo -e "${CYAN}==> Starting Minecraft Crossplay Server...${NC}"
    $COMPOSE_CMD up -d
    echo -e "${GREEN}[OK] Container launched.${NC}"
    echo -e "Use ${BOLD}./server.sh logs${NC} to follow server startup progress."
    echo -e "Use ${BOLD}./server.sh status${NC} to check health."
}

stop_server() {
    check_docker
    echo -e "${YELLOW}==> Gracefully shutting down Minecraft server...${NC}"
    # Send Minecraft save and stop commands via rcon if container is running
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]; then
        echo -e "Notifying players and saving world..."
        docker exec "$CONTAINER_NAME" rcon-cli say Server shutting down in 5 seconds... 2>/dev/null || true
        docker exec "$CONTAINER_NAME" rcon-cli save-all 2>/dev/null || true
        docker exec "$CONTAINER_NAME" rcon-cli stop 2>/dev/null || true
        sleep 5
    fi
    $COMPOSE_CMD down
    echo -e "${GREEN}[OK] Minecraft server stopped cleanly.${NC}"
}

restart_server() {
    check_docker
    echo -e "${CYAN}==> Restarting Minecraft server...${NC}"
    stop_server
    sleep 2
    start_server
}

status_server() {
    check_docker
    echo -e "${BOLD}${CYAN}--- Server Container Status ---${NC}"
    $COMPOSE_CMD ps
    echo ""
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]; then
        HEALTH=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$CONTAINER_NAME" 2>/dev/null || echo "unknown")
        echo -e "Health State: ${BOLD}${GREEN}${HEALTH}${NC}"
        echo ""
        echo -e "${BOLD}${CYAN}--- Resource Usage ---${NC}"
        docker stats --no-stream "$CONTAINER_NAME"
    else
        echo -e "${YELLOW}Server is currently STOPPED.${NC}"
    fi
}

logs_server() {
    check_docker
    echo -e "${CYAN}==> Following logs (Press Ctrl+C to exit)...${NC}"
    $COMPOSE_CMD logs -f --tail=100
}

console_server() {
    check_docker
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" != "true" ]; then
        echo -e "${RED}[ERROR] Container $CONTAINER_NAME is not running. Start it first.${NC}"
        exit 1
    fi
    echo -e "${GREEN}==> Connecting to Minecraft RCON Console. Type commands directly (e.g. 'op username', 'list', 'help').${NC}"
    echo -e "${YELLOW}Type 'exit' or press Ctrl+C to disconnect from the console (server keeps running).${NC}"
    docker exec -it "$CONTAINER_NAME" rcon-cli
}

exec_command() {
    check_docker
    if [ -z "$1" ]; then
        echo -e "${RED}[ERROR] No command specified. Example: ./server.sh cmd \"list\"${NC}"
        exit 1
    fi
    docker exec "$CONTAINER_NAME" rcon-cli "$@"
}

backup_server() {
    check_docker
    mkdir -p "$BACKUP_DIR"
    TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
    BACKUP_FILE="$BACKUP_DIR/world_backup_${TIMESTAMP}.tar.gz"

    echo -e "${CYAN}==> Creating backup: ${BACKUP_FILE}${NC}"

    IS_RUNNING=false
    if [ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]; then
        IS_RUNNING=true
        echo -e "Pausing world saves for atomic snapshot..."
        docker exec "$CONTAINER_NAME" rcon-cli save-off 2>/dev/null || true
        docker exec "$CONTAINER_NAME" rcon-cli save-all flush 2>/dev/null || true
        sleep 2
    fi

    tar -czf "$BACKUP_FILE" -C "$SCRIPT_DIR" data/

    if [ "$IS_RUNNING" = "true" ]; then
        echo -e "Re-enabling world saves..."
        docker exec "$CONTAINER_NAME" rcon-cli save-on 2>/dev/null || true
    fi

    BACKUP_SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    echo -e "${GREEN}[OK] Backup completed successfully! (Size: $BACKUP_SIZE)${NC}"
}

update_server() {
    check_docker
    echo -e "${CYAN}==> Pulling latest images & updates...${NC}"
    $COMPOSE_CMD pull
    echo -e "${GREEN}Updating completed. Restart the server to apply.${NC}"
}

show_help() {
    echo -e "${BOLD}${CYAN}Minecraft Crossplay Server Controller (Java & Bedrock)${NC}"
    echo ""
    echo -e "Usage: ${BOLD}./server.sh [command]${NC}"
    echo ""
    echo "Commands:"
    echo "  start       Start the Minecraft server in the background"
    echo "  stop        Gracefully save and stop the server"
    echo "  restart     Restart the server"
    echo "  status      Check container health, status, and RAM/CPU usage"
    echo "  logs        Stream real-time server logs (Ctrl+C to quit)"
    echo "  console     Open interactive Minecraft RCON admin console"
    echo "  cmd <cmd>   Execute a single server command (e.g. ./server.sh cmd \"say hello\")"
    echo "  backup      Create a safe, compressed timestamped backup of worlds & data"
    echo "  update      Pull latest Docker image updates"
    echo "  help        Display this help message"
    echo ""
}

# Main routing
case "${1:-}" in
    start)
        start_server
        ;;
    stop)
        stop_server
        ;;
    restart)
        restart_server
        ;;
    status)
        status_server
        ;;
    logs)
        logs_server
        ;;
    console)
        console_server
        ;;
    cmd)
        shift
        exec_command "$@"
        ;;
    backup)
        backup_server
        ;;
    update)
        update_server
        ;;
    help|--help|-h)
        show_help
        ;;
    "")
        show_help
        ;;
    *)
        echo -e "${RED}[ERROR] Unknown command: $1${NC}"
        show_help
        exit 1
        ;;
esac
