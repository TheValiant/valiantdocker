#!/bin/bash

# Configuration variables
DOCKER_IMAGE="alpine:edge"
DOCKER_NAME="valiant-img"
VALIANT_DIR="${HOME}/Documents/valiant_docker"
ALIASES_FILE="${HOME}/.valiant_aliases"

# Auto-detect shell configuration file
if [ -n "$BASH_VERSION" ]; then
    SHELL_RC="${HOME}/.bashrc"
    SHELL_NAME="bash"
elif [ -n "$ZSH_VERSION" ]; then
    SHELL_RC="${HOME}/.zshrc"
    SHELL_NAME="zsh"
else
    echo "ERROR: Unsupported shell. Only Bash and Zsh are supported."
    exit 1
fi

# Color codes
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# Print message with color
print_msg() {
    local color="$1"
    local message="$2"
    printf "%b%s%b\n" "${color}" "${message}" "${RESET}"
}

# Handle errors
handle_error() {
    print_msg "${RED}" "ERROR: $1"
    exit 1
}

# Check if docker is running and start if needed
ensure_docker_running() {
    print_msg "${YELLOW}" "Checking if Docker is running..."
    
    if ! docker info > /dev/null 2>&1; then
        print_msg "${YELLOW}" "Docker is not running. Starting Docker..."
        if [[ "${OSTYPE}" == "darwin"* ]]; then
            # Check if goinfre exists (42 school environment)
            if [[ -d "${HOME}/goinfre" ]]; then
                print_msg "${YELLOW}" "Detected goinfre directory, using it for Docker..."
                mkdir -p "${HOME}/goinfre/com.docker.docker"
                rm -rf "${HOME}/Library/Containers/com.docker.docker"
                ln -s "${HOME}/goinfre/com.docker.docker" "${HOME}/Library/Containers/com.docker.docker"
            fi
            open -a /Applications/Docker.app || handle_error "Failed to start Docker app"
        else
            # Try multiple methods to start Docker on Linux
            if command -v systemctl > /dev/null 2>&1; then
                print_msg "${YELLOW}" "Using systemctl to start Docker..."
                sudo systemctl start docker || handle_error "Failed to start Docker with systemctl"
            elif command -v service > /dev/null 2>&1; then
                print_msg "${YELLOW}" "Using service to start Docker..."
                sudo service docker start || handle_error "Failed to start Docker with service"
            else
                handle_error "Could not determine how to start Docker on this system"
            fi
        fi

        print_msg "${YELLOW}" "Waiting for Docker to launch..."
        local max_attempts=30
        local attempts=0
        while ! docker info > /dev/null 2>&1; do
            sleep 1
            attempts=$((attempts + 1))
            if [[ ${attempts} -ge ${max_attempts} ]]; then
                handle_error "Docker failed to start after ${max_attempts} seconds"
            fi
        done
    fi

    print_msg "${GREEN}" "Docker is running."
}

# Create aliases file
setup_aliases() {
    print_msg "${YELLOW}" "Setting up aliases in ${ALIASES_FILE}"
    
    # Check if file exists and prompt
    if [[ -f "${ALIASES_FILE}" ]]; then
        print_msg "${YELLOW}" "Aliases file already exists."
        read -p "Do you want to overwrite it? (y/N) " -n 1 -r
        echo # move to a new line
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_msg "${GREEN}" "Skipping aliases file creation."
            return
        fi
        print_msg "${YELLOW}" "Overwriting aliases file..."
    fi
    
    cat > "${ALIASES_FILE}" <<EOL
alias valiant-build='docker build -t ${DOCKER_NAME} ${VALIANT_DIR}/'
alias valiant-start='docker run -v \$(pwd):/app -it ${DOCKER_NAME}'
alias edit-valias='vim ${ALIASES_FILE}'

dock() {
EOL

    # Add macOS-specific dock function if on macOS
    if [[ "${OSTYPE}" == "darwin"* ]]; then
        cat >> "${ALIASES_FILE}" <<EOL
    if [[ -d "\${HOME}/goinfre" ]]; then
        mkdir -p "\${HOME}/goinfre/com.docker.docker"
        rm -rf "\${HOME}/Library/Containers/com.docker.docker"
        ln -s "\${HOME}/goinfre/com.docker.docker" "\${HOME}/Library/Containers/com.docker.docker"
    fi
    open -a /Applications/Docker.app
EOL
    else
        cat >> "${ALIASES_FILE}" <<EOL
    echo "dock function is only available on macOS"
EOL
    fi

    cat >> "${ALIASES_FILE}" <<EOL
}

alias sz='source ${SHELL_RC}'
alias vza='vim ${ALIASES_FILE}'
alias edit_docker='vim ${VALIANT_DIR}/Dockerfile'
EOL

    print_msg "${GREEN}" "Aliases created successfully."
}

