# Linux Character Driver Example

This project demonstrates a basic Linux character driver that allocates major and minor numbers.

## Files

- `basic_major.c`: Implements a simple character driver that allocates a range of device numbers.
- `char_drv.c`: (If exists) Another character driver implementation.
- `Makefile`: Build system for compiling the kernel modules.

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
   sudo insmod basic_major.ko
   ```

2. Check the kernel logs to see the allocated major and minor numbers:
   ```bash
   dmesg | tail
   ```
   You should see output similar to:
   ```
   major init
   Major = X, minor = 0
   ```

3. Check the device numbers in /proc/devices:
   ```bash
   cat /proc/devices | grep Iranna
   ```

4. Unload the module:
   ```bash
   sudo rmmod basic_major
   ```

## Cleaning Up

To clean the build files:
```bash
make clean
```

## License

This project is licensed under the GPL license.
