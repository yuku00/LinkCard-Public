/* Load-only control: the compiler barrier emits no runtime instruction. */
__attribute__((used))
static const char MailLoadCheckVersion[] = "MailLoadCheck 0.1.0 | TrollFools native load-only control";

__attribute__((constructor, used, noinline))
static void MailLoadCheckInit(void)
{
    __asm__ __volatile__("" ::: "memory");
}
