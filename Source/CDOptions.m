// CDOptions.m
// cocoadialog
//
// Copyright (c) 2004-2017 Mark A. Stratman <mark@sporkstorms.org>, Mark Carver <mark.carver@me.com>.
// All rights reserved.
// Licensed under GPL-2.

#import "CDOptions.h"

#import "NSString+CDString.h"

@implementation CDOptions

@synthesize requiredOptions;

- (instancetype)init {
  self = [super init];
  if (self) {
    _arguments = @[].mutableCopy;
    _deprecatedOptions = @{}.mutableCopy;
    _options = @{}.mutableCopy;
    _missingArgumentBreaks = @[].mutableCopy;
    _terminal = [CDTerminal sharedInstance];
    requiredOptions = @{}.mutableCopy;
    _seenOptions = @[].mutableCopy;
    _unknownOptions = @[].mutableCopy;
  }
  return self;
}

- (NSArray<NSString *> *)allKeys {
  return _options.allKeys;
}

- (NSArray<CDOption *> *)allValues {
  return _options.allValues;
}

- (NSDictionary <NSString *, CDOptions *> *)groupByScope {
  NSMutableDictionary<NSString *, CDOptions *> *scopes = [NSMutableDictionary dictionary];
  for (NSString *name in _options) {
    CDOption *opt = _options[name];

    // Skip hidden options.
    if (opt.hidden) {
      continue;
    }

    NSString *scope = opt.scope != nil ? opt.scope : @"USAGE_CATEGORY_CONTROLS".localized;
    if (scopes[scope] == nil) {
      scopes[scope] = [CDOptions options];
    }

    scopes[scope][opt.name] = opt;
  }
  return scopes;
}

- (NSMutableDictionary<NSString *, CDOption *> *)requiredOptions {
  NSMutableDictionary *required = [NSMutableDictionary dictionaryWithDictionary:requiredOptions];
  for (NSString *name in _options) {
    if (_options[name].required) {
      required[name] = _options[name];
    }
  }
  return required;
}

+ (BOOL)argIsKey:(NSString *)arg inOptions:(NSDictionary *)options {
  return [self isOption:arg] && options[[arg substringFromIndex:2]] != nil;
}

+ (BOOL)isOption:(NSString *)arg {
  return arg && arg.length >= 2 && [[arg substringWithRange:NSMakeRange(0, 2)] isEqualToString:@"--"];
}

+ (NSString *)optionNameFromArgument:(NSString *)arg {
  return [self isOption:arg] ? [arg substringFromIndex:2] : nil;
}

+ (instancetype)options {
  return [[self alloc] init];
}

+ (instancetype)sharedInstance {
  static CDOptions *sharedInstance;
  static dispatch_once_t onceToken;
  dispatch_once(&onceToken, ^{
    sharedInstance = [[CDOptions alloc] init];
  });
  return sharedInstance;
}

- (NSUInteger)count {
  return _options.count;
}

- (NSString *)getArgument:(unsigned int)index {
  return self.arguments != nil && index < self.arguments.count ? self.arguments[index] : nil;
}

- (instancetype)initWithObjects:(id _Nonnull const[])objects forKeys:(id <NSCopying> _Nonnull const[])keys count:(NSUInteger)cnt {
  self = [super init];
  if (self) {
    _options = [[NSMutableDictionary alloc] initWithObjects:objects forKeys:keys count:cnt];
  }
  return self;
}

- (NSEnumerator *)keyEnumerator {
  return _options.keyEnumerator;
}

- (void)remove:(NSString *)name {
  [_options removeObjectForKey:name];
}

- (NSUInteger)countByEnumeratingWithState:(NSFastEnumerationState *)state objects:(id __unsafe_unretained[])stackbuf count:(NSUInteger)len {
  return [_options countByEnumeratingWithState:state objects:stackbuf count:len];
}

- (CDOption *)objectForKey:(NSString *)key {
  CDOption *opt = _options[key];
  if (opt) {
    if (self.getOptionOnceCallback && ![self.seenOptions containsObject:key]) {
      [self.seenOptions addObject:key];
      self.getOptionOnceCallback(opt);
    }
    if (self.getOptionCallback) {
      self.getOptionCallback(opt);
    }
  }
  return opt;
}

- (CDOption *)objectForKeyedSubscript:(NSString *)key {
  return [self objectForKey:key];
}

- (void)setObject:(CDOption *)opt forKey:(NSString *)key {
  if (self.setOptionCallback != nil) {
    self.setOptionCallback(opt, key);
  }

  // Add "double dash" note for multiple option values.
  if (opt.minimumValues.unsignedIntegerValue >= 1 && opt.maximumValues.unsignedIntegerValue == 0) {
    NSString *doubleDash = @"OPTION_MULTIPLE_DOUBLE_DASH".localized;
    if (![opt.notes containsObject:doubleDash]) {
      [opt.notes addObject:doubleDash];
    }
  }

  // Handle deprecated options.
  if (opt.deprecatedTo != nil) {
    opt.hidden = YES;
    self.deprecatedOptions[opt.name] = opt;
  }
  else {
    _options[opt.name] = opt;
  }

  // Add any deprecated options this option contains.
  for (CDOption *depOpt in opt.deprecatedOptions) {
    depOpt.deprecatedTo = opt.name;
    self[depOpt.name] = depOpt;
  }
}

