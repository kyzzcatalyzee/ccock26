#import "CCOCK18RootListController.h"
#import <Preferences/PSSpecifier.h>
#import <spawn.h>
#import <unistd.h>
#import <rootless.h>

#define kCCLogPath @"/var/mobile/Library/Preferences/ccock26-crash.log"

@interface CCOCK18LogViewController : UIViewController
@end

@implementation CCOCK18LogViewController {
    UITextView *_text;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Crash Log";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    _text = [[UITextView alloc] initWithFrame:self.view.bounds];
    _text.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _text.editable = NO;
    _text.font = [UIFont fontWithName:@"Menlo" size:10] ?: [UIFont systemFontOfSize:10];
    [self.view addSubview:_text];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Close" style:UIBarButtonItemStylePlain target:self action:@selector(close)];
    self.navigationItem.rightBarButtonItems = @[
        [[UIBarButtonItem alloc] initWithTitle:@"Clear" style:UIBarButtonItemStylePlain target:self action:@selector(clear)],
        [[UIBarButtonItem alloc] initWithTitle:@"Copy" style:UIBarButtonItemStylePlain target:self action:@selector(copyAll)],
    ];
    [self reload];
}
- (void)reload {
    NSString *t = [NSString stringWithContentsOfFile:kCCLogPath encoding:NSUTF8StringEncoding error:nil];
    if (!t.length) t = @"(empty)\n\nNo log yet. The log starts after the next respring.";
    _text.text = t;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self->_text.text.length) [self->_text scrollRangeToVisible:NSMakeRange(self->_text.text.length - 1, 1)];
    });
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (void)copyAll { UIPasteboard.generalPasteboard.string = _text.text ?: @""; }
- (void)clear {
    [@"" writeToFile:kCCLogPath atomically:NO encoding:NSUTF8StringEncoding error:nil];
    [self reload];
}
@end

@implementation CCOCK18RootListController

- (void)showCrashLog {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[CCOCK18LogViewController new]];
    [self presentViewController:nav animated:YES completion:nil];
}

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

- (void)respring {
    pid_t pid;
    const char *args[] = { "killall", "-9", "SpringBoard", NULL };
    posix_spawn(&pid, ROOT_PATH("/usr/bin/killall"), NULL, NULL, (char *const *)args, NULL);
}

@end