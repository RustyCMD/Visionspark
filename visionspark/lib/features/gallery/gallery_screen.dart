import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './gallery_image_detail_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../shared/design_system/design_system.dart';

class GalleryImage {
  final String id;
  final String imageUrl;
  final String? thumbnailUrlSigned;
  final String? prompt;
  final DateTime createdAt;
  final String? userId;
  final int likeCount;
  final bool isLikedByCurrentUser;

  GalleryImage({
    required this.id,
    required this.imageUrl,
    this.thumbnailUrlSigned,
    this.prompt,
    required this.createdAt,
    this.userId,
    required this.likeCount,
    required this.isLikedByCurrentUser,
  });

  factory GalleryImage.fromMap(Map<String, dynamic> map, String imageUrl, int likeCount, bool isLikedByCurrentUser) {
    return GalleryImage(
      id: map['id'],
      imageUrl: imageUrl,
      thumbnailUrlSigned: map['thumbnail_url_signed'],
      prompt: map['prompt'],
      createdAt: DateTime.parse(map['created_at']),
      userId: map['user_id'],
      likeCount: likeCount,
      isLikedByCurrentUser: isLikedByCurrentUser,
    );
  }
}

class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> with TickerProviderStateMixin {
  List<GalleryImage> _galleryImages = [];
  bool _isLoading = true;
  String? _errorMessage;
  late TabController _tabController;
  final Set<String> _likeProcessing = {};
  Timer? _throttleTimer;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _fetchGalleryImages();
    });
    
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    
    _fetchGalleryImages();
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _tabController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _fetchGalleryImages({bool isRefresh = false}) async {
    if (isRefresh) {
      if (_throttleTimer?.isActive ?? false) return;
      _throttleTimer = Timer(const Duration(seconds: 5), () {});
    }

    if (mounted) setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');

      final response = await Supabase.instance.client.functions.invoke('get-gallery-feed');
      if (response.data == null) throw Exception('No data received.');
      if (response.data['error'] != null) throw Exception('API Error: ${response.data['error']}');

      final List imagesData = response.data['images'] ?? [];
      final List<GalleryImage> fetchedImages = imagesData.map((imgMap) {
        return GalleryImage(
          id: imgMap['id'],
          imageUrl: imgMap['image_url'],
          thumbnailUrlSigned: imgMap['thumbnail_url_signed'],
          prompt: imgMap['prompt'],
          createdAt: DateTime.parse(imgMap['created_at']),
          userId: imgMap['user_id'],
          likeCount: imgMap['like_count'] ?? 0,
          isLikedByCurrentUser: imgMap['is_liked_by_current_user'] ?? false,
        );
      }).toList();
      
      if (mounted) {
        setState(() => _galleryImages = fetchedImages);
        _animationController.forward();
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Failed to fetch gallery: ${e.toString()}');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _toggleLike(String imageId) async {
    if (_likeProcessing.contains(imageId)) return;
    if (mounted) setState(() => _likeProcessing.add(imageId));

    final index = _galleryImages.indexWhere((img) => img.id == imageId);
    if (index == -1) {
      if (mounted) setState(() => _likeProcessing.remove(imageId));
      return;
    }

    final image = _galleryImages[index];
    final originalImageState = image;
    final wasLiked = image.isLikedByCurrentUser;

    if (mounted) {
      setState(() {
        _galleryImages[index] = GalleryImage(
          id: image.id, imageUrl: image.imageUrl, thumbnailUrlSigned: image.thumbnailUrlSigned,
          prompt: image.prompt, createdAt: image.createdAt, userId: image.userId,
          likeCount: wasLiked ? image.likeCount - 1 : image.likeCount + 1,
          isLikedByCurrentUser: !wasLiked,
        );
      });
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return;
      if (!wasLiked) {
        await Supabase.instance.client.from('gallery_likes').insert({'gallery_image_id': image.id, 'user_id': user.id});
      } else {
        await Supabase.instance.client.from('gallery_likes').delete().match({'gallery_image_id': image.id, 'user_id': user.id});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _galleryImages[index] = originalImageState);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to update like: ${e.toString()}')));
      }
    }
    if (mounted) setState(() => _likeProcessing.remove(imageId));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: VSResponsiveLayout(
        child: Column(
          children: [
            _buildTabSection(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildGalleryBody(isMyCreations: false),
                  _buildGalleryBody(isMyCreations: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      margin: VSResponsive.getResponsiveMargin(context).add(
        const EdgeInsets.symmetric(vertical: VSDesignTokens.space4),
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(VSDesignTokens.radiusL),
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.primary.withValues(alpha: 0.8),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withValues(alpha: 0.3),
              blurRadius: VSDesignTokens.space2,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(VSDesignTokens.space1),
        labelStyle: textTheme.titleMedium?.copyWith(
          fontWeight: VSTypography.weightBold,
        ),
        unselectedLabelStyle: textTheme.titleMedium?.copyWith(
          fontWeight: VSTypography.weightMedium,
        ),
        tabs: const [
          Tab(text: 'Discover'),
          Tab(text: 'My Gallery'),
        ],
      ),
    );
  }

  Widget _buildGalleryBody({required bool isMyCreations}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return Center(
        child: VSLoadingIndicator(
          message: 'Loading gallery...',
          size: VSDesignTokens.iconXL,
        ),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: VSCard(
          margin: VSResponsive.getResponsiveMargin(context),
          padding: const EdgeInsets.all(VSDesignTokens.space6),
          color: colorScheme.errorContainer.withValues(alpha: 0.1),
          border: Border.all(
            color: colorScheme.error.withValues(alpha: 0.3),
            width: 1,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: VSDesignTokens.iconXXL,
                color: colorScheme.error,
              ),
              const SizedBox(height: VSDesignTokens.space4),
              VSResponsiveText(
                text: 'Oops! Something went wrong',
                baseStyle: textTheme.titleLarge?.copyWith(
                  color: colorScheme.onErrorContainer,
                  fontWeight: VSTypography.weightBold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: VSDesignTokens.space2),
              Text(
                _errorMessage!,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onErrorContainer.withValues(alpha: 0.8),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: VSDesignTokens.space6),
              VSButton(
                text: 'Try Again',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => _fetchGalleryImages(isRefresh: true),
                variant: VSButtonVariant.danger,
                isFullWidth: true,
              ),
            ],
          ),
        ),
      );
    }
    
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final imagesToShow = isMyCreations 
        ? _galleryImages.where((img) => img.userId == currentUserId).toList() 
        : _galleryImages;

    if (imagesToShow.isEmpty) {
      return Center(
        child: VSEmptyState(
          icon: isMyCreations ? Icons.add_photo_alternate_outlined : Icons.photo_library_outlined,
          title: isMyCreations ? "You haven't created any images yet." : 'The gallery is empty.',
          subtitle: isMyCreations
            ? 'Start creating amazing images with AI!'
            : 'Check back later for new creations.',
        ),
      );
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      onRefresh: () => _fetchGalleryImages(isRefresh: true),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: VSResponsiveGrid(
          mobileColumns: 2,
          tabletColumns: 3,
          desktopColumns: 4,
          mainAxisSpacing: VSDesignTokens.space4,
          crossAxisSpacing: VSDesignTokens.space4,
          padding: VSResponsive.getResponsivePadding(context),
          childAspectRatio: 0.65, // Adjusted to provide sufficient space for text content below image
          children: List.generate(imagesToShow.length, (index) {
            return _buildImageCard(imagesToShow[index], index);
          }),
        ),
      ),
    );
  }

  Widget _buildImageCard(GalleryImage image, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return VSAccessibleCard(
      onTap: () => GalleryImageDetailDialog.show(context, image),
      semanticLabel: 'Gallery image${image.prompt != null ? ": ${image.prompt}" : ""}',
      semanticHint: 'Tap to view full image and details',
      padding: EdgeInsets.zero,
      elevation: VSDesignTokens.elevation2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Image section with fixed aspect ratio
          Hero(
            tag: image.id,
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer.withValues(alpha: 0.3),
                ),
                child: CachedNetworkImage(
                  imageUrl: image.thumbnailUrlSigned ?? image.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          colorScheme.surfaceContainer.withValues(alpha: 0.3),
                          colorScheme.surfaceContainer.withValues(alpha: 0.1),
                        ],
                      ),
                    ),
                    child: Center(
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      ),
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.1),
                    ),
                    child: Center(
                      child: Icon(
                        Icons.broken_image_rounded,
                        size: 32,
                        color: colorScheme.error.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Content section with flexible sizing to prevent overflow
          Flexible(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(VSDesignTokens.space3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Prompt text with constrained height
                  Flexible(
                    child: image.prompt != null && image.prompt!.isNotEmpty
                      ? Text(
                          image.prompt!,
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            height: 1.2,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Text(
                          'No prompt available',
                          style: textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            fontStyle: FontStyle.italic,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  ),
                  const SizedBox(height: VSDesignTokens.space2),
                  // Bottom row with time and like button
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatTimeAgo(image.createdAt),
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: VSDesignTokens.space2),
                      _buildLikeButton(image),
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

  Widget _buildLikeButton(GalleryImage image) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isProcessing = _likeProcessing.contains(image.id);

    return VSAccessibleButton(
      onPressed: isProcessing ? null : () => _toggleLike(image.id),
      semanticLabel: image.isLikedByCurrentUser
        ? 'Unlike image. Currently ${image.likeCount} likes'
        : 'Like image. Currently ${image.likeCount} likes',
      backgroundColor: image.isLikedByCurrentUser
        ? colorScheme.primaryContainer.withValues(alpha: 0.3)
        : colorScheme.surfaceContainer.withValues(alpha: 0.5),
      borderRadius: VSDesignTokens.radiusXL,
      padding: const EdgeInsets.symmetric(
        horizontal: VSDesignTokens.space3,
        vertical: VSDesignTokens.space1,
      ),
      child: IntrinsicWidth(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isProcessing)
              SizedBox(
                width: VSDesignTokens.iconXS,
                height: VSDesignTokens.iconXS,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              )
            else
              Icon(
                image.isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
                color: image.isLikedByCurrentUser
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                size: VSDesignTokens.iconXS,
              ),
            const SizedBox(width: VSDesignTokens.space1),
            Flexible(
              child: Text(
                '${image.likeCount}',
                style: textTheme.labelSmall?.copyWith(
                  fontWeight: VSTypography.weightSemiBold,
                  color: image.isLikedByCurrentUser
                    ? colorScheme.onPrimaryContainer
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}