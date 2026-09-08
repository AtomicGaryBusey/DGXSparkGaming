/* namedobj32.c — does a NAMED-OBJECT COLLISION fault Wine's 32-bit syscall return path?
 *
 * WHY THIS EXISTS
 *   Prey (2006) and Quake 4 both log the same recurring fault under WINEDEBUG=+seh:
 *
 *     trace:seh:handle_syscall_fault code=c0000005 addr=0x4000d1f0 ip=4000d1f0
 *       info[0]=00000000  info[1]=0000007c        <- a READ of null+0x7c
 *       eax=c0000035 ebx=0 ecx=0 esi=0 edi=00000004
 *       ebp=02e9f7e8 esp=02e9f4ac                 <- IDENTICAL on all 276 faults
 *     backtrace: ntdll.so + 0x71f0 (_init + 0x1f0)
 *     returning to user mode ip=7bf1d620 ret=c0000005
 *
 *   Three things in that record drive this probe:
 *
 *   1. `eax=c0000035` is STATUS_OBJECT_NAME_COLLISION — the ORDINARY status for
 *      creating a named kernel object that already exists. It is a success-ish
 *      return, not a crash. So a syscall COMPLETED and the fault is in the path
 *      that returns its status.
 *   2. esp/ebp/eax/edi are byte-identical across every occurrence, so it is one
 *      code path re-entered, not memory corruption wandering around.
 *   3. Wine HANDLES it ("returning to user mode"), which is why both games are
 *      playable regardless. It is only visible because +seh tracing was on.
 *
 *   THE QUESTION IT ANSWERS: is that fault caused by the object-name collision
 *   itself — a translator/Wine bug reachable by any 32-bit program — or is it
 *   something specific to id Tech 4 that merely happens to carry c0000035 in eax?
 *
 *   This matters because the fault was originally written up here as a "shared
 *   input-path bug" behind the odd mouse behaviour in both games. That label was
 *   already refuted once (tools/probes/dinput/ walks the whole DirectInput 8
 *   sequence and returns DI_OK with zero faults). This is the second, narrower
 *   hypothesis, and it is being tested BEFORE anything is written down — the
 *   pattern that should have been applied to the descriptor_buffer signature and
 *   the x87 tag-word attribution, both of which were published and retracted.
 *
 * BUILD (32-bit, matching every id Tech 4 title here):
 *   ~/dgx-gaming-work/toolchain/root/usr/bin/i686-w64-mingw32-gcc-win32 \
 *       -O1 -o namedobj32.exe namedobj32.c
 *
 * RUN — under BOTH translators, with SEH tracing on, or the result means nothing:
 *   WINEDEBUG=+seh tools/run-both.sh --wine namedobj32.exe
 *
 * THE ANSWER (2026-09-08) — Box64 bug #3, upstream, not ours
 *   Reproduced 100%, 1 fault per call, byte-identical to the games' record:
 *
 *     32-bit PE + Box64 (box32)  100 faults, CreateFileA/CreateDirectoryA return
 *                                err=998 ERROR_NOACCESS  <- WRONG
 *     32-bit PE + FEX              0 faults, err=80 / err=183               correct
 *     64-bit PE + Box64            0 faults, err=80 / err=183               correct
 *
 *   Identical under STOCK box64 v0.4.4 and under our patched build, so the two
 *   local patches did not cause it.
 *
 *   The trigger is exactly NtCreateFile with FILE_CREATE disposition returning
 *   STATUS_OBJECT_NAME_COLLISION. Everything adjacent is clean, which is what
 *   makes it narrow rather than "the filesystem is broken":
 *
 *     CreateMutex/Event/Semaphore/FileMapping on an existing NAME  clean, err=183
 *     CreateFileA OPEN_EXISTING on a missing file (c0000034)       clean, err=2
 *     CreateFileA CREATE_ALWAYS on an existing file (succeeds)     clean, err=183
 *     RemoveDirectoryA on a missing directory                      clean, err=2
 *
 *   So it is not "named objects" at all — the kernel-object collisions are fine.
 *   It is the filesystem create path, and only the collision status.
 *
 *   IT IS NOT COSMETIC. The fault REPLACES the status: Wine returns c0000005
 *   where c0000035 belonged ("returning to user mode ret=c0000005"), so the
 *   application receives ERROR_NOACCESS instead of ERROR_FILE_EXISTS /
 *   ERROR_ALREADY_EXISTS. "Create the directory, ignore it if it already
 *   exists" is one of the most common patterns in Windows code, and under box32
 *   it takes the error branch.
 *
 *   WHAT IT DOES NOT EXPLAIN: the odd mouse behaviour in Prey and Quake 4. This
 *   probe explains the FAULTS, which were only ever visible because +seh
 *   tracing was on and which Wine handles. Nothing here connects them to input.
 *   The mouse remains unexplained; see docs/OPEN-QUESTIONS.md.
 *
 * READING IT
 *   The probe's own stdout only proves it really produced collisions (each line
 *   must say ALREADY_EXISTS). The ANSWER is in the Wine trace around it:
 *
 *     faults present, both runtimes  -> Wine's 32-bit syscall return path; not a
 *                                       translator bug and not an id Tech 4 bug.
 *     faults present, one runtime    -> that translator is implicated.
 *     NO faults, both runtimes       -> collisions are NOT the trigger. The eax
 *                                       value is a coincidence of that code path
 *                                       and the id Tech 4 fault stays unexplained.
 *                                       Say so; do not invent a third story.
 */
