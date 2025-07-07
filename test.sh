#!/bin/bash

# Docker Service Manager - Termux Edition
# Comprehensive tool for managing Docker services with automatic dependency checking

# Colors for better UI
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
CONFIG_DIR="$HOME/.docker_service_manager"
SERVICES_DIR="$CONFIG_DIR/services"
DATA_DIR="$HOME/docker_services_data"
TMUX_SESSION="docker_services"

# Create necessary directories
mkdir -p "$CONFIG_DIR" "$SERVICES_DIR" "$DATA_DIR"

# Function to clear screen
clear_screen() {
    clear
}

# Function to print colored text
print_colored() {
    local color=$1
    local text=$2
    echo -e "${color}${text}${NC}"
}

# Function to print header
print_header() {
    clear_screen
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Docker Service Manager                    ║${NC}"
    echo -e "${GREEN}║                      Termux Edition                         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check udocker
    if ! command -v udocker &> /dev/null; then
        missing_deps+=("udocker")
    fi
    
    # Check tmux
    if ! command -v tmux &> /dev/null; then
        missing_deps+=("tmux")
    fi
    
    # Check curl for GitHub API
    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi
    
    # Check jq for JSON parsing
    if ! command -v jq &> /dev/null; then
        missing_deps+=("jq")
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_colored $RED "Missing dependencies detected:"
        for dep in "${missing_deps[@]}"; do
            print_colored $YELLOW "   - $dep"
        done
        echo
        print_colored $YELLOW "Installing missing dependencies..."
        
        # Install missing dependencies
        if [[ " ${missing_deps[*]} " =~ " udocker " ]]; then
            print_colored $YELLOW "Installing udocker..."
            pkg install git -y
            git clone --depth 1 https://github.com/George-Seven/Termux-Udocker ~/Termux-Udocker
            bash ~/Termux-Udocker/install_udocker.sh
        fi
        
        if [[ " ${missing_deps[*]} " =~ " tmux " ]]; then
            print_colored $YELLOW "Installing tmux..."
            pkg install tmux -y
        fi
        
        if [[ " ${missing_deps[*]} " =~ " curl " ]]; then
            print_colored $YELLOW "Installing curl..."
            pkg install curl -y
        fi
        
        if [[ " ${missing_deps[*]} " =~ " jq " ]]; then
            print_colored $YELLOW "Installing jq..."
            pkg install jq -y
        fi
        
        print_colored $GREEN "Dependencies installed successfully!"
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
    else
        print_colored $GREEN "All dependencies are installed"
    fi
}

# Function to detect architecture
detect_architecture() {
    local arch=$(uname -m)
    case $arch in
        aarch64|arm64)
            echo "arm64"
            ;;
        armv7l|armhf)
            echo "arm"
            ;;
        x86_64|amd64)
            echo "amd64"
            ;;
        i386|i686)
            echo "386"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

# Function to search Docker Hub repositories
search_dockerhub() {
    local search_term=$1
    
    # If search term contains slash, it's likely a specific repo
    if [[ "$search_term" == *"/"* ]]; then
        # Check if the specific repository exists
        local namespace=$(echo "$search_term" | cut -d'/' -f1)
        local repository=$(echo "$search_term" | cut -d'/' -f2)
        
        local check_response=$(curl -s "https://hub.docker.com/v2/repositories/$namespace/$repository/")
        if [ $? -eq 0 ] && echo "$check_response" | jq -e '.name' > /dev/null 2>&1; then
            echo "$search_term"
            return
        fi
    fi
    
    # Use Docker Hub API to search
    local response=$(curl -s "https://hub.docker.com/v2/search/repositories/?query=$search_term&page_size=10")
    
    if [ $? -eq 0 ] && echo "$response" | jq -e '.results' > /dev/null 2>&1; then
        # Parse the JSON response properly
        local results=$(echo "$response" | jq -r '.results[]?.name // empty' 2>/dev/null | grep -v "^$" | head -10)
        if [ -n "$results" ]; then
            echo "$results"
        else
            # If no results, provide the search term as-is
            echo "$search_term"
        fi
    else
        # Fallback: provide the search term as-is
        echo "$search_term"
    fi
}

