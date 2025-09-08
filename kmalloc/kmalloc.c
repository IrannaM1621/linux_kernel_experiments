#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/slab.h>    // kmalloc, kfree, ksize
#include <linux/init.h>

#define REQUEST_SIZE 1000  // Example requested size

static int __init kmalloc_test_init(void)
{
    u8 *buf;

    pr_info("kmalloc_test: Module init\n");

    // Allocate memory
    buf = kmalloc(REQUEST_SIZE, GFP_KERNEL);
    if (!buf) {
        pr_err("kmalloc_test: kmalloc failed\n");
        return -ENOMEM;
    }

    // Print requested vs actual allocated size
    pr_info("kmalloc_test: Requested %zu bytes, Actually allocated %zu bytes\n",
            (size_t)REQUEST_SIZE, ksize(buf));
    
	// Free memory
    kfree(buf);

    return 0;
}

static void __exit kmalloc_test_exit(void)
{
    pr_info("kmalloc_test: Module exit\n");
}

module_init(kmalloc_test_init);
module_exit(kmalloc_test_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Iranna M");
MODULE_DESCRIPTION("Test actual kmalloc allocation size using ksize()");

