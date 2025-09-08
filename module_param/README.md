# Linux Kernel Module Parameters

This directory contains two Linux kernel modules that demonstrate how to use module parameters:
1. `param.c` - Shows basic module parameter usage
2. `param_arr.c` - Demonstrates array parameters in kernel modules

## Module Descriptions

### 1. param.ko - Single Parameter Module
This module demonstrates how to pass a single integer parameter to a kernel module.

### 2. param_arr.ko - Array Parameter Module
This module shows how to pass an array of integers as a module parameter.

## Building the Modules

1. Ensure you have the Linux kernel headers installed:
   ```bash
   sudo apt-get install linux-headers-$(uname -r)
   ```

2. Compile the modules:
   ```bash
   make
   ```

## Loading and Testing the Modules

### For param.ko (Single Parameter)

1. Load the module with a parameter:
   ```bash
   sudo insmod param.ko param=42
   ```

2. Check the kernel logs:
   ```bash
   dmesg | tail -n 2
   ```
   Should show:
   ```
   Parameter Demo
   Parameter = 42
   ```

3. Unload the module:
   ```bash
   sudo rmmod param
   ```

### For param_arr.ko (Array Parameter)

1. Load the module with array parameters:
   ```bash
   sudo insmod param_arr.ko param_array=10,20,30
   ```

2. Check the kernel logs:
   ```bash
   dmesg | tail -n 4
   ```
   Should show:
   ```
   Param array Demo
   Param_array[0] = 10
   Param_array[1] = 20
   Param_array[2] = 30
   ```

3. Unload the module:
   ```bash
   sudo rmmod param_arr
   ```

## Key Concepts

- `module_param()`: Macro to declare a module parameter
- `module_param_array()`: Macro to declare an array parameter
- Parameter permissions (S_IRUSR | S_IWUSR): Controls read/write access to parameters in sysfs
- Parameters can be passed during module insertion or modified via sysfs

## Cleaning Up

To clean the build files:
```bash
make clean
```

## License

Both modules are licensed under the GPL license.
