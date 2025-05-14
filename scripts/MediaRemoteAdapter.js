// Prints real-time updates using the MediaRemote framework.
// Requires the path to the MediaRemoteAdapter framework as first argument.
// Invocation:
// osascript -l JavaScript MediaRemote.js /path/to/MediaRemoteAdapter.framework
// Send SIGTERM signal to gracefully terminate and clean up.

ObjC.import('stdlib');
ObjC.import('Foundation');

function printErr(message) {
    $.NSFileHandle.fileHandleWithStandardError.writeData(
        $(message).dataUsingEncoding($.NSUTF8StringEncoding));
}

function fatal(message) {
    printErr(message);
    $.exit(1);
}

const args = ObjC.unwrap($.NSProcessInfo.processInfo.arguments);
const userArgs = args.slice(4);
if (userArgs.length != 1) {
    fatal('Exactly one command line argument is required');
}

const bundlePath = ObjC.unwrap(userArgs[0]);
const bundle = $.NSBundle.bundleWithPath(bundlePath);
if (bundle.load !== true) {
    fatal('Failed to initialize the MediaRemoteAdapter framework');
}

const MediaRemoteAdapter = $.NSClassFromString('MediaRemoteAdapter');
MediaRemoteAdapter.loop