- (void)setObject:(CDOption *)opt forKeyedSubscript:(NSString *)key {
  [self setObject:opt forKey:key];
}

- (CDOptions *(^)(NSArray <CDOption *> *))addOptions {
  return ^CDOptions *(NSArray <CDOption *> *opts) {
    for (CDOption *option in opts) {
      self[option.name] = option;
    }
    return self;
  };
}

- (CDOptions *(^)(NSString *, NSArray <CDOption *> *))addOptionsToScope {
  return ^CDOptions *(NSString *scope, NSArray <CDOption *> *opts) {
    for (CDOption *option in opts) {
      self[option.name] = option.setScope(scope);
    }
    return self;
  };
}

- (CDOptions *(^)(NSArray *))processArguments {
  return ^CDOptions *(NSArray *arguments) {
    NSMutableArray *args = arguments.mutableCopy;
    NSUInteger count = args.count;

    // Parse provided arguments.
    NSString *arg;
    BOOL unknownOption = NO;
    for (NSUInteger i = 0; i < count; i++) {
      arg = args[i];

      NSString *optionName = [CDOptions optionNameFromArgument:arg];

      // Capture normal arguments.
      if (!optionName) {
        if (!unknownOption) {
          [self.arguments addObject:arg];
        }
        continue;
      }
        // Skip standalone double dash argument breaks.
      else if ([optionName isBlank]) {
        continue;
      }

      CDOption *option;

      // Handle deprecated options.
      CDOption *deprecated = self.deprecatedOptions[optionName];
      if (deprecated) {
        deprecated.wasProvided = YES;
        option = deprecated;
      }
      else {
        option = _options[optionName];
      }

      // If provided option isn't actually an available option,
      // add it to the list of unknown options and skip.
      if (!option) {
        [self.unknownOptions addObject:optionName];
        unknownOption = YES;
        continue;
      }

      unknownOption = NO;

      // Flag that the option was provided.
      option.wasProvided = YES;

      // Retrieve the minimum and maximum values allowed for this option.
      NSInteger max = option.maximumValues.integerValue;
      NSInteger min = option.minimumValues.integerValue;

      // Create an array to store values (in case option allows more than one).
      NSMutableArray<NSString *> *values = [NSMutableArray array];

      // Increase index to next argument.
      i++;

      // Determine how many values should be extracted.
      BOOL argumentBreak = NO;
      BOOL possibleOptionsDetected = NO;
      NSUInteger stop = max == 0 ? count : i + max;

      // Make sure we don't go past the argument count.
      if (stop > count) {
        stop = count;
      }

      // Extract value(s).
      for (; i < stop; i++) {
        // Detect argument breaks.
        argumentBreak = [args[i] isEqualToString:@"--"];

        // Detect possible options.
        if (!argumentBreak && [CDOptions isOption:args[i]]) {
          possibleOptionsDetected = YES;
        }

        // Stop if there are no more arguments, if it's a double dash argument break, or if option has no min.
        if (i >= count || !args[i] || argumentBreak || (possibleOptionsDetected && min == 0 && max == 1 && !values.count)) {
          break;
        }
        [values addObject:args[i]];
      }

      // Keep track of multiple arguments that didn't specify argument breaks.
      if ((max == 0) && possibleOptionsDetected && !argumentBreak) {
        [self.missingArgumentBreaks addObject:optionName];
      }

      // Decrease index since it's exiting the values loop and about
      // to get increased again at the start of the next argument loop.
      i--;

      // Determine if parent option was not provided and override this option.
      if (option.parentOption != nil && _options[option.parentOption.name] != nil && !_options[option.parentOption.name].wasProvided) {
        option.wasProvided = NO;
        option.values = @[].mutableCopy;
      }
        // Set the provided values on the option.
      else {
        option.values = values.mutableCopy;
      }
    }

    // Process deprecated options.
    for (NSString *name in self.deprecatedOptions) {
      CDOption *from = self.deprecatedOptions[name];
      CDOption *to = _options[from.deprecatedTo];

      // Skip deprecated options that weren't provided or real options that don't exist.
      if (!from.wasProvided || !to) {
        continue;
      }

      // Indicate that the replacement option was provided.
      to.wasProvided = YES;

      if (from.deprecatedValueIndex) {
        [to setValue:from.stringValue atIndex:from.deprecatedValueIndex.unsignedIntegerValue];
      }
      else {
        to.values = from.arrayValue.mutableCopy;
      }
    }

    return self;
  };
}

- (CDOptions *(^)(CDControl *))processWithControl {
  return ^CDOptions *(CDControl *control) {
    if (self.processedWithControl) {
      return self;
    }

    for (NSString *name in _options) {
      if (_options[name].processBlocks.count) {
        for (CDOptionProcessBlock block in _options[name].processBlocks) {
          block(control);
        }
      }
    }

    _processedWithControl = YES;

    return self;
  };
}


@end
