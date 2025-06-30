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
      transitionDuration: const Duration(milliseconds: 400),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
          child: child,
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return GalleryImageDetailDialog(galleryItem: galleryItem);
      },
    );
  }

  @override
  State<GalleryImageDetailDialog> createState() => _GalleryImageDetailDialogState();
}

class _GalleryImageDetailDialogState extends State<GalleryImageDetailDialog> with TickerProviderStateMixin {
  bool _isSaving = false;
  static const MethodChannel _channel = MethodChannel('com.visionspark.app/media');
  late AnimationController _overlayController;
  late Animation<double> _overlayOpacity;

  @override
  void initState() {
    super.initState();
    _overlayController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _overlayOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(_overlayController);
    _overlayController.forward();
  }

  @override
  void dispose() {
    _overlayController.dispose();
    super.dispose();
  }

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
        scaffoldMessenger.showSnackBar(SnackBar(
          content: Text('Image saved to Gallery: $filename'),
          backgroundColor: Theme.of(context).colorScheme.primary,
        ));
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Prompt copied to clipboard!'),
        backgroundColor: Theme.of(context).colorScheme.primary,
      ));
    }
  }

  void _shareImage() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Sharing image URL: ${widget.galleryItem.imageUrl}'),
      backgroundColor: Theme.of(context).colorScheme.primary,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20.0),
      child: Container(
        height: size.height * 0.85,
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.95),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.3),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header with close button
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Image Detail',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainer.withOpacity(0.8),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: colorScheme.outline.withOpacity(0.2),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSurface,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // Main image with interactive viewer
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withOpacity(0.2),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Hero(
                    tag: widget.galleryItem.id,
                    child: InteractiveViewer(
                      child: Image.network(
                        widget.galleryItem.imageUrl,
                        fit: BoxFit.contain,
                        width: double.infinity,
                        height: double.infinity,
                        loadingBuilder: (context, child, progress) => progress == null 
                          ? child 
                          : Center(
                              child: CircularProgressIndicator(
                                color: colorScheme.primary,
                                strokeWidth: 3,
                              ),
                            ),
                        errorBuilder: (context, error, stack) => Container(
                          color: colorScheme.surfaceContainer,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.broken_image_rounded,
                                  size: 60,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Bottom section with prompt and actions
            Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer.withOpacity(0.6),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: Column(
                children: [
                  _buildPromptSection(colorScheme),
                  const SizedBox(height: 20),
                  _buildActionButtons(colorScheme),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptSection(ColorScheme colorScheme) {
    return GestureDetector(
      onTap: _copyPrompt,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.8),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(
                  'Prompt',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Icon(
                  Icons.copy_rounded,
                  size: 16,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.galleryItem.prompt ?? "No prompt available",
              style: TextStyle(
                fontSize: 15,
                color: colorScheme.onSurface.withOpacity(0.8),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(ColorScheme colorScheme) {
    return Row(
      children: [
        Expanded(
          child: _buildModernActionButton(
            colorScheme: colorScheme,
            icon: _isSaving ? null : Icons.download_rounded,
            label: 'Save',
            onPressed: _isSaving ? null : _saveImageFromUrl,
            isLoading: _isSaving,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildModernActionButton(
            colorScheme: colorScheme,
            icon: Icons.share_rounded,
            label: 'Share',
            onPressed: _shareImage,
            isPrimary: false,
          ),
        ),
      ],
    );
  }

  Widget _buildModernActionButton({
    required ColorScheme colorScheme,
    IconData? icon,
    required String label,
    required VoidCallback? onPressed,
    bool isLoading = false,
    bool isPrimary = true,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: isPrimary
          ? LinearGradient(
              colors: [colorScheme.primary, colorScheme.secondary],
            )
          : null,
        color: isPrimary ? null : colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isPrimary 
            ? Colors.transparent 
            : colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: isPrimary ? [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isPrimary ? colorScheme.onPrimary : colorScheme.primary,
                      ),
                    ),
                  )
                else if (icon != null) ...[
                  Icon(
                    icon,
                    size: 20,
                    color: isPrimary ? colorScheme.onPrimary : colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isPrimary ? colorScheme.onPrimary : colorScheme.onSurface,
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