#ifndef MediaRemoteAdapter_h
#define MediaRemoteAdapter_h

// The C functions that are exposed to the caller.
extern void loop(void);
extern void stop(void);
extern void test(void);

// Playback Commands
extern void send_command(int command);
extern void set_time(double seconds);

#endif /* MediaRemoteAdapter_h */ 