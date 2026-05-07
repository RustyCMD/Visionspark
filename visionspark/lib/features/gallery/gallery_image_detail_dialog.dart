import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

import '../../shared/design_system/design_system.dart';
import '../../shared/utils/snackbar_utils.dart';
import 'gallery_screen.dart';

class GalleryImageDetailDialog extends StatefulWidget {
  final GalleryImage galleryItem;
  const GalleryImageDetailDialog({super.key, required this.galleryItem});

  static Future<void> show(BuildContext context, GalleryImage item) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black,
      transitionDuration: VSDesignTokens.durationMedium,
      pageBuilder: (_, animation, __) {
        return SlideTransition(
          position: Tween(begin: const Offset(0, 1), end: Offset.zero).animate(
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
          ),
          child: GalleryImageDetailDialog(galleryItem: item),
        );
      },
    );
  }

  @override
  State<GalleryImageDetailDialog> createState() => _GalleryImageDetailDialogState();
}

class _GalleryImageDetailDialogState extends State<GalleryImageDetailDialog> {
  static const _channel = MethodChannel('com.visionspark.app/media');
  bool _saving = false;
  bool _detailsOpen = false;

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final perm = Platform.isAndroid
          ? ((await DeviceInfoPlugin().androidInfo).version.sdkInt >= 33
              ? Permission.photos
              : Permission.storage)
          : Permission.photos;
      var status = await perm.status;
      if (!status.isGranted) status = await perm.request();
      if (!status.isGranted) {
        if (mounted) VSSnackbar.showError(context, 'Storage permission denied.');
        return;
      }
      final url = widget.galleryItem.imageUrl;
      if (url == null) throw Exception('No URL');
      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) throw Exception('Download failed');
      final filename = 'Visionspark_${DateTime.now().millisecondsSinceEpoch}.png';
      await _channel.invokeMethod('saveImageToGallery', {
        'imageBytes': res.bodyBytes,
        'filename': filename,
        'albumName': 'Visionspark',
      });
      if (mounted) VSSnackbar.showSuccess(context, 'Saved: $filename');
    } catch (e) {
      if (mounted) VSSnackbar.showError(context, 'Could not save: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _copyPrompt() {
    final p = widget.galleryItem.prompt;
    if (p == null || p.isEmpty) return;
    Clipboard.setData(ClipboardData(text: p));
    VSSnackbar.showSuccess(context, 'Prompt copied.');
  }

  void _shareUrl() {
    final url = widget.galleryItem.imageUrl ?? '';
    Clipboard.setData(ClipboardData(text: url));
    VSSnackbar.showInfo(context, 'Image URL copied to clipboard.');
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _circleButton(
          icon: Icons.close_rounded,
          tooltip: 'Close',
          onTap: () => Navigator.of(context).pop(),
        ),
        actions: [
          _circleButton(
            icon: _detailsOpen ? Icons.info : Icons.info_outline,
            tooltip: _detailsOpen ? 'Hide details' : 'Show details',
            onTap: () => setState(() => _detailsOpen = !_detailsOpen),
          ),
          const SizedBox(width: VSDesignTokens.space2),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: Hero(
              tag: widget.galleryItem.id,
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: widget.galleryItem.imageUrl == null
                    ? const SizedBox.shrink()
                    : Image.network(
                        widget.galleryItem.imageUrl!,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, p) => p == null
                            ? child
                            : Center(
                                child: VSLoadingIndicator(
                                  message: 'Loading image…',
                                  color: cs.primary,
                                ),
                              ),
                        errorBuilder: (_, __, ___) => const Center(
                          child: VSEmptyState(
                            icon: Icons.broken_image_outlined,
                            title: 'Failed to load',
                            subtitle: 'Check your connection and try again.',
                          ),
                        ),
                      ),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: VSDesignTokens.durationMedium,
            curve: Curves.easeOutCubic,
            left: 16,
            right: 16,
            bottom: _detailsOpen ? size.height * 0.4 + 24 : 24,
            child: _actions(),
          ),
          AnimatedPositioned(
            duration: VSDesignTokens.durationMedium,
            curve: Curves.easeOutCubic,
            left: 16,
            right: 16,
            bottom: _detailsOpen ? 24 : -size.height * 0.5,
            child: _details(size),
          ),
        ],
      ),
    );
  }

  Widget _circleButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.all(VSDesignTokens.space2),
      child: Material(
        color: Colors.black.withValues(alpha: 0.45),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }

  Widget _actions() {
    final cs = Theme.of(context).colorScheme;
    final hasPrompt = (widget.galleryItem.prompt ?? '').isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(VSDesignTokens.space3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXXL),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionTile(
            icon: Icons.download_rounded,
            label: 'Save',
            loading: _saving,
            onTap: _save,
            accent: cs.primary,
          ),
          _ActionTile(
            icon: Icons.share_rounded,
            label: 'Share',
            onTap: _shareUrl,
            accent: cs.primary,
          ),
          _ActionTile(
            icon: Icons.copy_all_rounded,
            label: 'Copy',
            onTap: hasPrompt ? _copyPrompt : null,
            accent: cs.primary,
          ),
        ],
      ),
    );
  }

  Widget _details(Size size) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final p = widget.galleryItem.prompt ?? '';
    return Container(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      constraints: BoxConstraints(maxHeight: size.height * 0.4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXXL),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(VSDesignTokens.space2),
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(VSDesignTokens.radiusS),
                  ),
                  child: Icon(Icons.auto_awesome, color: cs.primary, size: 20),
                ),
                const SizedBox(width: VSDesignTokens.space3),
                Text(
                  'Image details',
                  style: tt.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: VSTypography.weightBold,
                  ),
                ),
              ],
            ),
            if (p.isNotEmpty) ...[
              const SizedBox(height: VSDesignTokens.space5),
              Text(
                'Prompt',
                style: tt.titleSmall?.copyWith(
                  color: Colors.white70,
                  fontWeight: VSTypography.weightSemiBold,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: VSDesignTokens.space2),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(VSDesignTokens.space4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: SelectableText(
                  p,
                  style: tt.bodyLarge?.copyWith(color: Colors.white, height: 1.5),
                ),
              ),
            ],
            const SizedBox(height: VSDesignTokens.space4),
            Row(
              children: [
                _Chip(
                  icon: Icons.favorite_rounded,
                  text: '${widget.galleryItem.likeCount} likes',
                  iconColor: cs.primary,
                ),
                const SizedBox(width: VSDesignTokens.space2),
                _Chip(
                  icon: Icons.schedule_rounded,
                  text: _format(widget.galleryItem.createdAt),
                  iconColor: Colors.white70,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _format(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.inDays == 0) {
      if (diff.inHours == 0) return '${diff.inMinutes}m ago';
      return '${diff.inHours}h ago';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}d ago';
    }
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.day}';
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  final Color accent;
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.accent,
    this.loading = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Expanded(
      child: Material(
        color: enabled ? accent.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusL),
        child: InkWell(
          onTap: enabled && !loading ? onTap : null,
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusL),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VSDesignTokens.space3,
              vertical: VSDesignTokens.space4,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (loading)
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                  )
                else
                  Icon(icon, color: enabled ? accent : Colors.white38, size: 22),
                const SizedBox(height: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: enabled ? Colors.white : Colors.white38,
                    fontSize: 12,
                    fontWeight: VSTypography.weightSemiBold,
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

class _Chip extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color iconColor;
  const _Chip({required this.icon, required this.text, required this.iconColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VSDesignTokens.space3,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: iconColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: VSTypography.weightMedium,
            ),
          ),
        ],
      ),
    );
  }
}