#include <windows.h>
#include <stdio.h>

#define REPS 50

/* Markers go to STDERR, unbuffered, because that is where the Wine trace goes.
 * An earlier revision printed them to stdout and the block buffering made the
 * interleaving a lie: the CreateFileA line appeared in the middle of a fault run
 * it had nothing to do with, and the CreateDirectoryA line never appeared at all
 * before the log was cut. Ordering evidence is worthless unless both streams are
 * the same stream. */
static void mark(const char *what) {
    fflush(stdout);
    fprintf(stderr, "### PROBE-MARK %s\n", what);
    fflush(stderr);
}

static void report(const char *what, HANDLE h, DWORD err) {
    printf("  %-32s handle=%-10p err=%-6lu %s\n", what, (void *)h, (unsigned long)err,
           err == ERROR_ALREADY_EXISTS ? "ALREADY_EXISTS <- collision"
                                       : (h ? "created (no collision)" : "FAILED"));
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    setvbuf(stderr, NULL, _IONBF, 0);
    printf("32-bit named-object collision probe (%d reps each)\n", REPS);
    printf("--------------------------------------------------------------\n");

    /* Hold the first handle open so every later create is a genuine collision. */
    HANDLE m0 = CreateMutexA(NULL, FALSE, "Local\\dgxspark_probe_mutex");
    HANDLE e0 = CreateEventA(NULL, TRUE, FALSE, "Local\\dgxspark_probe_event");
    HANDLE s0 = CreateSemaphoreA(NULL, 1, 1, "Local\\dgxspark_probe_sem");
    HANDLE f0 = CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0,
                                   4096, "Local\\dgxspark_probe_map");
    printf("  anchors: mutex=%p event=%p sem=%p map=%p\n", m0, e0, s0, f0);

    /* Each of these returns a VALID handle plus ERROR_ALREADY_EXISTS, which is
     * STATUS_OBJECT_NAME_COLLISION (c0000035) at the syscall layer. */
    mark("CreateMutexA");
    for (int i = 0; i < REPS; i++) {
        SetLastError(0);
        HANDLE h = CreateMutexA(NULL, FALSE, "Local\\dgxspark_probe_mutex");
        DWORD e = GetLastError();
        if (i == 0) report("CreateMutexA (existing)", h, e);
        if (h) CloseHandle(h);
    }
    mark("CreateEventA");
    for (int i = 0; i < REPS; i++) {
        SetLastError(0);
        HANDLE h = CreateEventA(NULL, TRUE, FALSE, "Local\\dgxspark_probe_event");
        DWORD e = GetLastError();
        if (i == 0) report("CreateEventA (existing)", h, e);
        if (h) CloseHandle(h);
    }
    mark("CreateSemaphoreA");
    for (int i = 0; i < REPS; i++) {
        SetLastError(0);
        HANDLE h = CreateSemaphoreA(NULL, 1, 1, "Local\\dgxspark_probe_sem");
        DWORD e = GetLastError();
        if (i == 0) report("CreateSemaphoreA (existing)", h, e);
        if (h) CloseHandle(h);
    }
    mark("CreateFileMappingA");
    for (int i = 0; i < REPS; i++) {
        SetLastError(0);
        HANDLE h = CreateFileMappingA(INVALID_HANDLE_VALUE, NULL, PAGE_READWRITE, 0,
                                      4096, "Local\\dgxspark_probe_map");
        DWORD e = GetLastError();
        if (i == 0) report("CreateFileMappingA (existing)", h, e);
        if (h) CloseHandle(h);
    }

    /* CreateFileA with CREATE_NEW on an existing file is the FILE-object form of
     * the same status, and goes through a different syscall. */
    char tmp[MAX_PATH], path[MAX_PATH];
    GetTempPathA(sizeof tmp, tmp);
    wsprintfA(path, "%sdgxspark_probe.tmp", tmp);
    HANDLE fh = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, NULL);
    if (fh != INVALID_HANDLE_VALUE) CloseHandle(fh);
    mark("CreateFileA_CREATE_NEW");
    for (int i = 0; i < REPS; i++) {
        SetLastError(0);
        HANDLE h = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_NEW,
                               FILE_ATTRIBUTE_NORMAL, NULL);
        DWORD e = GetLastError();
        if (i == 0) report("CreateFileA CREATE_NEW (exists)", h, e);
        if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    }
    DeleteFileA(path);

    /* A directory collision too — same status, yet another syscall. */
    char dir[MAX_PATH];
    wsprintfA(dir, "%sdgxspark_probe_dir", tmp);
    CreateDirectoryA(dir, NULL);
    mark("CreateDirectoryA");
    for (int i = 0; i < REPS; i++) {
        SetLastError(0);
        BOOL ok = CreateDirectoryA(dir, NULL);
        DWORD e = GetLastError();
        if (i == 0) report("CreateDirectoryA (exists)", (HANDLE)(UINT_PTR)ok, e);
    }
    RemoveDirectoryA(dir);

    /* ---- Which failing status faults? ------------------------------------
     * The fault always carries eax=c0000035 (OBJECT_NAME_COLLISION). These
     * cases separate "a collision faults" from "any failing NtCreateFile
     * faults", which is the difference between a narrow bug and a broad one.
     * c0000034 (OBJECT_NAME_NOT_FOUND) is the adjacent status and the control. */
    char missing[MAX_PATH], missdir[MAX_PATH];
    wsprintfA(missing, "%sdgxspark_no_such_file.tmp", tmp);
    wsprintfA(missdir, "%sdgxspark_no_such_dir", tmp);
    DeleteFileA(missing); RemoveDirectoryA(missdir);

    mark("CreateFileA_OPEN_EXISTING_missing");   /* expect c0000034, NOT a collision */
    for (int i = 0; i < REPS; i++) {
        SetLastError(0);
        HANDLE h = CreateFileA(missing, GENERIC_READ, 0, NULL, OPEN_EXISTING,
                               FILE_ATTRIBUTE_NORMAL, NULL);
        if (i == 0) report("CreateFileA OPEN_EXISTING (missing)", h, GetLastError());
        if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    }

    mark("CreateFileA_CREATE_ALWAYS_existing");  /* succeeds, but sets ALREADY_EXISTS */
    HANDLE seed = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                              FILE_ATTRIBUTE_NORMAL, NULL);
    if (seed != INVALID_HANDLE_VALUE) CloseHandle(seed);
    for (int i = 0; i < REPS; i++) {
        SetLastError(0);
        HANDLE h = CreateFileA(path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                               FILE_ATTRIBUTE_NORMAL, NULL);
        if (i == 0) report("CreateFileA CREATE_ALWAYS (exists)", h, GetLastError());
        if (h != INVALID_HANDLE_VALUE) CloseHandle(h);
    }
    DeleteFileA(path);

    mark("RemoveDirectoryA_missing");            /* a non-create fs syscall */
    for (int i = 0; i < REPS; i++) {
        SetLastError(0);
        BOOL ok = RemoveDirectoryA(missdir);
        if (i == 0) report("RemoveDirectoryA (missing)", (HANDLE)(UINT_PTR)ok, GetLastError());
    }

    mark("done");
    if (m0) CloseHandle(m0);
    if (e0) CloseHandle(e0);
    if (s0) CloseHandle(s0);
    if (f0) CloseHandle(f0);

    printf("--------------------------------------------------------------\n");
    printf("Produced ~%d name collisions. Count faults in the Wine trace with a\n", REPS * 6);
    printf("pattern ANCHORED to the trace prefix, e.g. grep -c ':seh:.*c000''0005'.\n");
    printf("Do NOT grep for the bare fault code: an earlier revision of this probe\n");
    printf("printed the literal search strings in this very block, and the grep then\n");
    printf("matched the probe's own stdout and reported a fault that never happened.\n");
    printf("Zero faults here means name collisions are NOT the trigger, and the\n");
    printf("id Tech 4 fault stays an open question. Do not guess a third time.\n");
    return 0;
}
