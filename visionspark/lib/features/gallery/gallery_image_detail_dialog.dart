import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Added for MethodChannel
// import 'package:flutter/services.dart'; // Keep commented if MethodChannel not used
// import 'package:image_gallery_saver/image_gallery_saver.dart'; // Removed
// import 'package:gallery_saver/gallery_saver.dart'; // Removed
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
// Assuming GalleryImage class is in gallery_screen.dart or a shared model file
// If not, you might need to move/import it here.
import './gallery_screen.dart'; // Contains GalleryImage for now
import 'package:http/http.dart' as http;

class GalleryImageDetailDialog extends StatefulWidget {
  final GalleryImage galleryItem;

  const GalleryImageDetailDialog({super.key, required this.galleryItem});

  static Future<void> show(BuildContext context, GalleryImage galleryItem) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Center(
            child: GalleryImageDetailDialog(galleryItem: galleryItem),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
    );
  }

  @override
  State<GalleryImageDetailDialog> createState() => _GalleryImageDetailDialogState();
}

class _GalleryImageDetailDialogState extends State<GalleryImageDetailDialog> {
  bool _isSaving = false;
  // static const platform = MethodChannel('com.example.visionspark/media_scanner'); // Keep commented out
  static const MethodChannel _channel = MethodChannel('com.visionspark.app/media'); // Added MethodChannel

  Future<Permission> _getAndroidStoragePermission() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    debugPrint("[Permissions] Device Android SDK Int: $sdkInt"); // Log SDK Int
    if (sdkInt >= 33) { // Android 13+
      debugPrint("[Permissions] Requesting Permission.photos for Android SDK $sdkInt");
      return Permission.photos;
    } else { // Android 12 and below
      debugPrint("[Permissions] Requesting Permission.storage for Android SDK $sdkInt");
      return Permission.storage;
    }
  }

  Future<PermissionStatus> _getStoragePermissionStatus() async {
    if (Platform.isIOS) {
      return await Permission.photos.status;
    } else if (Platform.isAndroid) {
      final permission = await _getAndroidStoragePermission();
      return await permission.status;
    }
    return PermissionStatus.denied; // Default for other platforms
  }

  Future<PermissionStatus> _requestStoragePermission() async {
    if (Platform.isIOS) {
      return await Permission.photos.request();
    } else if (Platform.isAndroid) {
      final permission = await _getAndroidStoragePermission();
      return await permission.request();
    }
    return PermissionStatus.denied; // Default for other platforms
  }

  Future<void> _saveImageFromUrl() async {
    if (!mounted) return;
    setState(() {
      _isSaving = true;
    });

    try {
      debugPrint("[GalleryDialog] Initial permission check...");
      PermissionStatus status = await _getStoragePermissionStatus();
      debugPrint("[GalleryDialog] Initial status: $status");

      if (!status.isGranted) {
        if (status.isPermanentlyDenied) {
          debugPrint("[GalleryDialog] Permission permanently denied. Showing settings snackbar.");
          if (!mounted) {
            setState(() => _isSaving = false);
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Storage permission is permanently denied. Please enable it in app settings.'),
              action: SnackBarAction(
                label: 'Settings',
                onPressed: () {
                  openAppSettings();
                },
              ),
              duration: const Duration(seconds: 5),
            ),
          );
          setState(() => _isSaving = false);
          return;
        }
        debugPrint("[GalleryDialog] Requesting permission...");
        status = await _requestStoragePermission();
        debugPrint("[GalleryDialog] Status after request: $status");
      }

      if (status.isGranted) {
        debugPrint("[GalleryDialog] Permission granted. Proceeding to save via MethodChannel.");
        // Download the image bytes first
        final http.Response imageDataResponse = await http.get(Uri.parse(widget.galleryItem.imageUrl));
        if (imageDataResponse.statusCode != 200) {
          throw Exception('Failed to download image data. Status: ${imageDataResponse.statusCode}');
        }
        final Uint8List imageBytes = imageDataResponse.bodyBytes;
        final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        final String filename = 'Visionspark_$timestamp.png';

        // Use MethodChannel
        try {
          final bool? saveSuccess = await _channel.invokeMethod('saveImageToGallery', {
            'imageBytes': imageBytes,
            'filename': filename,
            'albumName': 'Visionspark'
          });

          if (!mounted) return; 
          if (saveSuccess == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Image saved to Gallery as $filename')),
            );
          } else {
            debugPrint("Gallery Dialog: Image save failed. MethodChannel result: $saveSuccess");
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to save image via native code.')),
            );
          }
        } on PlatformException catch (e) {
          debugPrint("[GalleryDialog] Failed to save image via MethodChannel: '${e.message}'.");
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save image: ${e.message}')),
          );
        }
      } else if (status.isPermanentlyDenied) {
        // This case should ideally be caught by the first check, but as a fallback:
        debugPrint("[GalleryDialog] Permission is permanently denied (after request check). Showing settings snackbar.");
        if (!mounted) {
           setState(() => _isSaving = false);
           return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Storage permission is permanently denied. Please enable it in app settings.'),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () {
                openAppSettings();
              },
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      } else {
        debugPrint("[GalleryDialog] Permission denied after request. Showing denial snackbar.");
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Storage permission denied. Cannot save image.')),
        );
      }
    } catch (e, s) {
      debugPrint('Gallery Dialog: Error saving image: $e\n$s');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save image: ${e.toString()}')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color lilacPurple = Color(0xFFD0B8E1);
    const Color darkText = Color(0xFF22223B);
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85, maxWidth: 500),
          child: Container(
            padding: const EdgeInsets.all(24.0),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: lilacPurple.withValues(alpha: 25),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.network(
                            widget.galleryItem.imageUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return const Center(child: CircularProgressIndicator());
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(child: Icon(Icons.broken_image, size: 60));
                            },
                          ),
                        ),
                      ),
                    ),
                    if (widget.galleryItem.prompt != null && widget.galleryItem.prompt!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 16.0, bottom: 10.0),
                        child: Text(
                          'Prompt: ${widget.galleryItem.prompt}',
                          style: TextStyle(
                            fontSize: 15,
                            color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _saveImageFromUrl,
                      icon: _isSaving
                          ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: lilacPurple))
                          : const Icon(Icons.save_alt),
                      label: const Text('Save to Device'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: lilacPurple,
                        foregroundColor: darkText,
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ],
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton(
                    icon: Icon(Icons.close, color: darkText.withValues(alpha: 153)),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
} 