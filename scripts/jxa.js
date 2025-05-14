ObjC.import('Foundation');
ObjC.import('stdlib');

const path = '/Users/macintosh/git/osascript-mediaremote/build/MediaRemoteAdapter.framework';
const bundle = $.NSBundle.bundleWithPath($(path));
if (bundle.load !== true) {
    console.log('Failure');
    $.exit(1);
}

const MyLibHelloWorld = $.NSClassFromString('MediaRemoteAdapter');

MyLibHelloWorld.loop
