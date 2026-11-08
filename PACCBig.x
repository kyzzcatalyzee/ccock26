// PACCBig.x - big Connectivity and Music layouts for CCock26 (written for CCock26, zilvyn)
//
// When Connectivity or Now Playing is stretched to 4 columns, Apple's own drawing of the module is
// hidden and a layout drawn here is shown instead:
//   Connectivity 4x4 / 4x6 : one card per button (Airplane, Wi-Fi, Cellular, Bluetooth, AirDrop, Hotspot)
//   Music 4x2              : artwork, title, artist and the three transport buttons
//   Music 4x4 / 4x6        : artwork, title, seek bar, transport buttons and a volume bar
// Taps on the connectivity cards are forwarded to Apple's real buttons, so the real toggles do the work.

#import "PACC.h"
#import <QuartzCore/QuartzCore.h>

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

// 1 = Connectivity, 2 = Now Playing, 0 = anything else
int PACCBigKind(NSString *mid) {
    NSString *l = mid.lowercaseString;
    if (!l.length) return 0;
    if ([l containsString:@"connectivity"]) return 1;
    if ([l containsString:@"nowplaying"] || [l containsString:@"mediacontrols"]) return 2;
    return 0;
}

BOOL PACCBigSizeAllowed(NSString *mid, NSUInteger w, NSUInteger h) {
    int k = PACCBigKind(mid);
    if (k == 1) return (w == 2 && h == 2) || (w == 4 && (h == 4 || h == 6));
    if (k == 2) return (w == 2 && h == 2) || (w == 4 && (h == 2 || h == 4 || h == 6));
    return NO;
}

