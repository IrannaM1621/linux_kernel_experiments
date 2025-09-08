#include<linux/init.h>
#include<linux/module.h>
#include<linux/kdev_t.h>
#include<linux/fs.h>
#include<linux/cdev.h>
#include<linux/uaccess.h>

#define DEVICE_NAME "char_driver"
#define BUFFER_SIZE 1024

static int major;
static char device_buffer[BUFFER_SIZE] = {0};
static struct cdev my_cdev;
static struct class *my_class;

static int char_open(struct inode *inode, struct file *file)
{
	pr_info("simple driver opened\n");
	return 0;
}

static int char_release(struct inode* inode, struct file *file)
{
	pr_info("simple drivevr closed\n");
	return 0;
}

static ssize_t char_read(struct file *file, char __user *buf , size_t count, loff_t *ppos)
{
	if(*ppos > BUFFER_SIZE) {
		pr_err("Number of copy bytes are more count = %zu\n", count);
		return -ENOMEM;
	}
	
	if(*ppos + count > BUFFER_SIZE)
		count = BUFFER_SIZE - *ppos;
	
	
	if(copy_to_user(buf, device_buffer + *ppos, count)) {
		pr_err("error in copy_to_user\n");
		return -EFAULT;
	}
	
	*ppos += count;
	return count;
}


static ssize_t char_write(struct file *file, const char __user *buf, size_t count, loff_t *ppos)
{
	pr_info("write count = %zu\n", count); 
	if(*ppos > BUFFER_SIZE){
		pr_err("Number of copy bytes are more count = %zu \n", count);
		return -ENOMEM;
	}
	
	if(*ppos + count > BUFFER_SIZE)
		count = BUFFER_SIZE - *ppos;
	
	if(copy_from_user(device_buffer + *ppos, buf, count)) {
		pr_err("error in copy_from_user\n");
		return -EFAULT;
	}
	
	*ppos +=count;
	 pr_info("char_write: received %zu bytes\n", count);
	return count;
}


static struct file_operations fops = {
	.owner	   = THIS_MODULE,
	.open      = char_open,
	.release   = char_release,
	.read 	   = char_read,
	.write	   = char_write,
};

static char * char_devnode(const struct device *dev, umode_t *mode)
{
	if(mode)
		*mode = 0666;
	return NULL;
}

static int __init char_init(void)
{
	dev_t dev;
	int ret;
	/*
	* &dev: Pointer to dev_t variable where the allocated major/minor number pair is stored.
	* 0: Starting minor number (we use minor = 0).
	* 1: Number of devices to allocate (we want 1 device).
	* DEVICE_NAME: The name shown in /proc/devices.
	*/
	ret = alloc_chrdev_region(&dev, 0, 1, DEVICE_NAME);
	if(ret <0) {
		pr_err("Failed to allocate chardev region\n");
		return ret;
	}

	major = MAJOR(dev);

	/*Initializes the cdev structure (my_cdev) and links it with your file_operations (fops).*/
	cdev_init(&my_cdev, &fops);

	my_cdev.owner = THIS_MODULE;
	/* 
	*   Adds your character device to the kernel using the cdev structure and dev_t from earlier.
	*  Registers your device with the kernel so it knows how to handle operations on it.
	*  The 1 means you’re adding one device (with one minor number).
	*/
	ret = cdev_add(&my_cdev, dev, 1);
	if(ret < 0) {
		unregister_chrdev_region(dev,1);
		pr_err("Failed to add cdev\n");
		return ret;
	}
	
	my_class = class_create( DEVICE_NAME);
	if(IS_ERR(my_class)) {
		cdev_del(&my_cdev);
		unregister_chrdev_region(dev,1);
		pr_err("Failed to create the Class\n");
		return PTR_ERR(my_class);
	}
	
	my_class->devnode = char_devnode;
	device_create(my_class, NULL, dev, NULL, DEVICE_NAME);
	pr_info("simple char dev: Loaded successfully\n");
	pr_info("Major = %d\n", major);
	return 0;
}

static void __exit char_exit(void)
{
	device_destroy(my_class, MKDEV(major, 0));
	class_destroy(my_class);
	cdev_del(&my_cdev);
	unregister_chrdev_region(MKDEV(major, 0), 1);
	pr_info("simple char dev: unloaded successfully\n");
}

module_init(char_init);
module_exit(char_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Iranna M");
MODULE_DESCRIPTION("Simple Character Driver");
	
