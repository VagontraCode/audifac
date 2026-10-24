import 'dart:typed_data';

import 'package:audifac/widgets/artwork_viewer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('format from the first bytes', () {
    expect(ArtworkViewer.format(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0])), 'JPEG');
    expect(ArtworkViewer.format(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D])), 'PNG');
    expect(ArtworkViewer.format(Uint8List.fromList('RIFF\x00\x00\x00\x00WEBPVP8 '.codeUnits)), 'WebP');
    expect(ArtworkViewer.format(Uint8List.fromList('RIFF\x00\x00\x00\x00WAVE'.codeUnits)), isNull);
    expect(ArtworkViewer.format(Uint8List.fromList([0xFF])), isNull);
  });

  test('size label', () {
    expect(ArtworkViewer.size(312400), '312 KB');
    expect(ArtworkViewer.size(1400000), '1.4 MB');
  });
}
