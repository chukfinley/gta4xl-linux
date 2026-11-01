/* reboot-to <download|recovery|...>: reboot(2) with RESTART2 so sec_reboot sees the command. */
#define SYS_sync 81
#define SYS_reboot 142
#define SYS_write 64
#define SYS_exit 93

static long sys(long n, long a, long b, long c, long d)
{
	register long x8 __asm__("x8") = n;
	register long x0 __asm__("x0") = a;
	register long x1 __asm__("x1") = b;
	register long x2 __asm__("x2") = c;
	register long x3 __asm__("x3") = d;

	__asm__ volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
	return x0;
}

static int run(int argc, char **argv)
{
	static const char usage[] = "usage: reboot-to <download|recovery|bootloader>\n";

	if (argc < 2) {
		sys(SYS_write, 2, (long)usage, sizeof(usage) - 1, 0);
		return 1;
	}
	sys(SYS_sync, 0, 0, 0, 0);
	/* LINUX_REBOOT_MAGIC1, MAGIC2, LINUX_REBOOT_CMD_RESTART2 */
	sys(SYS_reboot, 0xfee1dead, 672274793, 0xa1b2c3d4, (long)argv[1]);
	return 1;
}

__attribute__((used)) void cstart(long *sp)
{
	sys(SYS_exit, run((int)sp[0], (char **)(sp + 1)), 0, 0, 0);
}

__asm__(".global _start\n_start:\n mov x0, sp\n bl cstart\n");