// The allowed size closest to what the finger asked for.
void PACCBigSnapSize(NSString *mid, NSInteger wantW, NSInteger wantH, NSUInteger *outW, NSUInteger *outH) {
    NSUInteger cands[][2] = { {2, 2}, {4, 2}, {4, 4}, {4, 6} };
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

// 2 = play / pause, 4 = next, 5 = previous, 24 = seek to position
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
@property (nonatomic) CGFloat value;                 // 0...1
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
@property (nonatomic, weak) UIControl *target;      // Apple's round button
@property (nonatomic, weak) UIView *labeled;        // Apple's labeled button
@property (nonatomic, strong) UIImageView *icon;
@property (nonatomic, strong) UILabel *title;
@property (nonatomic, strong) UILabel *sub;
@property (nonatomic) BOOL isOn;
@property (nonatomic) BOOL tall;                    // square card: icon on top, text at the bottom
@property (nonatomic, strong) UIView *material;     // the same material the stock controls use
- (void)setOn:(BOOL)on;
@end

static UIColor *PACBigOnColor(NSString *key) {
    if ([key isEqualToString:@"air"]) return [UIColor colorWithRed:1.0 green:0.62 blue:0.04 alpha:1];
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

static UIImage *PACBigIconForKey(NSString *key, CGFloat pt) {
    if ([key isEqualToString:@"air"])     return PACBigSymbol(@[@"airplane"], pt);
    if ([key isEqualToString:@"wifi"])    return PACBigSymbol(@[@"wifi"], pt);
    if ([key isEqualToString:@"cell"])    return PACBigSymbol(@[@"antenna.radiowaves.left.and.right"], pt);
    if ([key isEqualToString:@"bt"])      return PACBigSymbol(@[@"bluetooth", @"dot.radiowaves.left.and.right"], pt);
    if ([key isEqualToString:@"airdrop"]) return PACBigSymbol(@[@"airdrop", @"dot.radiowaves.up.forward", @"wave.3.right"], pt);
    if ([key isEqualToString:@"hotspot"]) return PACBigSymbol(@[@"personalhotspot", @"antenna.radiowaves.left.and.right.circle"], pt);
    return PACBigSymbol(@[@"circle.fill"], pt);
}

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
        [self addTarget:self action:@selector(tapped) forControlEvents:UIControlEventTouchUpInside];
    }
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat h = self.bounds.size.height, w = self.bounds.size.width;
    if (_material) {
        if (!CGRectEqualToRect(_material.frame, self.bounds)) _material.frame = self.bounds;
        [self sendSubviewToBack:_material];
    }
    if (_tall) {
        self.layer.cornerRadius = MIN(36.0, h * 0.3);
        CGFloat d = 44.0;
        _icon.frame = CGRectMake(16.0, 16.0, d, d);
        _icon.layer.cornerRadius = d * 0.5;
        _icon.layer.masksToBounds = YES;
        _icon.image = PACBigIconForKey(_key, d * 0.46);
        _title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        _sub.font = [UIFont systemFontOfSize:14 weight:UIFontWeightRegular];
        CGFloat tw = MAX(0, w - 32.0);
        _sub.frame = CGRectMake(16.0, h - 16.0 - 17.0, tw, 17.0);
        _title.frame = CGRectMake(16.0, h - 16.0 - 17.0 - 21.0, tw, 21.0);
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
- (void)setOn:(BOOL)on {
    _isOn = on;
    if (_tall) {
        _icon.backgroundColor = on ? PACBigOnColor(_key) : [UIColor colorWithWhite:1 alpha:0.85];
        _icon.tintColor = on ? UIColor.whiteColor : [UIColor colorWithWhite:0.42 alpha:1];
    } else {
        _icon.backgroundColor = on ? PACBigOnColor(_key) : [UIColor colorWithWhite:1 alpha:0.2];
        _icon.tintColor = UIColor.whiteColor;
    }
}
- (void)tapped {
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

// ControlCenterUI walks the views of a module and sends it its own selectors (caAnimationContainerView, ...).
// Our overlay sits among them, so it answers those instead of crashing SpringBoard.
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

#pragma mark - big connectivity

@interface PACBigConn : PACBigView
@property (nonatomic, weak) UIView *apple;           // the module's own view with Apple's buttons
- (void)refresh;
@end

@implementation PACBigConn {
    NSMutableDictionary<NSString *, PACBigCard *> *_cards;
    NSTimer *_timer;
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
    if (self.window) {
        __weak typeof(self) ws = self;
        _timer = [NSTimer timerWithTimeInterval:0.6 repeats:YES block:^(NSTimer *t) { [ws refresh]; }];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    }
}
- (void)dealloc { [_timer invalidate]; }
- (void)layoutSubviews { [super layoutSubviews]; [self refresh]; }
- (void)refresh {
    PACCCrumb("PACBigConn refresh");
    @try { [self refreshImpl]; } @catch (NSException *e) { NSLog(@"[CCock26] connectivity refresh: %@", e); }
}
- (void)refreshImpl {
    Class L = NSClassFromString(@"CCUILabeledRoundButton");
    if (!L || !self.apple) return;
    NSMutableArray *found = [NSMutableArray array];
    PACBigCollect(self.apple, L, 0, found);

    NSArray *order = @[@"air", @"wifi", @"cell", @"bt", @"airdrop", @"hotspot"];
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
    // all six are always shown; one the device does not have (no Cellular or Hotspot) stays dimmed and cannot be pressed
    for (NSString *k in order) [keys addObject:k];
    for (NSString *k in byKey) if (![keys containsObject:k]) [keys addObject:k];

    CGSize S = self.bounds.size;
    if (S.width < 40 || S.height < 40) return;
    // iOS 26 look: Airplane Mode as a wide pill on top, square cards in two columns, Hotspot as a pill at the bottom
    BOOL hasTop = [keys containsObject:@"air"], hasBottom = [keys containsObject:@"hotspot"];
    NSMutableArray<NSString *> *cardKeys = [keys mutableCopy];
    [cardKeys removeObject:@"air"]; [cardKeys removeObject:@"hotspot"];
    NSUInteger cardRows = (cardKeys.count + 1) / 2;
    NSUInteger pills = (hasTop ? 1 : 0) + (hasBottom ? 1 : 0);
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
    if (hasBottom) frames[@"hotspot"] = [NSValue valueWithCGRect:CGRectMake(0, yy, S.width, ph)];

    for (NSUInteger i = 0; i < keys.count; i++) {
        NSString *k = keys[i];
        UIView *labeled = byKey[k];
        PACBigCard *card = _cards[k];
        if (!card) {
            card = [[PACBigCard alloc] initWithFrame:CGRectZero];
            card.key = k;
            _cards[k] = card;
            [self addSubview:card];
        }
        BOOL tall = !([k isEqualToString:@"air"] || [k isEqualToString:@"hotspot"]) && ch >= 100.0;
        if (card.tall != tall) { card.tall = tall; [card setNeedsLayout]; }
        NSValue *fv = frames[k];
        if (fv) card.frame = fv.CGRectValue;
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
        if (![card.sub.text isEqualToString:sub]) card.sub.text = sub;
        [card setOn:on];
        card.alpha = round ? (round.enabled ? 1.0 : 0.5) : 0.4;
        card.enabled = round != nil && !gEditModeActive;
    }
}
@end

#pragma mark - big music

@interface PACBigMusic : PACBigView
@property (nonatomic) BOOL compact;                  // 4x2 strip
@property (nonatomic) BOOL standalone;               // a copy that draws its own material
- (void)refresh;
@end

// Built exactly like the material of the old built-in music page, which LiquidAss already styles.
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

@implementation PACBigMusic {
    UIView *_blur;
    UIImageView *_art;
    UILabel *_title, *_artist, *_elapsed, *_remaining;
    UIButton *_prev, *_play, *_next;
    PACBigBar *_seek, *_vol;
    UIImageView *_volLo, *_volHi;
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
    _blur.frame = self.bounds;
    self.layer.cornerRadius = MIN(34.0, h * 0.5);
    _blur.layer.cornerRadius = self.layer.cornerRadius;
    _blur.layer.cornerCurve = kCACornerCurveContinuous;
    _blur.clipsToBounds = YES;
    // LiquidAss: the glass sits behind everything and takes the place of the plain material (as on the old music page)
    _blur.hidden = PACCLIQApplyGlass(self, self.layer.cornerRadius);
    CGFloat pad = 14.0;
    BOOL full = !self.compact;
    _seek.hidden = _elapsed.hidden = _remaining.hidden = _vol.hidden = _volLo.hidden = _volHi.hidden = !full;

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
            v.layer.mask = mk;            // an empty mask hides the view and everything below it
        } else if (!hide && masked) {
            v.layer.mask = nil;
        }
    }
}

// Shows or removes the big layout of a module. Safe to call on every layout pass.
// The module's own background (a material view in its container). Connectivity draws one material per tile, so the big
// layout hides this one and the tiles float on their own.
static void PACBigHideModuleMaterial(UIView *host, BOOL hide) {
    UIView *container = host.superview;
    Class cls = NSClassFromString(@"CCUIContentModuleContainerView");
    while (container && cls && ![container isKindOfClass:cls]) container = container.superview;
    if (!container) return;
    for (UIView *s in container.subviews) {
        if (s == host || [host isDescendantOfView:s]) continue;
        if (![NSStringFromClass(s.class) containsString:@"Material"]) continue;
        CGFloat a = hide ? 0.0 : 1.0;
        if (fabs(s.alpha - a) > 0.01) s.alpha = a;
    }
}

void PACCBigStyle(UIViewController *m, NSString *mid, NSUInteger w, NSUInteger h, BOOL expanded) {
    PACCCrumb("PACCBigStyle");
    UIView *host = m.view;
    if (!host) return;
    int kind = PACCBigKind(mid);
    UIView *existing = [host viewWithTag:kPACBigTag];
    BOOL big = NO;
    if (kind == 1) big = (w >= 4 && h >= 4);
    else if (kind == 2) big = (w >= 4 && h >= 2);
    if (expanded || !big || !gEnabled || PACCBigKind(mid) == 0 ||
        host.bounds.size.width < 60 || host.bounds.size.height < 60) {
        if (existing) {
            [existing removeFromSuperview];
            PACBigMask(host, nil, NO);
        }
        if (kind) PACBigHideModuleMaterial(host, NO);
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
    if (!CGRectEqualToRect(bv.frame, host.bounds)) bv.frame = host.bounds;
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

UIView *PACCBigNewClone(int kind) {
    if (kind == 1) return [[PACBigConn alloc] initWithFrame:CGRectZero];
    PACBigMusic *m = [[PACBigMusic alloc] initWithFrame:CGRectZero];
    m.standalone = YES;                  // a copy has no module behind it, so it brings its own material
    return m;
}

// apple: the view of the real Connectivity module, whose buttons the cards press
void PACCBigConfigureClone(UIView *v, int kind, NSUInteger w, NSUInteger h, UIView *apple) {
    if (kind == 1 && [v isKindOfClass:PACBigConn.class]) {
        PACBigConn *c = (PACBigConn *)v;
        if (c.apple != apple) c.apple = apple;
    } else if (kind == 2 && [v isKindOfClass:PACBigMusic.class]) {
        PACBigMusic *p = (PACBigMusic *)v;
        BOOL compact = (h < 4);
        if (p.compact != compact) { p.compact = compact; [p setNeedsLayout]; }
    }
    v.layer.cornerCurve = kCACornerCurveContinuous;
}
