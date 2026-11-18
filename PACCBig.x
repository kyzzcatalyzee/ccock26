
#import "PACC.h"
#import <CFNetwork/CFNetwork.h>
#import <notify.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/runtime.h>
#include <time.h>
#include <dlfcn.h>
#import <UIKit/UIGestureRecognizerSubclass.h>
#include <stdio.h>

static const NSInteger kPACBigTag = 182100;
static NSString * const kPACBigMaskName = @"pac.big";

#pragma mark - small helpers

static id PACBigKV(id obj, NSString *key) {
    if (!obj || !key.length) return nil;
    @try { return [obj valueForKey:key]; } @catch (__unused NSException *e) { return nil; }
}

static void PACBigCollect(UIView *root, Class cls, int depth, NSMutableArray *out) {
    for (UIView *s in root.subviews) {
        if (s.tag == kPACBigTag) continue;
        if ([s isKindOfClass:cls]) [out addObject:s];
        if (depth < 10) PACBigCollect(s, cls, depth + 1, out);
    }
}

int PACCBigKind(NSString *mid) {
    NSString *l = mid.lowercaseString;
    if (!l.length) return 0;
    if ([l hasPrefix:@"pacc.toggle."]) return 3;
    if ([l containsString:@"connectivity"]) return 1;
    if ([l containsString:@"nowplaying"] || [l containsString:@"mediacontrols"]) return 2;
    return 0;
}

BOOL PACCBigSizeAllowed(NSString *mid, NSUInteger w, NSUInteger h) {
    int k = PACCBigKind(mid);
    if (k == 1) return (w == 2 && h == 2) || (w == 4 && (h == 4 || h == 6));
    if (k == 2) return (w == 2 && h == 2) || (w == 4 && (h == 2 || h == 4 || h == 6));
    if (k == 3) return (w == 1 && h == 1) || (w == 2 && h == 1);
    return NO;
}

void PACCBigSnapSize(NSString *mid, NSInteger wantW, NSInteger wantH, NSUInteger *outW, NSUInteger *outH) {
    NSUInteger cands[][2] = { {1, 1}, {2, 1}, {2, 2}, {4, 2}, {4, 4}, {4, 6} };
    NSInteger best = NSIntegerMax;
    NSUInteger bw = 2, bh = 2;
    for (size_t i = 0; i < sizeof(cands) / sizeof(cands[0]); i++) {
        if (!PACCBigSizeAllowed(mid, cands[i][0], cands[i][1])) continue;
        NSInteger d = labs((long)((NSInteger)cands[i][0] - wantW)) * 2 + labs((long)((NSInteger)cands[i][1] - wantH));
        if (d < best) { best = d; bw = cands[i][0]; bh = cands[i][1]; }
    }
    *outW = bw; *outH = bh;
}

#pragma mark - MediaRemote and volume

typedef void (*PACBigInfoFn)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef Boolean (*PACBigSendFn)(int, CFDictionaryRef);

static void *PACBigMR(void) {
    static void *h; static dispatch_once_t once;
    dispatch_once(&once, ^{ h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY); });
    return h;
}

static void PACBigSend(int cmd, NSDictionary *opts) {
    void *h = PACBigMR();
    PACBigSendFn fn = h ? (PACBigSendFn)dlsym(h, "MRMediaRemoteSendCommand") : NULL;
    if (fn) fn(cmd, (__bridge CFDictionaryRef)opts);
}

static id PACBigAVSys(void) {
    Class c = NSClassFromString(@"AVSystemController");
    SEL s = NSSelectorFromString(@"sharedAVSystemController");
    return (c && [c respondsToSelector:s]) ? ((id (*)(id, SEL))objc_msgSend)(c, s) : nil;
}

static float PACBigGetVolume(void) {
    Class mc = NSClassFromString(@"SBMediaController");
    SEL sh = NSSelectorFromString(@"sharedInstance");
    id m = (mc && [mc respondsToSelector:sh]) ? ((id (*)(id, SEL))objc_msgSend)(mc, sh) : nil;
    SEL g = NSSelectorFromString(@"volume");
    if (m && [m respondsToSelector:g]) return MAX(0.f, MIN(1.f, ((float (*)(id, SEL))objc_msgSend)(m, g)));
    id av = PACBigAVSys();
    SEL g2 = NSSelectorFromString(@"getVolume:forCategory:");
    if (av && [av respondsToSelector:g2]) {
        float v = 0;
        if (((BOOL (*)(id, SEL, float *, id))objc_msgSend)(av, g2, &v, @"Audio/Video")) return MAX(0.f, MIN(1.f, v));
    }
    return MAX(0.f, MIN(1.f, [[AVAudioSession sharedInstance] outputVolume]));
}

static void PACBigSetVolume(float v) {
    v = MAX(0.f, MIN(1.f, v));
    Class mc = NSClassFromString(@"SBMediaController");
    SEL sh = NSSelectorFromString(@"sharedInstance");
    id m = (mc && [mc respondsToSelector:sh]) ? ((id (*)(id, SEL))objc_msgSend)(mc, sh) : nil;
    SEL st = NSSelectorFromString(@"setVolume:");
    if (m && [m respondsToSelector:st]) { ((void (*)(id, SEL, float))objc_msgSend)(m, st, v); return; }
    id av = PACBigAVSys();
    SEL s2 = NSSelectorFromString(@"setVolumeTo:forCategory:");
    if (av && [av respondsToSelector:s2]) ((BOOL (*)(id, SEL, float, id))objc_msgSend)(av, s2, v, @"Audio/Video");
}

static NSString *PACBigTime(double t, BOOL negative) {
    if (t < 0) t = 0;
    int s = (int)t;
    return [NSString stringWithFormat:@"%@%d:%02d", negative ? @"-" : @"", s / 60, s % 60];
}

#pragma mark - slider

@interface PACBigBar : UIControl
@property (nonatomic) CGFloat value;
@property (nonatomic, readonly) BOOL dragging;
@property (nonatomic, copy) void (^onChange)(CGFloat v, BOOL finished);
@end

@implementation PACBigBar {
    UIView *_track, *_fill;
    NSMutableArray<UIGestureRecognizer *> *_locked;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _track = [UIView new];
        _track.backgroundColor = [UIColor colorWithWhite:1 alpha:0.25];
        _track.userInteractionEnabled = NO;
        _track.clipsToBounds = YES;
        [self addSubview:_track];
        _fill = [UIView new];
        _fill.backgroundColor = UIColor.whiteColor;
        [_track addSubview:_fill];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = 7.0;
    _track.bounds = CGRectMake(0, 0, self.bounds.size.width, h);
    _track.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    _track.layer.cornerRadius = h * 0.5;
    [self applyFill];
}
- (void)applyFill {
    CGFloat v = MAX(0, MIN(1, _value));
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    _fill.frame = CGRectMake(0, 0, _track.bounds.size.width * v, _track.bounds.size.height);
    [CATransaction commit];
}
- (void)setValue:(CGFloat)value {
    if (_dragging) return;
    _value = value;
    [self applyFill];
}
- (void)lock {
    if (_locked) return;
    _locked = [NSMutableArray array];
    for (UIView *w = self.superview; w; w = w.superview) {
        for (UIGestureRecognizer *gr in w.gestureRecognizers) {
            if (!gr.enabled) continue;
            if ([gr isKindOfClass:UIPanGestureRecognizer.class] || [gr isKindOfClass:UISwipeGestureRecognizer.class]) {
                gr.enabled = NO;
                [_locked addObject:gr];
            }
        }
    }
}
- (void)unlock {
    for (UIGestureRecognizer *gr in _locked) gr.enabled = YES;
    _locked = nil;
}
- (void)grow:(BOOL)on {
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.55 initialSpringVelocity:0.8
                        options:UIViewAnimationOptionAllowUserInteraction | UIViewAnimationOptionBeginFromCurrentState
                     animations:^{ self->_track.transform = on ? CGAffineTransformMakeScale(1.0, 1.9) : CGAffineTransformIdentity; }
                     completion:nil];
}
- (CGFloat)valueForTouch:(UITouch *)t {
    CGFloat w = self.bounds.size.width;
    return w > 1 ? MAX(0, MIN(1, [t locationInView:self].x / w)) : 0;
}
- (BOOL)beginTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    _dragging = YES;
    [self lock];
    [self grow:YES];
    if (gHapticsEnabled) Haptic();
    _value = [self valueForTouch:t];
    [self applyFill];
    if (self.onChange) self.onChange(_value, NO);
    return YES;
}
- (BOOL)continueTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e {
    _value = [self valueForTouch:t];
    [self applyFill];
    if (self.onChange) self.onChange(_value, NO);
    return YES;
}
- (void)finish:(BOOL)commit {
    _dragging = NO;
    [self unlock];
    [self grow:NO];
    if (commit && self.onChange) self.onChange(_value, YES);
}
- (void)endTrackingWithTouch:(UITouch *)t withEvent:(UIEvent *)e { [self finish:YES]; }
- (void)cancelTrackingWithEvent:(UIEvent *)e { [self finish:NO]; }
@end

#pragma mark - connectivity cards

@interface PACBigCard : UIControl
@property (nonatomic, copy) NSString *key;
@property (nonatomic, weak) UIControl *target;
@property (nonatomic, weak) UIView *labeled;
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *sub;
@property (nonatomic) BOOL isOn;
@property (nonatomic) BOOL tall;
@property (nonatomic) BOOL iconOnly;
@property (nonatomic, copy) void (^onTap)(void);
@property (nonatomic, copy) void (^onMenu)(PACBigCard *card);
@property (nonatomic, strong) UIView *material;
@property (nonatomic, copy) NSString *subPlain;
- (void)setOn:(BOOL)on;
- (void)setSubText:(NSString *)text;
- (void)tapped;
@end

static UIColor *PACBigOnColor(NSString *key) {
    if ([key isEqualToString:@"air"]) return [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1];
    if ([key isEqualToString:@"ringeroff"]) return [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1];
    if ([key isEqualToString:@"cell"] || [key isEqualToString:@"hotspot"]) return [UIColor colorWithRed:0.2 green:0.78 blue:0.35 alpha:1];
    return [UIColor colorWithRed:0.04 green:0.52 blue:1.0 alpha:1];
}

static NSString *PACBigKey(NSString *title) {
    NSString *t = title.lowercaseString;
    if ([t containsString:@"airplane"] || [t containsString:@"aeroplane"] || [t containsString:@"pesawat"]) return @"air";
    if ([t containsString:@"wi-fi"] || [t containsString:@"wifi"] || [t containsString:@"wlan"]) return @"wifi";
    if ([t containsString:@"airdrop"]) return @"airdrop";
    if ([t containsString:@"cellular"] || [t containsString:@"mobile"] || [t containsString:@"seluler"]) return @"cell";
    if ([t containsString:@"bluetooth"]) return @"bt";
    if ([t containsString:@"hotspot"]) return @"hotspot";
    return title.length ? title : @"?";
}

static UIImage *PACBigSymbol(NSArray<NSString *> *names, CGFloat pt) {
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold];
    for (NSString *n in names) {
        UIImage *i = [UIImage systemImageNamed:n withConfiguration:cfg];
        if (i) return [i imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    }
    return nil;
}

static UIImage *PACBigDrawn(NSString *kind, CGFloat pt) {
    CGFloat s = ceil(pt * 1.4);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat preferredFormat];
    UIGraphicsImageRenderer *r = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(s, s) format:fmt];
    UIImage *img = [r imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.blackColor setStroke];
        [UIColor.blackColor setFill];
        if ([kind isEqualToString:@"bt"]) {
            CGPoint p[6] = {{0.22,0.30},{0.76,0.72},{0.50,0.94},{0.50,0.06},{0.76,0.28},{0.22,0.70}};
            UIBezierPath *path = [UIBezierPath bezierPath];
            for (int i = 0; i < 6; i++) {
                CGPoint q = CGPointMake(s * (0.1 + 0.8 * p[i].x), s * (0.06 + 0.88 * p[i].y));
                if (i == 0) [path moveToPoint:q]; else [path addLineToPoint:q];
            }
            path.lineWidth = s * 0.085; path.lineCapStyle = kCGLineCapRound; path.lineJoinStyle = kCGLineJoinRound;
            [path stroke];
        } else {
            CGPoint c = CGPointMake(s * 0.5, s * 0.56);
            CGFloat radii[3] = {0.15, 0.28, 0.41};
            for (int i = 0; i < 3; i++) {
                UIBezierPath *arc = [UIBezierPath bezierPathWithArcCenter:c radius:s * radii[i]
                                                                startAngle:130.0 * M_PI / 180.0 endAngle:410.0 * M_PI / 180.0 clockwise:YES];
                arc.lineWidth = s * 0.075; arc.lineCapStyle = kCGLineCapRound;
                [arc stroke];
            }
            [[UIBezierPath bezierPathWithOvalInRect:CGRectMake(c.x - s * 0.06, c.y - s * 0.06, s * 0.12, s * 0.12)] fill];
        }
    }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

