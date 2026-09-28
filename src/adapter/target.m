// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#import "adapter/target.h"

#include <signal.h>
#include <stdlib.h>
#include <unistd.h>

#import <Foundation/Foundation.h>

#import "adapter/env.h"
#import "adapter/globals.h"
#import "adapter/now_playing.h"
#import "utility/helpers.h"

// How long to wait for the daemon to elect the target application.
#define ELECTION_TIMEOUT_MILLIS 1000
#define ELECTION_POLL_MILLIS 50
#define ELECTED_QUERY_TIMEOUT_MILLIS 2000

static volatile sig_atomic_t g_overrideActive = 0;

// The override is stored by the daemon and outlives this process, so it has to
// be cleared on every way out: the normal path, failf() (which exits) and
// termination signals.
static void clearOverride(void) {
    if (!g_overrideActive) {
        return;
    }
    g_overrideActive = 0;
    // Both setters skip a value equal to the one this process last set.
    // This process set the application and enabled the override, so these
    // calls do reach the daemon.
    g_mediaRemote.setOverriddenNowPlayingApplication(nil);
    g_mediaRemote.setNowPlayingApplicationOverrideEnabled(false);
    // Round trip, so the requests are delivered before the process exits.
    waitForCommandCompletion();
}

// Not async-signal-safe, but a stuck override breaks now playing for the
// whole system (Control Center, media keys) until something clears it, which
// is worse than the small risk of doing this work in a handler.
static void handleSignal(int sig) {
    clearOverride();
    signal(sig, SIG_DFL);
    raise(sig);
}

static bool clientMatches(MRClient *client, NSString *bundleIdentifier) {
    if (client == nil) {
        return false;
    }
    return [[client bundleIdentifier] isEqualToString:bundleIdentifier] ||
           [[client parentApplicationBundleIdentifier]
               isEqualToString:bundleIdentifier];
}

static bool isElected(NSString *bundleIdentifier) {
    __block bool elected = false;
    id semaphore = dispatch_semaphore_create(0);
    g_mediaRemote.getNowPlayingClient(g_serialdispatchQueue, ^(id client) {
      elected = clientMatches(client, bundleIdentifier);
      dispatch_semaphore_signal(semaphore);
    });
    dispatch_semaphore_wait(
        semaphore,
        dispatch_time(DISPATCH_TIME_NOW, ELECTED_QUERY_TIMEOUT_MILLIS * NSEC_PER_MSEC));
    return elected;
}

void beginTargetApplication(void) {
    NSString *bundleIdentifier = getEnvOption(@"bundle_id");
    if (bundleIdentifier == nil) {
        return;
    }
    if ([bundleIdentifier length] == 0) {
        fail(@"Missing value for option 'bundle-id'");
    }
    if (g_mediaRemote.setOverriddenNowPlayingApplication == NULL ||
        g_mediaRemote.setNowPlayingApplicationOverrideEnabled == NULL) {
        fail(@"Targeting an application is not supported on this system");
    }

    atexit(clearOverride);
    signal(SIGINT, handleSignal);
    signal(SIGTERM, handleSignal);
    signal(SIGHUP, handleSignal);

    // Enabled first: setting the application while the override is disabled
    // leaves the daemon without an elected application until it is enabled.
    g_overrideActive = 1;
    g_mediaRemote.setNowPlayingApplicationOverrideEnabled(true);
    g_mediaRemote.setOverriddenNowPlayingApplication(bundleIdentifier);

    // The election is asynchronous. A command sent before it lands would
    // reach the previously elected application.
    int attempts = ELECTION_TIMEOUT_MILLIS / ELECTION_POLL_MILLIS;
    for (int i = 0; i < attempts; i++) {
        if (isElected(bundleIdentifier)) {
            return;
        }
        usleep(ELECTION_POLL_MILLIS * 1000);
    }
    failf(@"Application is not registered with MediaRemote: %@",
          bundleIdentifier);
}

void endTargetApplication(void) {
    if (!g_overrideActive) {
        return;
    }
    // The daemon resolves a command's destination when it handles it, which
    // can be after the command function returned. Clearing the override
    // before that would send the command to the system's own election.
    usleep(250 * 1000);
    clearOverride();
}
