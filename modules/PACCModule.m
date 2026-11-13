
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

#ifndef PACC_KIND
#define PACC_KIND 0
#endif

@interface PACC_VC_CLASS : UIViewController
@end

@interface PACC_MODULE : NSObject
@property (nonatomic, strong) id contentModuleContext;
@property (nonatomic, strong) PACC_VC_CLASS *controller;
- (UIViewController *)contentViewController;
- (UIViewController *)backgroundViewController;
@end

static UIImage *PACCModGlyph(CGFloat pt) {
    __unused UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold];
#if PACC_KIND == 0
    UIImage *i = [UIImage systemImageNamed:@"wifi" withConfiguration:cfg];
#elif PACC_KIND == 1
    UIImage *i = [UIImage systemImageNamed:@"cellularbars" withConfiguration:cfg] ?:
                 [UIImage systemImageNamed:@"antenna.radiowaves.left.and.right" withConfiguration:cfg];
#else
    UIImage *i = nil;
#endif
    if (i) return [i imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    CGFloat s = ceil(pt * 1.4);
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s)];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.blackColor setStroke];
        [UIColor.blackColor setFill];
#if PACC_KIND == 2
        CGPoint p[6] = {{0.22,0.30},{0.76,0.72},{0.50,0.94},{0.50,0.06},{0.76,0.28},{0.22,0.70}};
        UIBezierPath *path = [UIBezierPath bezierPath];
        for (int k = 0; k < 6; k++) {
            CGPoint q = CGPointMake(s * (0.1 + 0.8 * p[k].x), s * (0.06 + 0.88 * p[k].y));
            if (k == 0) [path moveToPoint:q]; else [path addLineToPoint:q];
        }
        path.lineWidth = s * 0.085; path.lineCapStyle = kCGLineCapRound; path.lineJoinStyle = kCGLineJoinRound;
        [path stroke];
#else
        CGPoint c = CGPointMake(s * 0.5, s * 0.5);
        UIBezierPath *ring = [UIBezierPath bezierPathWithArcCenter:c radius:s * 0.11 startAngle:0 endAngle:2 * M_PI clockwise:YES];
        ring.lineWidth = s * 0.085; [ring stroke];
        CGFloat radii[2] = {0.27, 0.43};
        for (int k = 0; k < 2; k++) {
            UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:c radius:s * radii[k]
                                                            startAngle:125.0 * M_PI / 180.0 endAngle:415.0 * M_PI / 180.0 clockwise:YES];
            arc.lineWidth = s * 0.085; arc.lineCapStyle = kCGLineCapRound;
            [arc stroke];
        }
#endif
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIColor *PACCModOnColor(void) {
#if PACC_KIND == 1 || PACC_KIND == 3
    return [UIColor colorWithRed:0.2 green:0.78 blue:0.35 alpha:1];
#else
    return [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1];
#endif
}

@implementation PACC_VC_CLASS {
    UIView *_fill;
    UIImageView *_glyph;
    UILabel *_title;
    UILabel *_sub;
    NSTimer *_timer;
    NSInteger _last;
}

+ (void)load {
    Protocol *p = objc_getProtocol("CCUIContentModuleContentViewController");
    if (p && !class_conformsToProtocol(self, p)) class_addProtocol(self, p);
}