static UIImage *PACBigIconForKey(NSString *key, CGFloat pt) {
    if ([key isEqualToString:@"ringer"])    return PACBigSymbol(@[@"bell.fill"], pt);
    if ([key isEqualToString:@"ringeroff"]) return PACBigSymbol(@[@"bell.slash.fill"], pt);
    if ([key isEqualToString:@"air"])     return PACBigSymbol(@[@"airplane"], pt);
    if ([key isEqualToString:@"wifi"])    return PACBigSymbol(@[@"wifi"], pt);
    if ([key isEqualToString:@"cell"])    return PACCGlyphPNG(@"cellularbars") ?: PACBigSymbol(@[@"cellularbars", @"antenna.radiowaves.left.and.right"], pt);
    if ([key isEqualToString:@"bt"])      return PACBigDrawn(@"bt", pt);
    if ([key isEqualToString:@"airdrop"]) return PACBigSymbol(@[@"airdrop"], pt) ?: PACBigDrawn(@"airdrop", pt);
    if ([key isEqualToString:@"vpn"]) {
        UIImage *p = PACCBundledSymbol(@"network.connected.to.line.below.fill", UIColor.whiteColor, NO);
        if (p) {
            UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold];
            return [[p imageByApplyingSymbolConfiguration:c] ?: p imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
        return PACBigSymbol(@[@"network", @"globe"], pt);
    }
    if ([key isEqualToString:@"hotspot"]) return PACCGlyphPNG(@"personalhotspot") ?: PACBigSymbol(@[@"personalhotspot", @"antenna.radiowaves.left.and.right.circle"], pt);
    return PACBigSymbol(@[@"circle.fill"], pt);
}

BOOL PACBigLGGlass(UIView *host, CGFloat radius);

@implementation PACBigCard
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.backgroundColor = UIColor.clearColor;
        self.clipsToBounds = YES;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        _material = PACCModuleMaterial();
        _material.userInteractionEnabled = NO;
        [self addSubview:_material];
        _icon = [UIImageView new];
        _icon.contentMode = UIViewContentModeCenter;
        _icon.tintColor = UIColor.whiteColor;
        _icon.userInteractionEnabled = NO;
        [self addSubview:_icon];
        _title = [UILabel new];
        _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _title.textColor = UIColor.whiteColor;
        _title.userInteractionEnabled = NO;
        [self addSubview:_title];
        _sub = [UILabel new];
        _sub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        _sub.textColor = [UIColor colorWithWhite:1 alpha:0.7];
        _sub.userInteractionEnabled = NO;
        [self addSubview:_sub];
        [self addTarget:self action:@selector(tapped:forEvent:) forControlEvents:UIControlEventTouchUpInside];
        UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(longPressed:)];
        lp.minimumPressDuration = 0.35;
        [self addGestureRecognizer:lp];
    }
    return self;
}
- (BOOL)pacMenuCapable {
    return self.onMenu && self.enabled && ([_key isEqualToString:@"wifi"] || [_key isEqualToString:@"airdrop"] || [_key isEqualToString:@"bt"]);
}
- (void)longPressed:(UILongPressGestureRecognizer *)g {
    if (g.state != UIGestureRecognizerStateBegan || ![self pacMenuCapable]) return;
    if (gHapticsEnabled) Haptic();
    self.onMenu(self);
}
- (void)tapped:(id)sender forEvent:(UIEvent *)e {
    if ([self pacMenuCapable]) {
        UITouch *t = [[e touchesForView:self] anyObject];
        CGPoint p = t ? [t locationInView:self] : CGPointZero;
        BOOL onIcon = CGRectContainsPoint(CGRectInset(_icon.frame, -10.0, -10.0), p);
        if ([_key isEqualToString:@"airdrop"] || !onIcon) {
            if (gHapticsEnabled) Haptic();
            self.onMenu(self);
            return;
        }
    }
    [self tapped];
}
- (void)layoutSubviews {
    [self pacLayoutCore];
    if (PACCLIQGlassOn()) _material.hidden = PACBigLGGlass(self, self.layer.cornerRadius);
    else _material.hidden = NO;
    {
        NSMutableArray<UIView *> *q = [NSMutableArray arrayWithArray:self.subviews];
        NSUInteger seen = 0;
        while (q.count && seen++ < 40) {
            UIView *v = q.firstObject;
            [q removeObjectAtIndex:0];
            NSString *cn = NSStringFromClass(v.class);
            if ([cn hasPrefix:@"LG"] && [cn containsString:@"Backdrop"]) { PACBigFixLGRadius(v, self.layer.cornerRadius); continue; }
            [q addObjectsFromArray:v.subviews];
        }
    }
}
- (void)pacLayoutCore {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height, w = self.bounds.size.width;
    if (_material) {
        if (!CGRectEqualToRect(_material.frame, self.bounds)) _material.frame = self.bounds;
        [self sendSubviewToBack:_material];
    }
    _title.hidden = _iconOnly; _sub.hidden = _iconOnly;
    if (_iconOnly) {
        self.layer.cornerRadius = h * 0.5;
        _icon.frame = self.bounds;
        _icon.layer.cornerRadius = h * 0.5;
        _icon.layer.masksToBounds = YES;
        _icon.image = PACBigIconForKey(_key, h * 0.40);
        return;
    }
    if (_tall) {
        self.layer.cornerRadius = MIN(30.0, h * 0.24);
        CGFloat d = 38.0;
        _icon.frame = CGRectMake(14.0, 14.0, d, d);
        _icon.layer.cornerRadius = d * 0.5;
        _icon.layer.masksToBounds = YES;
        _icon.image = PACBigIconForKey(_key, d * 0.46);
        _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        _sub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        CGFloat tw = MAX(0, w - 28.0);
        _sub.frame = CGRectMake(14.0, h - 14.0 - 15.0, tw, 15.0);
        _title.frame = CGRectMake(14.0, h - 14.0 - 15.0 - 18.0, tw, 18.0);
        return;
    }
    self.layer.cornerRadius = MIN(h * 0.5, 36.0);
    _title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _sub.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
    CGFloat d = MIN(h - 20.0, 52.0);
    CGFloat x = (h - d) * 0.5;
    _icon.frame = CGRectMake(x, (h - d) * 0.5, d, d);
    _icon.layer.cornerRadius = d * 0.5;
    _icon.layer.masksToBounds = YES;
    _icon.image = PACBigIconForKey(_key, d * 0.46);
    CGFloat tx = x + d + 10.0;
    CGFloat tw = MAX(0, w - tx - 10.0);
    _title.frame = CGRectMake(tx, h * 0.5 - 18.0, tw, 18.0);
    _sub.frame = CGRectMake(tx, h * 0.5 + 1.0, tw, 16.0);
}
- (void)setSubText:(NSString *)text {
    BOOL chev = _tall && ([_key isEqualToString:@"wifi"] || [_key isEqualToString:@"airdrop"] || [_key isEqualToString:@"bt"]);
    NSString *sig = [NSString stringWithFormat:@"%@|%d", text, (int)chev];
    if ([_subPlain isEqualToString:sig]) return;
    _subPlain = sig;
    if (!chev) { _sub.attributedText = nil; _sub.text = text; return; }
    NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:[text stringByAppendingString:@" "]
                                                                          attributes:@{NSFontAttributeName: _sub.font, NSForegroundColorAttributeName: _sub.textColor}];
    UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightSemibold];
    UIImage *ci = [[UIImage systemImageNamed:@"chevron.up.chevron.down" withConfiguration:cfg] imageWithTintColor:[UIColor colorWithWhite:1 alpha:0.7] renderingMode:UIImageRenderingModeAlwaysOriginal];
    if (ci) {
        NSTextAttachment *att = [NSTextAttachment new];
        att.image = ci;
        att.bounds = CGRectMake(0, -1.0, ci.size.width, ci.size.height);
        [as appendAttributedString:[NSAttributedString attributedStringWithAttachment:att]];
    }
    _sub.attributedText = as;
}
- (void)setOn:(BOOL)on {
    _isOn = on;
    if (_tall) {
        _icon.backgroundColor = on ? PACBigOnColor(_key) : [UIColor colorWithWhite:1 alpha:0.2];
        _icon.tintColor = UIColor.whiteColor;
    } else {
        _icon.backgroundColor = on ? PACBigOnColor(_key) : [UIColor colorWithWhite:1 alpha:0.2];
        _icon.tintColor = UIColor.whiteColor;
    }
}
- (void)tapped {
    if (self.onTap) {
        if (gHapticsEnabled) Haptic();
        self.onTap();
        [UIView animateWithDuration:0.12 animations:^{ self.transform = CGAffineTransformMakeScale(0.95, 0.95); }
                         completion:^(BOOL f) {
            [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.4 options:0
                             animations:^{ self.transform = CGAffineTransformIdentity; } completion:nil];
        }];
        return;
    }
    UIControl *round = self.target;
    if (!round) return;
    if (gHapticsEnabled) Haptic();
    [round sendActionsForControlEvents:UIControlEventTouchUpInside];
    [round sendActionsForControlEvents:UIControlEventPrimaryActionTriggered];
    [UIView animateWithDuration:0.12 animations:^{ self.transform = CGAffineTransformMakeScale(0.95, 0.95); }
                     completion:^(BOOL f) {
        [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.9 options:0
                         animations:^{ self.transform = CGAffineTransformIdentity; } completion:nil];
    }];
}
@end

#pragma mark - base view

@interface PACBigView : UIView
@end

@implementation PACBigView
- (UIView *)caAnimationContainerView { return self; }
- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    NSMethodSignature *sig = [super methodSignatureForSelector:sel];
    return sig ?: [NSMethodSignature signatureWithObjCTypes:"@@:"];
}
- (void)forwardInvocation:(NSInvocation *)inv {
    id nothing = nil;
    if (inv.methodSignature.methodReturnLength == sizeof(id)) [inv setReturnValue:&nothing];
}
@end

#pragma mark - connectivity menu

static id sPACBigAirDrop;

static id PACBigAirDropCtl(void) {
    if (!sPACBigAirDrop) {
        Class C = NSClassFromString(@"SFAirDropDiscoveryController");
        if (!C) {
            dlopen("/System/Library/PrivateFrameworks/Sharing.framework/Sharing", RTLD_LAZY);
            C = NSClassFromString(@"SFAirDropDiscoveryController");
        }
        if (C) sPACBigAirDrop = [[C alloc] init];
    }
    return sPACBigAirDrop;
}

static int PACBigAirDropMode(void) {
    id c = PACBigAirDropCtl();
    SEL s = NSSelectorFromString(@"discoverableMode");
    if (!c || ![c respondsToSelector:s]) return -1;
    NSMethodSignature *sig = [c methodSignatureForSelector:s];
    if (!sig) return -1;
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = c;
    inv.selector = s;
    [inv invoke];
    if (sig.methodReturnType[0] == '@') {
        __unsafe_unretained id m = nil;
        [inv getReturnValue:&m];
        NSString *str = [m isKindOfClass:NSString.class] ? [(NSString *)m lowercaseString] : @"";
        if ([str containsString:@"every"]) return 2;
        if ([str containsString:@"contact"]) return 1;
        return 0;
    }
    long long v = 0;
    if (sig.methodReturnLength <= sizeof(v)) [inv getReturnValue:&v];
    return (int)MAX(0LL, MIN(2LL, v));
}

static BOOL PACBigSetAirDropMode(int mode) {
    id c = PACBigAirDropCtl();
    SEL s = NSSelectorFromString(@"setDiscoverableMode:");
    if (!c || ![c respondsToSelector:s]) return NO;
    NSMethodSignature *sig = [c methodSignatureForSelector:s];
    if (!sig || sig.numberOfArguments < 3) return NO;
    mode = MAX(0, MIN(2, mode));
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.target = c;
    inv.selector = s;
    if ([sig getArgumentTypeAtIndex:2][0] == '@') {
        NSArray *names = @[@"Off", @"ContactsOnly", @"Everyone"];
        __unsafe_unretained id arg = names[mode];
        [inv setArgument:&arg atIndex:2];
    } else {
        long long v = mode;
        [inv setArgument:&v atIndex:2];
    }
    [inv invoke];
    if (mode == 2) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(600.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (PACBigAirDropMode() == 2) PACBigSetAirDropMode(1);
        });
    }
    return YES;
}

static void PACBigOpenSettings(NSString *url) {
    Class W = NSClassFromString(@"LSApplicationWorkspace");
    SEL d = NSSelectorFromString(@"defaultWorkspace");
    if (!W || ![W respondsToSelector:d]) return;
    id ws = ((id (*)(id, SEL))objc_msgSend)(W, d);
    SEL o = NSSelectorFromString(@"openSensitiveURL:withOptions:");
    if (ws && [ws respondsToSelector:o]) ((BOOL (*)(id, SEL, id, id))objc_msgSend)(ws, o, [NSURL URLWithString:url], nil);
}

static NSDictionary *PACBigMenuItem(NSString *title, BOOL on, void (^act)(void)) {
    return @{@"t": title, @"on": @(on), @"a": [act copy]};
}

static UIColor *PACBigDyn(UIColor *dark, UIColor *light) {
    BOOL isDark = [UIScreen mainScreen].traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark;
    return isDark ? dark : light;
}

static id PACBigMakeBlur(CGFloat r) {
    Class C = NSClassFromString(@"CAFilter");
    SEL sel = NSSelectorFromString(@"filterWithType:");
    if (!C || ![C respondsToSelector:sel]) return nil;
    id f = ((id (*)(id, SEL, id))objc_msgSend)(C, sel, @"gaussianBlur");
    if (!f) return nil;
    @try {
        [f setValue:@(r) forKey:@"inputRadius"];
        [f setValue:@"pacBlur" forKey:@"name"];
    } @catch (...) { return nil; }
    return f;
}

static void PACBigAnimateBlur(UIView *v, CGFloat from, CGFloat to, CFTimeInterval dur, CFTimeInterval delay, BOOL clearAtEnd) {
    if (!v) return;
    id f = PACBigMakeBlur(to);
    if (!f) return;
    v.layer.filters = @[f];
    CABasicAnimation *a = [CABasicAnimation animationWithKeyPath:@"filters.pacBlur.inputRadius"];
    a.fromValue = @(from);
    a.toValue = @(to);
    a.duration = dur;
    a.beginTime = CACurrentMediaTime() + delay;
    a.fillMode = kCAFillModeBackwards;
    a.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
    [v.layer addAnimation:a forKey:@"PACBlur"];
    if (clearAtEnd) {
        __weak UIView *wv = v;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((delay + dur + 0.05) * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ wv.layer.filters = nil; });
    }
}

