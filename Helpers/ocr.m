#import <Foundation/Foundation.h>
#import <PDFKit/PDFKit.h>
#import <Vision/Vision.h>

// Local-only OCR. stdout is a single JSON document; no document contents in logs.
int main(int argc, const char *argv[]) { @autoreleasepool {
    if (argc != 2) { fprintf(stderr, "Expected a PDF path\n"); return 2; }
    PDFDocument *pdf = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:@(argv[1])]];
    if (!pdf || pdf.isLocked || pdf.pageCount == 0) { fprintf(stderr, "PDF is unreadable or locked\n"); return 2; }
    NSMutableArray *pages = [NSMutableArray array];
    for (NSUInteger i=0; i<pdf.pageCount; i++) { @autoreleasepool {
        PDFPage *page = [pdf pageAtIndex:i];
        NSString *text = page.string;
        double confidence = 1;
        if (text.length < 20) {
            CGRect bounds = [page boundsForBox:kPDFDisplayBoxMediaBox];
            double scale = MIN(3.0, 2600.0 / MAX(bounds.size.width, bounds.size.height));
            NSImage *thumb = [page thumbnailOfSize:NSMakeSize(bounds.size.width*scale, bounds.size.height*scale) forBox:kPDFDisplayBoxMediaBox];
            CGImageRef image = [thumb CGImageForProposedRect:NULL context:nil hints:nil];
            if (!image) { fprintf(stderr, "Could not render page\n"); return 3; }
            VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
            request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
            request.usesLanguageCorrection = YES;
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
            NSError *error = nil;
            if (![handler performRequests:@[request] error:&error]) { fprintf(stderr, "Local OCR failed\n"); return 3; }
            NSMutableArray *lines = [NSMutableArray array]; double sum = 0;
            for (VNRecognizedTextObservation *observation in request.results) {
                VNRecognizedText *best = [observation topCandidates:1].firstObject;
                if (best) { [lines addObject:best.string]; sum += best.confidence; }
            }
            text = [lines componentsJoinedByString:@"\n"];
            confidence = lines.count ? sum / lines.count : 0;
        }
        [pages addObject:@{@"page":@(i+1), @"text":text ?: @"", @"confidence":@(confidence)}];
    }}
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"pageCount":@(pdf.pageCount),@"pages":pages} options:0 error:nil];
    fwrite(data.bytes, 1, data.length, stdout); return 0;
}}
