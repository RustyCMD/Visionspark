import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/design_system/design_system.dart';
import 'gallery_image_detail_dialog.dart';

class GalleryImage {
  final String id;
  final String? imageUrl;
  final String? thumbnailUrlSigned;
  final String? prompt;
  final DateTime createdAt;
  final String? userId;
  final int likeCount;
  final bool isLikedByCurrentUser;

  const GalleryImage({
    required this.id,
    required this.imageUrl,
    this.thumbnailUrlSigned,
    this.prompt,
    required this.createdAt,
    this.userId,
    required this.likeCount,
    required this.isLikedByCurrentUser,
  });

  factory GalleryImage.fromMap(
    Map<String, dynamic> map,
    String? imageUrl,
    int likeCount,
    bool isLikedByCurrentUser,
  ) {
    return GalleryImage(
      id: map['id'] as String,
      imageUrl: imageUrl,
      thumbnailUrlSigned: map['thumbnail_url_signed'] as String?,
      prompt: map['prompt'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      userId: map['user_id'] as String?,
      likeCount: likeCount,
      isLikedByCurrentUser: isLikedByCurrentUser,
    );
  }

  GalleryImage copyWith({int? likeCount, bool? isLikedByCurrentUser}) =>
      GalleryImage(
        id: id,
        imageUrl: imageUrl,
        thumbnailUrlSigned: thumbnailUrlSigned,
        prompt: prompt,
        createdAt: createdAt,
        userId: userId,
        likeCount: likeCount ?? this.likeCount,
        isLikedByCurrentUser: isLikedByCurrentUser ?? this.isLikedByCurrentUser,
      );
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  Timer? _throttle;
  final _likeBusy = <String>{};

  List<GalleryImage> _images = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this)
      ..addListener(() {
        if (!_tab.indexIsChanging) setState(() {});
      });
    _fetch();
  }

  @override
  void dispose() {
    _tab.dispose();
    _throttle?.cancel();
    super.dispose();
  }

  Future<void> _fetch({bool refresh = false}) async {
    if (refresh) {
      if (_throttle?.isActive ?? false) return;
      _throttle = Timer(const Duration(seconds: 4), () {});
    }
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');
      final resp = await Supabase.instance.client.functions.invoke('get-gallery-feed');
      if (resp.data == null) throw Exception('No data');
      if (resp.data['error'] != null) throw Exception(resp.data['error']);
      final List raw = resp.data['images'] ?? [];
      final list = raw.map<GalleryImage>((m) {
        return GalleryImage(
          id: m['id'] as String,
          imageUrl: m['image_url'] as String?,
          thumbnailUrlSigned: m['thumbnail_url_signed'] as String?,
          prompt: m['prompt'] as String?,
          createdAt: DateTime.parse(m['created_at'] as String),
          userId: m['user_id'] as String?,
          likeCount: (m['like_count'] ?? 0) as int,
          isLikedByCurrentUser: (m['is_liked_by_current_user'] ?? false) as bool,
        );
      }).toList();
      if (mounted) setState(() => _images = list);
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not load gallery: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike(String id) async {
    if (_likeBusy.contains(id)) return;
    final i = _images.indexWhere((img) => img.id == id);
    if (i < 0) return;
    setState(() => _likeBusy.add(id));
    final original = _images[i];
    final wasLiked = original.isLikedByCurrentUser;
    setState(() {
      _images[i] = original.copyWith(
        likeCount: wasLiked ? original.likeCount - 1 : original.likeCount + 1,
        isLikedByCurrentUser: !wasLiked,
      );
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      if (wasLiked) {
        await Supabase.instance.client
            .from('gallery_likes')
            .delete()
            .match({'gallery_image_id': id, 'user_id': user.id});
      } else {
        await Supabase.instance.client
            .from('gallery_likes')
            .insert({'gallery_image_id': id, 'user_id': user.id});
      }
    } catch (_) {
      if (mounted) {
        setState(() => _images[i] = original);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update like — try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _likeBusy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VSResponsiveLayout(
        child: Column(
          children: [
            _tabs(),
            Expanded(
              child: TabBarView(
                controller: _tab,
                children: [
                  _gallery(isMine: false),
                  _gallery(isMine: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tabs() {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: VSResponsive.getResponsiveMargin(context).add(
        const EdgeInsets.symmetric(vertical: VSDesignTokens.space4),
      ),
      padding: const EdgeInsets.all(VSDesignTokens.space1),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: TabBar(
        controller: _tab,
        labelColor: cs.onPrimary,
        unselectedLabelColor: cs.onSurfaceVariant,
        dividerColor: Colors.transparent,
        splashBorderRadius: BorderRadius.circular(VSDesignTokens.radiusL),
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusL),
          gradient: LinearGradient(
            colors: [cs.primary, cs.secondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: cs.primary.withValues(alpha: 0.4),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        labelStyle: const TextStyle(fontWeight: VSTypography.weightBold),
        tabs: const [
          Tab(text: 'Discover'),
          Tab(text: 'My gallery'),
        ],
      ),
    );
  }

  Widget _gallery({required bool isMine}) {
    final cs = Theme.of(context).colorScheme;
    if (_loading) {
      return Center(child: VSLoadingIndicator(message: 'Loading gallery…'));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: VSResponsive.getResponsiveMargin(context),
          child: VSCard(
            padding: const EdgeInsets.all(VSDesignTokens.space6),
            color: cs.errorContainer,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline_rounded,
                    color: cs.onErrorContainer, size: VSDesignTokens.iconL),
                const SizedBox(height: VSDesignTokens.space3),
                Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: VSDesignTokens.space5),
                VSButton(
                  text: 'Try again',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () => _fetch(refresh: true),
                  variant: VSButtonVariant.danger,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final me = Supabase.instance.client.auth.currentUser?.id;
    final list = isMine ? _images.where((i) => i.userId == me).toList() : _images;

    if (list.isEmpty) {
      return Center(
        child: VSEmptyState(
          icon: isMine
              ? Icons.add_photo_alternate_outlined
              : Icons.photo_library_outlined,
          title: isMine
              ? 'You haven\'t shared any creations yet'
              : 'The gallery is empty',
          subtitle: isMine
              ? 'Generate or enhance an image, then share it.'
              : 'Check back soon — new creations land here.',
        ),
      );
    }

    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () => _fetch(refresh: true),
      child: VSResponsiveGrid(
        mobileColumns: 2,
        tabletColumns: 3,
        desktopColumns: 4,
        padding: VSResponsive.getResponsivePadding(context),
        childAspectRatio: 0.72,
        children: [for (final img in list) _Tile(image: img, onLike: _toggleLike, busyLike: _likeBusy.contains(img.id))],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final GalleryImage image;
  final ValueChanged<String> onLike;
  final bool busyLike;
  const _Tile({required this.image, required this.onLike, required this.busyLike});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return VSAccessibleCard(
      onTap: () => GalleryImageDetailDialog.show(context, image),
      semanticLabel: 'Gallery image. Prompt: ${image.prompt ?? 'none'}.',
      semanticHint: 'Tap to open',
      padding: EdgeInsets.zero,
      borderRadius: VSDesignTokens.radiusL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.outlineVariant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Hero(
            tag: image.id,
            child: AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(VSDesignTokens.radiusL),
                ),
                child: image.imageUrl == null && image.thumbnailUrlSigned == null
                    ? Container(color: cs.surfaceContainerHigh)
                    : CachedNetworkImage(
                        imageUrl: image.thumbnailUrlSigned ?? image.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: cs.surfaceContainerHigh,
                          child: Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: cs.primary,
                              ),
                            ),
                          ),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: cs.errorContainer.withValues(alpha: 0.5),
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: cs.error,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Flexible(
            child: Padding(
              padding: const EdgeInsets.all(VSDesignTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      (image.prompt?.isNotEmpty ?? false)
                          ? image.prompt!
                          : 'No prompt',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: tt.bodySmall?.copyWith(
                        color: (image.prompt?.isNotEmpty ?? false)
                            ? cs.onSurface
                            : cs.onSurfaceVariant.withValues(alpha: 0.7),
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _ago(image.createdAt),
                          style: tt.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                      _LikePill(image: image, onLike: onLike, busy: busyLike),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inDays > 0) return '${d.inDays}d';
    if (d.inHours > 0) return '${d.inHours}h';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return 'now';
  }
}

class _LikePill extends StatelessWidget {
  final GalleryImage image;
  final ValueChanged<String> onLike;
  final bool busy;
  const _LikePill({required this.image, required this.onLike, required this.busy});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final liked = image.isLikedByCurrentUser;
    return Material(
      color: liked
          ? cs.primaryContainer.withValues(alpha: 0.45)
          : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(VSDesignTokens.radiusRound),
      child: InkWell(
        onTap: busy ? null : () => onLike(image.id),
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusRound),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space3,
            vertical: 4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (busy)
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                )
              else
                Icon(
                  liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  size: 14,
                  color: liked ? cs.primary : cs.onSurfaceVariant,
                ),
              const SizedBox(width: 4),
              Text(
                '${image.likeCount}',
                style: tt.labelSmall?.copyWith(
                  fontWeight: VSTypography.weightSemiBold,
                  color: liked ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