static CGPathRef PACBigBlobPath(CGSize sz, CGFloat tl, CGFloat tr, CGFloat br, CGFloat bl) {
    CGFloat w = sz.width, h = sz.height;
    CGFloat f = 1.0;
    if (tl + tr > 0.01) f = MIN(f, w / (tl + tr));
    if (bl + br > 0.01) f = MIN(f, w / (bl + br));
    if (tl + bl > 0.01) f = MIN(f, h / (tl + bl));
    if (tr + br > 0.01) f = MIN(f, h / (tr + br));
    tl *= f; tr *= f; br *= f; bl *= f;
    const CGFloat k = 0.5523;
    UIBezierPath *p = [UIBezierPath bezierPath];
    [p moveToPoint:CGPointMake(tl, 0)];
    [p addLineToPoint:CGPointMake(w - tr, 0)];
    [p addCurveToPoint:CGPointMake(w, tr) controlPoint1:CGPointMake(w - tr * (1.0 - k), 0) controlPoint2:CGPointMake(w, tr * (1.0 - k))];
    [p addLineToPoint:CGPointMake(w, h - br)];
    [p addCurveToPoint:CGPointMake(w - br, h) controlPoint1:CGPointMake(w, h - br * (1.0 - k)) controlPoint2:CGPointMake(w - br * (1.0 - k), h)];
    [p addLineToPoint:CGPointMake(bl, h)];
    [p addCurveToPoint:CGPointMake(0, h - bl) controlPoint1:CGPointMake(bl * (1.0 - k), h) controlPoint2:CGPointMake(0, h - bl * (1.0 - k))];
    [p addLineToPoint:CGPointMake(0, tl)];
    [p addCurveToPoint:CGPointMake(tl, 0) controlPoint1:CGPointMake(0, tl * (1.0 - k)) controlPoint2:CGPointMake(tl * (1.0 - k), 0)];
    [p closePath];
    return CGPathCreateCopy(p.CGPath);
}

static const void *kPACMenuMF = &kPACMenuMF;

static CGPathRef PACBigBlobPathAt(CGRect r, CGPoint origin, CGFloat tl, CGFloat tr, CGFloat br, CGFloat bl) {
    CGPathRef base = PACBigBlobPath(r.size, tl, tr, br, bl);
    CGAffineTransform t = CGAffineTransformMakeTranslation(r.origin.x - origin.x, r.origin.y - origin.y);
    CGPathRef moved = CGPathCreateCopyByTransformingPath(base, &t);
    CGPathRelease(base);
    return moved;
}

static CGRect PACBigMidRect(CGRect a, CGRect b) {
    return CGRectMake((a.origin.x + b.origin.x) * 0.5, (a.origin.y + b.origin.y) * 0.5,
                      (a.size.width + b.size.width) * 0.5, (a.size.height + b.size.height) * 0.5);
}

@interface PACBigOutsideTap : UIGestureRecognizer <UIGestureRecognizerDelegate>
@property (nonatomic, weak) UIView *safeView;
@property (nonatomic, copy) void (^onTap)(void);
@end

@implementation PACBigOutsideTap
- (instancetype)initWithTarget:(id)t action:(SEL)a {
    if ((self = [super initWithTarget:t action:a])) self.delegate = self;
    return self;
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    UITouch *t = touches.anyObject;
    UIView *v = self.safeView;
    if (!v || !t || [t.view isDescendantOfView:v]) { self.state = UIGestureRecognizerStateFailed; return; }
    self.state = UIGestureRecognizerStateBegan;
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    if (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged) self.state = UIGestureRecognizerStateChanged;
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    if (self.state == UIGestureRecognizerStateBegan || self.state == UIGestureRecognizerStateChanged) {
        self.state = UIGestureRecognizerStateEnded;
        void (^cb)(void) = self.onTap;
        if (cb) dispatch_async(dispatch_get_main_queue(), cb);
    }
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)e {
    self.state = UIGestureRecognizerStateCancelled;
}
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)g shouldBeRequiredToFailByGestureRecognizer:(UIGestureRecognizer *)other { return YES; }
@end

static void *PACBigWiFiSym(const char *n) {
    static void *h;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ h = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY); });
    return h ? dlsym(h, n) : NULL;
}

static void PACBigNoopAssoc(void *d, void *n, CFDictionaryRef r, int e, void *c) {}

static CFTypeRef sPACBigWFClient;
static NSArray<NSDictionary *> *sPACBigWFScan;
static BOOL sPACBigWFScanning;
static BOOL sPACBigWFScheduled;

static void PACBigWFScanCB(CFTypeRef dev, CFArrayRef results, CFTypeRef err, void *ctx) {
    CFStringRef (*ssidOf)(CFTypeRef) = PACBigWiFiSym("WiFiNetworkGetSSID");
    CFTypeRef (*prop)(CFTypeRef, CFStringRef) = PACBigWiFiSym("WiFiNetworkGetProperty");
    NSMutableDictionary *best = [NSMutableDictionary dictionary];
    if (results && ssidOf) {
        for (CFIndex i = 0; i < CFArrayGetCount(results); i++) {
            CFTypeRef n = CFArrayGetValueAtIndex(results, i);
            CFStringRef cs = n ? ssidOf(n) : NULL;
            NSString *name = cs ? [(__bridge NSString *)cs copy] : nil;
            if (!name.length) continue;
            double rssi = -200.0;
            if (prop) {
                CFTypeRef r = prop(n, CFSTR("RSSI"));
                if (r && CFGetTypeID(r) == CFNumberGetTypeID()) CFNumberGetValue(r, kCFNumberDoubleType, &rssi);
            }
            NSDictionary *old = best[name];
            if (!old || [old[@"rssi"] doubleValue] < rssi) best[name] = @{@"n": name, @"rssi": @(rssi), @"net": (__bridge id)n};
        }
    }
    NSArray *sorted = [best.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *x, NSDictionary *y) {
        return [y[@"rssi"] compare:x[@"rssi"]];
    }];
    dispatch_async(dispatch_get_main_queue(), ^{
        sPACBigWFScan = sorted;
        sPACBigWFScanning = NO;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"PACBigWiFiScanDone" object:nil];
    });
}

static void PACBigWiFiStartScan(void) {
    if (sPACBigWFScanning) return;
    CFTypeRef (*create)(CFAllocatorRef, int) = PACBigWiFiSym("WiFiManagerClientCreate");
    CFArrayRef (*copyDev)(CFTypeRef) = PACBigWiFiSym("WiFiManagerClientCopyDevices");
    void (*sched)(CFTypeRef, CFRunLoopRef, CFStringRef) = PACBigWiFiSym("WiFiManagerClientScheduleWithRunLoop");
    int (*scan)(CFTypeRef, CFDictionaryRef, void *, void *) = PACBigWiFiSym("WiFiDeviceClientScanAsync");
    if (!create || !copyDev || !scan) return;
    if (!sPACBigWFClient) sPACBigWFClient = create(kCFAllocatorDefault, 0);
    if (!sPACBigWFClient) return;
    if (sched && !sPACBigWFScheduled) {
        sched(sPACBigWFClient, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        sPACBigWFScheduled = YES;
    }
    CFArrayRef devs = copyDev(sPACBigWFClient);
    CFTypeRef dev = (devs && CFArrayGetCount(devs) > 0) ? CFArrayGetValueAtIndex(devs, 0) : NULL;
    if (dev) {
        sPACBigWFScanning = YES;
        scan(dev, (__bridge CFDictionaryRef)@{}, (void *)PACBigWFScanCB, NULL);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(8.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ sPACBigWFScanning = NO; });
    }
    if (devs) CFRelease(devs);
}

static NSArray<NSDictionary *> *PACBigWiFiItems(NSUInteger maxN) {
    CFTypeRef (*create)(CFAllocatorRef, int) = PACBigWiFiSym("WiFiManagerClientCreate");
    CFArrayRef (*copyDev)(CFTypeRef) = PACBigWiFiSym("WiFiManagerClientCopyDevices");
    CFArrayRef (*copyNets)(CFTypeRef) = PACBigWiFiSym("WiFiManagerClientCopyNetworks");
    CFTypeRef (*curNet)(CFTypeRef) = PACBigWiFiSym("WiFiDeviceClientCopyCurrentNetwork");
    CFStringRef (*ssidOf)(CFTypeRef) = PACBigWiFiSym("WiFiNetworkGetSSID");
    int (*assoc)(CFTypeRef, CFTypeRef, void *, void *) = PACBigWiFiSym("WiFiDeviceClientAssociateAsync");
    if (!create || !copyDev || !copyNets || !ssidOf) return @[];
    if (!sPACBigWFClient) sPACBigWFClient = create(kCFAllocatorDefault, 0);
    if (!sPACBigWFClient) return @[];
    CFArrayRef devs = copyDev(sPACBigWFClient);
    CFTypeRef dev = (devs && CFArrayGetCount(devs) > 0) ? CFArrayGetValueAtIndex(devs, 0) : NULL;
    NSString *curName = nil;
    if (dev && curNet) {
        CFTypeRef n = curNet(dev);
        if (n) {
            CFStringRef cs = ssidOf(n);
            if (cs) curName = [(__bridge NSString *)cs copy];
            CFRelease(n);
        }
    }
    id devObj = dev ? (__bridge id)dev : nil;
    NSMutableDictionary *known = [NSMutableDictionary dictionary];
    CFArrayRef nets = copyNets(sPACBigWFClient);
    for (CFIndex i = 0; nets && i < CFArrayGetCount(nets); i++) {
        CFTypeRef n = CFArrayGetValueAtIndex(nets, i);
        CFStringRef cs = n ? ssidOf(n) : NULL;
        NSString *name = cs ? [(__bridge NSString *)cs copy] : nil;
        if (name.length && !known[name]) known[name] = (__bridge id)n;
    }
    NSMutableArray *out = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    NSArray *scan = sPACBigWFScan;
    NSMutableArray *names = [NSMutableArray array];
    if (scan.count) {
        for (NSDictionary *e in scan) [names addObject:e[@"n"]];
    } else {
        [names addObjectsFromArray:known.allKeys];
    }
    if (curName.length && ![names containsObject:curName]) [names insertObject:curName atIndex:0];
    for (NSString *name in names) {
        if ([seen containsObject:name]) continue;
        [seen addObject:name];
        BOOL isCur = curName && [name isEqualToString:curName];
        id knownNet = known[name];
        NSDictionary *it = PACBigMenuItem(name, isCur, ^{
            if (isCur) return;
            if (knownNet && assoc && devObj) assoc((__bridge CFTypeRef)devObj, (__bridge CFTypeRef)knownNet, (void *)PACBigNoopAssoc, NULL);
            else PACBigOpenSettings(@"prefs:root=WIFI");
        });
        if (isCur) [out insertObject:it atIndex:0]; else [out addObject:it];
    }
    if (devs) CFRelease(devs);
    if (nets) CFRelease(nets);
    if (out.count > maxN) [out removeObjectsInRange:NSMakeRange(maxN, out.count - maxN)];
    return out;
}

static NSArray<NSDictionary *> *PACBigBTItems(NSUInteger maxN) {
    Class C = NSClassFromString(@"BluetoothManager");
    if (!C) {
        dlopen("/System/Library/PrivateFrameworks/BluetoothManager.framework/BluetoothManager", RTLD_LAZY);
        C = NSClassFromString(@"BluetoothManager");
    }
    SEL si = NSSelectorFromString(@"sharedInstance");
    SEL pd = NSSelectorFromString(@"pairedDevices");
    if (!C || ![C respondsToSelector:si]) return @[];
    id m = ((id (*)(id, SEL))objc_msgSend)(C, si);
    if (!m || ![m respondsToSelector:pd]) return @[];
    NSArray *devs = ((id (*)(id, SEL))objc_msgSend)(m, pd);
    if (![devs isKindOfClass:NSArray.class]) return @[];
    SEL sn = NSSelectorFromString(@"name");
    SEL sc = NSSelectorFromString(@"connected");
    SEL sCon = NSSelectorFromString(@"connect");
    SEL sDis = NSSelectorFromString(@"disconnect");
    NSMutableArray *out = [NSMutableArray array];
    for (id d in devs) {
        if (![d respondsToSelector:sn]) continue;
        NSString *name = ((id (*)(id, SEL))objc_msgSend)(d, sn);
        if (![name isKindOfClass:NSString.class] || !name.length) continue;
        BOOL conn = [d respondsToSelector:sc] ? ((BOOL (*)(id, SEL))objc_msgSend)(d, sc) : NO;
        NSDictionary *it = PACBigMenuItem(name, conn, ^{
            SEL act = conn ? sDis : sCon;
            if ([d respondsToSelector:act]) ((void (*)(id, SEL))objc_msgSend)(d, act);
        });
        if (conn) [out insertObject:it atIndex:0]; else [out addObject:it];
    }
    if (out.count > maxN) [out removeObjectsInRange:NSMakeRange(maxN, out.count - maxN)];
    return out;
}

#pragma mark - big connectivity

static BOOL PACBigVPNActive(void) {
    BOOL on = NO;
    CFDictionaryRef proxy = CFNetworkCopySystemProxySettings();
    if (proxy) {
        NSDictionary *scoped = ((__bridge NSDictionary *)proxy)[@"__SCOPED__"];
        for (NSString *k in scoped) {
            NSString *l = k.lowercaseString;
            if ([l hasPrefix:@"tap"] || [l hasPrefix:@"tun"] || [l hasPrefix:@"ppp"] || [l hasPrefix:@"ipsec"] || [l hasPrefix:@"utun"]) { on = YES; break; }
        }
        CFRelease(proxy);
    }
    return on;
}

@interface PACBigConn : PACBigView
@property (nonatomic, weak) UIView *apple;
- (void)refresh;
- (void)openMenuFromCard:(PACBigCard *)card;
- (void)closeMenu;
- (void)pacScanUpdated;
@end

