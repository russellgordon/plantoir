/*
 * Runnable Swift (#493): readLine() flushes stdout first, for programs
 * compiled with the FULL standard library. Linked with
 * `-Xlinker --wrap=swift_stdlib_readLine_stdin`, so the library's own
 * readLine() reaches this, which flushes and then calls the library's real
 * entry point. Without it a prompt printed with `terminator: ""` is still in
 * stdout's buffer when the program reads, and the input line the page echoes
 * appears before the prompt (measured 2026-10-17). Embedded Swift has no
 * entry point of its own; ReadLineShim.swift is it, and flushes the same way.
 */
#include <stdio.h>
#include <sys/types.h>

ssize_t __real_swift_stdlib_readLine_stdin(unsigned char **line);

ssize_t __wrap_swift_stdlib_readLine_stdin(unsigned char **line) {
    fflush(stdout);
    return __real_swift_stdlib_readLine_stdin(line);
}
