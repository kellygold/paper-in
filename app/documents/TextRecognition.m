#import "TextRecognition.h"
#import <Vision/Vision.h>

@implementation PIRecognizedLine
- (instancetype)initWithText:(NSString *)text box:(CGRect)box {
    if ((self = [super init])) { _text = [text copy]; _box = box; }
    return self;
}
@end

NSArray<PIRecognizedLine *> *PIRecognizeText(CGImageRef image, NSError **error) {
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    if (![handler performRequests:@[request] error:error]) { return nil; }
    NSMutableArray<PIRecognizedLine *> *lines = [NSMutableArray array];
    for (VNRecognizedTextObservation *observation in request.results) {
        NSString *text = [observation topCandidates:1].firstObject.string;
        if (text.length) {
            [lines addObject:[[PIRecognizedLine alloc] initWithText:text box:observation.boundingBox]];
        }
    }
    return lines;
}