@implementation PACBigConn {
    NSMutableDictionary<NSString *, PACBigCard *> *_cards;
    NSTimer *_timer;
    UIControl *_dim;
    PACBigOutsideTap *_outsideTap;
    UIView *_menu;
    PACBigCard *_menuCard;
    NSArray<NSDictionary *> *_menuItems;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.tag = kPACBigTag;
        _cards = [NSMutableDictionary dictionary];
    }
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_timer invalidate]; _timer = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"PACBigWiFiScanDone" object:nil];
    if (self.window) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pacScanUpdated) name:@"PACBigWiFiScanDone" object:nil];
        PACBigWiFiStartScan();
        __weak typeof(self) ws = self;
        _timer = [NSTimer timerWithTimeInterval:0.6 repeats:YES block:^(NSTimer *t) { [ws refresh]; }];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    } else if (_menu) {
        [_menu removeFromSuperview]; _menu = nil;
        [_dim removeFromSuperview]; _dim = nil;
        [_outsideTap.view removeGestureRecognizer:_outsideTap]; _outsideTap = nil;
        _menuCard.alpha = 1.0; _menuCard = nil;
    }
}
- (void)dealloc { [_timer invalidate]; [[NSNotificationCenter defaultCenter] removeObserver:self]; }
- (void)layoutSubviews { [super layoutSubviews]; [self refresh]; }
- (NSArray<NSDictionary *> *)menuItemsForCard:(PACBigCard *)card {
    NSString *k = card.key;
    __weak PACBigCard *wc = card;
    if ([k isEqualToString:@"airdrop"]) {
        int cur = PACBigAirDropMode();
        NSArray *names = @[@"Receiving Off", @"Contacts Only", @"Everyone for 10 Minutes"];
        NSMutableArray *out = [NSMutableArray array];
        for (int i = 0; i < 3; i++) {
            [out addObject:PACBigMenuItem(names[i], cur == i, ^{
                if (!PACBigSetAirDropMode(i)) [wc tapped];
            })];
        }
        return out;
    }
    BOOL wifi = [k isEqualToString:@"wifi"];
    NSString *name = wifi ? @"Wi-Fi" : @"Bluetooth";
    NSString *url = wifi ? @"prefs:root=WIFI" : @"prefs:root=Bluetooth";
    NSUInteger maxRows = MAX((NSUInteger)2, (NSUInteger)((self.bounds.size.height - 12.0) / 46.0));
    maxRows = MIN(maxRows, (NSUInteger)7);
    NSArray *list = wifi ? (card.isOn ? PACBigWiFiItems(maxRows - 1) : @[]) : PACBigBTItems(maxRows - 1);
    NSMutableArray *res = [NSMutableArray array];
    if (list.count) [res addObjectsFromArray:list];
    else [res addObject:PACBigMenuItem(name, card.isOn, ^{ [wc tapped]; })];
    [res addObject:PACBigMenuItem([name stringByAppendingString:@" Settings"], NO, ^{ PACBigOpenSettings(url); })];
    return res;
}
- (CGRect)pacMenuFrameForCount:(NSUInteger)n card:(PACBigCard *)card width:(CGFloat)mw {
    CGSize S = self.bounds.size;
    CGRect cf = card.frame;
    CGFloat mh = 12.0 + 46.0 * n;
    CGFloat mx = (CGRectGetMidX(cf) > S.width * 0.5) ? CGRectGetMaxX(cf) - mw : cf.origin.x;
    mx = MAX(0, MIN(mx, S.width - mw));
    CGFloat my = MAX(0, MIN(cf.origin.y, S.height - mh));
    return CGRectMake(mx, my, mw, mh);
}
- (UIView *)pacContentForItems:(NSArray<NSDictionary *> *)items width:(CGFloat)mw {
    CGFloat rowH = 46.0, padV = 6.0;
    UIView *content = [[UIView alloc] initWithFrame:CGRectMake(0, 0, mw, padV * 2.0 + rowH * items.count)];
    for (NSUInteger i = 0; i < items.count; i++) {
        NSDictionary *it = items[i];
        UIControl *row = [[UIControl alloc] initWithFrame:CGRectMake(0, padV + i * rowH, mw, rowH)];
        row.tag = (NSInteger)i;
        if ([it[@"on"] boolValue]) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightBold];
            UIImageView *ck = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark" withConfiguration:cfg]];
            ck.tintColor = PACBigDyn(UIColor.whiteColor, [UIColor colorWithWhite:0.08 alpha:1.0]);
            ck.contentMode = UIViewContentModeCenter;
            ck.frame = CGRectMake(14, 0, 22, rowH);
            ck.userInteractionEnabled = NO;
            [row addSubview:ck];
        }
        UILabel *lb = [[UILabel alloc] initWithFrame:CGRectMake(44, 0, mw - 44 - 14, rowH)];
        lb.text = it[@"t"];
        lb.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
        lb.textColor = PACBigDyn(UIColor.whiteColor, [UIColor colorWithWhite:0.08 alpha:1.0]);
        lb.userInteractionEnabled = NO;
        [row addSubview:lb];
        if (i > 0) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(44, 0, mw - 44 - 14, 0.5)];
            sep.backgroundColor = PACBigDyn([UIColor colorWithWhite:1 alpha:0.18], [UIColor colorWithWhite:0 alpha:0.14]);
            sep.userInteractionEnabled = NO;
            [row addSubview:sep];
        }
        [row addTarget:self action:@selector(menuRowDown:) forControlEvents:UIControlEventTouchDown];
        [row addTarget:self action:@selector(menuRowUp:) forControlEvents:UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [row addTarget:self action:@selector(menuRowTapped:) forControlEvents:UIControlEventTouchUpInside];
        [content addSubview:row];
    }
    return content;
}
- (void)pacScanUpdated {
    PACBigCard *card = _menuCard;
    UIView *menu = _menu;
    if (!menu || !card || ![card.key isEqualToString:@"wifi"]) return;
    NSArray<NSDictionary *> *items = [self menuItemsForCard:card];
    if (!items.count) return;
    BOOL same = items.count == _menuItems.count;
    for (NSUInteger i = 0; same && i < items.count; i++) {
        if (![items[i][@"t"] isEqualToString:_menuItems[i][@"t"]] || [items[i][@"on"] boolValue] != [_menuItems[i][@"on"] boolValue]) same = NO;
    }
    if (same) return;
    _menuItems = items;
    CGFloat mw = menu.bounds.size.width;
    CGRect mf = [self pacMenuFrameForCount:items.count card:card width:mw];
    UIView *old = menu.subviews.lastObject;
    UIView *content = [self pacContentForItems:items width:mw];
    content.alpha = 0;
    [menu addSubview:content];
    [UIView animateWithDuration:0.2 animations:^{ old.alpha = 0; content.alpha = 1; } completion:^(BOOL f) { [old removeFromSuperview]; }];
    [UIView animateWithDuration:0.4 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0.0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ menu.frame = mf; } completion:nil];
}
- (void)openMenuFromCard:(PACBigCard *)card {
    if (_menu || !card || !self.window) return;
    if ([card.key isEqualToString:@"wifi"]) PACBigWiFiStartScan();
    NSArray<NSDictionary *> *items = [self menuItemsForCard:card];
    if (!items.count) return;
    _menuItems = items;
    _menuCard = card;

    CGSize S = self.bounds.size;
    CGRect cf = card.frame;
    CGFloat mw = MIN(S.width, MAX(cf.size.width * 1.5, 250.0));
    CGRect mf = [self pacMenuFrameForCount:items.count card:card width:mw];
    CGFloat mh = mf.size.height;
    CGFloat endRad = MIN(36.0, mh * 0.3);

    _dim = [[UIControl alloc] initWithFrame:self.bounds];
    _dim.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_dim addTarget:self action:@selector(closeMenu) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_dim];
    {
        __weak typeof(self) wself = self;
        PACBigOutsideTap *ot = [[PACBigOutsideTap alloc] initWithTarget:nil action:NULL];
        ot.onTap = ^{ [wself closeMenu]; };
        [self.window addGestureRecognizer:ot];
        _outsideTap = ot;
    }

    CGRect over = mf;
    over.origin.y += 7.0;
    over.size.height += 13.0;
    over.size.width += 4.0;
    over.origin.x -= 2.0;
    CGFloat cside = MIN(cf.size.width, cf.size.height) * 0.85;
    CGRect cr = CGRectMake(CGRectGetMidX(cf) - cside * 0.5, CGRectGetMidY(cf) - cside * 0.5, cside, cside);
    CGFloat bw = cside * 1.02;
    CGFloat bh = cside * 1.25;
    CGFloat drop = 34.0;
    CGRect pull = CGRectMake(CGRectGetMidX(cf) - bw * 0.5, over.origin.y + drop, bw, bh);
    CGRect U = CGRectInset(CGRectUnion(CGRectUnion(cf, pull), CGRectUnion(mf, over)), -6.0, -6.0);
    CGPoint uo = U.origin;

    UIView *menu = [[UIView alloc] initWithFrame:U];
    objc_setAssociatedObject(menu, kPACMenuMF, [NSValue valueWithCGRect:mf], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    _outsideTap.safeView = menu;
    menu.clipsToBounds = NO;
    menu.layer.cornerRadius = 0.0;
    menu.layer.cornerCurve = kCACornerCurveContinuous;
    UIView *mat = PACCModuleMaterial();
    mat.userInteractionEnabled = NO;
    mat.frame = menu.bounds;
    mat.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [menu addSubview:mat];
    if (PACCLIQGlassOn()) {
        mat.hidden = PACBigLGGlass(menu, endRad);
        PACCLIQSetFixedBlur(menu, 7.0);
        PACCLIQSpecularFade(menu, YES, 0.0, 0.0);
    }
    UIView *frost = [[UIView alloc] initWithFrame:menu.bounds];
    frost.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    frost.backgroundColor = PACBigDyn([UIColor colorWithWhite:0.0 alpha:0.32], [UIColor colorWithWhite:1.0 alpha:0.38]);
    frost.userInteractionEnabled = NO;
    frost.alpha = 0;
    [menu addSubview:frost];

    UIView *content = [self pacContentForItems:items width:mw];
    content.alpha = 0;
    {
        CGFloat k = 1.32;
        CGSize cs = content.bounds.size;
        content.transform = CGAffineTransformConcat(CGAffineTransformMakeScale(k, k),
                                                    CGAffineTransformMakeTranslation(-(k - 1.0) * cs.width * 0.5, -(k - 1.0) * cs.height * 0.5));
    }
    {
        CGSize cs0 = content.bounds.size;
        content.center = CGPointMake(mf.origin.x - uo.x + cs0.width * 0.5, mf.origin.y - uo.y + cs0.height * 0.5);
    }
    [menu addSubview:content];
    UIView *snap = [card snapshotViewAfterScreenUpdates:NO];
    if (snap) {
        snap.frame = CGRectMake(cf.origin.x - uo.x, cf.origin.y - uo.y, cf.size.width, cf.size.height);
        snap.userInteractionEnabled = NO;
        [menu insertSubview:snap belowSubview:content];
    }
    [self addSubview:menu];
    _menu = menu;

    card.alpha = 0;
    {
        CGRect smr = PACBigMidRect(pull, mf);
        CGFloat mr = MIN(smr.size.width, smr.size.height) * 0.4;
        CGFloat r0 = MAX(1.0, card.layer.cornerRadius);
        CGPathRef p0 = PACBigBlobPathAt(cf, uo, r0, r0, r0, r0);
        CGPathRef p1 = PACBigBlobPathAt(cr, uo, cside * 0.5, cside * 0.5, cside * 0.5, cside * 0.5);
        CGPathRef p2 = PACBigBlobPathAt(pull, uo, bw * 0.5, bw * 0.47, bw * 0.5, bw * 0.46);
        CGPathRef p3 = PACBigBlobPathAt(smr, uo, mr, mr, mr, mr);
        CGPathRef p4 = PACBigBlobPathAt(mf, uo, endRad, endRad, endRad, endRad);
        CAShapeLayer *mk = [CAShapeLayer layer];
        mk.frame = CGRectMake(0, 0, U.size.width, U.size.height);
        mk.path = p4;
        menu.layer.mask = mk;
        __weak typeof(self) wself = self;
        CGSize csz = content.bounds.size;
        [CATransaction begin];
        [CATransaction setCompletionBlock:^{
            typeof(self) me = wself;
            if (!me || me->_menu != menu) return;
            menu.layer.mask = nil;
            menu.frame = mf;
            content.center = CGPointMake(csz.width * 0.5, csz.height * 0.5);
            menu.clipsToBounds = YES;
            menu.layer.cornerRadius = endRad;
            [UIView animateWithDuration:0.12 delay:0 options:UIViewAnimationOptionCurveEaseOut | UIViewAnimationOptionAllowUserInteraction
                             animations:^{
                                 menu.transform = CGAffineTransformMakeScale(1.03, 1.03);
                                 content.transform = CGAffineTransformMakeScale(1.0 / 1.03, 1.0 / 1.03);
                             }
                             completion:^(BOOL f1) {
                [UIView animateWithDuration:0.5 delay:0 usingSpringWithDamping:0.5 initialSpringVelocity:0.0
                                    options:UIViewAnimationOptionAllowUserInteraction
                                 animations:^{
                                     menu.transform = CGAffineTransformIdentity;
                                     content.transform = CGAffineTransformIdentity;
                                 } completion:nil];
            }];
        }];
        CAKeyframeAnimation *ka = [CAKeyframeAnimation animationWithKeyPath:@"path"];
        ka.values = @[(__bridge id)p0, (__bridge id)p1, (__bridge id)p2, (__bridge id)p3, (__bridge id)p4];
        ka.keyTimes = @[@0.0, @0.14, @0.62, @0.8, @1.0];
        ka.duration = 0.38;
        ka.calculationMode = kCAAnimationCubic;
        [mk addAnimation:ka forKey:@"pacBlob"];
        [CATransaction commit];
        CGPathRelease(p0); CGPathRelease(p1); CGPathRelease(p2); CGPathRelease(p3); CGPathRelease(p4);
    }
    [UIView animateWithDuration:0.25 delay:0.04 options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ frost.alpha = 1; } completion:nil];
    [UIView animateWithDuration:0.16 delay:0.12 options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ content.alpha = 1; } completion:nil];
    [UIView animateWithDuration:0.14 delay:0.0 options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ snap.alpha = 0; } completion:^(BOOL f) { [snap removeFromSuperview]; }];
    [UIView animateWithDuration:0.4 delay:0.1 usingSpringWithDamping:0.9 initialSpringVelocity:0.0
                        options:UIViewAnimationOptionAllowUserInteraction
                     animations:^{ content.transform = CGAffineTransformIdentity; } completion:nil];
    PACBigAnimateBlur(content, 7.0, 0.0, 0.34, 0.1, YES);
    PACCLIQSpecularFade(menu, NO, 0.35, 0.36);
}
- (void)menuRowDown:(UIControl *)row { row.backgroundColor = PACBigDyn([UIColor colorWithWhite:1 alpha:0.14], [UIColor colorWithWhite:0 alpha:0.08]); }
- (void)menuRowUp:(UIControl *)row { row.backgroundColor = UIColor.clearColor; }
- (void)menuRowTapped:(UIControl *)row {
    void (^act)(void) = (row.tag >= 0 && (NSUInteger)row.tag < _menuItems.count) ? _menuItems[row.tag][@"a"] : nil;
    if (gHapticsEnabled) Haptic();
    [self closeMenu];
    if (act) act();
}
- (void)closeMenu {
    UIView *menu = _menu;
    PACBigCard *card = _menuCard;
    if (!menu) return;
    UIControl *dim = _dim;
    PACBigOutsideTap *ot = _outsideTap;
    _menu = nil; _menuCard = nil; _dim = nil; _menuItems = nil; _outsideTap = nil;
    [ot.view removeGestureRecognizer:ot];
    [dim removeFromSuperview];
    UIView *content = menu.subviews.lastObject;
    menu.userInteractionEnabled = NO;
    CGRect cfr = card ? card.frame : menu.frame;
    CGFloat sd = MIN(cfr.size.width, cfr.size.height) * 0.85;
    CGRect circle = CGRectMake(CGRectGetMidX(cfr) - sd * 0.5, CGRectGetMidY(cfr) - sd * 0.5, sd, sd);
    CGFloat cardRad = card ? card.layer.cornerRadius : sd * 0.5;
    PACBigAnimateBlur(content, 0.0, 3.0, 0.1, 0.0, NO);
    PACCLIQSpecularFade(menu, YES, 0.1, 0.0);
    [UIView animateWithDuration:0.08 animations:^{ content.alpha = 0; }];
    [menu.layer removeAllAnimations];
    menu.transform = CGAffineTransformIdentity;
    content.transform = CGAffineTransformIdentity;
    NSValue *nv = objc_getAssociatedObject(menu, kPACMenuMF);
    CGRect mf = nv ? nv.CGRectValue : menu.frame;
    [menu.layer.mask removeAllAnimations];
    CGFloat bw = sd * 1.02;
    CGFloat bh = sd * 1.25;
    CGFloat drop = 34.0;
    CGRect pull = CGRectMake(CGRectGetMidX(cfr) - bw * 0.5, mf.origin.y + drop, bw, bh);
    CGFloat endRad = menu.layer.cornerRadius;
    if (endRad < 1.0) endRad = MIN(36.0, mf.size.height * 0.3);
    CGRect U = CGRectInset(CGRectUnion(CGRectUnion(mf, pull), CGRectUnion(circle, cfr)), -6.0, -6.0);
    CGPoint uo = U.origin;
    CGSize csz = content.bounds.size;
    menu.clipsToBounds = NO;
    menu.layer.cornerRadius = 0.0;
    menu.frame = U;
    content.center = CGPointMake(mf.origin.x - uo.x + csz.width * 0.5, mf.origin.y - uo.y + csz.height * 0.5);
    {
        CGRect smr = PACBigMidRect(pull, mf);
        CGFloat mr = MIN(smr.size.width, smr.size.height) * 0.4;
        CGPathRef p4 = PACBigBlobPathAt(mf, uo, endRad, endRad, endRad, endRad);
        CGPathRef p3 = PACBigBlobPathAt(smr, uo, mr, mr, mr, mr);
        CGPathRef p2 = PACBigBlobPathAt(pull, uo, bw * 0.5, bw * 0.47, bw * 0.5, bw * 0.46);
        CGPathRef p1 = PACBigBlobPathAt(circle, uo, sd * 0.5, sd * 0.5, sd * 0.5, sd * 0.5);
        CGFloat r0 = MAX(1.0, cardRad);
        CGPathRef p0 = PACBigBlobPathAt(cfr, uo, r0, r0, r0, r0);
        CAShapeLayer *mk = [CAShapeLayer layer];
        mk.frame = CGRectMake(0, 0, U.size.width, U.size.height);
        mk.path = p0;
        menu.layer.mask = mk;
        CAKeyframeAnimation *ka = [CAKeyframeAnimation animationWithKeyPath:@"path"];
        ka.values = @[(__bridge id)p4, (__bridge id)p3, (__bridge id)p2, (__bridge id)p1, (__bridge id)p0];
        ka.keyTimes = @[@0.0, @0.2, @0.38, @0.86, @1.0];
        ka.duration = 0.38;
        ka.calculationMode = kCAAnimationCubic;
        [mk addAnimation:ka forKey:@"pacBlobClose"];
        CGPathRelease(p0); CGPathRelease(p1); CGPathRelease(p2); CGPathRelease(p3); CGPathRelease(p4);
    }
    {
        CGFloat k = 1.25;
        CGSize cs1 = content.bounds.size;
        CGAffineTransform grow = CGAffineTransformConcat(CGAffineTransformMakeScale(k, k),
                                                         CGAffineTransformMakeTranslation(-(k - 1.0) * cs1.width * 0.5, -(k - 1.0) * cs1.height * 0.5));
        [UIView animateWithDuration:0.3 delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{ content.transform = grow; } completion:nil];
    }
    [UIView animateWithDuration:0.1 delay:0.28 options:0 animations:^{ menu.alpha = 0; } completion:^(BOOL f) { [menu removeFromSuperview]; }];
    if (card) {
        card.transform = CGAffineTransformMakeScale(0.6, 0.6);
        [UIView animateWithDuration:0.1 delay:0.28 options:0 animations:^{ card.alpha = 1.0; } completion:nil];
        [UIView animateWithDuration:0.55 delay:0.28 usingSpringWithDamping:0.55 initialSpringVelocity:0.0 options:0 animations:^{
            card.transform = CGAffineTransformIdentity;
        } completion:nil];
        CABasicAnimation *ra = [CABasicAnimation animationWithKeyPath:@"cornerRadius"];
        ra.fromValue = @(MIN(cfr.size.width, cfr.size.height) * 0.5);
        ra.toValue = @(cardRad);
        ra.duration = 0.45;
        ra.beginTime = CACurrentMediaTime() + 0.28;
        ra.fillMode = kCAFillModeBackwards;
        ra.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];
        [card.layer addAnimation:ra forKey:@"PACCloseRound"];
    }
}
- (void)refresh {
    PACCCrumb("PACBigConn refresh");
    @try { [self refreshImpl]; } @catch (NSException *e) { NSLog(@"[CCock26] connectivity refresh: %@", e); }
}
- (void)refreshImpl {
    Class L = NSClassFromString(@"CCUILabeledRoundButton");
    if (!L || !self.apple) return;
    NSMutableArray *found = [NSMutableArray array];
    PACBigCollect(self.apple, L, 0, found);

    NSArray *order = @[@"air", @"wifi", @"airdrop", @"cell", @"bt", @"hotspot", @"vpn"];
    NSMutableDictionary<NSString *, UIView *> *byKey = [NSMutableDictionary dictionary];
    for (UIView *b in found) {
        id t = PACBigKV(b, @"title");
        NSString *title = [t isKindOfClass:NSString.class] ? t : @"";
        if (!title.length) {
            NSMutableArray *labels = [NSMutableArray array];
            PACBigCollect(b, UILabel.class, 0, labels);
            for (UILabel *lb in labels) if (lb.text.length) { title = lb.text; break; }
        }
        NSString *k = PACBigKey(title);
        if (!byKey[k]) byKey[k] = b;
    }
    NSMutableArray<NSString *> *keys = [NSMutableArray array];
    {
        static NSString *lastNote;
        NSString *note = [NSString stringWithFormat:@"connectivity overlay: %lu labeled buttons, apple host %@",
                          (unsigned long)found.count, NSStringFromClass(self.apple.class)];
        if (![note isEqualToString:lastNote]) { lastNote = note; PACCCrashLog(note); }
    }
    if (!byKey.count) return;
    for (NSString *k in order) [keys addObject:k];
    for (NSString *k in byKey) if (![keys containsObject:k]) [keys addObject:k];

    CGSize S = self.bounds.size;
    if (S.width < 40 || S.height < 40) return;
    BOOL hasTop = [keys containsObject:@"air"];
    NSMutableArray<NSString *> *bottomKeys = [NSMutableArray array];
    for (NSString *bk in @[@"hotspot", @"vpn"]) if ([keys containsObject:bk]) [bottomKeys addObject:bk];
    NSMutableArray<NSString *> *cardKeys = [keys mutableCopy];
    [cardKeys removeObject:@"air"]; [cardKeys removeObjectsInArray:bottomKeys];
    NSUInteger cardRows = (cardKeys.count + 1) / 2;
    NSUInteger pills = (hasTop ? 1 : 0) + bottomKeys.count;
    CGFloat gap = 12.0;
    CGFloat cw = (S.width - gap) / 2.0;
    CGFloat ph = MAX(52.0, MIN(70.0, S.height * 0.135));
    NSUInteger totalRows = cardRows + pills;
    CGFloat ch = cardRows ? (S.height - pills * ph - gap * (totalRows - 1)) / cardRows : 0;
    ch = MIN(ch, 180.0);
    if (ch < 60.0) { ph = 52.0; ch = MAX(52.0, cardRows ? (S.height - pills * ph - gap * (totalRows - 1)) / cardRows : 0); }
    CGFloat usedH = ph * pills + ch * cardRows + gap * (totalRows - 1);
    CGFloat y0 = MAX(0, (S.height - usedH) * 0.5);
    NSMutableDictionary<NSString *, NSValue *> *frames = [NSMutableDictionary dictionary];
    CGFloat yy = y0;
    if (hasTop) { frames[@"air"] = [NSValue valueWithCGRect:CGRectMake(0, yy, S.width, ph)]; yy += ph + gap; }
    for (NSUInteger i = 0; i < cardKeys.count; i++) {
        frames[cardKeys[i]] = [NSValue valueWithCGRect:CGRectMake((i % 2) * (cw + gap), yy + (i / 2) * (ch + gap), cw, ch)];
    }
    yy += cardRows ? cardRows * (ch + gap) : 0;
    for (NSString *bk in bottomKeys) { frames[bk] = [NSValue valueWithCGRect:CGRectMake(0, yy, S.width, ph)]; yy += ph + gap; }

    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *k = keys[i];
        UIView *labeled = byKey[k];
        PACBigCard *card = _cards[k];
        if (!card) {
            card = [[PACBigCard alloc] initWithFrame:CGRectZero];
            card.key = k;
            __weak typeof(self) wself = self;
            card.onMenu = ^(PACBigCard *c) { [wself openMenuFromCard:c]; };
            _cards[k] = card;
            [self addSubview:card];
        }
        BOOL tall = !([k isEqualToString:@"air"] || [k isEqualToString:@"hotspot"] || [k isEqualToString:@"vpn"]) && ch >= 100.0;
        if (card.tall != tall) { card.tall = tall; [card setNeedsLayout]; }
        NSValue *fv = frames[k];
        if (fv) card.frame = fv.CGRectValue;
        if ([k isEqualToString:@"vpn"]) {
            BOOL vpnOn = PACBigVPNActive();
            card.target = nil; card.labeled = nil;
            if (![card.title.text isEqualToString:@"VPN"]) card.title.text = @"VPN";
            NSString *vs = vpnOn ? @"Connected" : @"Not Connected";
            [card setSubText:vs];
            [card setOn:vpnOn];
            card.alpha = 1.0;
            card.enabled = NO;
            continue;
        }
        id rb = PACBigKV(labeled, @"buttonView");
        UIControl *round = [rb isKindOfClass:UIControl.class] ? rb : nil;
        if (!round) {
            NSMutableArray *all = [NSMutableArray array];
            PACBigCollect(labeled, UIControl.class, 0, all);
            for (UIControl *c in all) if ([NSStringFromClass(c.class) containsString:@"RoundButton"]) { round = c; break; }
        }
        card.target = round;
        card.labeled = labeled;
        NSString *title = PACBigKV(labeled, @"title");
        if (![title isKindOfClass:NSString.class] || !title.length) {
            title = @{@"air": @"Airplane Mode", @"wifi": @"Wi-Fi", @"cell": @"Cellular Data",
                      @"bt": @"Bluetooth", @"airdrop": @"AirDrop", @"hotspot": @"Hotspot"}[k] ?: k;
        }
        BOOL on = round.isSelected;
        NSString *sub = PACBigKV(labeled, @"subtitle");
        if (![sub isKindOfClass:NSString.class] || !sub.length || [sub isEqualToString:title]) sub = on ? @"On" : @"Off";
        if (!round) sub = @"Unavailable";
        if (![card.title.text isEqualToString:title]) card.title.text = title;
        [card setSubText:sub];
        [card setOn:on];
        if (card != _menuCard) card.alpha = round ? (round.enabled ? 1.0 : 0.5) : 0.4;
        card.enabled = round != nil && !gEditModeActive;
    }
}
@end

