#!/bin/bash

# Configuration variables
DOCKER_IMAGE="alpine:experimental"
DOCKER_NAME="valiant-img"
VALIANT_DIR="${HOME}/Documents/valiant_docker"
ALIASES_FILE="${HOME}/.valiant_aliases"
SHELL_RC="${HOME}/.zshrc"

# Color codes
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

# Print message with color
print_msg() {
    local color="$1"
    local message="$2"
    # Fix for SC2059 - don't use variables in printf format string
    printf "%b%s%b\n" "${color}" "${message}" "${RESET}"
}

# Handle errors
handle_error() {
    print_msg "${RED}" "ERROR: $1"
    exit 1
}

# Check if docker is running and start if needed
ensure_docker_running() {
    print_msg "${RED}" "Checking if Docker is running..."
    
    if ! docker info > /dev/null 2>&1; then
        print_msg "${RED}" "Docker is not running. Starting Docker..."
        if [[ "${OSTYPE}" == "darwin"* ]]; then
            mkdir -p ~/goinfre/com.docker.docker && rm -rf ~/Library/Containers/com.docker.docker && ln -s ~/goinfre/com.docker.docker ~/Library/Containers/com.docker.docker && open -a /Applications/Docker.app
        else
            sudo systemctl start docker || handle_error "Failed to start Docker"
        fi

        print_msg "${RED}" "Waiting for Docker to launch..."
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
    print_msg "${RED}" "Setting up aliases in ${ALIASES_FILE}"
    
    cat > "${ALIASES_FILE}" <<EOL
alias valiant-build='docker build -t ${DOCKER_NAME} ${VALIANT_DIR}/'
alias valiant-start='docker run -v \$(pwd):/app -it ${DOCKER_NAME}'
alias edit-valias='vim ${ALIASES_FILE}'

dock() {
    mkdir -p ~/goinfre/com.docker.docker
    rm -rf ~/Library/Containers/com.docker.docker
    ln -s ~/goinfre/com.docker.docker ~/Library/Containers/com.docker.docker
    open -a /Applications/Docker.app
}

alias sz='source ${SHELL_RC}'
alias vza='vim ${ALIASES_FILE}'
alias edit_docker='vim ${VALIANT_DIR}/Dockerfile'
EOL

    print_msg "${GREEN}" "Aliases created successfully."
}

# Update shell configuration
update_shell_config() {
    print_msg "${RED}" "Updating ${SHELL_RC} to source the aliases"
    
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
    print_msg "${RED}" "Creating the Dockerfile"
    
    if [[ ! -d "${VALIANT_DIR}" ]]; then
        mkdir -p "${VALIANT_DIR}" || handle_error "Failed to create directory ${VALIANT_DIR}"
    fi

    if [[ -f "${VALIANT_DIR}/Dockerfile" ]]; then
        print_msg "${YELLOW}" "Dockerfile already exists, overwriting"
    fi

    cat > "${VALIANT_DIR}/Dockerfile" <<EOF
FROM alpine:experimental

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

# Main script
main() {
    ensure_docker_running
    
    print_msg "${RED}" "Pulling ${DOCKER_IMAGE} image..."
    docker pull "${DOCKER_IMAGE}" || handle_error "Failed to pull Docker image"
    
    setup_aliases
    update_shell_config
    create_dockerfile
    
    print_msg "${GREEN}" "Setup complete! Restart your terminal to use the new aliases."
    print_msg "${GREEN}" "Run 'dock' to start docker"
    print_msg "${GREEN}" "Run 'valiant-build' to build the image"
    print_msg "${GREEN}" "Run 'valiant-start' to start the container"
    print_msg "${GREEN}" "Run 'edit-valias' to edit the aliases"
}

# Run the script
main
