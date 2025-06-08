import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import './gallery_screen.dart'; // Contains GalleryImage
import 'package:http/http.dart' as http;

class GalleryImageDetailDialog extends StatefulWidget {
  final GalleryImage galleryItem;

  const GalleryImageDetailDialog({super.key, required this.galleryItem});

  static Future<void> show(BuildContext context, GalleryImage galleryItem) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return GalleryImageDetailDialog(galleryItem: galleryItem);
      },
    );
  }

  @override
  State<GalleryImageDetailDialog> createState() => _GalleryImageDetailDialogState();
}

class _GalleryImageDetailDialogState extends State<GalleryImageDetailDialog> {
  bool _isSaving = false;
  static const MethodChannel _channel = MethodChannel('com.visionspark.app/media');

  // --- Permission Handling Logic (Unchanged but important) ---
  Future<void> _saveImageFromUrl() async {
    if (!mounted || _isSaving) return;
    setState(() => _isSaving = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final photosPermission = Platform.isAndroid 
          ? (await DeviceInfoPlugin().androidInfo).version.sdkInt >= 33 ? Permission.photos : Permission.storage
          : Permission.photos;

      PermissionStatus status = await photosPermission.status;
      if (!status.isGranted) status = await photosPermission.request();

      if (status.isGranted) {
        final http.Response response = await http.get(Uri.parse(widget.galleryItem.imageUrl));
        if (response.statusCode != 200) throw Exception('Failed to download image.');
        
        final filename = 'Visionspark_${DateTime.now().millisecondsSinceEpoch}.png';
        await _channel.invokeMethod('saveImageToGallery', {
          'imageBytes': response.bodyBytes, 'filename': filename, 'albumName': 'Visionspark'
        });
        scaffoldMessenger.showSnackBar(SnackBar(content: Text('Image saved to Gallery: $filename')));
      } else {
        scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Storage permission denied.')));
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text('Failed to save image: ${e.toString()}')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _copyPrompt() {
    if (widget.galleryItem.prompt != null && widget.galleryItem.prompt!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: widget.galleryItem.prompt!));
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Prompt copied to clipboard!')));
    }
  }

  void _shareImage() {
    // In a real app, you would use the `share_plus` package here.
    // For this example, we'll just show a snackbar.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sharing image URL: ${widget.galleryItem.imageUrl}')));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            alignment: Alignment.topRight,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AspectRatio(
                    aspectRatio: 1,
                    child: Hero(
                      tag: widget.galleryItem.id,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: InteractiveViewer(
                          child: Image.network(
                            widget.galleryItem.imageUrl,
                            fit: BoxFit.contain,
                            loadingBuilder: (context, child, progress) => progress == null ? child : const Center(child: CircularProgressIndicator()),
                            errorBuilder: (context, error, stack) => const Center(child: Icon(Icons.broken_image, size: 60)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildPromptSection(colorScheme),
                  const SizedBox(height: 20),
                  _buildActionBar(),
                ],
              ),
              IconButton(
                icon: const CircleAvatar(backgroundColor: Colors.black54, child: Icon(Icons.close, color: Colors.white)),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromptSection(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _copyPrompt,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceVariant.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Prompt: ${widget.galleryItem.prompt ?? "Not available"}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.copy_all_outlined, color: Colors.white70, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildActionButton(
          onPressed: _isSaving ? null : _saveImageFromUrl,
          icon: Icons.save_alt_outlined,
          label: 'Save',
          child: _isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : null,
        ),
        _buildActionButton(onPressed: _shareImage, icon: Icons.share_outlined, label: 'Share'),
        _buildActionButton(onPressed: _copyPrompt, icon: Icons.copy_all_outlined, label: 'Copy Prompt'),
      ],
    );
  }

  Widget _buildActionButton({required VoidCallback? onPressed, required IconData icon, required String label, Widget? child}) {
    return Column(
      children: [
        ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(16),
            backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.2),
            foregroundColor: Colors.white,
          ),
          child: child ?? Icon(icon, size: 24),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}