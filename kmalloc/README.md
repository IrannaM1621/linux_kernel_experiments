# Linux Kernel kmalloc Test Module

This module demonstrates how to use `kmalloc()` for dynamic memory allocation in the Linux kernel and how to check the actual allocated memory size using `ksize()`.

## Overview

The module shows the difference between the requested memory size and the actual memory allocated by the kernel's slab allocator. This is particularly useful for understanding memory allocation overhead in the Linux kernel.

## Files

- `kmalloc.c`: The main module source code
- `Makefile`: Build system for compiling the kernel module

## Building the Module

1. Ensure you have the Linux kernel headers installed:
   ```bash
   sudo apt-get install linux-headers-$(uname -r)
   ```

2. Compile the module:
   ```bash
   make
   ```

## Loading and Testing the Module

1. Load the module:
   ```bash
   sudo insmod kmalloc.ko
   ```

2. Check the kernel logs to see the memory allocation information:
   ```bash
   dmesg | tail -n 5
   ```
   You should see output similar to:
   ```
   [ 1234.567890] kmalloc_test: Module init
   [ 1234.567891] kmalloc_test: Requested 1000 bytes, Actually allocated 1024 bytes
   ```
   Note how the kernel allocated more memory than requested due to memory alignment and slab allocation policies.

3. Unload the module:
   ```bash
   sudo rmmod kmalloc
   ```

4. Verify the module was unloaded:
   ```bash
   dmesg | tail -n 1
   ```
   Should show:
   ```
   [ 1234.567892] kmalloc_test: Module exit
   ```

## Key Concepts

- `kmalloc()`: Kernel function for dynamic memory allocation
- `kfree()`: Kernel function to free allocated memory
- `ksize()`: Returns the actual size of the allocated memory block
- `GFP_KERNEL`: Flag indicating normal kernel memory allocation

## Cleaning Up

To clean the build files:
```bash
make clean
```

## License

This project is licensed under the GPL license.