# Function to get available tags for a Docker image
get_image_tags() {
    local image_name=$1
    local arch=$(detect_architecture)
    
    # Split image name into namespace and repository
    local namespace=""
    local repository=""
    
    if [[ "$image_name" == *"/"* ]]; then
        namespace=$(echo "$image_name" | cut -d'/' -f1)
        repository=$(echo "$image_name" | cut -d'/' -f2)
    else
        namespace="library"
        repository="$image_name"
    fi
    
    # Try to get tags from Docker Hub API
    local response=$(curl -s "https://hub.docker.com/v2/repositories/$namespace/$repository/tags/?page_size=50")
    
    if [ $? -eq 0 ] && echo "$response" | jq -e '.results' > /dev/null 2>&1; then
        # Parse tags and filter for architecture
        local all_tags=$(echo "$response" | jq -r '.results[]?.name // empty' 2>/dev/null | grep -v "^$")
        
        # Filter tags based on architecture
        local filtered_tags=()
        while IFS= read -r tag; do
            if [ -n "$tag" ]; then
                case $arch in
                    "arm64"|"arm")
                        if [[ "$tag" =~ (arm|aarch|arm64) ]] || [[ "$tag" =~ ^(latest|stable|main)$ ]]; then
                            filtered_tags+=("$tag")
                        fi
                        ;;
                    "amd64")
                        if [[ "$tag" =~ (amd64|x86) ]] || [[ "$tag" =~ ^(latest|stable|main)$ ]]; then
                            filtered_tags+=("$tag")
                        fi
                        ;;
                    *)
                        filtered_tags+=("$tag")
                        ;;
                esac
            fi
        done <<< "$all_tags"
        
        # If no filtered tags, show all tags
        if [ ${#filtered_tags[@]} -eq 0 ]; then
            while IFS= read -r tag; do
                if [ -n "$tag" ]; then
                    filtered_tags+=("$tag")
                fi
            done <<< "$all_tags"
        fi
        
        # Output filtered tags
        for tag in "${filtered_tags[@]}"; do
            echo "$tag"
        done
    else
        # Fallback: suggest common tags based on architecture
        case $arch in
            "arm64"|"arm")
                echo -e "arm\narm64\nlatest\nstable"
                ;;
            "amd64")
                echo -e "amd64\nx86_64\nlatest\nstable"
                ;;
            *)
                echo -e "latest\nstable\nmain"
                ;;
        esac
    fi
}

