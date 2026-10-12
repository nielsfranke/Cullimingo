import 'package:cullimingo/core/files/open_external.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a gvfs SMB path stays one URI for dbus-send (#14)', () {
    final uri = showItemsUri(
      '/run/user/1000/gvfs/smb-share:server=nas.local,share=photos/'
      'unsorted/IMG 1.HEIC',
    );

    // dbus-send splits `array:string:` elements on commas.
    expect(uri, isNot(contains(',')));
    expect(
      Uri.parse(uri).toFilePath(),
      '/run/user/1000/gvfs/smb-share:server=nas.local,share=photos/'
      'unsorted/IMG 1.HEIC',
    );
  });
}
