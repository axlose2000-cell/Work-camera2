import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:work_camera_gallery/gallery_screen.dart';

void main() {
  testWidgets('GalleryScreen renders correctly', (WidgetTester tester) async {
    // Build the GalleryScreen widget.
    await tester.pumpWidget(MaterialApp(home: GalleryScreen()));

    // Verify that the GalleryScreen is displayed.
    expect(find.text('Gallery'), findsOneWidget);
  });
}
