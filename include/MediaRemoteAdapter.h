// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_H
#define MEDIAREMOTEADAPTER_ADAPTER_H

#import <Foundation/Foundation.h>

// Methods suffixed with "_env" read its parameters from the environment.
// Parameters must have the format:
// MEDIAREMOTEADAPTER_<FUNC_NAME>_<PARAM_INDEX>_<PARAM_NAME>
// Example: MEDIAREMOTEADAPTER_adapter_send_0_command

// Prints the current MediaRemote now playing information to stdout.
// Data is encoded as a JSON dictionary or "null" when there is no information.
extern void adapter_get();

// Streams MediaRemote now playing updates to stdout.
// Each update is printed on a separate lined, encoded as a JSON dictionary.
// Exits when the process receives a SIGTERM signal.
extern void adapter_stream();
extern void adapter_stream_env();

extern void adapter_send(int command);
extern void adapter_send_env();

extern NSString *kBundleIdentifier;
extern NSString *kPlaying;
extern NSString *kTitle;
extern NSString *kArtist;
extern NSString *kAlbum;
extern NSString *kDurationMicros;
extern NSString *kElapsedTimeMicros;
extern NSString *kTimestampEpochMicros;
extern NSString *kArtworkMimeType;
extern NSString *kArtworkDataBase64;

// PRIVATE API

// Stops any active calls to stream().
extern void _adapter_stream_cancel();

// Tests whether the process is entitled to use the MediaRemote framework.
// Prints "1" to stdout when it is entitled and "0" otherwise.
// NOTE This does not work reliably yet.
extern void _adapter_test();

#endif // MEDIAREMOTEADAPTER_ADAPTER_H
