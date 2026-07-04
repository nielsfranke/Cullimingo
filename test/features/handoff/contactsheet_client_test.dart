import 'dart:convert';
import 'dart:io';

import 'package:cullimingo/features/handoff/data/contactsheet_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('ContactSheetClient', () {
    test('listGalleries sends the bearer token and parses the list', () async {
      late http.Request seen;
      final client = ContactSheetClient(
        baseUrl: 'https://cs.example.com/',
        token: 'cs_pat_abc',
        client: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode([
              {
                'id': 'g1',
                'name': 'Wedding',
                'share_token': 'tok1',
                'parent_id': null,
              },
            ]),
            200,
          );
        }),
      );

      final galleries = await client.listGalleries();

      // Trailing slash on baseUrl is trimmed, token sent as bearer.
      expect(seen.url.toString(), 'https://cs.example.com/api/galleries');
      expect(seen.headers['Authorization'], 'Bearer cs_pat_abc');
      expect(galleries.single.id, 'g1');
      expect(galleries.single.name, 'Wedding');
      expect(galleries.single.shareToken, 'tok1');
    });

    test('createGallery posts the name and parses the new gallery', () async {
      late http.Request seen;
      final client = ContactSheetClient(
        baseUrl: 'https://cs.example.com',
        token: 't',
        client: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'id': 'g2',
              'name': 'Shoot',
              'share_token': 'tok2',
              'parent_id': null,
            }),
            201,
          );
        }),
      );

      final gallery = await client.createGallery(name: 'Shoot');

      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/galleries');
      expect(jsonDecode(seen.body), {'name': 'Shoot'});
      expect(gallery.id, 'g2');
    });

    test('createGallery sends parent_id for a sub-gallery', () async {
      late http.Request seen;
      final client = ContactSheetClient(
        baseUrl: 'https://cs.example.com',
        token: 't',
        client: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode({
              'id': 'g3',
              'name': 'Sub',
              'share_token': 'tok3',
              'parent_id': 'g2',
            }),
            201,
          );
        }),
      );

      await client.createGallery(name: 'Sub', parentId: 'g2');

      expect(jsonDecode(seen.body), {'name': 'Sub', 'parent_id': 'g2'});
    });

    test('uploadImages posts multipart files and parses results', () async {
      final tmp = Directory.systemTemp.createTempSync('cs_upload');
      final f1 = File('${tmp.path}/a.jpg')..writeAsBytesSync([1, 2, 3]);
      late http.Request seen;
      final client = ContactSheetClient(
        baseUrl: 'https://cs.example.com',
        token: 't',
        client: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode([
              {
                'id': 'i1',
                'original_filename': 'a.jpg',
                'processing_status': 'pending',
              },
            ]),
            201,
          );
        }),
      );

      final uploads = await client.uploadImages(
        galleryId: 'g2',
        files: [f1],
      );

      expect(seen.method, 'POST');
      expect(seen.url.path, '/api/galleries/g2/images');
      expect(seen.headers['content-type'], contains('multipart/form-data'));
      expect(uploads.single.id, 'i1');
      expect(uploads.single.originalFilename, 'a.jpg');

      tmp.deleteSync(recursive: true);
    });

    test('pullGalleryMarks GETs the public gallery and parses marks', () async {
      late http.Request seen;
      final client = ContactSheetClient(
        baseUrl: 'https://cs.example.com',
        token: 't',
        client: MockClient((req) async {
          seen = req;
          return http.Response(
            jsonEncode([
              {
                'id': 'i1',
                'original_filename': '_AIV1.ARW',
                'rating': 5,
                'color_flag': 'green',
                'likes': 2,
              },
            ]),
            200,
          );
        }),
      );

      final marks = await client.pullGalleryMarks('shareTok');

      expect(seen.method, 'GET');
      expect(seen.url.path, '/api/public/g/shareTok/images');
      expect(marks.single.filename, '_AIV1.ARW');
      expect(marks.single.rating, 5);
      expect(marks.single.colorFlag, 'green');
      expect(marks.single.likes, 2);
    });

    test('a 401 maps to a helpful ContactSheetException', () async {
      final client = ContactSheetClient(
        baseUrl: 'https://cs.example.com',
        token: 'bad',
        client: MockClient((_) async => http.Response('nope', 401)),
      );

      expect(
        client.listGalleries,
        throwsA(
          isA<ContactSheetException>()
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', contains('token')),
        ),
      );
    });
  });
}
