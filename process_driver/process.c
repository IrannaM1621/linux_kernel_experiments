#include<linux/module.h>
#include<linux/init.h>
#include<linux/sched.h>

static int process_init(void)
{
	struct task_struct *task;
	for_each_process(task) {
		printk("Task name = %s\t, PID = %d\t, Status = %d\n", task->comm, task->pid, task->__state);
	}
	return 0;

}

static void process_exit(void)
{
	printk("Process ListDriver Exit\n");
}

module_init(process_init);
module_exit(process_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Iranna M");
MODULE_DESCRIPTION("Process List Driver");