#pragma mark - single toggle (Wi-Fi, Cellular, Bluetooth, Hotspot, Silent Mode)

static BOOL PACBigRingerMuted(void) {
    static int token = 0; static BOOL ok = NO;
    if (!ok) ok = (notify_register_check("com.apple.springboard.ringerstate", &token) == NOTIFY_STATUS_OK);
    if (!ok) return NO;
    uint64_t st = 1;
    notify_get_state(token, &st);
    return st == 0;
}

static void PACBigSetRingerMuted(BOOL muted) {
    id app = UIApplication.sharedApplication;
    id ctl = nil;
    SEL rc = NSSelectorFromString(@"ringerControl");
    if ([app respondsToSelector:rc]) ctl = ((id (*)(id, SEL))objc_msgSend)(app, rc);
    if (!ctl) {
        Class C = NSClassFromString(@"SBRingerControl");
        SEL si = NSSelectorFromString(@"sharedInstance");
        if (C && [C respondsToSelector:si]) ctl = ((id (*)(id, SEL))objc_msgSend)(C, si);
    }
    SEL set = NSSelectorFromString(@"setRingerMuted:");
    if (ctl && [ctl respondsToSelector:set]) ((void (*)(id, SEL, BOOL))objc_msgSend)(ctl, set, muted);
    else NSLog(@"[CCock26] ringer control unavailable");
}

