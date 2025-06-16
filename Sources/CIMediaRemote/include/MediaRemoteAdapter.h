//
//  MediaRemoteAdapter.h
//
//  Copyright © 2024 Ethan Bills. All rights reserved.
//

#ifndef MediaRemoteAdapter_h
#define MediaRemoteAdapter_h

#import <Foundation/Foundation.h>

#ifdef __cplusplus
extern "C" {
#endif

void bootstrap(void);
void loop(void);
void play(void);
void pause_command(void);
void toggle_play_pause(void);
void next_track(void);
void previous_track(void);
void stop_command(void);
void set_time_from_env(void);

#ifdef __cplusplus
}
#endif

#endif /* MediaRemoteAdapter_h */ 