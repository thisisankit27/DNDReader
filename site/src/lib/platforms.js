// Editorial facts about each platform. Version-independent: sizes, file names and hashes come from the
// release data, never from here.
export const PLATFORMS = {
  ubuntu: {
    slug: 'ubuntu',
    name: 'Ubuntu',
    kind: 'installer package',
    requirement: 'Ubuntu 26.04, on a 64-bit Intel or AMD computer',
  },
  windows: {
    slug: 'windows',
    name: 'Windows',
    kind: 'installer',
    requirement: 'Windows 10 (version 1809) or newer, 64-bit',
  },
  android: {
    slug: 'android',
    name: 'Android',
    kind: 'app file',
    requirement: 'Android 8.0 or newer',
  },
};
export const ORDER = ['ubuntu', 'windows', 'android'];

export const ABI_COPY = {
  'arm64-v8a': 'The right file for almost every phone and tablet made since about 2017.',
  'armeabi-v7a': 'For older 32-bit phones. This build has been compiled but has never been run on a device.',
  x86_64: 'For Android emulators on a computer. Not for phones.',
};
