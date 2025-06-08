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
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        bottom: TabBar(
          controller: _tabController,
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
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_errorMessage != null) return Center(child: Padding(padding: const EdgeInsets.all(16.0), child: Text(_errorMessage!, textAlign: TextAlign.center)));
    
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final imagesToShow = isMyCreations ? _galleryImages.where((img) => img.userId == currentUserId).toList() : _galleryImages;

    if (imagesToShow.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.photo_library_outlined, size: 64, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              isMyCreations ? "You haven't created any images yet." : 'The gallery is empty.',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchGalleryImages(isRefresh: true),
      child: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
          childAspectRatio: 0.67, // Further adjusted to resolve remaining overflow
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => GalleryImageDetailDialog.show(context, image),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Hero(
              tag: image.id,
              child: AspectRatio(
                aspectRatio: 1,
                child: CachedNetworkImage(
                  imageUrl: image.thumbnailUrlSigned ?? image.imageUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(color: colorScheme.surfaceVariant),
                  errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image, size: 40)),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      image.prompt ?? 'No prompt provided.',
                      style: textTheme.bodySmall,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(), // Pushes the like button to the bottom
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
    final isProcessing = _likeProcessing.contains(image.id);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isProcessing ? null : () => _toggleLike(image.id),
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              isProcessing
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(
                      image.isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
                      color: image.isLikedByCurrentUser ? colorScheme.primary : colorScheme.onSurface.withOpacity(0.7),
                      size: 20,
                    ),
              const SizedBox(width: 6),
              Text(
                '${image.likeCount}',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.onSurface.withOpacity(0.9)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}