#!/bin/bash

printf "\033[31mChecking if Docker is running...\033[0m\n"

if ! pgrep -x "dockerd" > /dev/null; then
    printf "\033[31mDocker is not running. Starting Docker...\033[0m\n"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        mkdir -p ~/goinfre/com.docker.docker && rm -rf ~/Library/Containers/com.docker.docker && ln -s ~/goinfre/com.docker.docker ~/Library/Containers/com.docker.docker && open -a /Applications/Docker.app
    else
        sudo systemctl start docker
    fi

    printf "\033[31mWaiting for Docker to launch...\033[0m\n"
    while ! docker system info > /dev/null 2>&1; do
        sleep 1
    done
fi

printf "\033[32mDocker is running.\033[0m\n"
printf "\033[31mPulling debian:experimental image...\033[0m\n"
docker pull debian:experimental

printf "\033[31mAppending the aliases to ~/.valiant_aliases \033[0m\n"

if [ -f ~/.valiant_aliases ]; then
    /bin/rm ~/.valiant_aliases
fi

/bin/cat <<EOL > ~/.valiant_aliases
alias valiant-build='docker build -t valiant-img ~/Documents/valiant_docker/'
alias valiant-start='docker run -v \$(pwd):/app -it valiant-img'
alias edit-valias='vim ~/.valiant_aliases'

dock() {
    mkdir -p ~/goinfre/com.docker.docker
    rm -rf ~/Library/Containers/com.docker.docker
    ln -s ~/goinfre/com.docker.docker ~/Library/Containers/com.docker.docker
    open -a /Applications/Docker.app
}

alias sz='source ~/.zshrc'
alias vza='vim ~/.valiant_aliases'
alias edit_docker='vim ~/Documents/valiant_docker/Dockerfile'
EOL

printf "\033[32mAppending success.\033[0m\n"

printf "\033[31mAppending to ~/.zshrc to source the aliases\033[0m\n"

if ! grep -Fxq "source ~/.valiant_aliases" ~/.zshrc; then
    echo "source ~/.valiant_aliases" >> ~/.zshrc
fi

printf "\033[32mAppending success.\033[0m\n"

printf "\033[31mCreating the Dockerfile\033[0m\n"

if [ ! -d ~/Documents/valiant_docker ]; then
    mkdir -p ~/Documents/valiant_docker
fi

if [ -f ~/Documents/valiant_docker/Dockerfile ]; then
    printf "\033[31mDockerfile already exists, overwriting\033[0m\n"
    /bin/rm ~/Documents/valiant_docker/Dockerfile
fi

cat <<EOF > ~/Documents/valiant_docker/Dockerfile
FROM debian:experimental

RUN echo "deb http://deb.debian.org/debian/ experimental main contrib non-free non-free-firmware" > /etc/apt/sources.list.d/experimental.list

# Install packages (including zsh-theme-powerlevel9k)
RUN apt-get update && apt-get upgrade -y && \
    apt-get install --no-install-recommends --no-install-suggests -y \
    gcc \
    make \
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
    g++ \
    zsh-theme-powerlevel9k \
    llvm-21 \
    libclang-rt-21-dev \
    clang-tools-21 \
    clang-tidy-21 \
    clang-21 \
    libbsd-dev \
    build-essential \
    netcat-openbsd \
    libx11-dev \
    libxext-dev \
    libxrandr-dev \
    libxi-dev \
    libxinerama-dev \
    libxcursor-dev \
    xorg-dev \
    libreadline-dev && \
    apt-get clean

RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-21 100 \
    && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-21 100 \
    && update-alternatives --install /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-21 100 \
    && update-alternatives --install /usr/bin/cc cc /usr/bin/clang 100 \
    && update-alternatives --install /usr/bin/c++ c++ /usr/bin/clang++ 100

# Install Oh My Zsh
RUN sh -c "\$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

# Add aliases to .zshrc
RUN echo "alias val='valgrind --leak-check=full --leak-resolution=high -s --show-leak-kinds=all --leak-check-heuristics=all --num-callers=500 --sigill-diagnostics=yes --track-origins=yes --undef-value-errors=yes'" >> ~/.zshrc

ENV TSAN_OPTIONS="second_deadlock_stack=1,history_size=7,memory_limit_mb=4096,detect_deadlocks=1" ASAN_OPTIONS="detect_leaks=1,leak_check_at_exit=true,leak_check=true,debug=true"
ENV TERM="xterm-256color"
WORKDIR /app/

CMD ["/bin/zsh"]
EOF

printf "\033[32mDockerfile created.\033[0m\n"

printf "\033[32m Install success, restart the open terminals to be able to use the image\033[0m\n"

printf "\033[32m Run dock to start docker\033[0m\n"
printf "\033[32m Run valiant-build to build the image\033[0m\n"
printf "\033[32m Run valiant-start to start the container\033[0m\n"
printf "\033[32m Run edit-valias to edit the aliases\033[0m\n"
