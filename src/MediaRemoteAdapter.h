#ifndef MediaRemoteAdapter_h
#define MediaRemoteAdapter_h

#ifdef __cplusplus
extern "C" {
#endif

/// Starts the media monitoring loop on a background thread.
/// This function will return immediately.
void loop(void);

/// Stops the media monitoring loop.
void stop_media_remote_loop(void);

/// Registers a C callback function to receive now-playing data.
/// The callback will be invoked with a UTF-8 encoded JSON string.
///
/// @param callback A function pointer to handle the data.
void register_media_data_callback(void (*callback)(const char* json_string));

#ifdef __cplusplus
}
#endif

#endif /* MediaRemoteAdapter_h */ 