@interface PACBigToggle : PACBigView
@property (nonatomic, copy) NSString *key;
@property (nonatomic, weak) UIView *apple;
@end

@implementation PACBigToggle {
    PACBigCard *_card;
    NSTimer *_timer;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        _card = [[PACBigCard alloc] initWithFrame:CGRectZero];
        [self addSubview:_card];
    }
    return self;
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    [_timer invalidate]; _timer = nil;
    if (self.window) {
        __weak typeof(self) ws = self;
        _timer = [NSTimer timerWithTimeInterval:0.6 repeats:YES block:^(NSTimer *t) { [ws refresh]; }];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}
- (void)dealloc { [_timer invalidate]; }
- (void)layoutSubviews { [super layoutSubviews]; [self refresh]; }
- (void)refresh {
    @try { [self refreshImpl]; } @catch (NSException *e) { NSLog(@"[CCock26] toggle refresh: %@", e); }
}
- (void)refreshImpl {
    CGSize S = self.bounds.size;
    if (S.width < 20 || S.height < 20 || !self.key.length) return;
    _card.frame = self.bounds;
    BOOL iconOnly = S.width < S.height * 1.4;
    if (_card.iconOnly != iconOnly) { _card.iconOnly = iconOnly; [_card setNeedsLayout]; }
    if ([self.key isEqualToString:@"ringer"]) {
        BOOL muted = PACBigRingerMuted();
        NSString *k = muted ? @"ringeroff" : @"ringer";
        if (![_card.key isEqualToString:k]) { _card.key = k; [_card setNeedsLayout]; }
        _card.onTap = ^{ PACBigSetRingerMuted(!PACBigRingerMuted()); };
        _card.target = nil; _card.labeled = nil;
        if (![_card.title.text isEqualToString:@"Silent Mode"]) _card.title.text = @"Silent Mode";
        NSString *rs = muted ? @"On" : @"Off";
        if (![_card.sub.text isEqualToString:rs]) _card.sub.text = rs;
        [_card setOn:muted];
        _card.alpha = 1.0;
        _card.enabled = !gEditModeActive;
        return;
    }
    _card.key = self.key;

    UIView *labeled = nil;
    Class L = NSClassFromString(@"CCUILabeledRoundButton");
    if (L && self.apple) {
        NSMutableArray *found = [NSMutableArray array];
        PACBigCollect(self.apple, L, 0, found);
        for (UIView *b in found) {
            id t = PACBigKV(b, @"title");
            NSString *title = [t isKindOfClass:NSString.class] ? t : @"";
            if (!title.length) {
                NSMutableArray *labels = [NSMutableArray array];
                PACBigCollect(b, UILabel.class, 0, labels);
                for (UILabel *lb in labels) if (lb.text.length) { title = lb.text; break; }
            }
            if ([PACBigKey(title) isEqualToString:self.key]) { labeled = b; break; }
        }
    }
    id rb = PACBigKV(labeled, @"buttonView");
    UIControl *round = [rb isKindOfClass:UIControl.class] ? rb : nil;
    if (!round && labeled) {
        NSMutableArray *all = [NSMutableArray array];
        PACBigCollect(labeled, UIControl.class, 0, all);
        for (UIControl *c in all) if ([NSStringFromClass(c.class) containsString:@"RoundButton"]) { round = c; break; }
    }
    _card.target = round;
    _card.labeled = labeled;
    NSString *title = PACBigKV(labeled, @"title");
    if (![title isKindOfClass:NSString.class] || !title.length) {
        title = @{@"wifi": @"Wi-Fi", @"cell": @"Cellular Data", @"bt": @"Bluetooth", @"hotspot": @"Hotspot"}[self.key] ?: self.key;
    }
    BOOL on = round.isSelected;
    NSString *sub = PACBigKV(labeled, @"subtitle");
    if (![sub isKindOfClass:NSString.class] || !sub.length || [sub isEqualToString:title]) sub = on ? @"On" : @"Off";
    if (!round) sub = @"Unavailable";
    if (![_card.title.text isEqualToString:title]) _card.title.text = title;
    if (![_card.sub.text isEqualToString:sub]) _card.sub.text = sub;
    [_card setOn:on];
    _card.alpha = round ? (round.enabled ? 1.0 : 0.5) : 0.4;
    _card.enabled = round != nil && !gEditModeActive;
}
@end

#pragma mark - big music

@interface PACBigMusic : PACBigView
@property (nonatomic) BOOL compact;
@property (nonatomic) BOOL standalone;
- (void)refresh;
@end

static UIView *PACBigMediaMaterial(void) {
    UIView *material = nil;
    Class cls = NSClassFromString(@"MTMaterialView");
    SEL full = NSSelectorFromString(@"materialViewWithRecipe:options:initialWeight:");
    if ([cls respondsToSelector:full]) {
        material = ((id (*)(id, SEL, long long, unsigned long long, double))objc_msgSend)(cls, full, (long long)4, (unsigned long long)0, 1.0);
    }
    if (!material && [cls respondsToSelector:NSSelectorFromString(@"materialViewWithRecipe:")]) {
        material = ((id (*)(id, SEL, long long))objc_msgSend)(cls, NSSelectorFromString(@"materialViewWithRecipe:"), (long long)4);
    }
    if (material && [material respondsToSelector:NSSelectorFromString(@"setWeight:")]) {
        ((void (*)(id, SEL, double))objc_msgSend)(material, NSSelectorFromString(@"setWeight:"), 1.0);
    }
    if (material && [material respondsToSelector:NSSelectorFromString(@"setGroupName:")]) {
        ((void (*)(id, SEL, id))objc_msgSend)(material, NSSelectorFromString(@"setGroupName:"), @"ccMediaPlayer");
    }
    if (!material) {
        UIVisualEffectView *fb = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThickMaterialDark]];
        fb.alpha = 0.92;
        material = fb;
    }
    material.layer.cornerCurve = kCACornerCurveContinuous;
    material.layer.masksToBounds = YES;
    return material;
}

BOOL PACBigLGGlass(UIView *host, CGFloat radius) {
    UIView *stale = [host viewWithTag:190002];
    if (stale) [stale removeFromSuperview];
    return PACCLIQApplyGlass(host, radius);
}

