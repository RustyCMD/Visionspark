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
      barrierColor: Colors.black,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: GalleryImageDetailDialog(galleryItem: galleryItem),
        );
      },
    );
  }

  @override
  State<GalleryImageDetailDialog> createState() => _GalleryImageDetailDialogState();
}

class _GalleryImageDetailDialogState extends State<GalleryImageDetailDialog> 
    with TickerProviderStateMixin {
  bool _isSaving = false;
  bool _showDetails = false;
  static const MethodChannel _channel = MethodChannel('com.visionspark.app/media');
  
  late AnimationController _detailsAnimationController;
  late Animation<double> _detailsAnimation;

  @override
  void initState() {
    super.initState();
    _detailsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _detailsAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _detailsAnimationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _detailsAnimationController.dispose();
    super.dispose();
  }

  void _toggleDetails() {
    setState(() {
      _showDetails = !_showDetails;
    });
    if (_showDetails) {
      _detailsAnimationController.forward();
    } else {
      _detailsAnimationController.reverse();
    }
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
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text('Image saved to Gallery: $filename'),
              ],
            ),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      } else {
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Text('Storage permission denied.'),
              ],
            ),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text('Failed to save image: ${e.toString()}')),
            ],
          ),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _copyPrompt() {
    if (widget.galleryItem.prompt != null && widget.galleryItem.prompt!.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: widget.galleryItem.prompt!));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text('Prompt copied to clipboard!'),
            ],
          ),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _shareImage() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.share, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text('Sharing image URL: ${widget.galleryItem.imageUrl}')),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: Container(
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.3),
              shape: BoxShape.circle,
            ),
            child: IconButton(
              icon: Icon(
                _showDetails ? Icons.info : Icons.info_outline,
                color: Colors.white,
              ),
              onPressed: _toggleDetails,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Main image
          Center(
            child: Hero(
              tag: widget.galleryItem.id,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 3.0,
                child: Container(
                  constraints: BoxConstraints(
                    maxWidth: size.width,
                    maxHeight: size.height,
                  ),
                  child: Image.network(
                    widget.galleryItem.imageUrl,
                    fit: BoxFit.contain,
                    loadingBuilder: (context, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        width: size.width * 0.8,
                        height: size.height * 0.6,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade900,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircularProgressIndicator(
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                    : null,
                                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Loading image...',
                                style: textTheme.bodyLarge?.copyWith(color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                    errorBuilder: (context, error, stack) => Container(
                      width: size.width * 0.8,
                      height: size.height * 0.6,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade900,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.broken_image_rounded,
                              size: 64,
                              color: Colors.white54,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Failed to load image',
                              style: textTheme.bodyLarge?.copyWith(color: Colors.white70),
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

          // Details overlay
          AnimatedBuilder(
            animation: _detailsAnimation,
            builder: (context, child) {
              return Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Transform.translate(
                  offset: Offset(0, (1 - _detailsAnimation.value) * 200),
                  child: Opacity(
                    opacity: _detailsAnimation.value,
                    child: _buildDetailsOverlay(colorScheme, textTheme, size),
                  ),
                ),
              );
            },
          ),

          // Action buttons
          Positioned(
            bottom: size.height * 0.05,
            left: 0,
            right: 0,
            child: _buildActionButtons(colorScheme, textTheme, size),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsOverlay(ColorScheme colorScheme, TextTheme textTheme, Size size) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.8),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'Image Details',
                style: textTheme.titleLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (widget.galleryItem.prompt != null && widget.galleryItem.prompt!.isNotEmpty) ...[
            Text(
              'Prompt',
              style: textTheme.titleSmall?.copyWith(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.white.withOpacity(0.1),
                  width: 1,
                ),
              ),
              child: SelectableText(
                widget.galleryItem.prompt!,
                style: textTheme.bodyLarge?.copyWith(
                  color: Colors.white,
                  height: 1.5,
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              _buildInfoChip(
                Icons.favorite,
                '${widget.galleryItem.likeCount} likes',
                colorScheme.primary,
              ),
              const SizedBox(width: 12),
              _buildInfoChip(
                Icons.schedule,
                _formatDate(widget.galleryItem.createdAt),
                Colors.white70,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(ColorScheme colorScheme, TextTheme textTheme, Size size) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: size.width * 0.08),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildActionButton(
            icon: Icons.save_alt_rounded,
            label: 'Save',
            onPressed: _isSaving ? null : _saveImageFromUrl,
            isLoading: _isSaving,
            colorScheme: colorScheme,
          ),
          _buildActionButton(
            icon: Icons.share_rounded,
            label: 'Share',
            onPressed: _shareImage,
            colorScheme: colorScheme,
          ),
          _buildActionButton(
            icon: Icons.copy_all_rounded,
            label: 'Copy',
            onPressed: widget.galleryItem.prompt != null && widget.galleryItem.prompt!.isNotEmpty 
                ? _copyPrompt 
                : null,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required ColorScheme colorScheme,
    bool isLoading = false,
  }) {
    final isEnabled = onPressed != null;
    
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        child: Material(
          color: isEnabled 
              ? colorScheme.primary.withOpacity(0.15)
              : Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isLoading)
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isEnabled ? colorScheme.primary : Colors.white38,
                        ),
                      ),
                    )
                  else
                    Icon(
                      icon,
                      size: 24,
                      color: isEnabled ? colorScheme.primary : Colors.white38,
                    ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      color: isEnabled ? Colors.white : Colors.white38,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes}m ago';
      }
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[date.month - 1]} ${date.day}';
    }
  }
}