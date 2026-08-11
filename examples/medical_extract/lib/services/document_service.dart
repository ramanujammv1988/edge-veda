import 'dart:io';
import 'package:image_picker/image_picker.dart';

/// Service for capturing and loading medical documents.
class DocumentService {
  final ImagePicker _picker = ImagePicker();

  /// Pick a document image from camera.
  Future<String?> captureFromCamera() async {
    final image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 90,
    );
    return image?.path;
  }

  /// Pick a document image from gallery.
  Future<String?> pickFromGallery() async {
    final image = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    return image?.path;
  }

  /// Load text from a plain text file.
  Future<String?> loadTextFile(String path) async {
    try {
      return await File(path).readAsString();
    } catch (_) {
      return null;
    }
  }
}
