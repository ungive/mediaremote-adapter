// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_TARGET_H
#define MEDIAREMOTEADAPTER_ADAPTER_TARGET_H

// Directs the commands that follow at the application named by the
// --bundle-id option, if one was given. MediaRemote delivers commands to the
// application it elected as the now playing application, so this overrides
// that election until endTargetApplication() is called (or the process
// exits). Fails if the application does not become the elected one, in which
// case nothing should be sent.
void beginTargetApplication(void);

// Waits for the commands sent since beginTargetApplication() to be handled,
// then restores the system's own election. No-op without --bundle-id.
void endTargetApplication(void);

#endif // MEDIAREMOTEADAPTER_ADAPTER_TARGET_H
