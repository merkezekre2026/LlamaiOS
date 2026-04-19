#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef BOOL (^LLMLlamaTokenCallback)(NSString *token, NSInteger tokenCount, double tokensPerSecond);

@interface LLMLlamaGenerationParameters : NSObject
@property(nonatomic) double temperature;
@property(nonatomic) double topP;
@property(nonatomic) NSInteger topK;
@property(nonatomic) double repeatPenalty;
@property(nonatomic) NSInteger maxNewTokens;
@property(nonatomic) NSInteger seed;
@property(nonatomic) NSInteger threads;
@end

@interface LLMLlamaGenerationStats : NSObject
@property(nonatomic) NSInteger tokenCount;
@property(nonatomic) double elapsedSeconds;
@property(nonatomic) double tokensPerSecond;
@end

@interface LlamaCppBridge : NSObject
@property(nonatomic, readonly) BOOL isModelLoaded;
- (NSDictionary<NSString *, NSString *> *)readMetadataAtPath:(NSString *)path error:(NSError **)error;
- (BOOL)loadModelAtPath:(NSString *)path
          contextLength:(NSInteger)contextLength
              gpuLayers:(NSInteger)gpuLayers
                threads:(NSInteger)threads
                  error:(NSError **)error;
- (void)unloadModel;
- (void)cancelGeneration;
- (LLMLlamaGenerationStats *)generateWithPrompt:(NSString *)prompt
                                     parameters:(LLMLlamaGenerationParameters *)parameters
                                        onToken:(LLMLlamaTokenCallback)onToken
                                          error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