@implementation PACBigMusic {
    UIView *_blur;
    UIImageView *_art;
    UILabel *_title, *_artist, *_elapsed, *_remaining;
    UIButton *_prev, *_play, *_next;
    PACBigBar *_seek, *_vol;
    UIImageView *_volLo, *_volHi;
    UIView *_airBg;
    UIImageView *_airIcon;
    NSTimer *_timer;
    double _elapsedSec, _duration, _rate;
    NSDate *_stamp;
    BOOL _playing;
    CFTimeInterval _holdUntil;
}
- (instancetype)initWithFrame:(CGRect)f {
    if ((self = [super initWithFrame:f])) {
        self.tag = kPACBigTag;
        self.layer.cornerCurve = kCACornerCurveContinuous;
        self.layer.masksToBounds = YES;
        _blur = PACBigMediaMaterial();
        _blur.userInteractionEnabled = NO;
        [self addSubview:_blur];

        _art = [UIImageView new];
        _art.contentMode = UIViewContentModeScaleAspectFill;
        _art.clipsToBounds = YES;
        _art.backgroundColor = [UIColor colorWithWhite:1 alpha:0.1];
        _art.layer.cornerCurve = kCACornerCurveContinuous;
        [self addSubview:_art];

        _title = [UILabel new]; _title.textColor = UIColor.whiteColor;
        _title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
        [self addSubview:_title];
        _artist = [UILabel new]; _artist.textColor = [UIColor colorWithWhite:1 alpha:0.65];
        _artist.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        [self addSubview:_artist];

        _prev = [self transport:@"backward.fill" action:@selector(prevTap)];
        _play = [self transport:@"play.fill" action:@selector(playTap)];
        _next = [self transport:@"forward.fill" action:@selector(nextTap)];

        __weak typeof(self) ws = self;
        _seek = [[PACBigBar alloc] initWithFrame:CGRectZero];
        _seek.onChange = ^(CGFloat v, BOOL finished) {
            PACBigMusic *s = ws; if (!s) return;
            s->_holdUntil = CACurrentMediaTime() + 1.2;
            s->_elapsedSec = v * s->_duration;
            s->_stamp = [NSDate date];
            [s updateTimes];
            if (finished && s->_duration > 0) {
                PACBigSend(24, @{ @"kMRMediaRemoteOptionPlaybackPosition": @(v * s->_duration) });
            }
        };
        [self addSubview:_seek];
        _elapsed = [UILabel new]; _remaining = [UILabel new];
        for (UILabel *l in @[_elapsed, _remaining]) {
            l.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
            l.textColor = [UIColor colorWithWhite:1 alpha:0.6];
            [self addSubview:l];
        }
        _remaining.textAlignment = NSTextAlignmentRight;

        _airBg = [UIView new];
        _airBg.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        _airBg.userInteractionEnabled = NO;
        _airBg.hidden = YES;
        [self addSubview:_airBg];
        _airIcon = [UIImageView new];
        _airIcon.tintColor = [UIColor colorWithWhite:1 alpha:0.9];
        _airIcon.contentMode = UIViewContentModeCenter;
        _airIcon.hidden = YES;
        [_airBg addSubview:_airIcon];

        _vol = [[PACBigBar alloc] initWithFrame:CGRectZero];
        _vol.onChange = ^(CGFloat v, BOOL finished) { PACBigSetVolume((float)v); };
        [self addSubview:_vol];
        _volLo = [self volIcon:@"speaker.fill"];
        _volHi = [self volIcon:@"speaker.wave.3.fill"];
    }
    return self;
}
- (UIImageView *)volIcon:(NSString *)n {
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:13 weight:UIImageSymbolWeightMedium];
    UIImageView *v = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:n withConfiguration:c]];
    v.tintColor = [UIColor colorWithWhite:1 alpha:0.7];
    v.contentMode = UIViewContentModeCenter;
    [self addSubview:v];
    return v;
}
- (UIButton *)transport:(NSString *)sym action:(SEL)a {
    UIButton *b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.tintColor = UIColor.whiteColor;
    [b addTarget:self action:a forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:b];
    return b;
}
- (void)setSymbol:(NSString *)sym size:(CGFloat)pt on:(UIButton *)b {
    UIImageSymbolConfiguration *c = [UIImageSymbolConfiguration configurationWithPointSize:pt weight:UIImageSymbolWeightSemibold];
    [b setImage:[[UIImage systemImageNamed:sym withConfiguration:c] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
}
- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (self.window) {
        UIView *lg = [self viewWithTag:190002];
        if (lg && [lg respondsToSelector:NSSelectorFromString(@"lgInvalidateFilterContents")]) ((void (*)(id, SEL))objc_msgSend)(lg, NSSelectorFromString(@"lgInvalidateFilterContents"));
    }
    [_timer invalidate]; _timer = nil;
    if (self.window) {
        [self refresh];
        __weak typeof(self) ws = self;
        _timer = [NSTimer timerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [ws tick]; }];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}
- (void)dealloc { [_timer invalidate]; }

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
    self.layer.cornerRadius = MIN(34.0, h * 0.5);
    if (!_blur.superview) [self insertSubview:_blur atIndex:0];
    _blur.frame = self.bounds;
    _blur.layer.cornerRadius = self.layer.cornerRadius;
    _blur.layer.cornerCurve = kCACornerCurveContinuous;
    _blur.clipsToBounds = YES;
    _blur.hidden = (PACCLIQGlassOn() && PACBigLGGlass(self, self.layer.cornerRadius));
    CGFloat pad = 14.0;
    BOOL tile = (w < 260.0 && h >= 120.0);
    BOOL full = !self.compact && !tile;
    _seek.hidden = _elapsed.hidden = _remaining.hidden = _vol.hidden = _volLo.hidden = _volHi.hidden = !full;
    _airBg.hidden = _airIcon.hidden = !tile;
    _artist.hidden = tile && !_playing;
    if (tile) {
        CGFloat sc = w / 163.0, m = 14.0 * sc, art = round(56.0 * sc), d = round(42.0 * sc);
        _art.frame = CGRectMake(m, m, art, art);
        _art.layer.cornerRadius = 12.0 * sc;
        _airBg.frame = CGRectMake(w - m - d, m, d, d);
        _airBg.layer.cornerRadius = d * 0.5;
        UIImageSymbolConfiguration *ac = [UIImageSymbolConfiguration configurationWithPointSize:d * 0.4 weight:UIImageSymbolWeightMedium];
        UIImage *ai = [UIImage systemImageNamed:@"airplayaudio" withConfiguration:ac] ?: [UIImage systemImageNamed:@"airplay.audio" withConfiguration:ac];
        _airIcon.image = [ai imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        _airIcon.frame = _airBg.bounds;
        UIFont *tf = [UIFont systemFontOfSize:14.5 * sc * (_playing ? 1.0 : 0.9) weight:UIFontWeightSemibold];
        UIFont *af = [UIFont systemFontOfSize:14.5 * sc weight:UIFontWeightRegular];
        _title.font = tf; _artist.font = af;
        CGFloat ty = _playing ? m + art + 7.0 * sc : m + art + 16.0 * sc;
        _title.frame = CGRectMake(m + 2.0 * sc, ty, w - 2.0 * m, ceil(tf.lineHeight));
        _artist.frame = CGRectMake(m + 2.0 * sc, ty + ceil(tf.lineHeight), w - 2.0 * m, ceil(af.lineHeight));
        CGFloat cy = round(h * 0.84), bw = round(42.0 * sc);
        _prev.frame = CGRectMake(round(w / 2 - 46.0 * sc - bw / 2), cy - bw / 2, bw, bw);
        _play.frame = CGRectMake(round(w / 2 - bw / 2), cy - bw / 2, bw, bw);
        _next.frame = CGRectMake(round(w / 2 + 46.0 * sc - bw / 2), cy - bw / 2, bw, bw);
        [self setSymbol:@"backward.fill" size:22 on:_prev];
        [self setSymbol:_playing ? @"pause.fill" : @"play.fill" size:30 on:_play];
        [self setSymbol:@"forward.fill" size:22 on:_next];
        _prev.alpha = _next.alpha = 1.0;
        return;
    }
    _title.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    _artist.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
    _prev.alpha = _next.alpha = 1.0;

    if (!full) {
        CGFloat a = h - pad * 2;
        _art.frame = CGRectMake(pad, pad, a, a);
        _art.layer.cornerRadius = 14;
        CGFloat x = pad + a + 14, tw = w - x - pad;
        _title.frame = CGRectMake(x, pad + 4, tw, 20);
        _artist.frame = CGRectMake(x, pad + 25, tw, 18);
        CGFloat bw = 44, by = h - pad - 46;
        CGFloat total = bw * 3, bx = x + (tw - total) * 0.5;
        _prev.frame = CGRectMake(bx, by, bw, 44);
        _play.frame = CGRectMake(bx + bw, by, bw, 44);
        _next.frame = CGRectMake(bx + bw * 2, by, bw, 44);
        [self setSymbol:@"backward.fill" size:20 on:_prev];
        [self setSymbol:_playing ? @"pause.fill" : @"play.fill" size:26 on:_play];
        [self setSymbol:@"forward.fill" size:20 on:_next];
        return;
    }

    pad = 18.0;
    CGFloat volY = h - pad - 24;
    CGFloat transY = volY - 8 - 56;
    CGFloat seekY = transY - 6 - 34;
    CGFloat top = pad;
    BOOL big = h >= 400;
    if (big) {
        CGFloat a = MIN(w - pad * 2, seekY - 70 - top);
        a = MAX(a, 120);
        _art.frame = CGRectMake((w - a) * 0.5, top, a, a);
        _art.layer.cornerRadius = 18;
        _title.frame = CGRectMake(pad, CGRectGetMaxY(_art.frame) + 10, w - pad * 2, 22);
        _artist.frame = CGRectMake(pad, CGRectGetMaxY(_art.frame) + 32, w - pad * 2, 18);
    } else {
        _art.frame = CGRectMake(pad, top, 64, 64);
        _art.layer.cornerRadius = 12;
        CGFloat x = pad + 64 + 12;
        _title.frame = CGRectMake(x, top + 11, w - x - pad, 22);
        _artist.frame = CGRectMake(x, top + 33, w - x - pad, 18);
    }
    _seek.frame = CGRectMake(pad, seekY, w - pad * 2, 24);
    _elapsed.frame = CGRectMake(pad, seekY + 22, 80, 14);
    _remaining.frame = CGRectMake(w - pad - 80, seekY + 22, 80, 14);
    CGFloat bw = 64, total = bw * 3, bx = (w - total) * 0.5;
    _prev.frame = CGRectMake(bx, transY, bw, 56);
    _play.frame = CGRectMake(bx + bw, transY, bw, 56);
    _next.frame = CGRectMake(bx + bw * 2, transY, bw, 56);
    [self setSymbol:@"backward.fill" size:26 on:_prev];
    [self setSymbol:_playing ? @"pause.fill" : @"play.fill" size:34 on:_play];
    [self setSymbol:@"forward.fill" size:26 on:_next];
    _volLo.frame = CGRectMake(pad, volY, 22, 24);
    _volHi.frame = CGRectMake(w - pad - 22, volY, 22, 24);
    _vol.frame = CGRectMake(pad + 30, volY, w - pad * 2 - 60, 24);
    _vol.value = PACBigGetVolume();
}

- (void)updateTimes {
    double e = _elapsedSec;
    if (_playing && _rate > 0 && _stamp && !_seek.dragging && CACurrentMediaTime() >= _holdUntil) {
        e += [[NSDate date] timeIntervalSinceDate:_stamp] * _rate;
    }
    if (_duration > 0) e = MIN(e, _duration);
    _elapsed.text = PACBigTime(e, NO);
    _remaining.text = PACBigTime(_duration - e, YES);
    if (!_seek.dragging && _duration > 0) _seek.value = e / _duration;
}
- (void)tick {
    [self updateTimes];
    if (!_vol.dragging && !_vol.hidden) _vol.value = PACBigGetVolume();
    static int n; if ((++n % 2) == 0) [self refresh];
}
- (void)refresh {
    void *h = PACBigMR();
    PACBigInfoFn get = h ? (PACBigInfoFn)dlsym(h, "MRMediaRemoteGetNowPlayingInfo") : NULL;
    if (!get) return;
    __weak typeof(self) ws = self;
    get(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        PACBigMusic *s = ws; if (!s) return;
        NSDictionary *d = (__bridge NSDictionary *)info;
        if (![d isKindOfClass:NSDictionary.class]) d = @{};
        NSString *title = d[@"kMRMediaRemoteNowPlayingInfoTitle"];
        NSString *artist = d[@"kMRMediaRemoteNowPlayingInfoArtist"];
        NSData *art = d[@"kMRMediaRemoteNowPlayingInfoArtworkData"];
        id el = d[@"kMRMediaRemoteNowPlayingInfoElapsedTime"], du = d[@"kMRMediaRemoteNowPlayingInfoDuration"];
        id ra = d[@"kMRMediaRemoteNowPlayingInfoPlaybackRate"], ts = d[@"kMRMediaRemoteNowPlayingInfoTimestamp"];
        BOOL has = [title isKindOfClass:NSString.class] && title.length;
        s->_title.text = has ? title : @"Not Playing";
        s->_artist.text = [artist isKindOfClass:NSString.class] ? artist : @"";
        if (CACurrentMediaTime() >= s->_holdUntil) {
            s->_elapsedSec = [el respondsToSelector:@selector(doubleValue)] ? [el doubleValue] : 0;
            s->_stamp = [ts isKindOfClass:NSDate.class] ? ts : [NSDate date];
        }
        s->_duration = [du respondsToSelector:@selector(doubleValue)] ? [du doubleValue] : 0;
        s->_rate = [ra respondsToSelector:@selector(doubleValue)] ? [ra doubleValue] : 0;
        BOOL playing = has && s->_rate > 0;
        if (playing != s->_playing) { s->_playing = playing; [s setNeedsLayout]; }
        if ([art isKindOfClass:NSData.class]) {
            UIImage *img = [UIImage imageWithData:art];
            if (img) { s->_art.image = img; s->_art.contentMode = UIViewContentModeScaleAspectFill; }
        } else if (!has) {
            s->_art.image = nil;
        }
        [s updateTimes];
    });
}
- (void)after { __weak typeof(self) ws = self; dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.35 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [ws refresh]; }); }
- (void)prevTap { if (gHapticsEnabled) Haptic(); PACBigSend(5, nil); [self after]; }
- (void)nextTap { if (gHapticsEnabled) Haptic(); PACBigSend(4, nil); [self after]; }
- (void)playTap {
    if (gHapticsEnabled) Haptic();
    PACBigSend(2, nil);
    _playing = !_playing;
    [self setNeedsLayout];
    [self after];
}
@end

#pragma mark - entry point

static void PACBigMask(UIView *host, UIView *keep, BOOL hide) {
    for (UIView *v in host.subviews) {
        if (v == keep || v.tag == kPACBigTag) continue;
        BOOL masked = [v.layer.mask.name isEqualToString:kPACBigMaskName];
        if (hide && !masked) {
            CALayer *mk = [CALayer layer];
            mk.name = kPACBigMaskName;
            v.layer.mask = mk;
        } else if (!hide && masked) {
            v.layer.mask = nil;
        }
    }
}

static const char kPACPlateMask = 0;

