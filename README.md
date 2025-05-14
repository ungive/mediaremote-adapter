# mediaremote-osascript

Get now playing information with the MediaRemote framework
on macOS 15.4 and newer.

This works by using the `/usr/bin/osascript` binary,
which is entitled to use the MediaRemote framework,
and dynamically loading a custom helper framework
which prints real-time updates to stdout.
How to make use of this project:

```
$ git clone https://github.com/ungive/mediaremote-osascript.git
$ cd mediaremote-osascript
$ mkdir build && cd build
$ cmake ..
$ cmake --build .
$ cd ..
$ FRAMEWORK_PATH=$(realpath ./build/MediaRemoteAdapter.framework)
$ /usr/bin/osascript -l JavaScript ./scripts/MediaRemoteAdapter.js "$FRAMEWORK_PATH"
```

The output of this command is characterised by the following rules:

- The script runs indefinitely until the process is terminated with a signal
- Each line printed to stdout contains a single JSON dictionary with the following keys:
    - type (string): Always "data". There are no other types at the moment
    - diff (boolean): Whether to update the previous non-diff payload. When this value is true, only the keys for updated values are set in the payload. Other keys should retain the value of the data payloads before this one
    - payload (dictionary): The now playing metadata. The keys should be self-explanatory. For details check the convertNowPlayingInformation function in [src/MediaRemoteAdapter.m](./src/MediaRemoteAdapter.m). All available keys are always set to either a value or null when diff is false. There are no missing keys when diff is true. For a list of all keys check [src/MediaRemoteAdapterKeys.m](./src/MediaRemoteAdapterKeys.m)
- The script exits with an exit code other than 0 when a fatal error occured, e.g. when the MediaRemote framework could not be loaded. This may be used to stop any retries of executing this command again
- The script terminates gracefully when a SIGTERM signal is sent to the process. This signal should be used to cancel the observation of changes to now playing items
- You must always pass the full path of the adapter framework to the script as the first argument
- Each line printed to stderr is an error message

Here is an example of what the output may look like:

```
{"type":"data","diff":false,"payload":{"artist":"Sara Rikas","timestampEpochMicros":1747256447190675,"title":"Cigarety","bundleIdentifier":"com.tidal.desktop","elapsedTimeMicros":0,"playing":false,"album":"Ja, Sára","artworkMimeType":"image\/jpeg","durationMicros":281346077,"artworkDataBase64":null}}
{"type":"data","diff":true,"payload":{"artworkDataBase64":"\/9j\/4AAQSkZJRgABAQAAS..."}}
{"type":"data","diff":true,"payload":{"timestampEpochMicros":1747260249656367,"elapsedTimeMicros":75372614}}
{"type":"data","diff":true,"payload":{"timestampEpochMicros":1747260311282554,"elapsedTimeMicros":0,"durationMicros":281000000}}
{"type":"data","diff":true,"payload":{"timestampEpochMicros":1747260312118660,"playing":true,"durationMicros":281346077}}
{"type":"data","diff":true,"payload":{"timestampEpochMicros":1747260324723482,"elapsedTimeMicros":12772000,"playing":false}}
```

The artwork data is shortened for brevity.
