#ifndef MediaRemoteAdapter_h
#define MediaRemoteAdapter_h

#import "MediaRemote.h"
#import "MediaRemoteAdapterKeys.h"

// The C functions that are exposed to the caller.
extern void loop(void);
extern void stop(void);
extern void test(void);

// Playback Commands
extern void play(void);
extern void pause_command(void);
extern void toggle_play_pause(void);
extern void next_track(void);
extern void previous_track(void);
extern void stop_command(void);
extern void set_time_from_env(void);

#endif /* MediaRemoteAdapter_h */ 