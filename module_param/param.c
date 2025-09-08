#include<linux/module.h>
#include<linux/init.h>
#include<linux/param.h>

int param;
module_param(param, int, S_IRUSR | S_IWUSR);

static int param_init(void)
{
    printk(KERN_ALERT "Parameter Demo\n");
    printk(KERN_ALERT"Parameter = %d\n", param);

    return 0;
}

static void param_exit(void)
{
    printk("Param Demo exit\n");
}

module_init(param_init);
module_exit(param_exit);

MODULE_AUTHOR("Iranna M");
MODULE_LICENSE("GPL");
MODULE_DESCRIPTION("Parameter Demo");

