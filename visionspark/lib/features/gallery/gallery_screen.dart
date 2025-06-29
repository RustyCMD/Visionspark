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
      appBar: AppBar(
        toolbarHeight: 0, // Keeps app bar minimal, only showing the TabBar below
        bottom: TabBar(
          controller: _tabController,
          labelColor: colorScheme.primary, // Active tab text color
          unselectedLabelColor: colorScheme.onSurfaceVariant, // Inactive tab text color
          indicatorColor: colorScheme.primary, // Indicator line color
          tabs: const [Tab(text: 'All'), Tab(text: 'My Creations')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGalleryBody(isMyCreations: false),
          _buildGalleryBody(isMyCreations: true),
        ],
      ),
    );
  }

  Widget _buildGalleryBody({required bool isMyCreations}) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (_isLoading) return Center(child: CircularProgressIndicator(color: colorScheme.primary));
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            _errorMessage!,
            textAlign: TextAlign.center,
            style: textTheme.titleMedium?.copyWith(color: colorScheme.error),
          ),
        ),
      );
    }
    
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final imagesToShow = isMyCreations ? _galleryImages.where((img) => img.userId == currentUserId).toList() : _galleryImages;

    if (imagesToShow.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 64, color: colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              isMyCreations ? "You haven't created any images yet." : 'The gallery is empty.',
              style: textTheme.titleLarge?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: colorScheme.primary, // Color of the refresh indicator
      onRefresh: () => _fetchGalleryImages(isRefresh: true),
      child: GridView.builder(
        padding: const EdgeInsets.all(12.0), // Slightly reduced padding
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12.0, // Slightly reduced spacing
          mainAxisSpacing: 12.0,  // Slightly reduced spacing
          childAspectRatio: 0.70, // Adjusted for potentially better fit with new card style
        ),
        itemCount: imagesToShow.length,
        itemBuilder: (context, index) => _buildImageCard(imagesToShow[index]),
      ),
    );
  }

  Widget _buildImageCard(GalleryImage image) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), // Slightly smaller radius
      color: colorScheme.surfaceContainerLow, // Use a themed surface color for cards
      child: InkWell(
        onTap: () => GalleryImageDetailDialog.show(context, image),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: image.id,
              child: AspectRatio(
                aspectRatio: 1, // Square image preview
                child: CachedNetworkImage(
                  imageUrl: image.thumbnailUrlSigned ?? image.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: colorScheme.surfaceVariant.withOpacity(0.5)),
                  errorWidget: (context, url, error) => Center(child: Icon(Icons.broken_image, size: 40, color: colorScheme.onSurfaceVariant.withOpacity(0.7))),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10.0), // Adjusted padding
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween, // Ensure like button is at bottom
                  children: [
                    Text(
                      image.prompt ?? 'No prompt provided.',
                      style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                      maxLines: 3, // Keep max lines
                      overflow: TextOverflow.ellipsis,
                    ),
                    // Spacer removed to allow MainAxisAlignment.spaceBetween to work
                    Align(
                      alignment: Alignment.bottomRight,
                      child: _buildLikeButton(image),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLikeButton(GalleryImage image) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isProcessing = _likeProcessing.contains(image.id);

    return Material(
      color: Colors.transparent, // Keep transparent for InkWell effect
      child: InkWell(
        onTap: isProcessing ? null : () => _toggleLike(image.id),
        borderRadius: BorderRadius.circular(20),
        splashColor: colorScheme.primary.withOpacity(0.12),
        highlightColor: colorScheme.primary.withOpacity(0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), // Adjusted padding
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isProcessing
                  ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))
                  : Icon(
                      image.isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
                      color: image.isLikedByCurrentUser ? colorScheme.primary : colorScheme.onSurfaceVariant.withOpacity(0.7),
                      size: 20,
                    ),
              const SizedBox(width: 6),
              Text(
                '${image.likeCount}',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurfaceVariant.withOpacity(0.9)
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}