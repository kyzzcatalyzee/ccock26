#import "PACC.h"
#import <signal.h>
#import <execinfo.h>
#import <fcntl.h>
#import <unistd.h>
#import <string.h>
#import <stdio.h>
#import <dlfcn.h>
#import <sys/stat.h>

#define kPACCLogPath "/var/mobile/Library/Preferences/ccock26-crash.log"
#define kPACCCrumbCount 10
#define kPACCCrumbLen 96

static int gLogFD = -1;
static char gCrumbs[kPACCCrumbCount][kPACCCrumbLen];
static volatile unsigned gCrumbIndex = 0;
static void *gImageBase = NULL;
static struct sigaction gOldActions[32];
static NSUncaughtExceptionHandler *gOldExceptionHandler = NULL;

static void PACCCrashWrite(const char *s) {
    if (gLogFD < 0 || !s) return;
    ssize_t r = write(gLogFD, s, strlen(s)); (void)r;
}

void PACCCrumb(const char *label) {
    if (!label) return;
    unsigned i = gCrumbIndex++ % kPACCCrumbCount;
    strlcpy(gCrumbs[i], label, kPACCCrumbLen);
}

void PACCCrashLog(NSString *line) {
    if (gLogFD < 0 || !line.length) return;
    NSString *out = [NSString stringWithFormat:@"[%.0f] %@\n", [NSDate date].timeIntervalSince1970, line];
    PACCCrashWrite(out.UTF8String);
}

static void PACCCrashDump(const char *title) {
    char buf[256];
    snprintf(buf, sizeof(buf), "\n===== CRASH: %s  (time %ld) =====\n", title, (long)time(NULL));
    PACCCrashWrite(buf);
    snprintf(buf, sizeof(buf), "tweak image base: %p\nlast steps (oldest first):\n", gImageBase);
    PACCCrashWrite(buf);
    for (unsigned k = 0; k < kPACCCrumbCount; k++) {
        unsigned i = (gCrumbIndex + k) % kPACCCrumbCount;
        if (!gCrumbs[i][0]) continue;
        PACCCrashWrite("  ");
        PACCCrashWrite(gCrumbs[i]);
        PACCCrashWrite("\n");
    }
    PACCCrashWrite("backtrace:\n");
    void *frames[64];
    int n = backtrace(frames, 64);
    if (gLogFD >= 0) backtrace_symbols_fd(frames, n, gLogFD);
    PACCCrashWrite("===== end =====\n");
    if (gLogFD >= 0) fsync(gLogFD);
}

static void PACCSignalHandler(int sig, siginfo_t *info, void *ctx) {
    char name[32];
    snprintf(name, sizeof(name), "signal %d", sig);
    PACCCrashDump(name);
    struct sigaction *old = (sig > 0 && sig < 32) ? &gOldActions[sig] : NULL;
    if (old && (old->sa_flags & SA_SIGINFO) && old->sa_sigaction) {
        old->sa_sigaction(sig, info, ctx);
    } else if (old && old->sa_handler != SIG_DFL && old->sa_handler != SIG_IGN && old->sa_handler) {
        old->sa_handler(sig);
    } else {
        signal(sig, SIG_DFL);
        raise(sig);
    }
}

static void PACCExceptionHandler(NSException *e) {
    PACCCrashWrite("\n===== UNCAUGHT EXCEPTION =====\n");
    PACCCrashWrite(e.name.UTF8String ?: "?");
    PACCCrashWrite("\n");
    PACCCrashWrite(e.reason.UTF8String ?: "?");
    PACCCrashWrite("\n");
    for (NSString *s in e.callStackSymbols) {
        PACCCrashWrite(s.UTF8String);
        PACCCrashWrite("\n");
    }
    PACCCrashDump("exception");
    if (gOldExceptionHandler) gOldExceptionHandler(e);
}

%ctor {
    @autoreleasepool {
        struct stat st;
        if (stat(kPACCLogPath, &st) == 0 && st.st_size > 96 * 1024) unlink(kPACCLogPath);
        gLogFD = open(kPACCLogPath, O_WRONLY | O_CREAT | O_APPEND, 0666);
        if (gLogFD < 0) return;
        chmod(kPACCLogPath, 0666);
        Dl_info di;
        if (dladdr((void *)PACCCrumb, &di)) gImageBase = di.dli_fbase;

        NSString *ver = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleIdentifier"] ?: @"?";
        PACCCrashLog([NSString stringWithFormat:@"CCock26 loaded in %@ (image %p)", ver, gImageBase]);

        gOldExceptionHandler = NSGetUncaughtExceptionHandler();
        NSSetUncaughtExceptionHandler(&PACCExceptionHandler);
        int sigs[] = { SIGSEGV, SIGBUS, SIGABRT, SIGILL, SIGTRAP, SIGFPE };
        for (size_t i = 0; i < sizeof(sigs) / sizeof(sigs[0]); i++) {
            struct sigaction sa;
            memset(&sa, 0, sizeof(sa));
            sa.sa_sigaction = PACCSignalHandler;
            sa.sa_flags = SA_SIGINFO;
            sigemptyset(&sa.sa_mask);
            sigaction(sigs[i], &sa, &gOldActions[sigs[i]]);
        }
    }
}
