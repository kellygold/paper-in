#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// Thin Objective-C boundary avoids Swift/Vision SDK module incompatibilities.
@interface PIRecognizedLine : NSObject
@property(nonatomic, readonly) NSString *text;
@property(nonatomic, readonly) CGRect box;
@end

NSArray<PIRecognizedLine *> * _Nullable PIRecognizeText(CGImageRef image, NSError **error);

NS_ASSUME_NONNULL_END
