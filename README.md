# valiantdocker
### A Linux based docker container containing valgrind and other usefull tools not installed by default. 
#### Mainly usefull for running valgrind in 42 lab computers, which can then be used to test for memory leaks.

## Installation
Run the following command to automatically download the script and install the docker image.

``sh -c "$(curl -L https://raw.githubusercontent.com/assemblycalamity/valiantdocker/refs/heads/main/valiant_docker.sh)"``

## Usage
1. ``valiant-build`` to build the docker image.
2. ``valiant-start`` to start a new docker container with the built image.

Aliases can be configured and edited in the ``~/.valiant-aliases`` file.
