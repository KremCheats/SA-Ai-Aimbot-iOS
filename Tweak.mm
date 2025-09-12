#import <UIKit/UIKit.h>
#import <CoreML/CoreML.h>
#import <Vision/Vision.h>
#import <Foundation/Foundation.h>
#import <IOKit/hid/IOHIDEventSystemClient.h>
#import <IOKit/hid/IOHIDEvent.h>
#import <mach/mach_time.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import <stdarg.h>
#import <string.h>
#import <stdio.h>

extern "C" {
    IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
    void IOHIDEventSystemClientDispatchEvent(IOHIDEventSystemClientRef client, IOHIDEventRef event);
}

#define LOG_HOST "192.168.0.12"
#define LOG_PORT 5005
#define CAPTURE_INTERVAL 0.1

@class ScreenAnalyzer;
static ScreenAnalyzer *analyzer = nil;

@interface ScreenAnalyzer : NSObject
@property (nonatomic, strong) MLModel *model;
@property (nonatomic, strong) VNCoreMLModel *vnModel;
@property (nonatomic, strong) VNCoreMLRequest *vnRequest;
@property (nonatomic, strong) UIView *overlayView;
@property (nonatomic, strong) CAShapeLayer *overlayShape;
@property (nonatomic, strong) NSTimer *timer;
@property (atomic, assign) BOOL isProcessing;
@end

@implementation ScreenAnalyzer

static void sendTouchEvent(int type, CGPoint point) {
    static IOHIDEventSystemClientRef client = NULL;
    if (!client) client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    uint64_t time = mach_absolute_time();
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat normX = point.x / screenSize.width;
    CGFloat normY = point.y / screenSize.height;
    IOHIDEventRef event = IOHIDEventCreateDigitizerFingerEvent(
        kCFAllocatorDefault, *(AbsoluteTime *)&time, 0, 1, type != 2, type != 2, 1.0, normX, normY, 0.0, 0, kIOHIDDigitizerEventRange | kIOHIDDigitizerEventTouch, 0
    );
    if (!event) return;
    IOHIDEventSystemClientDispatchEvent(client, event);
    CFRelease(event);
}

- (void)performFakeSwipeFrom:(CGPoint)start to:(CGPoint)end duration:(CGFloat)duration {
    int steps = 10;
    CGFloat dx = (end.x - start.x) / steps;
    CGFloat dy = (end.y - start.y) / steps;
    CGFloat delay = duration / steps;
    __block int currentStep = 0;
    dispatch_block_t stepBlock;
    stepBlock = ^{
        if (currentStep == 0) {
            sendTouchEvent(0, start);
        } else if (currentStep < steps) {
            CGPoint p = CGPointMake(start.x + dx * currentStep, start.y + dy * currentStep);
            sendTouchEvent(1, p);
        } else {
            sendTouchEvent(2, end);
            return;
        }
        currentStep++;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), stepBlock);
    };
    dispatch_async(dispatch_get_main_queue(), stepBlock);
}

#pragma mark - Analyzer Init

- (instancetype)init {
    self = [super init];
    if (self) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self startAnalyzer];
        });
    }
    return self;
}

- (void)startAnalyzer {
    NSString *modelPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/SafeModel.mlmodelc"];
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:modelPath isDirectory:&isDir];
    NSURL *modelURL = [NSURL fileURLWithPath:modelPath isDirectory:YES];
    NSError *loadErr = nil;
    self.model = [MLModel modelWithContentsOfURL:modelURL error:&loadErr];
    if (!self.model) return;
    NSError *vnErr = nil;
    self.vnModel = [VNCoreMLModel modelForMLModel:self.model error:&vnErr];
    if (!self.vnModel) return;
    
    __weak typeof(self) weakSelf = self;
    self.vnRequest = [[VNCoreMLRequest alloc] initWithModel:self.vnModel completionHandler:^(VNRequest *req, NSError *err) {
        if (err) {
            weakSelf.isProcessing = NO;
            return;
        }
        for (VNObservation *obs in req.results) {
            if (![obs isKindOfClass:[VNCoreMLFeatureValueObservation class]]) continue;
            VNCoreMLFeatureValueObservation *fvObs = (VNCoreMLFeatureValueObservation *)obs;
            MLMultiArray *out = fvObs.featureValue.multiArrayValue;
            if (!out) continue;
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakSelf drawDetections:out];
                weakSelf.isProcessing = NO;
            });
            break;
        }
    }];
    
    self.overlayView = [[UIView alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.overlayView.userInteractionEnabled = NO;
    self.overlayView.backgroundColor = [UIColor clearColor];
    self.overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    
    self.overlayShape = [CAShapeLayer layer];
    self.overlayShape.frame = self.overlayView.bounds;
    self.overlayShape.strokeColor = [UIColor redColor].CGColor;
    self.overlayShape.fillColor = [UIColor clearColor].CGColor;
    self.overlayShape.lineWidth = 2.0;
    self.overlayShape.contentsScale = [UIScreen mainScreen].scale;
    [self.overlayView.layer addSublayer:self.overlayShape];
    
    UIWindow *win = [self currentKeyWindow];
    if (win) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [win addSubview:self.overlayView];
        });
    }
    
    self.timer = [NSTimer scheduledTimerWithTimeInterval:CAPTURE_INTERVAL target:self selector:@selector(captureAndAnalyze) userInfo:nil repeats:YES];
}