# Update shell configuration
update_shell_config() {
    print_msg "${YELLOW}" "Updating ${SHELL_RC} to source the aliases"
    
    if ! grep -Fxq "source ${ALIASES_FILE}" "${SHELL_RC}"; then
        print_msg "${YELLOW}" "Adding source line to ${SHELL_RC}"
        echo "source ${ALIASES_FILE}" >> "${SHELL_RC}" || handle_error "Failed to update ${SHELL_RC}"
    else
        print_msg "${GREEN}" "${SHELL_RC} already configured"
    fi
    
    print_msg "${GREEN}" "Shell configuration updated successfully."
}

# Create Dockerfile
create_dockerfile() {
    print_msg "${YELLOW}" "Creating the Dockerfile"
    
    if [[ ! -d "${VALIANT_DIR}" ]]; then
        mkdir -p "${VALIANT_DIR}" || handle_error "Failed to create directory ${VALIANT_DIR}"
    fi

    if [[ -f "${VALIANT_DIR}/Dockerfile" ]]; then
        print_msg "${YELLOW}" "Dockerfile already exists."
        read -p "Do you want to overwrite it? (y/N) " -n 1 -r
        echo # move to a new line
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_msg "${GREEN}" "Skipping Dockerfile creation."
            return
        fi
        print_msg "${YELLOW}" "Overwriting Dockerfile..."
    fi

    cat > "${VALIANT_DIR}/Dockerfile" <<EOF
FROM alpine:edge

# Use edge repositories (including testing) to access newer packages
RUN echo "https://dl-cdn.alpinelinux.org/alpine/edge/main" > /etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/community" >> /etc/apk/repositories && \
    echo "https://dl-cdn.alpinelinux.org/alpine/edge/testing" >> /etc/apk/repositories

# Install packages
RUN apk update && apk upgrade --no-cache && \
    apk add --no-cache \
        build-base \
        gdb \
        valgrind \
        cppcheck \
        ltrace \
        strace \
        vim \
        zsh \
        curl \
        ca-certificates \
        git \
        bear \
        clang \
        clang-extra-tools \
        llvm \
        compiler-rt \
        libbsd \
        libbsd-dev \
        netcat-openbsd \
        shellcheck \
        readline-dev

# Install Oh My Zsh (non-interactive)
RUN CHSH=no RUNZSH=no KEEP_ZSHRC=yes sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Add aliases to .zshrc
RUN echo "alias val='valgrind --leak-check=full --leak-resolution=high -s --show-leak-kinds=all --leak-check-heuristics=all --num-callers=500 --sigill-diagnostics=yes --track-origins=yes --undef-value-errors=yes'" >> ~/.zshrc && \
    echo "alias valreaper='valgrind --leak-check=full --leak-resolution=high -s --track-origins=yes --num-callers=500 --show-mismatched-frees=yes --show-leak-kinds=all --track-fds=yes --trace-children=yes --gen-suppressions=no --error-limit=no --undef-value-errors=yes --expensive-definedness-checks=yes --malloc-fill=0x41 --free-fill=0x42 --read-var-info=yes --keep-debuginfo=yes --show-realloc-size-zero=yes --partial-loads-ok=no'" >> ~/.zshrc

ENV TSAN_OPTIONS="second_deadlock_stack=1,history_size=7,memory_limit_mb=4096,detect_deadlocks=1" ASAN_OPTIONS="detect_leaks=1,leak_check_at_exit=true,leak_check=true,debug=true"
ENV TERM="xterm-256color"
WORKDIR /app/

CMD ["/bin/zsh"]
EOF

    print_msg "${GREEN}" "Dockerfile created successfully."
}

