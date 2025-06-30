import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './gallery_image_detail_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';

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

class _GalleryScreenState extends State<GalleryScreen> with SingleTickerProviderStateMixin {
  List<GalleryImage> _galleryImages = [];
  bool _isLoading = true;
  String? _errorMessage;
  late TabController _tabController;
  final Set<String> _likeProcessing = {};
  
  // Throttle refresh to prevent spamming the backend
  Timer? _throttleTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      _fetchGalleryImages();
    });
    _fetchGalleryImages();
  }

  @override
  void dispose() {
    _throttleTimer?.cancel();
    _tabController.dispose();
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
      
      if (mounted) setState(() => _galleryImages = fetchedImages);
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

    // Optimistic UI update
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
      // Revert UI on error
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
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainer.withOpacity(0.3),
            ],
          ),
        ),
        child: Column(
          children: [
            // Custom tab bar with modern design
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer.withOpacity(0.8),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: TabBar(
                controller: _tabController,
                indicator: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: colorScheme.onPrimary,
                unselectedLabelColor: colorScheme.onSurface.withOpacity(0.7),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 16,
                ),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(text: 'Explore'),
                  Tab(text: 'My Gallery'),
                ],
              ),
            ),
            
            // Tab bar view content
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildModernGalleryBody(isMyCreations: false),
                  _buildModernGalleryBody(isMyCreations: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModernGalleryBody({required bool isMyCreations}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: colorScheme.primary,
              strokeWidth: 3,
            ),
            const SizedBox(height: 16),
            Text(
              'Loading gallery...',
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
                Icons.error_outline_rounded,
                size: 48,
                color: colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                'Oops! Something went wrong',
                style: textTheme.titleLarge?.copyWith(
                  color: colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
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
      return Center(
        child: Container(
          margin: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer.withOpacity(0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isMyCreations ? Icons.add_photo_alternate_rounded : Icons.photo_library_outlined,
                  size: 60,
                  color: colorScheme.onSurface.withOpacity(0.4),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                isMyCreations ? "No creations yet" : 'Gallery is empty',
                style: textTheme.headlineSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isMyCreations 
                  ? "Your amazing creations will appear here"
                  : 'Be the first to share something beautiful',
                style: textTheme.bodyLarge?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.6),
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
      backgroundColor: colorScheme.surface,
      onRefresh: () => _fetchGalleryImages(isRefresh: true),
      child: GridView.builder(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16,
          mainAxisSpacing: 16,
          childAspectRatio: 0.75,
        ),
        itemCount: imagesToShow.length,
        itemBuilder: (context, index) => _buildModernImageCard(imagesToShow[index]),
      ),
    );
  }

  Widget _buildModernImageCard(GalleryImage image) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 20,
            offset: const Offset(0, 8),
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
                  margin: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: colorScheme.shadow.withOpacity(0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Hero(
                      tag: image.id,
                      child: CachedNetworkImage(
                        imageUrl: image.thumbnailUrlSigned ?? image.imageUrl,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        placeholder: (context, url) => Container(
                          color: colorScheme.surfaceContainer.withOpacity(0.5),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: colorScheme.primary,
                              strokeWidth: 2,
                            ),
                          ),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: colorScheme.surfaceContainer,
                          child: Center(
                            child: Icon(
                              Icons.broken_image_rounded,
                              size: 40,
                              color: colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                        ),
                      ),
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
                          image.prompt ?? 'No prompt provided.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurface.withOpacity(0.8),
                            height: 1.3,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      
                      const SizedBox(height: 12),
                      
                      // Like button
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          _buildModernLikeButton(image),
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
    );
  }

  Widget _buildModernLikeButton(GalleryImage image) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isProcessing = _likeProcessing.contains(image.id);

    return Container(
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
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isProcessing ? null : () => _toggleLike(image.id),
          borderRadius: BorderRadius.circular(20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isProcessing)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              else
                Icon(
                  image.isLikedByCurrentUser ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: image.isLikedByCurrentUser ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.7),
                  size: 18,
                ),
              const SizedBox(width: 6),
              Text(
                '${image.likeCount}',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w600,
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