/*
 * Emit a seccomp BPF program, for `bwrap --add-seccomp-fd`, that applies to
 * the whole sandbox and refuses terminal input injection:
 *
 * - TIOCSTI pushes bytes into a terminal's input queue. Whatever is still
 *   queued when the sandbox exits is read by the host shell (CVE-2017-5226).
 * - TIOCLINUX can do the same on a Linux virtual console (CVE-2023-28100).
 *
 * Both are refused with EPERM; every other system call is allowed. The
 * request argument is compared on its low 32 bits only, because the kernel
 * truncates it to an unsigned int.
 *
 * The program targets the build machine's native architecture plus its
 * 32-bit compat ABIs, so a 32-bit binary cannot sidestep the rule.
 */
#include <errno.h>
#include <seccomp.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int add_arch(scmp_filter_ctx ctx, uint32_t arch) {
  int rc = seccomp_arch_add(ctx, arch);
  return rc == -EEXIST ? 0 : rc;
}

int main(void) {
  static const unsigned long requests[] = {TIOCSTI, TIOCLINUX};
  scmp_filter_ctx ctx;
  size_t i;
  int rc;

  ctx = seccomp_init(SCMP_ACT_ALLOW);
  if (ctx == NULL) {
    fputs("seccomp_init failed\n", stderr);
    return 1;
  }

  switch (seccomp_arch_native()) {
  case SCMP_ARCH_X86_64:
    if ((rc = add_arch(ctx, SCMP_ARCH_X86)) < 0 ||
        (rc = add_arch(ctx, SCMP_ARCH_X32)) < 0)
      goto fail;
    break;
  case SCMP_ARCH_AARCH64:
    if ((rc = add_arch(ctx, SCMP_ARCH_ARM)) < 0)
      goto fail;
    break;
  default:
    break;
  }

  for (i = 0; i < sizeof(requests) / sizeof(requests[0]); i++) {
    rc = seccomp_rule_add(ctx, SCMP_ACT_ERRNO(EPERM), SCMP_SYS(ioctl), 1,
                          SCMP_A1(SCMP_CMP_MASKED_EQ, 0xFFFFFFFFu,
                                  (scmp_datum_t)requests[i]));
    if (rc < 0)
      goto fail;
  }

  if ((rc = seccomp_export_bpf(ctx, STDOUT_FILENO)) < 0)
    goto fail;

  seccomp_release(ctx);
  return 0;

fail:
  fprintf(stderr, "building seccomp filter failed: %s\n", strerror(-rc));
  seccomp_release(ctx);
  return 1;
}
