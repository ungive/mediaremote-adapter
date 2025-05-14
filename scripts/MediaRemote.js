// Prints real-time updates using the MediaRemote framework.
// Requires the path to the MediaRemoteAdapter framework as first argument.
// Invocation:
// osascript -l JavaScript MediaRemote.js /path/to/MediaRemoteAdapter.framework

ObjC.import('stdlib');
ObjC.import('Foundation');

function fatal(message) {
    console.log(JSON.stringify({
        'type': 'error',
        'message': message,
        'fatal': true,
    }));
    $.exit(1);
}

ObjC.import('Foundation');
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
