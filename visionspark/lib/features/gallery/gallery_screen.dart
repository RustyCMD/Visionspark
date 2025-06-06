import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './gallery_image_detail_dialog.dart'; // Import the new dialog
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
  DateTime? _lastRefreshTime;
  Timer? _throttleTimer;
  bool _isThrottled = false;
  late TabController _tabController;
  final Set<String> _likeProcessing = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this, initialIndex: 1);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging || !_tabController.indexIsChanging && _tabController.previousIndex == _tabController.index) return;
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
      final now = DateTime.now();
      if (_lastRefreshTime != null && now.difference(_lastRefreshTime!) < const Duration(seconds: 3)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please wait before refreshing again.')),
          );
        }
        return;
      }
      if (mounted) {
        setState(() {
          _isThrottled = true;
        });
      }
      _throttleTimer?.cancel();
      _throttleTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) {
          setState(() {
            _isThrottled = false;
          });
        }
      });
      _lastRefreshTime = now;
    }

    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');
      
      final isMyCreationsTab = _tabController.index == 1;
      
      final response = await Supabase.instance.client.functions.invoke(
        'get-gallery-feed',
        // Parameters can be added here if the function supports them (e.g., for pagination or filtering)
        // body: {'limit': 20, 'offset': 0, 'filter_user_id': isMyCreationsTab ? user.id : null},
      );

      if (response.data == null) {
        throw Exception('No data received from gallery feed function.');
      }

      final data = response.data;

      if (data['error'] != null) {
        throw Exception('Failed to fetch gallery: ${data['error']}');
      }

      final List imagesData = data['images'] ?? [];
      List<GalleryImage> fetchedImages = [];
      for (var imgMap in imagesData) {
         // Filter for "My Creations" tab on the client-side as well, in case function doesn't filter
        if (isMyCreationsTab && imgMap['user_id'] != user.id) continue;
        if (imgMap['image_url'] == null || (imgMap['image_url'] is String && imgMap['image_url'].isEmpty)) {
            debugPrint("Skipping image ${imgMap['id']} due to missing or empty image_url.");
            continue;
        }
        
        fetchedImages.add(GalleryImage(
          id: imgMap['id'],
          imageUrl: imgMap['image_url'],
          thumbnailUrlSigned: imgMap['thumbnail_url_signed'],
          prompt: imgMap['prompt'],
          createdAt: DateTime.parse(imgMap['created_at']),
          userId: imgMap['user_id'],
          likeCount: imgMap['like_count'] ?? 0,
          isLikedByCurrentUser: imgMap['is_liked_by_current_user'] ?? false,
        ));
      }
      if (mounted) {
        setState(() {
          _galleryImages = fetchedImages;
        });
      }
    } catch (e) { // Simplified catch block
      debugPrint('Error fetching gallery images: ${e.toString()}');
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to fetch gallery images: ${e.toString()}';
        });
      }
    }
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleLike(GalleryImage image, int index) async {
    if (_likeProcessing.contains(image.id)) return;
    if (mounted) {
      setState(() { _likeProcessing.add(image.id); });
    }
    
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
       if (mounted) setState(() { _likeProcessing.remove(image.id); });
       return;
    }
    final wasLiked = image.isLikedByCurrentUser;
    
    // Optimistic update
    if (mounted) {
      setState(() {
        _galleryImages[index] = GalleryImage(
          id: image.id,
          imageUrl: image.imageUrl,
          thumbnailUrlSigned: image.thumbnailUrlSigned,
          prompt: image.prompt,
          createdAt: image.createdAt,
          userId: image.userId,
          likeCount: wasLiked ? image.likeCount - 1 : image.likeCount + 1,
          isLikedByCurrentUser: !wasLiked,
        );
      });
    }

    try {
      if (!wasLiked) {
        await Supabase.instance.client
            .from('gallery_likes')
            .insert({'user_id': user.id, 'gallery_image_id': image.id});
      } else {
        await Supabase.instance.client
            .from('gallery_likes')
            .delete()
            .eq('user_id', user.id)
            .eq('gallery_image_id', image.id);
      }
    } catch (e) {
      // Revert UI on error
      if (mounted) {
        setState(() {
          _galleryImages[index] = GalleryImage( // Revert to original state
            id: image.id,
            imageUrl: image.imageUrl,
            thumbnailUrlSigned: image.thumbnailUrlSigned,
            prompt: image.prompt,
            createdAt: image.createdAt,
            userId: image.userId,
            likeCount: image.likeCount, // Original like count
            isLikedByCurrentUser: wasLiked, // Original liked status
          );
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update like: ${e.toString()}')),
        );
      }
    }
    if (mounted) {
      setState(() { _likeProcessing.remove(image.id); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lilacPurple = colorScheme.primary;
    // Unused variables removed:
    // final mutedPeach = colorScheme.error.withAlpha((255 * 0.12).round());
    // final darkText = colorScheme.onSurface; 
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        toolbarHeight: 0,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: TabBar(
            controller: _tabController,
            labelColor: lilacPurple,
            unselectedLabelColor: colorScheme.onSurface, // Used colorScheme.onSurface directly
            indicatorColor: lilacPurple,
            labelPadding: EdgeInsets.zero,
            tabs: const [
              Tab(text: 'All'),
              Tab(text: 'My Creations'),
            ],
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildGalleryBody(isMyCreations: false),
          _buildGalleryBody(isMyCreations: true),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isThrottled ? null : () => _fetchGalleryImages(isRefresh: true),
        backgroundColor: lilacPurple,
        tooltip: 'Refresh Gallery',
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }

  Widget _buildGalleryBody({required bool isMyCreations}) {
    final colorScheme = Theme.of(context).colorScheme;
    final lilacPurple = colorScheme.primary;
    // Unused variables removed:
    // final mutedPeach = colorScheme.error.withAlpha((255 * 0.12).round());
    // final darkText = colorScheme.onSurface;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_errorMessage!, style: TextStyle(color: colorScheme.error, fontSize: 16), textAlign: TextAlign.center,),
        ),
      );
    }
    final currentImages = isMyCreations 
        ? _galleryImages.where((img) => img.userId == Supabase.instance.client.auth.currentUser?.id).toList()
        : _galleryImages;

    if (currentImages.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          margin: const EdgeInsets.all(24), // Added margin for better appearance
          decoration: BoxDecoration(
            color: colorScheme.primary.withAlpha((255 * 0.1).round()),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            isMyCreations
                ? "You haven't created any images yet. Start creating!"
                : 'The gallery is empty. Share some images!',
            style: TextStyle(
              fontSize: 20,
              color: colorScheme.onSurface.withAlpha((255 * 0.7).round()),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _fetchGalleryImages(isRefresh: true),
      backgroundColor: colorScheme.surface, // Use theme surface color
      color: lilacPurple, // Use primary color
      child: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
          childAspectRatio: 0.95, // Adjusted for better item proportions
        ),
        itemCount: currentImages.length,
        itemBuilder: (context, index) {
          final galleryItem = currentImages[index];
          return Card(
            elevation: 4,
            color: colorScheme.surface,
            shadowColor: lilacPurple.withAlpha((255 * 0.10).round()),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Stack(
              children: [
                InkWell(
                  onTap: () {
                    if (mounted) { // Guard showDialog with mounted check
                        GalleryImageDetailDialog.show(context, galleryItem);
                    }
                  },
                  child: GridTile(
                    footer: galleryItem.prompt != null && galleryItem.prompt!.isNotEmpty
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: lilacPurple.withAlpha((255 * 0.7).round()),
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(20), // Match card radius
                                bottomRight: Radius.circular(20), // Match card radius
                              ),
                            ),
                            child: Text(
                              galleryItem.prompt!,
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          )
                        : null,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20), // Ensure image also has rounded corners
                      child: CachedNetworkImage(
                        imageUrl: (galleryItem.thumbnailUrlSigned != null && galleryItem.thumbnailUrlSigned!.isNotEmpty)
                            ? galleryItem.thumbnailUrlSigned!
                            : galleryItem.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: colorScheme.surface.withAlpha((255 * 0.5).round()), // Lighter placeholder
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => const Center(child: Icon(Icons.broken_image, size: 40)),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 12,
                  child: GestureDetector(
                    onTap: _likeProcessing.contains(galleryItem.id) ? null : () => _toggleLike(galleryItem, _galleryImages.indexOf(galleryItem) /* find original index */),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Container(
                        key: ValueKey('${galleryItem.isLikedByCurrentUser}_${galleryItem.likeCount}'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withAlpha((255 * 0.85).round()), // Slightly transparent for depth
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withAlpha((255 * 0.08).round()),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _likeProcessing.contains(galleryItem.id)
                                ? SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))
                                : Icon(
                                    galleryItem.isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
                                    color: galleryItem.isLikedByCurrentUser
                                        ? colorScheme.primary
                                        : colorScheme.onSurface.withAlpha((255 * 0.6).round()),
                                    size: 22,
                                  ),
                            const SizedBox(width: 4),
                            Text(
                              '${galleryItem.likeCount}',
                              style: TextStyle(
                                color: galleryItem.isLikedByCurrentUser
                                    ? colorScheme.primary
                                    : colorScheme.onSurface.withAlpha((255 * 0.8).round()),
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
} 