static void PACBigMaskPlate(UIView *s, BOOL hide) {
    BOOL has = objc_getAssociatedObject(s, &kPACPlateMask) != nil;
    if (hide && !has) {
        s.layer.mask = [CALayer layer];
        objc_setAssociatedObject(s, &kPACPlateMask, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    } else if (!hide && has) {
        s.layer.mask = nil;
        objc_setAssociatedObject(s, &kPACPlateMask, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
}

static const char kPACPlateLGHidden = 0;

static void PACBigHideModuleMaterialEx(UIView *host, BOOL hide, BOOL includeLG) {
    CGFloat screenW = UIScreen.mainScreen.bounds.size.width;
    CGRect area = [host convertRect:host.bounds toView:nil];
    UIView *child = host;
    int up = 0;
    for (UIView *p = host.superview; p && up < 8; child = p, p = p.superview, up++) {
        for (UIView *s in p.subviews) {
            if (s == child || [s isKindOfClass:PACBigView.class]) continue;
            NSString *n = NSStringFromClass(s.class);
            if (!includeLG && PACCLIQGlassOn() && ([n hasPrefix:@"LG"] || [n isEqualToString:@"MTMaterialView"])) continue;
            if (!([n containsString:@"Material"] || [n containsString:@"Backdrop"] || [n containsString:@"Background"] ||
                  [n containsString:@"Blur"] || [n containsString:@"Platter"])) continue;
            CGRect f = [s convertRect:s.bounds toView:nil];
            if (f.size.width >= screenW * 0.97 || f.size.width < area.size.width * 0.8) continue;
            if (!CGRectIntersectsRect(f, area)) continue;
            PACBigMaskPlate(s, hide);
            if (includeLG && [n hasPrefix:@"LG"]) {
                if (hide && !s.hidden) {
                    s.hidden = YES;
                    objc_setAssociatedObject(s, &kPACPlateLGHidden, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                } else if (!hide && objc_getAssociatedObject(s, &kPACPlateLGHidden)) {
                    s.hidden = NO;
                    objc_setAssociatedObject(s, &kPACPlateLGHidden, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
            }
        }
    }
}

static void PACBigHideModuleMaterial(UIView *host, BOOL hide) {
    PACBigHideModuleMaterialEx(host, hide, NO);
}

void PACCBigStyle(UIViewController *m, NSString *mid, NSUInteger w, NSUInteger h, BOOL expanded) {
    PACCCrumb("PACCBigStyle");
    UIView *host = m.view;
    if (!host) return;
    int kind = PACCBigKind(mid);
    UIView *existing = [host viewWithTag:kPACBigTag];
    BOOL big = NO;
    if (kind == 1) big = (w >= 4 && h >= 4);
    else if (kind == 2) big = (w >= 2 && h >= 2 && !(w == 2 && h == 2));
    if (expanded || !big || !gEnabled || PACCBigKind(mid) == 0 ||
        host.bounds.size.width < 60 || host.bounds.size.height < 60) {
        if (existing) {
            [existing removeFromSuperview];
            PACBigMask(host, nil, NO);
        }
        if (kind && !(expanded && kind == 1)) PACBigHideModuleMaterial(host, NO);
        return;
    }
    PACBigHideModuleMaterial(host, YES);

    UIView *bv = existing;
    Class want = (kind == 1) ? PACBigConn.class : PACBigMusic.class;
    if (bv && ![bv isKindOfClass:want]) { [bv removeFromSuperview]; bv = nil; }
    if (!bv) {
        bv = [[want alloc] initWithFrame:host.bounds];
        bv.alpha = 0;
        [host addSubview:bv];
        [UIView animateWithDuration:0.3 animations:^{ bv.alpha = 1; }];
    }
    PACBigMask(host, bv, YES);
    if (host.subviews.lastObject != bv) [host bringSubviewToFront:bv];
    CGRect wantFrame = host.bounds;
    if (kind == 1 && h >= 6) {
        wantFrame = CGRectInset(wantFrame, 0.0, -kPACConnExtra * 0.5);
        host.clipsToBounds = NO;
    }
    if (!CGRectEqualToRect(bv.frame, wantFrame)) bv.frame = wantFrame;
    bv.userInteractionEnabled = !gEditModeActive;

    if (kind == 1) {
        PACBigConn *c = (PACBigConn *)bv;
        c.apple = host;
        [c refresh];
    } else {
        PACBigMusic *p = (PACBigMusic *)bv;
        BOOL compact = (h < 4);
        if (p.compact != compact) { p.compact = compact; [p setNeedsLayout]; }
    }
}

#pragma mark - stand-alone copies (a second Connectivity or Music on another page)

static void PACBigDropPlatter(UIView *root, UIView *mine) {
    for (UIView *host in @[root ?: UIView.new, mine ?: UIView.new]) {
        for (UIView *v in [host.subviews copy]) {
            if (v.tag == 190001) { v.layer.filters = nil; [v removeFromSuperview]; }
        }
    }
}

static const char kPACChromeKey = 0;
static const char kPACHiddenKey = 0;

void PACCBigStripContainer(UIView *container) {
    if (!container) return;
    UIView *mine = [container viewWithTag:190200];
    BOOL strip = (mine && !mine.hidden && mine.window);
    NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:container];
    while (queue.count) {
        UIView *v = queue.firstObject; [queue removeObjectAtIndex:0];
        if (v == mine) continue;
        [queue addObjectsFromArray:v.subviews];
        CALayer *l = v.layer;
        NSDictionary *saved = objc_getAssociatedObject(l, &kPACChromeKey);
        if (strip) {
            if (!saved) {
                id bgObj = l.backgroundColor ? (__bridge id)l.backgroundColor : (id)NSNull.null;
                saved = @{@"bg": bgObj,
                          @"f": l.filters ?: NSNull.null,
                          @"bf": l.backgroundFilters ?: NSNull.null,
                          @"bw": @(l.borderWidth), @"so": @(l.shadowOpacity)};
                objc_setAssociatedObject(l, &kPACChromeKey, saved, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            l.backgroundColor = NULL; l.filters = nil; l.backgroundFilters = nil; l.borderWidth = 0; l.shadowOpacity = 0;
            NSString *cn = NSStringFromClass(v.class);
            BOOL plate = [cn containsString:@"Material"] || [cn containsString:@"Backdrop"] || [cn containsString:@"LGLive"] ||
                         [cn containsString:@"Platter"] || [cn containsString:@"Background"] || [cn containsString:@"PACCLIQGlass"];
            if (plate && ![mine isDescendantOfView:v] && !v.hidden) {
                v.hidden = YES;
                objc_setAssociatedObject(v, &kPACHiddenKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        } else {
            if (saved) {
                id bg = saved[@"bg"], f = saved[@"f"], bf = saved[@"bf"];
                l.backgroundColor = (bg == NSNull.null) ? NULL : (__bridge CGColorRef)bg;
                l.filters = (f == NSNull.null) ? nil : f;
                l.backgroundFilters = (bf == NSNull.null) ? nil : bf;
                l.borderWidth = [saved[@"bw"] doubleValue];
                l.shadowOpacity = [saved[@"so"] floatValue];
                objc_setAssociatedObject(l, &kPACChromeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
            if (objc_getAssociatedObject(v, &kPACHiddenKey)) {
                v.hidden = NO;
                objc_setAssociatedObject(v, &kPACHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            }
        }
    }
}

void PACCBigConfigureExpanded(UIViewController *controller, BOOL expanded) {
    UIView *root = controller.view;
    if (!root) return;
    PACBigConn *mine = (PACBigConn *)[root viewWithTag:190200];
    Class L = NSClassFromString(@"CCUILabeledRoundButton");
    NSMutableArray *found = [NSMutableArray array];
    if (L) PACBigCollect(root, L, 0, found);
    if (!expanded) {
        if (mine && !mine.hidden) {
            PACBigHideModuleMaterialEx(root, NO, YES);
            mine.hidden = YES;
            UIView *c = root.superview; Class cc = NSClassFromString(@"CCUIContentModuleContainerView");
            while (c && cc && ![c isKindOfClass:cc]) c = c.superview;
            PACCBigStripContainer(c);
        }
        mine.hidden = YES;
        for (UIView *b in found) if (objc_getAssociatedObject(b, "pacHidden")) { b.alpha = 1.0; objc_setAssociatedObject(b, "pacHidden", nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
        return;
    }
    if (!mine) {
        mine = [[PACBigConn alloc] initWithFrame:CGRectZero];
        mine.tag = 190200;
        [root addSubview:mine];
    }
    mine.apple = root;
    mine.hidden = NO;
    {
        static NSString *lastSize;
        NSString *sz = [NSString stringWithFormat:@"expanded root %@ container %@ window %.0f", NSStringFromCGRect(root.bounds),
                        NSStringFromCGRect(root.superview.bounds), root.window.bounds.size.height];
        if (![sz isEqualToString:lastSize]) { lastSize = sz; PACCSizeLog(sz); }
    }
    PACBigHideModuleMaterialEx(root, YES, YES);
    PACBigDropPlatter(root, mine);
    {
        __weak UIView *wroot = root;
        for (NSNumber *d in @[@0.15, @0.5, @1.0]) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                UIView *r = wroot;
                UIView *m2 = r ? [r viewWithTag:190200] : nil;
                if (r && m2 && !m2.hidden && m2.window) { PACBigHideModuleMaterialEx(r, YES, YES); PACBigDropPlatter(r, (PACBigConn *)m2); }
            });
        }
    }
    mine.frame = root.bounds;
    {
        UIView *c = root.superview; Class cc = NSClassFromString(@"CCUIContentModuleContainerView");
        while (c && cc && ![c isKindOfClass:cc]) c = c.superview;
        PACCBigStripContainer(c);
    }
    [root bringSubviewToFront:mine];
    for (UIView *b in found) {
        if (b.alpha != 0.0) { b.alpha = 0.0; objc_setAssociatedObject(b, "pacHidden", @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC); }
    }
}

UIView *PACCBigNewClone(int kind) {
    if (kind == 1) return [[PACBigConn alloc] initWithFrame:CGRectZero];
    if (kind == 3) return [[PACBigToggle alloc] initWithFrame:CGRectZero];
    PACBigMusic *m = [[PACBigMusic alloc] initWithFrame:CGRectZero];
    m.standalone = YES;
    return m;
}

UIControl *PACCBigFindRound(UIView *apple, NSString *key) {
    Class L = NSClassFromString(@"CCUILabeledRoundButton");
    if (!L || !apple) return nil;
    NSMutableArray *found = [NSMutableArray array];
    PACBigCollect(apple, L, 0, found);
    for (UIView *b in found) {
        id t = PACBigKV(b, @"title");
        NSString *title = [t isKindOfClass:NSString.class] ? t : @"";
        if (!title.length) {
            NSMutableArray *labels = [NSMutableArray array];
            PACBigCollect(b, UILabel.class, 0, labels);
            for (UILabel *lb in labels) if (lb.text.length) { title = lb.text; break; }
        }
        if (![PACBigKey(title) isEqualToString:key]) continue;
        id rb = PACBigKV(b, @"buttonView");
        UIControl *round = [rb isKindOfClass:UIControl.class] ? rb : nil;
        if (!round) {
            NSMutableArray *all = [NSMutableArray array];
            PACBigCollect(b, UIControl.class, 0, all);
            for (UIControl *c in all) if ([NSStringFromClass(c.class) containsString:@"RoundButton"]) { round = c; break; }
        }
        return round;
    }
    return nil;
}

void PACCBigSetToggleMid(UIView *v, NSString *mid) {
    if (![v isKindOfClass:PACBigToggle.class]) return;
    NSString *k = [mid substringFromIndex:MIN(mid.length, (NSUInteger)12)];
    if (![k isEqualToString:((PACBigToggle *)v).key]) ((PACBigToggle *)v).key = k;
}

void PACCBigConfigureClone(UIView *v, int kind, NSUInteger w, NSUInteger h, UIView *apple) {
    if (kind == 3 && [v isKindOfClass:PACBigToggle.class]) {
        PACBigToggle *t = (PACBigToggle *)v;
        if (t.apple != apple) t.apple = apple;
    } else if (kind == 1 && [v isKindOfClass:PACBigConn.class]) {
        PACBigConn *c = (PACBigConn *)v;
        if (c.apple != apple) c.apple = apple;
    } else if (kind == 2 && [v isKindOfClass:PACBigMusic.class]) {
        PACBigMusic *p = (PACBigMusic *)v;
        BOOL compact = (h < 4);
        if (p.compact != compact) { p.compact = compact; [p setNeedsLayout]; }
    }
    v.layer.cornerCurve = kCACornerCurveContinuous;
}


#pragma mark - 2x2 Now Playing: Apple's own views laid out like iOS 26 (as ControlCenter26 does with the MRU views)

static BOOL PACMRUTile(UIView *v, CGSize *outSize) {
    return NO;
    if (!gEnabled) return NO;
    Class cc = NSClassFromString(@"CCUIContentModuleContainerView");
    int up = 0;
    for (UIView *p = v.superview; p && up < 16; p = p.superview, up++) {
        if (cc && [p isKindOfClass:cc]) {
            CGSize z = p.bounds.size;
            if (z.width >= 100 && z.width <= 260 && z.height >= 100 && z.height <= 260) { if (outSize) *outSize = z; return YES; }
            return NO;
        }
    }
    return NO;
}

static id PACMRUIvar(id obj, NSString *name) {
    @try { return [obj valueForKey:name]; } @catch (...) { return nil; }
}

%hook MRUNowPlayingView
- (void)layoutSubviews {
    %orig;
    CGSize z;
    if (!PACMRUTile((UIView *)self, &z)) return;
    CGRect b = ((UIView *)self).bounds;
    UIView *header = PACMRUIvar(self, @"_headerView");
    UIView *transport = PACMRUIvar(self, @"_transportControlsView");
    for (NSString *n in @[@"_timeControlsView", @"_volumeControlsView"]) {
        UIView *v = PACMRUIvar(self, n);
        if ([v isKindOfClass:UIView.class]) v.hidden = YES;
    }
    if ([header isKindOfClass:UIView.class]) header.frame = b;
    if ([transport isKindOfClass:UIView.class]) {
        CGFloat bh = floor(b.size.width * 0.22);
        transport.frame = CGRectMake(0, b.size.height * 0.82 - bh * 0.5, b.size.width, bh);
    }
}
%end

%hook MRUNowPlayingHeaderView
- (void)layoutSubviews {
    %orig;
    CGSize z;
    if (!PACMRUTile((UIView *)self, &z)) return;
    CGFloat w = ((UIView *)self).bounds.size.width, h = ((UIView *)self).bounds.size.height;
    CGFloat art = floor(w * 0.332), left = floor(w * 0.104), top = floor(h * 0.107), air = floor(w * 0.26);
    UIView *artwork = PACMRUIvar(self, @"_artworkView");
    UIView *route = PACMRUIvar(self, @"_routingButton");
    UIView *label = PACMRUIvar(self, @"_labelView");
    if ([artwork isKindOfClass:UIView.class]) {
        artwork.frame = CGRectMake(left, top, art, art);
        artwork.layer.cornerRadius = art * 0.24;
        artwork.layer.cornerCurve = kCACornerCurveContinuous;
        artwork.layer.masksToBounds = YES;
    }
    if ([route isKindOfClass:UIView.class]) {
        route.frame = CGRectMake(w - left - air, top, air, air);
        route.backgroundColor = [UIColor colorWithWhite:1 alpha:0.14];
        route.layer.cornerRadius = air * 0.5;
        route.layer.masksToBounds = YES;
    }
    if ([label isKindOfClass:UIView.class]) {
        CGFloat tx = floor(w * 0.12);
        label.frame = CGRectMake(tx, floor(h * 0.59) - w * 0.1, w - tx - left, w * 0.2);
    }
}
%end

%hook MRUArtworkView
- (void)layoutSubviews {
    %orig;
    CGSize z;
    if (!PACMRUTile((UIView *)self, &z)) return;
    UIView *v = (UIView *)self;
    for (UIView *sub in v.subviews) {
        if (![NSStringFromClass(sub.class) hasPrefix:@"MRU"] && ![sub isKindOfClass:UIImageView.class]) continue;
        sub.frame = v.bounds;
    }
    v.layer.cornerRadius = v.bounds.size.width * 0.24;
    v.layer.cornerCurve = kCACornerCurveContinuous;
    v.layer.masksToBounds = YES;
}
%end

static void PACMRUApplyTile(UIView *v) {
    CGSize z;
    if (!PACMRUTile(v, &z)) return;
    NSMutableArray<UIView *> *btns = [NSMutableArray array];
    for (UIView *sub in v.subviews) if ([NSStringFromClass(sub.class) hasPrefix:@"MRUTransportButton"] && !sub.hidden) [btns addObject:sub];
    if (btns.count != 3) return;
    [btns sortUsingComparator:^NSComparisonResult(UIView *a, UIView *b) {
        return CGRectGetMidX(a.frame) < CGRectGetMidX(b.frame) ? NSOrderedAscending : NSOrderedDescending;
    }];
    CGFloat w = v.bounds.size.width, h = v.bounds.size.height;
    CGFloat bw = floor(w * 0.26);
    NSArray<NSNumber *> *cxs = @[@(w * 0.23), @(w * 0.508), @(w * 0.77)];
    [UIView performWithoutAnimation:^{
        for (int i = 0; i < 3; i++) {
            [btns[i].layer removeAllAnimations];
            btns[i].transform = CGAffineTransformIdentity;
            btns[i].frame = CGRectMake(cxs[i].doubleValue - bw * 0.5, (h - MIN(h, bw)) * 0.5, bw, MIN(h, bw));
            CGFloat bs2 = (i == 1) ? 0.7 : 0.4;
            btns[i].transform = CGAffineTransformMakeScale(bs2, bs2);
        }
    }];
}

%hook MRUNowPlayingTransportControlsView
- (void)layoutSubviews {
    %orig;
    UIView *v = (UIView *)self;
    PACMRUApplyTile(v);
    __weak UIView *wv = v;
    for (NSNumber *d in @[@0.05, @0.2, @0.5, @0.9]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(d.doubleValue * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIView *sv = wv;
            if (sv) PACMRUApplyTile(sv);
        });
    }
}
%end

