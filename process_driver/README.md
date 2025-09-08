# Linux Process List Driver

This kernel module demonstrates how to iterate through the Linux kernel's process list and display information about each running process.

## Features

- Lists all currently running processes
- Displays process name, PID, and status for each process
- Simple and efficient implementation using kernel's task list

## Building the Module

1. Ensure you have the Linux kernel headers installed:
   ```bash
   sudo apt-get install linux-headers-$(uname -r)
   ```

2. Compile the module:
   ```bash
   make
   ```

## Loading and Using the Module

1. Load the module (requires root privileges):
   ```bash
   sudo insmod process.ko
   ```

2. View the process list in the kernel log:
   ```bash
   dmesg | tail -n 20  # Shows the last 20 lines of kernel log
   ```
   
   You should see output similar to:
   ```
   Task name = systemd, PID = 1, Status = 1
   Task name = kthreadd, PID = 2, Status = 1
   Task name = kworker/0:0, PID = 3, Status = 1
   ...
   ```

3. Unload the module when done:
   ```bash
   sudo rmmod process
   ```

## Understanding the Output

- **Task name**: The name of the process (command name)
- **PID**: Process ID
- **Status**: Process state (1=runnable, 2=uninterruptible sleep, 4=stopped, etc.)

## Key Concepts

- Uses the kernel's `task_struct` to access process information
- `for_each_process` macro to iterate through all processes
- Process states are represented as bit flags in the kernel

## Cleaning Up

To clean the build files:
```bash
make clean
```

## Security Note

This module requires root privileges to load and unload. Be cautious when loading kernel modules from untrusted sources.

## License

This project is licensed under the GPL license.
