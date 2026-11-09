// PACCModule.m - real Control Center modules (Wi-Fi, Cellular Data, Bluetooth, Hotspot) for CCock26 (zilvyn)
//
// One source file, built four times with -DPACC_KIND / -DPACC_MODULE / -DPACC_VC_CLASS. Each bundle shows up in
// Settings > Control Center like any other module. The module only draws the tile; the switching is done by the
// CCock26 tweak (class PACCRadioBridge), which presses the real Connectivity button.

#import <UIKit/UIKit.h>
#import <objc/message.h>

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
    // Bluetooth and Hotspot marks are drawn
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
    NSTimer *_timer;
    NSInteger _last;
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
    [v addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapped)]];
    _last = -2;
    self.view = v;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGRect b = self.view.bounds;
    _fill.frame = b;
    _fill.layer.cornerRadius = MIN(b.size.width, b.size.height) * 0.5;
    _glyph.frame = b;
    _glyph.image = PACCModGlyph(MIN(b.size.width, b.size.height) * 0.36);
}

- (NSInteger)state {
    Class B = NSClassFromString(@"PACCRadioBridge");
    SEL s = NSSelectorFromString(@"stateForKind:");
    if (!B || ![B respondsToSelector:s]) return -1;
    return ((NSInteger (*)(id, SEL, NSInteger))objc_msgSend)(B, s, PACC_KIND);
}

- (void)refresh {
    NSInteger st = [self state];
    if (st == _last) return;
    _last = st;
    BOOL on = (st == 1);
    [UIView animateWithDuration:0.2 animations:^{
        self->_fill.backgroundColor = PACCModOnColor();
        self->_fill.alpha = on ? 1.0 : 0.0;
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
- (UIViewController *)contentViewController {
    if (!_controller) _controller = [PACC_VC_CLASS new];
    return _controller;
}
- (UIViewController *)backgroundViewController { return nil; }
@end
