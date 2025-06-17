// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import "env.h"

#include <limits.h>

#import <Foundation/Foundation.h>

#import "utility/helpers.h"

static NSNumber *parseIntegerOrNil(NSString *str) {
    if (str == nil)
        return nil;
    NSScanner *scanner = [NSScanner scannerWithString:str];
    NSInteger value;
    if ([scanner scanInteger:&value] && [scanner isAtEnd]) {
        return @(value);
    } else {
        return nil;
    }
}

NSString *getEnvFuncParam(NSString *func_name, int param_pos,
                          NSString *param_name) {
    NSString *envVarName =
        [NSString stringWithFormat:@"MEDIAREMOTEADAPTER_%@_%d_%@", func_name,
                                   param_pos, param_name];
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    NSString *value = env[envVarName];
    return value;
}

NSString *getEnvFuncParamSafe(NSString *func_name, int param_pos,
                              NSString *param_name) {
    NSString *result = getEnvFuncParam(func_name, param_pos, param_name);
    if (result == nil) {
        failf(@"Missing parameter '%@' for "
              @"function '%@' at position '%d'",
              param_name, func_name, param_pos);
    }
    return result;
}

NSNumber *getEnvFuncParamInt(NSString *func_name, int param_pos,
                             NSString *param_name) {
    return parseIntegerOrNil(getEnvFuncParam(func_name, param_pos, param_name));
}

int getEnvFuncParamIntSafe(NSString *func_name, int param_pos,
                           NSString *param_name) {

    NSString *raw = getEnvFuncParam(func_name, param_pos, param_name);
    if (raw == nil) {
        failf(@"Missing parameter '%@' for "
              @"function '%@' at position '%d'",
              param_name, func_name, param_pos);
    }
    NSNumber *result = parseIntegerOrNil(raw);
    if (result == nil) {
        failf(@"Parameter '%@' for "
              @"function '%@' at position '%d' is not an integer: '%@'",
              param_name, func_name, param_pos, raw);
    }
    if ([raw length] > [[NSString stringWithFormat:@"%d", INT_MAX] length]) {
        failf(@"Parameter '%@' for "
              @"function '%@' at position '%d' is too large to fit into an "
              @"integer: %@",
              param_name, func_name, param_pos, raw);
    }
    return [result intValue];
}