- (UIWindow *)currentKeyWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (scene.activationState == UISceneActivationStateForegroundActive && [scene isKindOfClass:[UIWindowScene class]]) {
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *w in windowScene.windows) {
                if (w.isKeyWindow) return w;
            }
            if (windowScene.windows.count) return windowScene.windows[0];
        }
    }
    id<UIApplicationDelegate> del = [UIApplication sharedApplication].delegate;
    if (del && [del respondsToSelector:@selector(window)]) {
        return [del window];
    }
    return nil;
}

- (void)captureAndAnalyze {
    if (self.isProcessing) return;
    self.isProcessing = YES;
    UIWindow *keyWindow = [self currentKeyWindow];
    if (!keyWindow) {
        self.isProcessing = NO;
        return;
    }
    CGSize targetSize = CGSizeMake(640, 640);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        @autoreleasepool {
            __block UIImage *screenshot = nil;
            dispatch_sync(dispatch_get_main_queue(), ^{
                UIGraphicsBeginImageContextWithOptions(targetSize, NO, 1.0);
                [keyWindow drawViewHierarchyInRect:CGRectMake(0, 0, targetSize.width, targetSize.height) afterScreenUpdates:NO];
                screenshot = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
            });
            if (!screenshot) {
                self.isProcessing = NO;
                return;
            }
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:screenshot.CGImage options:@{}];
            NSError *err = nil;
            [handler performRequests:@[self.vnRequest] error:&err];
        }
    });
}

- (void)drawDetections:(MLMultiArray *)output {
    if (!output) {
        self.overlayShape.path = nil;
        return;
    }
    const int stride = 6;
    long total = output.count / stride;
    if (total <= 0) {
        self.overlayShape.path = nil;
        return;
    }
    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat scaleX = screenSize.width / 640.0;
    CGFloat scaleY = screenSize.height / 640.0;
    UIBezierPath *combined = [UIBezierPath bezierPath];
    float bestConf = 0.0f;
    CGRect bestRect = CGRectZero;
    for (int i = 0; i < total; i++) {
        long base = i * stride;
        if (base + 4 >= output.count) break;
        float x = [output[base+0] floatValue];
        float y = [output[base+1] floatValue];
        float w = [output[base+2] floatValue];
        float h = [output[base+3] floatValue];
        float conf = [output[base+4] floatValue];
        if (conf < 0.5f) continue;
        CGRect rect640 = CGRectMake(x - w/2.0f, y - h/2.0f, w, h);
        CGRect rectScreen = CGRectMake(rect640.origin.x * scaleX, rect640.origin.y * scaleY, rect640.size.width * scaleX, rect640.size.height * scaleY);
        rectScreen = CGRectIntersection(rectScreen, CGRectMake(0, 0, screenSize.width, screenSize.height));
        if (CGRectIsEmpty(rectScreen)) continue;
        [combined appendPath:[UIBezierPath bezierPathWithRect:rectScreen]];
        if (conf > bestConf) {
            bestConf = conf;
            bestRect = rectScreen;
        }
    }
    self.overlayShape.path = combined.CGPath;
    if (bestConf > 0.7f) {
        CGPoint screenCenter = CGPointMake(screenSize.width/2.0, screenSize.height/2.0);
        CGPoint boxCenter = CGPointMake(CGRectGetMidX(bestRect), CGRectGetMidY(bestRect));
        CGFloat dx = screenCenter.x - boxCenter.x;
        CGFloat dy = screenCenter.y - boxCenter.y;
        if (fabs(dx) > 10 || fabs(dy) > 10) {
            CGPoint start = screenCenter;
            CGPoint end = CGPointMake(screenCenter.x + dx, screenCenter.y + dy);
            [self performFakeSwipeFrom:start to:end duration:0.05];
        }
    }
}

@end

__attribute__((constructor))
static void init_analyzer() {
    analyzer = [ScreenAnalyzer new];
}