- (void)loadView {
    UIView *v = [UIView new];
    v.backgroundColor = UIColor.clearColor;
    _fill = [UIView new];
    _fill.userInteractionEnabled = NO;
    _fill.alpha = 0.0;
    _fill.layer.cornerCurve = kCACornerCurveContinuous;
    _fill.layer.masksToBounds = YES;
    [v addSubview:_fill];
    _glyph = [UIImageView new];
    _glyph.contentMode = UIViewContentModeCenter;
    _glyph.tintColor = UIColor.whiteColor;
    _glyph.userInteractionEnabled = NO;
    [v addSubview:_glyph];
    _title = [UILabel new];
    _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _title.textColor = UIColor.whiteColor;
    _title.userInteractionEnabled = NO;
    [v addSubview:_title];
    _sub = [UILabel new];
    _sub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    _sub.textColor = [UIColor colorWithWhite:1 alpha:0.7];
    _sub.userInteractionEnabled = NO;
    [v addSubview:_sub];
    [v addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    _last = -2;
    self.view = v;
}

- (BOOL)isWide {
    CGSize z = self.view.bounds.size;
    return z.width > z.height * 1.4;
}

- (void)dumpTree:(UIView *)root {
    static BOOL done = NO;
    if (done) return;
    done = YES;
    NSMutableString *out = [NSMutableString stringWithFormat:@"\n[module %d tree]\n", (int)PACC_KIND];
    NSMutableArray *queue = [NSMutableArray arrayWithObject:@[root, @0]];
    NSUInteger n = 0;
    while (queue.count && n < 250) {
        NSArray *e = queue.firstObject; [queue removeObjectAtIndex:0]; n++;
        UIView *v = e[0]; NSInteger d = [e[1] integerValue];
        NSString *txt = [v isKindOfClass:UILabel.class] ? [NSString stringWithFormat:@" text='%@'", ((UILabel *)v).text] : @"";
        [out appendFormat:@"%*s%@ %@ hidden=%d%@%@\n", (int)d * 2, "", NSStringFromClass(v.class), NSStringFromCGRect(v.frame), v.hidden, txt,
            v == self.view ? @"  <== our view" : @""];
        for (UIView *sv in v.subviews) [queue addObject:@[sv, @(d + 1)]];
    }
    NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/Library/Preferences/ccock26-crash.log"];
    if (!h) { [@"" writeToFile:@"/var/mobile/Library/Preferences/ccock26-crash.log" atomically:NO encoding:NSUTF8StringEncoding error:nil];
              h = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/Library/Preferences/ccock26-crash.log"]; }
    [h seekToEndOfFile];
    [h writeData:[out dataUsingEncoding:NSUTF8StringEncoding]];
    [h closeFile];
}

- (void)hideStrayLabels {
    NSString *last = [[[NSBundle bundleForClass:self.class].bundleIdentifier componentsSeparatedByString:@"."].lastObject lowercaseString];
    UIView *root = self.view;
    for (int i = 0; i < 5 && root.superview; i++) root = root.superview;
    [self dumpTree:root];
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:root];
    NSUInteger visited = 0;
    while (queue.count && visited < 400) {
        UIView *v = queue.firstObject; [queue removeObjectAtIndex:0]; visited++;
        if (v == _title || v == _sub) continue;
        if ([v isKindOfClass:UILabel.class]) {
            NSString *t = ((UILabel *)v).text.lowercaseString;
            if (t.length && [t isEqualToString:last] && !v.hidden) v.hidden = YES;
        }
        [queue addObjectsFromArray:v.subviews];
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    BOOL wide = [self isWide];
    CGRect circle = b;
    if (wide) {
        CGFloat d = MIN(b.size.height - 20.0, 52.0);
        circle = CGRectMake((b.size.height - d) * 0.5, (b.size.height - d) * 0.5, d, d);
    }
    _fill.frame = circle;
    _fill.layer.cornerRadius = MIN(circle.size.width, circle.size.height) * 0.5;
    _glyph.frame = circle;
    _glyph.image = PACCModGlyph(MIN(circle.size.width, circle.size.height) * (wide ? 0.46 : 0.36));
    _title.hidden = !wide; _sub.hidden = !wide;
    if (wide) {
        CGFloat tx = CGRectGetMaxX(circle) + 10.0;
        CGFloat tw = MAX(0, b.size.width - tx - 10.0);
        _title.frame = CGRectMake(tx, b.size.height * 0.5 - 18.0, tw, 18.0);
        _sub.frame = CGRectMake(tx, b.size.height * 0.5 + 1.0, tw, 16.0);
    }
    _last = -2;
    [self refresh];
    if (wide) {
        [self hideStrayLabels];
        dispatch_async(dispatch_get_main_queue(), ^{ [self hideStrayLabels]; });
    }
}

- (NSInteger)state {
    Class B = NSClassFromString(@"PACCRadioBridge");
    SEL s = NSSelectorFromString(@"stateForKind:");
    if (!B || ![B respondsToSelector:s]) return -1;
    return ((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(B, s, PACC_KIND);
}

- (void)refresh {
    NSInteger st = [self state];
    BOOL wide = [self isWide];
    if (st == _last) return;
    _last = st;
    BOOL on = (st == 1);
    NSString *name = @"";
#if PACC_KIND == 0
    name = @"Wi-Fi";
#elif PACC_KIND == 1
    name = @"Cellular Data";
#elif PACC_KIND == 2
    name = @"Bluetooth";
#else
    name = @"Hotspot";
#endif
    _title.text = name;
    _sub.text = (st < 0) ? @"Unavailable" : (on ? @"On" : @"Off");
    [UIView animateWithDuration:0.2 animations:^{
        if (on) {
            self->_fill.backgroundColor = PACCModOnColor();
            self->_fill.alpha = 1.0;
        } else if (wide) {
            self->_fill.backgroundColor = [UIColor colorWithWhite:1 alpha:0.2];
            self->_fill.alpha = 1.0;
        } else {
            self->_fill.alpha = 0.0;
        }
        self->_glyph.alpha = (st < 0) ? 0.45 : 1.0;
    }];
}

- (void)tapped {
    Class B = NSClassFromString(@"PACCRadioBridge");
    SEL s = NSSelectorFromString(@"toggleKind:");
    if (!B || ![B respondsToSelector:s]) return;
    UIImpactFeedbackGenerator *g = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [g impactOccurred];
    ((void (*)(id, SEL, NSInteger))objc_msgSend)(B, s, PACC_KIND);
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws refresh]; });
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [_timer invalidate];
    __weak typeof(self) ws = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.7 repeats:YES block:^(NSTimer *t) { [ws refresh]; }];
    [self refresh];
}

- (void)viewDidDisappear:(BOOL)animated {
    [super viewDidDisappear:animated];
    [_timer invalidate]; _timer = nil;
}

- (void)dealloc { [_timer invalidate]; }

- (CGFloat)preferredExpandedContentHeight { return 0; }
- (CGFloat)preferredExpandedContentWidth { return 0; }
- (BOOL)providesOwnPlatter { return NO; }
- (BOOL)shouldBeginTransitionToExpandedContentModule { return NO; }
@end

@implementation PACC_MODULE
+ (void)load {
    Protocol *p = objc_getProtocol("CCUIContentModule");
    if (p && !class_conformsToProtocol(self, p)) class_addProtocol(self, p);
    NSLog(@"[CCock26] module %d loaded, protocol %d", (int)PACC_KIND, p != NULL);
}
- (UIViewController *)contentViewController {
    if (!_controller) _controller = [PACC_VC_CLASS new];
    return _controller;
}
- (UIViewController *)backgroundViewController { return nil; }
@end
