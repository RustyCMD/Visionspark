import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './gallery_image_detail_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'dart:math' as math;

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
  
  late AnimationController _staggerController;
  late List<Animation<double>> _cardAnimations;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _fetchGalleryImages();
    });
    
    _staggerController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _cardAnimations = List.generate(
      20, // Generate enough animations for initial load
      (index) => Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(
          parent: _staggerController,
          curve: Interval(
            (index * 0.1).clamp(0, 1),
            ((index * 0.1) + 0.3).clamp(0, 1),
            curve: Curves.easeOutCubic,
          ),
        ),
      ),
    );
    
    _fetchGalleryImages();
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _tabController.dispose();
    _staggerController.dispose();
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
        _staggerController.reset();
        _staggerController.forward();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to update like: ${e.toString()}')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
    if (mounted) setState(() => _likeProcessing.remove(imageId));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.4, 1.0],
            colors: [
              colorScheme.surface,
              colorScheme.primary.withOpacity(0.01),
              colorScheme.secondary.withOpacity(0.02),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Custom tab bar with modern design
              _buildCustomTabBar(colorScheme, size),
              
              // Content
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildGalleryBody(isMyCreations: false, colorScheme: colorScheme, size: size),
                    _buildGalleryBody(isMyCreations: true, colorScheme: colorScheme, size: size),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomTabBar(ColorScheme colorScheme, Size size) {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: size.width * 0.06,
        vertical: size.height * 0.02,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(25),
        color: colorScheme.surfaceContainer.withOpacity(0.6),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        labelPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.primary.withOpacity(0.8),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.primary.withOpacity(0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: Colors.white,
        unselectedLabelColor: colorScheme.onSurface.withOpacity(0.6),
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

  Widget _buildGalleryBody({
    required bool isMyCreations,
    required ColorScheme colorScheme,
    required Size size,
  }) {
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: CircularProgressIndicator(
                color: colorScheme.primary,
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Loading amazing creations...',
              style: textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.errorContainer.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: colorScheme.error.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 64,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Oops! Something went wrong',
                style: textTheme.titleLarge?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.error.withOpacity(0.8),
                ),
                textAlign: TextAlign.center,
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
      return _buildEmptyState(isMyCreations, colorScheme, textTheme);
    }

    return RefreshIndicator(
      color: colorScheme.primary,
      backgroundColor: colorScheme.surface,
      onRefresh: () => _fetchGalleryImages(isRefresh: true),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: EdgeInsets.symmetric(
              horizontal: size.width * 0.04,
              vertical: size.height * 0.02,
            ),
            sliver: _buildMasonryGrid(imagesToShow, colorScheme, size),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isMyCreations, ColorScheme colorScheme, TextTheme textTheme) {
    return Center(
      child: Container(
        margin: const EdgeInsets.all(32),
        padding: const EdgeInsets.all(40),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer.withOpacity(0.3),
          borderRadius: BorderRadius.circular(32),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.1),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: colorScheme.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isMyCreations ? Icons.palette_outlined : Icons.explore_off_outlined,
                size: 64,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              isMyCreations ? "Your creative journey awaits!" : 'Nothing to explore yet',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              isMyCreations 
                  ? "Create your first AI masterpiece to see it here"
                  : 'Be the first to share your creativity with the world',
              style: textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasonryGrid(List<GalleryImage> images, ColorScheme colorScheme, Size size) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: size.width * 0.04,
        mainAxisSpacing: size.width * 0.04,
        childAspectRatio: 0.75,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index >= images.length) return null;
          
          final animationIndex = index % _cardAnimations.length;
          return AnimatedBuilder(
            animation: _cardAnimations[animationIndex],
            builder: (context, child) {
              return Transform.translate(
                offset: Offset(0, 30 * (1 - _cardAnimations[animationIndex].value)),
                child: Opacity(
                  opacity: _cardAnimations[animationIndex].value,
                  child: _buildModernImageCard(images[index], colorScheme, index),
                ),
              );
            },
          );
        },
        childCount: images.length,
      ),
    );
  }

  Widget _buildModernImageCard(GalleryImage image, ColorScheme colorScheme, int index) {
    final textTheme = Theme.of(context).textTheme;
    final random = math.Random(image.id.hashCode);
    final cardHeight = 250.0 + (random.nextDouble() * 100); // Vary height for masonry effect

    return Hero(
      tag: image.id,
      child: Container(
        height: cardHeight,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          color: colorScheme.surface,
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: 0,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => GalleryImageDetailDialog.show(context, image),
            borderRadius: BorderRadius.circular(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image section
                Expanded(
                  flex: 3,
                  child: Container(
                    decoration: const BoxDecoration(
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CachedNetworkImage(
                            imageUrl: image.thumbnailUrlSigned ?? image.imageUrl,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    colorScheme.primary.withOpacity(0.1),
                                    colorScheme.secondary.withOpacity(0.1),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: colorScheme.primary,
                                  strokeWidth: 2,
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    colorScheme.errorContainer.withOpacity(0.3),
                                    colorScheme.error.withOpacity(0.1),
                                  ],
                                ),
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 32,
                                  color: colorScheme.error.withOpacity(0.7),
                                ),
                              ),
                            ),
                          ),
                          
                          // Gradient overlay for better text readability
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 60,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.6),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                // Content section
                Expanded(
                  flex: 2,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Prompt text
                        Expanded(
                          child: Text(
                            image.prompt ?? 'AI Generated Artwork',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.8),
                              height: 1.3,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        
                        const SizedBox(height: 12),
                        
                        // Like button and stats
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _buildModernLikeButton(image, colorScheme),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.auto_awesome,
                                    size: 12,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'AI',
                                    style: TextStyle(
                                      color: colorScheme.primary,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernLikeButton(GalleryImage image, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final isProcessing = _likeProcessing.contains(image.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isProcessing ? null : () => _toggleLike(image.id),
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: image.isLikedByCurrentUser 
                ? colorScheme.primary.withOpacity(0.1)
                : colorScheme.surfaceContainer.withOpacity(0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: image.isLikedByCurrentUser 
                  ? colorScheme.primary.withOpacity(0.3)
                  : colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isProcessing
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colorScheme.primary,
                      ),
                    )
                  : Icon(
                      image.isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
                      color: image.isLikedByCurrentUser 
                          ? colorScheme.primary 
                          : colorScheme.onSurface.withOpacity(0.6),
                      size: 16,
                    ),
              const SizedBox(width: 6),
              Text(
                '${image.likeCount}',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: image.isLikedByCurrentUser 
                      ? colorScheme.primary
                      : colorScheme.onSurface.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}