# Uninstall function
uninstall() {
    print_msg "${YELLOW}" "Starting uninstallation..."
    
    # Remove aliases file
    if [[ -f "${ALIASES_FILE}" ]]; then
        rm -f "${ALIASES_FILE}"
        print_msg "${GREEN}" "Removed ${ALIASES_FILE}"
    fi
    
    # Remove source line from shell RC
    if [[ -f "${SHELL_RC}" ]]; then
        if grep -Fxq "source ${ALIASES_FILE}" "${SHELL_RC}"; then
            # Create a backup
            cp "${SHELL_RC}" "${SHELL_RC}.backup"
            grep -Fxv "source ${ALIASES_FILE}" "${SHELL_RC}" > "${SHELL_RC}.tmp"
            mv "${SHELL_RC}.tmp" "${SHELL_RC}"
            print_msg "${GREEN}" "Removed source line from ${SHELL_RC} (backup at ${SHELL_RC}.backup)"
        fi
    fi
    
    # Ask about Docker directory
    if [[ -d "${VALIANT_DIR}" ]]; then
        read -p "Do you want to remove ${VALIANT_DIR}? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "${VALIANT_DIR}"
            print_msg "${GREEN}" "Removed ${VALIANT_DIR}"
        else
            print_msg "${YELLOW}" "Kept ${VALIANT_DIR}"
        fi
    fi
    
    # Ask about Docker image and container
    if docker images | grep -q "${DOCKER_NAME}"; then
        read -p "Do you want to remove the Docker image '${DOCKER_NAME}'? (y/N) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            docker rmi "${DOCKER_NAME}" 2>/dev/null || print_msg "${YELLOW}" "Image may still be in use"
            print_msg "${GREEN}" "Attempted to remove Docker image"
        fi
    fi
    
    print_msg "${GREEN}" "Uninstallation complete!"
}

# Show usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Options:
    --uninstall    Remove all installed files and configurations
    --help         Show this help message

Without options, the script will set up the Valiant Docker environment.
EOF
    exit 0
}

# Main script
main() {
    # Parse arguments
    if [[ $# -gt 0 ]]; then
        case "$1" in
            --uninstall)
                uninstall
                exit 0
                ;;
            --help)
                usage
                ;;
            *)
                print_msg "${RED}" "Unknown option: $1"
                usage
                ;;
        esac
    fi
    
    ensure_docker_running
    
    print_msg "${YELLOW}" "Pulling ${DOCKER_IMAGE} image..."
    docker pull "${DOCKER_IMAGE}" || handle_error "Failed to pull Docker image"
    
    setup_aliases
    update_shell_config
    create_dockerfile
    
    print_msg "${GREEN}" "Setup complete! Restart your terminal or run 'source ${SHELL_RC}' to use the new aliases."
    print_msg "${GREEN}" "Detected shell: ${SHELL_NAME}"
    if [[ "${OSTYPE}" == "darwin"* ]]; then
        print_msg "${GREEN}" "Run 'dock' to start Docker"
    fi
    print_msg "${GREEN}" "Run 'valiant-build' to build the image"
    print_msg "${GREEN}" "Run 'valiant-start' to start the container"
    print_msg "${GREEN}" "Run 'edit-valias' to edit the aliases"
    print_msg "${YELLOW}" "To uninstall, run: $0 --uninstall"
}

# Run the script
main "$@"