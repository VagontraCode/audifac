import 'package:flutter/foundation.dart';

/// Notices for native code that isn't a Dart package (shown on the licenses
/// page next to the packages' own).
void registerNativeLicenses() {
  LicenseRegistry.addLicense(() => Stream.value(const LicenseEntryWithLineBreaks(['FFmpeg'], _ffmpeg)));
}

const _ffmpeg = '''
This app plays WMA, Monkey's Audio (APE), WavPack and TTA files with FFmpeg 7.1.1 (libavformat, libavcodec, libavutil), built from unmodified sources with tools/ffmpeg/build.sh in the app's source repository (https://github.com/VagontraCode/audifac).

FFmpeg is free software licensed under the GNU Lesser General Public License, version 2.1 or later (https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html). Its source code is available at https://ffmpeg.org/releases/ffmpeg-7.1.1.tar.xz. FFmpeg is a trademark of Fabrice Bellard, originator of the FFmpeg project.''';
