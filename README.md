# valiantdocker
### A Linux based docker container containing valgrind and other usefull tools not installed by default. 
#### Mainly usefull for running valgrind in 42 lab computers, which can then be used to test for memory leaks.

## Installation
Run the following command to automatically download the script and install the docker image.

``sh -c "$(curl -L https://raw.githubusercontent.com/assemblycalamity/valiantdocker/refs/heads/main/valiant_docker.sh)"``

## Features
- Valgrind memory analysis tools
- GDB debugger
- Other development utilities
- Pre-configured for C/C++ development
- Compatible with 42 school projects

## Usage

### Building and Starting
1. `valiant-build` - Build the docker image (only needed once or after updates).
2. `valiant-start` - Start a new docker container with the built image.
3. `dock` - start docker, especially if it is failing to start.

### Working with the Container
- Your current directory is automatically mounted inside the container at `/code`
- Any changes made to files will persist on your host machine
- To run valgrind on your program:
  ```
  cd /code
  make  # Compile your project
  valgrind ./your_program [args]
  ```

### Valgrind Examples
- Basic memory leak check:
  ```
  valgrind --leak-check=full ./your_program
  ```
- Detailed leak checking with origin tracking:
  ```
  valgrind --leak-check=full --show-leak-kinds=all --track-origins=yes ./your_program
  ```
- Save output to a file:
  ```
  valgrind --leak-check=full --log-file=valgrind-report.txt ./your_program
  ```
- For the paranoid
  ```
  valgrind --leak-check=full --leak-resolution=high -s --track-origins=yes \
           --num-callers=500 --show-mismatched-frees=yes --show-leak-kinds=all \
           --track-fds=yes --trace-children=yes --gen-suppressions=no \
           --error-limit=no --undef-value-errors=yes --expensive-definedness-checks=yes \
           --malloc-fill=0x41 --free-fill=0x42 --read-var-info=yes --keep-debuginfo=yes \
           --show-realloc-size-zero=yes --partial-loads-ok=no \
           ./your_program
  ```

### Aliases
Custom aliases can be configured and edited in the `~/.valiant-aliases` file.
Some useful aliases that are already set up:
- `val` - Run valgrind with common memory checking parameters


### Exiting the Container
Type `exit` or press `Ctrl+D` to leave the container shell.

## Troubleshooting
If you encounter any issues:
- Make sure Docker is installed and running
- Try rebuilding the container with `valiant-build`
- Ensure you have read/write permissions for the current directory
- Run the script again

## Contributing
Feel free to contribute to this project by submitting issues or pull requests on GitHub.
