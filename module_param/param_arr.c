#include<linux/module.h>
#include<linux/init.h>
#include<linux/param.h>
int param_array[3];
module_param_array(param_array, int, NULL, S_IRUSR | S_IWUSR);

static int param_array_init(void)
{
	printk("Param array Demo\n");
	for(int i = 0; i < 3; i++) {
		pr_alert("Param_array[%d] = %d\n", i, param_array[i]);
	}

	return 0;
}

static void param_array_exit(void)
{
	printk("Param array demo exit\n");
}

module_init(param_array_init);
module_exit(param_array_exit);


MODULE_LICENSE("GPL");
MODULE_AUTHOR("Iranna M");
MODULE_DESCRIPTION("Parameter array Demo");

