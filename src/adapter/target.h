// Copyright (c) 2025 Jonas van den Berg
// This file is licensed under the BSD 3-Clause License.

#ifndef MEDIAREMOTEADAPTER_ADAPTER_TARGET_H
#define MEDIAREMOTEADAPTER_ADAPTER_TARGET_H

// Reject --bundle-id before sending anything. A targeted command must never
// fall back to the elected application or change the system-wide election.
void beginTargetApplication(void);

#endif
