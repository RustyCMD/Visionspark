import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './gallery_image_detail_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    
    return Scaffold(
      body: Column(
        children: [
          _buildTabSection(colorScheme, size),
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
    );
  }

  Widget _buildTabSection(ColorScheme colorScheme, Size size) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: size.width * 0.06,
        vertical: size.height * 0.02,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withOpacity(0.6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: colorScheme.onPrimary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.primary.withOpacity(0.8),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        padding: const EdgeInsets.all(4),
        labelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 16,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 16,
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
    final size = MediaQuery.of(context).size;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'Loading gallery...',
              style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Container(
          margin: EdgeInsets.all(size.width * 0.06),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: colorScheme.error.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(color: colorScheme.error),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _fetchGalleryImages(isRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.error,
                  foregroundColor: colorScheme.onError,
                ),
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
        child: Container(
          margin: EdgeInsets.all(size.width * 0.06),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMyCreations ? Icons.add_photo_alternate_outlined : Icons.photo_library_outlined,
                  size: 48,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isMyCreations ? "You haven't created any images yet." : 'The gallery is empty.',
                style: textTheme.titleLarge?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isMyCreations 
                    ? 'Start creating amazing images with AI!'
                    : 'Check back later for new creations.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      onRefresh: () => _fetchGalleryImages(isRefresh: true),
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: StaggeredGrid.count(
            crossAxisCount: 2,
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: List.generate(imagesToShow.length, (index) {
              return StaggeredGridTile.fit(
                crossAxisExtent: MediaQuery.of(context).size.width / 2 - 24,
                child: _buildImageCard(imagesToShow[index], index),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildImageCard(GalleryImage image, int index) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final size = MediaQuery.of(context).size;
    
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => GalleryImageDetailDialog.show(context, image),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Hero(
                  tag: image.id,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainer.withOpacity(0.3),
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
                              colorScheme.surfaceContainer.withOpacity(0.3),
                              colorScheme.surfaceContainer.withOpacity(0.1),
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
                          color: colorScheme.errorContainer.withOpacity(0.1),
                        ),
                        child: Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            size: 32,
                            color: colorScheme.error.withOpacity(0.6),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (image.prompt != null && image.prompt!.isNotEmpty)
                      Text(
                        image.prompt!,
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      )
                    else
                      Text(
                        'No prompt available',
                        style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant.withOpacity(0.6),
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          _formatTimeAgo(image.createdAt),
                          style: textTheme.labelSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                          ),
                        ),
                        _buildLikeButton(image),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLikeButton(GalleryImage image) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isProcessing = _likeProcessing.contains(image.id);

    return Container(
      decoration: BoxDecoration(
        color: image.isLikedByCurrentUser 
            ? colorScheme.primaryContainer.withOpacity(0.3)
            : colorScheme.surfaceContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isProcessing ? null : () => _toggleLike(image.id),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isProcessing)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  )
                else
                  Icon(
                    image.isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
                    color: image.isLikedByCurrentUser 
                        ? colorScheme.primary 
                        : colorScheme.onSurfaceVariant.withOpacity(0.7),
                    size: 16,
                  ),
                const SizedBox(width: 6),
                Text(
                  '${image.likeCount}',
                  style: textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: image.isLikedByCurrentUser 
                        ? colorScheme.onPrimaryContainer 
                        : colorScheme.onSurfaceVariant.withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
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