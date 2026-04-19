#import "LlamaCppBridge.h"

#import <Foundation/Foundation.h>
#import <atomic>
#import <chrono>
#import <mutex>
#import <string>
#import <vector>

#if __has_include(<llama/llama.h>)
#import <llama/llama.h>
#elif __has_include(<llama.h>)
#import <llama.h>
#else
#error "Missing llama.cpp headers. Add the official llama.xcframework to Vendor/llama.xcframework."
#endif

static NSString * const LlamaCppBridgeErrorDomain = @"LlamaiOS.LlamaCppBridge";

typedef NS_ENUM(NSInteger, LlamaCppBridgeErrorCode) {
    LlamaCppBridgeErrorBackendUnavailable = 1,
    LlamaCppBridgeErrorModelLoadFailed = 2,
    LlamaCppBridgeErrorContextCreateFailed = 3,
    LlamaCppBridgeErrorTokenizeFailed = 4,
    LlamaCppBridgeErrorDecodeFailed = 5,
    LlamaCppBridgeErrorCancelled = 6,
    LlamaCppBridgeErrorInvalidModel = 7
};

static NSError *BridgeError(LlamaCppBridgeErrorCode code, NSString *message) {
    return [NSError errorWithDomain:LlamaCppBridgeErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation LLMLlamaGenerationParameters
- (instancetype)init {
    self = [super init];
    if (self) {
        _temperature = 0.7;
        _topP = 0.9;
        _topK = 40;
        _repeatPenalty = 1.1;
        _maxNewTokens = 512;
        _seed = -1;
        _threads = 4;
    }
    return self;
}
@end

@implementation LLMLlamaGenerationStats
@end

@interface LlamaCppBridge () {
    llama_model *_model;
    llama_context *_context;
    std::atomic_bool _cancelled;
    std::mutex _lock;
}
@end

@implementation LlamaCppBridge

- (instancetype)init {
    self = [super init];
    if (self) {
        _model = nullptr;
        _context = nullptr;
        _cancelled.store(false);
        llama_backend_init();
    }
    return self;
}

- (void)dealloc {
    [self unloadModel];
    llama_backend_free();
}

- (BOOL)isModelLoaded {
    std::lock_guard<std::mutex> guard(_lock);
    return _model != nullptr && _context != nullptr;
}

- (NSDictionary<NSString *, NSString *> *)readMetadataAtPath:(NSString *)path error:(NSError **)error {
    if (path.length == 0 || ![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
        if (error) {
            *error = BridgeError(LlamaCppBridgeErrorInvalidModel, @"The model file is not readable.");
        }
        return @{};
    }

    llama_model_params params = llama_model_default_params();
    params.n_gpu_layers = 0;
    params.no_alloc = true;
    llama_model *model = llama_model_load_from_file(path.UTF8String, params);
    if (!model) {
        if (error) {
            *error = BridgeError(LlamaCppBridgeErrorInvalidModel, @"llama.cpp could not open this GGUF model.");
        }
        return @{};
    }

    NSMutableDictionary<NSString *, NSString *> *metadata = [NSMutableDictionary dictionary];
    const int count = llama_model_meta_count(model);
    for (int i = 0; i < count; i++) {
        char key[256];
        char value[4096];
        const int keySize = llama_model_meta_key_by_index(model, i, key, sizeof(key));
        const int valueSize = llama_model_meta_val_str_by_index(model, i, value, sizeof(value));
        if (keySize > 0 && valueSize > 0) {
            metadata[[NSString stringWithUTF8String:key]] = [NSString stringWithUTF8String:value];
        }
    }

    llama_model_free(model);
    return metadata;
}

- (BOOL)loadModelAtPath:(NSString *)path
          contextLength:(NSInteger)contextLength
              gpuLayers:(NSInteger)gpuLayers
                threads:(NSInteger)threads
                  error:(NSError **)error {
    std::lock_guard<std::mutex> guard(_lock);
    [self unloadModelLocked];

    if (path.length == 0 || ![[NSFileManager defaultManager] isReadableFileAtPath:path]) {
        if (error) {
            *error = BridgeError(LlamaCppBridgeErrorInvalidModel, @"The selected model file is not readable.");
        }
        return NO;
    }

    llama_model_params modelParams = llama_model_default_params();
    modelParams.n_gpu_layers = (int)gpuLayers;

    _model = llama_model_load_from_file(path.UTF8String, modelParams);
    if (!_model) {
        if (error) {
            *error = BridgeError(LlamaCppBridgeErrorModelLoadFailed, @"llama.cpp failed to load the model. The file may be unsupported or too large for this device.");
        }
        return NO;
    }

    llama_context_params contextParams = llama_context_default_params();
    contextParams.n_ctx = (uint32_t)contextLength;
    contextParams.n_threads = (int)threads;
    contextParams.n_threads_batch = (int)threads;

    _context = llama_init_from_model(_model, contextParams);
    if (!_context) {
        llama_model_free(_model);
        _model = nullptr;
        if (error) {
            *error = BridgeError(LlamaCppBridgeErrorContextCreateFailed, @"llama.cpp could not create a context. Try a smaller model or context length.");
        }
        return NO;
    }

    return YES;
}

- (void)unloadModel {
    std::lock_guard<std::mutex> guard(_lock);
    [self unloadModelLocked];
}

- (void)unloadModelLocked {
    if (_context) {
        llama_free(_context);
        _context = nullptr;
    }
    if (_model) {
        llama_model_free(_model);
        _model = nullptr;
    }
}

- (void)cancelGeneration {
    _cancelled.store(true);
}

- (LLMLlamaGenerationStats *)generateWithPrompt:(NSString *)prompt
                                     parameters:(LLMLlamaGenerationParameters *)parameters
                                        onToken:(LLMLlamaTokenCallback)onToken
                                          error:(NSError **)error {
    std::unique_lock<std::mutex> guard(_lock);
    if (!_model || !_context) {
        if (error) {
            *error = BridgeError(LlamaCppBridgeErrorBackendUnavailable, @"No model is loaded.");
        }
        return nil;
    }

    _cancelled.store(false);
    llama_set_n_threads(_context, (int)parameters.threads, (int)parameters.threads);

    std::string promptString(prompt.UTF8String ?: "");
    const llama_vocab *vocab = llama_model_get_vocab(_model);
    const int tokenCapacity = (int)promptString.size() + 8;
    std::vector<llama_token> promptTokens(tokenCapacity);
    int promptTokenCount = llama_tokenize(vocab, promptString.c_str(), (int)promptString.size(), promptTokens.data(), tokenCapacity, true, true);
    if (promptTokenCount < 0) {
        promptTokens.resize((size_t)-promptTokenCount);
        promptTokenCount = llama_tokenize(vocab, promptString.c_str(), (int)promptString.size(), promptTokens.data(), (int)promptTokens.size(), true, true);
    }
    if (promptTokenCount < 0) {
        if (error) {
            *error = BridgeError(LlamaCppBridgeErrorTokenizeFailed, @"The prompt was too large to tokenize.");
        }
        return nil;
    }
    promptTokens.resize(promptTokenCount);

    llama_memory_clear(llama_get_memory(_context), true);

    llama_batch batch = llama_batch_get_one(promptTokens.data(), (int32_t)promptTokens.size());
    if (llama_decode(_context, batch) != 0) {
        if (error) {
            *error = BridgeError(LlamaCppBridgeErrorDecodeFailed, @"llama.cpp failed while processing the prompt.");
        }
        return nil;
    }

    llama_sampler_chain_params samplerParams = llama_sampler_chain_default_params();
    llama_sampler *sampler = llama_sampler_chain_init(samplerParams);
    llama_sampler_chain_add(sampler, llama_sampler_init_penalties(64, (float)parameters.repeatPenalty, 0.0f, 0.0f));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k((int32_t)parameters.topK));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p((float)parameters.topP, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp((float)parameters.temperature));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(parameters.seed < 0 ? LLAMA_DEFAULT_SEED : (uint32_t)parameters.seed));

    NSInteger generated = 0;
    auto start = std::chrono::steady_clock::now();

    for (NSInteger i = 0; i < parameters.maxNewTokens; i++) {
        if (_cancelled.load()) {
            llama_sampler_free(sampler);
            if (error) {
                *error = BridgeError(LlamaCppBridgeErrorCancelled, @"Generation was stopped.");
            }
            return nil;
        }

        llama_token token = llama_sampler_sample(sampler, _context, -1);
        llama_sampler_accept(sampler, token);

        if (llama_vocab_is_eog(vocab, token)) {
            break;
        }

        char piece[256];
        int pieceLength = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, true);
        if (pieceLength < 0) {
            pieceLength = 0;
        }
        NSString *tokenString = [[NSString alloc] initWithBytes:piece length:(NSUInteger)pieceLength encoding:NSUTF8StringEncoding] ?: @"";

        generated += 1;
        auto now = std::chrono::steady_clock::now();
        double elapsed = std::chrono::duration<double>(now - start).count();
        double tokensPerSecond = elapsed > 0 ? (double)generated / elapsed : 0;

        guard.unlock();
        BOOL shouldContinue = onToken(tokenString, generated, tokensPerSecond);
        guard.lock();
        if (!shouldContinue) {
            llama_sampler_free(sampler);
            if (error) {
                *error = BridgeError(LlamaCppBridgeErrorCancelled, @"Generation was stopped.");
            }
            return nil;
        }

        llama_token next = token;
        llama_batch nextBatch = llama_batch_get_one(&next, 1);
        if (llama_decode(_context, nextBatch) != 0) {
            llama_sampler_free(sampler);
            if (error) {
                *error = BridgeError(LlamaCppBridgeErrorDecodeFailed, @"llama.cpp failed while generating a token.");
            }
            return nil;
        }
    }

    llama_sampler_free(sampler);
    auto end = std::chrono::steady_clock::now();
    double elapsed = std::chrono::duration<double>(end - start).count();

    LLMLlamaGenerationStats *stats = [[LLMLlamaGenerationStats alloc] init];
    stats.tokenCount = generated;
    stats.elapsedSeconds = elapsed;
    stats.tokensPerSecond = elapsed > 0 ? (double)generated / elapsed : 0;
    return stats;
}

@end