# Function to check if port is in use
check_port_conflict() {
    local port=$1
    local current_service=$2
    
    # Check if port is used by other services
    for service_file in "$SERVICES_DIR"/*.conf; do
        if [ -f "$service_file" ]; then
            local service_name=$(basename "$service_file" .conf)
            if [ "$service_name" != "$current_service" ]; then
                source "$service_file"
                if [ "$EXTERNAL_PORT" = "$port" ] || [ "$PORT" = "$port" ]; then
                    echo "Port $port is already used by service: $service_name"
                    return 1
                fi
            fi
        fi
    done
    
    # Check if port is used by system
    if command -v netstat >/dev/null 2>&1; then
        if netstat -tuln 2>/dev/null | grep -q ":$port "; then
            echo "Port $port is already in use by system"
            return 1
        fi
    fi
    
    return 0
}

# Function to suggest available port
suggest_available_port() {
    local base_port=$1
    local current_service=$2
    
    for ((i=0; i<100; i++)); do
        local test_port=$((base_port + i))
        if check_port_conflict "$test_port" "$current_service"; then
            echo "$test_port"
            return 0
        fi
    done
    
    echo "$((base_port + 100))"
}

# Function to install a new service
install_service() {
    clear_screen
    print_colored $YELLOW "Installing New Service"
    echo
    
    print_colored $YELLOW "Available sources:"
    echo "  [1] Docker Hub"
    echo
    
    read -p "$(print_colored $YELLOW "Select source (1): ")" source_choice
    
    if [ "$source_choice" != "1" ]; then
        print_colored $RED "Invalid option. Please select 1."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    echo
    read -p "$(print_colored $YELLOW "Enter the string you want to search: ")" search_term
    
    if [ -z "$search_term" ]; then
        print_colored $RED "Search term cannot be empty."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    print_colored $YELLOW "Searching for images..."
    
    # Get search results and filter out empty lines
    local search_output=$(search_dockerhub "$search_term")
    local search_results=()
    
    # Convert multiline output to array, filtering empty lines
    while IFS= read -r line; do
        if [ -n "$line" ] && [ "$line" != "null" ]; then
            search_results+=("$line")
        fi
    done <<< "$search_output"
    
    # If no results from API, provide manual suggestions
    if [ ${#search_results[@]} -eq 0 ]; then
        print_colored $YELLOW "API search failed. Providing manual suggestions..."
        if [[ "$search_term" == *"/"* ]]; then
            search_results=("$search_term")
        else
            search_results=("$search_term" "library/$search_term" "$search_term/$search_term")
        fi
    fi
    
    echo
    echo "Search Results:"
    for i in "${!search_results[@]}"; do
        echo "  [$((i+1))] ${search_results[$i]}"
    done
    echo "  [$((${#search_results[@]}+1))] Continue search"
    echo
    
    read -p "$(print_colored $YELLOW "Select an image, or continue search: ")" image_choice
    
    if [ "$image_choice" -eq "$((${#search_results[@]}+1))" ] 2>/dev/null; then
        install_service
        return
    fi
    
    if ! [[ "$image_choice" =~ ^[0-9]+$ ]] || [ "$image_choice" -lt 1 ] || [ "$image_choice" -gt ${#search_results[@]} ]; then
        print_colored $RED "Invalid selection."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    local selected_image="${search_results[$((image_choice-1))]}"
    
    print_colored $YELLOW "Getting available tags for: $selected_image"
    
    # Get available tags and convert to array
    local tags_output=$(get_image_tags "$selected_image")
    local available_tags=()
    
    while IFS= read -r tag; do
        if [ -n "$tag" ] && [ "$tag" != "null" ]; then
            available_tags+=("$tag")
        fi
    done <<< "$tags_output"
    
    if [ ${#available_tags[@]} -eq 0 ]; then
        print_colored $RED "No tags found for: $selected_image"
        print_colored $YELLOW "Trying with 'latest' tag..."
        available_tags=("latest")
    fi
    
    echo
    echo "Available Tags:"
    for i in "${!available_tags[@]}"; do
        echo "  [$((i+1))] ${available_tags[$i]}"
    done
    echo
    
    read -p "$(print_colored $YELLOW "Select a tag (1): ")" tag_choice
    
    if [ -z "$tag_choice" ]; then
        tag_choice=1
    fi
    
    if ! [[ "$tag_choice" =~ ^[0-9]+$ ]] || [ "$tag_choice" -lt 1 ] || [ "$tag_choice" -gt ${#available_tags[@]} ]; then
        print_colored $RED "Invalid tag selection."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    local selected_tag="${available_tags[$((tag_choice-1))]}"
    local full_image="$selected_image:$selected_tag"
    
    echo
    print_colored $YELLOW "Service Configuration"
    echo "===================="
    echo
    
    # Pull image first to detect ports
    print_colored $YELLOW "Pulling image to detect exposed ports..."
    if ! UDOCKER_LOGLEVEL=3 udocker pull "$full_image"; then
        print_colored $RED "Failed to pull image: $full_image"
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi

    # Detect exposed ports from pulled image
    local detected_ports=$(udocker inspect "$full_image" 2>/dev/null | grep -i "ExposedPorts\|Port" | grep -oE "[0-9]+/tcp" | cut -d'/' -f1 | head -1)

    # Default values
    local default_container_name=$(echo "$selected_image" | sed 's/\//_/g')_container
    local default_window_name=$(echo "$selected_image" | sed 's/\//_/g')
    local service_name=$(echo "$selected_image" | sed 's/\//_/g')
    
    # Container Name Configuration
    echo "Container Name"
    echo "Default: $default_container_name"
    read -p "$(print_colored $YELLOW "Enter container name (or press Enter for default): ")" user_container_name
    local container_name=${user_container_name:-$default_container_name}
    echo
    
    # Port Configuration
    echo "Port Configuration"
    if [ -n "$detected_ports" ]; then
        echo "Detected port from image: $detected_ports"
        echo "This port will be used for container internal port"
        
        # Check if detected port is available
        local suggested_port=$detected_ports
        if ! check_port_conflict "$detected_ports" "$service_name"; then
            suggested_port=$(suggest_available_port "$detected_ports" "$service_name")
            print_colored $YELLOW "Port $detected_ports is in use. Suggested available port: $suggested_port"
        fi
        
        while true; do
            read -p "$(print_colored $YELLOW "Enter external port to map to $detected_ports (default: $suggested_port): ")" user_port
            local external_port=${user_port:-$suggested_port}
            
            # Validate port number
            if ! [[ "$external_port" =~ ^[0-9]+$ ]] || [ "$external_port" -lt 1 ] || [ "$external_port" -gt 65535 ]; then
                print_colored $RED "Invalid port number (1-65535)"
                continue
            fi
            
            # Check port conflict
            if check_port_conflict "$external_port" "$service_name"; then
                local internal_port=$detected_ports
                break
            else
                print_colored $RED "Port $external_port is already in use!"
                local alternative=$(suggest_available_port "$external_port" "$service_name")
                print_colored $YELLOW "Suggested alternative: $alternative"
            fi
        done
    else
        echo "No ports detected from image"
        while true; do
            read -p "$(print_colored $YELLOW "Enter external port: ")" external_port
            read -p "$(print_colored $YELLOW "Enter internal port: ")" internal_port
            
            # Validate port numbers
            if ! [[ "$external_port" =~ ^[0-9]+$ ]] || [ "$external_port" -lt 1 ] || [ "$external_port" -gt 65535 ]; then
                print_colored $RED "Invalid external port number (1-65535)"
                continue
            fi
            
            if ! [[ "$internal_port" =~ ^[0-9]+$ ]] || [ "$internal_port" -lt 1 ] || [ "$internal_port" -gt 65535 ]; then
                print_colored $RED "Invalid internal port number (1-65535)"
                continue
            fi
            
            # Check port conflict
            if check_port_conflict "$external_port" "$service_name"; then
                break
            else
                print_colored $RED "Port $external_port is already in use!"
                local alternative=$(suggest_available_port "$external_port" "$service_name")
                print_colored $YELLOW "Suggested alternative: $alternative"
            fi
        done
    fi

    local port=$external_port
    
    # Window Name Configuration
    echo "Window Name"
    echo "Default: $default_window_name"
    read -p "$(print_colored $YELLOW "Enter window name (or press Enter for default): ")" user_window_name
    local window_name=${user_window_name:-$default_window_name}
    echo
    
    # Display final configuration
    echo "Final Configuration"
    echo "==================="
    echo "Image     : $full_image"
    echo "Container : $container_name"
    echo "Port Mapping: $external_port:$internal_port"
    echo "Window    : $window_name"
    echo
    
    read -p "$(print_colored $YELLOW "Continue with this configuration? (Y/n): ")" confirm_config
    if [ "$confirm_config" = "n" ] || [ "$confirm_config" = "N" ]; then
        print_colored $YELLOW "Installation cancelled."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    # Check if service already exists
    local service_name=$(echo "$selected_image" | sed 's/\//_/g')
    local service_config="$SERVICES_DIR/$service_name.conf"
    
    if [ -f "$service_config" ]; then
        print_colored $YELLOW "Service '$service_name' already exists!"
        read -p "$(print_colored $YELLOW "Do you want to reinstall? (y/N): ")" reinstall
        if [ "$reinstall" != "y" ] && [ "$reinstall" != "Y" ]; then
            return
        fi
    fi
    
    print_colored $YELLOW "Creating container from pulled image: $full_image"
    # Image already pulled during port detection
    
    # Create container
    if ! UDOCKER_LOGLEVEL=3 udocker create --name="$container_name" "$full_image"; then
        print_colored $RED "Failed to create container: $container_name"
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    # Setup container
    if ! UDOCKER_LOGLEVEL=3 udocker setup --execmode=P1 "$container_name"; then
        print_colored $RED "Failed to setup container: $container_name"
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
        
    # Create data directory for the service
    local service_data_dir="$DATA_DIR/$service_name"
    mkdir -p "$service_data_dir"
    
    # Create service configuration
    cat > "$service_config" << EOF
SERVICE_NAME=$service_name
IMAGE=$full_image
CONTAINER_NAME=$container_name
EXTERNAL_PORT=$external_port
INTERNAL_PORT=$internal_port
PORT=$port
WINDOW_NAME=$window_name
DATA_DIR=$service_data_dir
INSTALL_DATE="$(date)"
EOF
    
    print_colored $GREEN "Service '$service_name' installed successfully!"
    echo "Service Details:"
    echo "   - Name: $service_name"
    echo "   - Image: $full_image"
    echo "   - Container: $container_name"
    echo "   - Port: $port"
    echo "   - Data Directory: $service_data_dir"
    echo
    
    read -p "$(print_colored $YELLOW "Press Enter to continue...")"
}

# Function to run services
run_services() {
    clear_screen
    print_colored $YELLOW "Run Services"
    echo
    
    # Get list of installed services
    local services=($(ls "$SERVICES_DIR"/*.conf 2>/dev/null | xargs -r -n1 basename | sed 's/\.conf$//' 2>/dev/null))
    
    if [ ${#services[@]} -eq 0 ]; then
        print_colored $YELLOW "No services installed yet."
        print_colored $YELLOW "Use option 1 to install services first."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")" 
        return
    fi
    
    echo "Available Services:"
    for i in "${!services[@]}"; do
        local service_name="${services[$i]}"
        local status="$(check_service_status "$service_name")"
        echo "  [$((i+1))] $service_name ($status)"
    done
    echo "  [0] Back to main menu"
    echo
    
    read -p "$(print_colored $YELLOW "Select service to run: ")" service_choice
    
    if [ "$service_choice" = "0" ]; then
        return
    fi
    
    if ! [[ "$service_choice" =~ ^[0-9]+$ ]] || [ "$service_choice" -lt 1 ] || [ "$service_choice" -gt ${#services[@]} ]; then
        print_colored $RED "Invalid selection."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    local selected_service="${services[$((service_choice-1))]}"
    start_service "$selected_service"
}

# Function to check service status
check_service_status() {
    local service_name=$1
    
    # Check if tmux session exists and has the service window
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        if tmux list-windows -t "$TMUX_SESSION" 2>/dev/null | grep -q "$service_name"; then
            echo "Running"
        else
            echo "Stopped"
        fi
    else
        echo "Stopped"
    fi
}

# Function to start a service
start_service() {
    local service_name=$1
    local service_config="$SERVICES_DIR/$service_name.conf"
    
    if [ ! -f "$service_config" ]; then
        print_colored $RED "Service configuration not found: $service_name"
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    # Source the configuration
    source "$service_config"
    
    # Check if service is already running
    if [ "$(check_service_status "$service_name")" = "Running" ]; then
        print_colored $YELLOW "Service '$service_name' is already running!"
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    print_colored $YELLOW "Starting service: $service_name"
    
    # Check if tmux session exists
    local session_exists=false
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        session_exists=true
    fi
    
    # Create or attach to tmux session
    if [ "$session_exists" = false ]; then
        # Create new session but don't create initial window yet
        tmux new-session -d -s "$TMUX_SESSION"
        print_colored $GREEN "Created new tmux session: $TMUX_SESSION"
        
        # Rename the default window (window 0) to our service name
        tmux rename-window -t "$TMUX_SESSION:0" "$service_name"
        
        # Use stored port configuration
        local port_mapping="$EXTERNAL_PORT:$INTERNAL_PORT"
        local run_command="cd ~/Termux-Udocker && UDOCKER_LOGLEVEL=3 udocker run -p $port_mapping -v \"$DATA_DIR\":/app/.sessions \"$CONTAINER_NAME\""
        
        # Send the command to the existing window (window 0)
        tmux send-keys -t "$TMUX_SESSION:$service_name" "$run_command" C-m
    else
        # Session exists, create new window for the service
        tmux new-window -t "$TMUX_SESSION" -n "$service_name"
        
        # Use stored port configuration
        local port_mapping="$EXTERNAL_PORT:$INTERNAL_PORT"
        local run_command="cd ~/Termux-Udocker && UDOCKER_LOGLEVEL=3 udocker run -p $port_mapping -v \"$DATA_DIR\":/app/.sessions \"$CONTAINER_NAME\""
        
        # Send the command to the new window
        tmux send-keys -t "$TMUX_SESSION:$service_name" "$run_command" C-m
    fi
    
    print_colored $GREEN "Service '$service_name' started successfully!"
    echo "Service Details:"
    echo "   - Access URL: http://localhost:$PORT"
    echo "   - tmux Session: $TMUX_SESSION"
    echo "   - tmux Window: $service_name"
    echo "   - Data Directory: $DATA_DIR"
    
    echo "Management Commands:"
    echo "   - View logs: tmux attach-session -t $TMUX_SESSION"
    echo "   - Switch to service: tmux select-window -t $TMUX_SESSION:$service_name"
    echo
    
    read -p "$(print_colored $YELLOW "Press Enter to continue...")"
}

# Function to remove services
remove_services() {
    clear_screen
    print_colored $YELLOW "Remove Services"
    echo
    
    # Get list of installed services
    local services=($(ls "$SERVICES_DIR"/*.conf 2>/dev/null | xargs -r -n1 basename | sed 's/\.conf$//' 2>/dev/null))
    
    if [ ${#services[@]} -eq 0 ]; then
        print_colored $YELLOW "No services installed."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")" 
        return
    fi
    
    echo "Installed Services:"
    for i in "${!services[@]}"; do
        local service_name="${services[$i]}"
        local status="$(check_service_status "$service_name")"
        echo "  [$((i+1))] $service_name ($status)"
    done
    echo "  [0] Back to main menu"
    echo
    
    read -p "$(print_colored $YELLOW "Select service to remove: ")" service_choice
    
    if [ "$service_choice" = "0" ]; then
        return
    fi
    
    if ! [[ "$service_choice" =~ ^[0-9]+$ ]] || [ "$service_choice" -lt 1 ] || [ "$service_choice" -gt ${#services[@]} ]; then
        print_colored $RED "Invalid selection."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    local selected_service="${services[$((service_choice-1))]}"
    
    print_colored $YELLOW "Are you sure you want to remove '$selected_service'?"
    print_colored $RED "This will delete all service data and configurations!"
    echo
    read -p "$(print_colored $YELLOW "Type 'YES' to confirm: ")" confirm
    
    if [ "$confirm" != "YES" ]; then
        print_colored $YELLOW "Removal cancelled."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    remove_service "$selected_service"
}

# Function to remove a service
remove_service() {
    local service_name=$1
    local service_config="$SERVICES_DIR/$service_name.conf"
    
    if [ ! -f "$service_config" ]; then
        print_colored $RED "Service configuration not found: $service_name"
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")"
        return
    fi
    
    # Source the configuration
    source "$service_config"
    
    print_colored $YELLOW "Removing service: $service_name"
    
    # Stop the service if running
    if [ "$(check_service_status "$service_name")" = "Running" ]; then
        print_colored $YELLOW "Stopping service..."
        tmux kill-window -t "$TMUX_SESSION:$service_name" 2>/dev/null
    fi
    
    # Remove udocker container
    print_colored $YELLOW "Removing container..."
    udocker rm "$CONTAINER_NAME" 2>/dev/null
    
    # Remove udocker image
    print_colored $YELLOW "Removing image..."
    udocker rmi "$IMAGE" 2>/dev/null
    
    # Remove service data directory
    if [ -d "$DATA_DIR" ]; then
        print_colored $YELLOW "Removing data directory..."
        rm -rf "$DATA_DIR"
    fi
    
    # Remove service configuration
    rm -f "$service_config"
    
    print_colored $GREEN "Service '$service_name' removed successfully!"
    echo
    read -p "$(print_colored $YELLOW "Press Enter to continue...")"
}

# Function to list services
list_services() {
    clear_screen
    print_colored $YELLOW "Service List"
    echo
    
    # Get list of installed services
    local services=($(ls "$SERVICES_DIR"/*.conf 2>/dev/null | xargs -r -n1 basename | sed 's/\.conf$//' 2>/dev/null))
    
    if [ ${#services[@]} -eq 0 ]; then
        print_colored $YELLOW "No services installed."
        echo
        read -p "$(print_colored $YELLOW "Press Enter to continue...")" 
        return
    fi
    
    echo "Installed Services:"
    echo
    
    for service_name in "${services[@]}"; do
        local service_config="$SERVICES_DIR/$service_name.conf"
        source "$service_config"
        local status="$(check_service_status "$service_name")"
        
        if [ "$status" = "Running" ]; then
            print_colored $GREEN "$service_name"
        else
            print_colored $RED "$service_name"
        fi
        
        echo "   Image: $IMAGE"
        echo "   Port: $PORT"
        echo "   Data: $DATA_DIR"
        echo "   Status: $status"
        if [ "$status" = "Running" ]; then
            echo "   URL: http://localhost:$PORT"
        fi
        echo
    done
    
    # Show tmux session info
    if tmux has-session -t "$TMUX_SESSION" 2>/dev/null; then
        echo "tmux Session: $TMUX_SESSION"
        echo "   Windows: $(tmux list-windows -t "$TMUX_SESSION" 2>/dev/null | wc -l)"
        echo "   Attach: tmux attach-session -t $TMUX_SESSION"
    fi
    
    echo
    read -p "$(print_colored $YELLOW "Press Enter to continue...")" 
}

# Function to show main menu
show_main_menu() {
    print_header
    
    echo "Main Menu:"
    echo "  [1] Install New Service"
    echo "  [2] Run Services"
    echo "  [3] Remove Services"
    echo "  [4] List Services"
    echo "  [5] Exit"
    echo
    
    read -p "$(print_colored $YELLOW "Select option (1-5): ")" choice
    
    case $choice in
        1)
            install_service
            ;;
        2)
            run_services
            ;;
        3)
            remove_services
            ;;
        4)
            list_services
            ;;
        5)
            clear_screen
            print_colored $GREEN "Thank you for using Docker Service Manager!"
            echo "GitHub: https://github.com/your-repo"
            exit 0
            ;;
        *)
            print_colored $RED "Invalid option. Please select 1-5."
            echo
            read -p "$(print_colored $YELLOW "Press Enter to continue...")"
            ;;
    esac
}

# Main function
main() {
    # Check dependencies first
    check_dependencies
    
    # Main loop
    while true; do
        show_main_menu
    done
}

# Run the script
main "$@"
