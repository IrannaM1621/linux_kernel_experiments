#include<linux/kernel.h>
#include<linux/module.h>
#include<linux/init.h>
#include<linux/fs.h>
#include<linux/version.h>

static dev_t first;


static int major_init(void)
{
	printk("major init\n");
	if((alloc_chrdev_region(&first,0, 3, "Iranna"))< 0) {
	
		printk(KERN_ERR "Unable to alloc region\n");
		return -1;
	}

	printk("Major = %d\t, minor = %d\t\n", MAJOR(first), MINOR(first));

	return 0;
}

static void major_exit(void) {
	unregister_chrdev_region(first, 3);
	printk("Major exit\n");
}

module_init(major_init);
module_exit(major_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Iranna M");
MODULE_DESCRIPTION("Major Minor Number allocation");


