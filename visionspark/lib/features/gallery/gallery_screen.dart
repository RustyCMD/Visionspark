import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import './gallery_image_detail_dialog.dart'; // Import the new dialog
import 'package:cached_network_image/cached_network_image.dart';

class GalleryImage {
  final String id;
  final String imageUrl;
  final String? prompt;
  final DateTime createdAt;
  final String? userId;
  final int likeCount;
  final bool isLikedByCurrentUser;

  GalleryImage({
    required this.id,
    required this.imageUrl,
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
      final now = DateTime.now();
      if (_lastRefreshTime != null && now.difference(_lastRefreshTime!) < const Duration(seconds: 3)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please wait before refreshing again.')),
          );
        }
        return;
      }
      setState(() {
        _isThrottled = true;
      });
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

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not authenticated');
      
      final isMyCreations = _tabController.index == 1;
      
      final response = await Supabase.instance.client.functions.invoke(
        'get-gallery-feed',
      );

      if (response.data == null) {
        throw Exception('No data received from gallery feed function.');
      }

      final data = response.data;

      if (data['error'] != null) {
        throw Exception('Failed to fetch gallery: ${data['error']}');
      }

      final List images = data['images'] ?? [];
      List<GalleryImage> fetchedImages = [];
      for (var img in images) {
        if (isMyCreations && img['user_id'] != user.id) continue;
        if (img['image_url'] == null) continue;
        fetchedImages.add(GalleryImage(
          id: img['id'],
          imageUrl: img['image_url'],
          prompt: img['prompt'],
          createdAt: DateTime.parse(img['created_at']),
          userId: img['user_id'],
          likeCount: img['like_count'] ?? 0,
          isLikedByCurrentUser: img['is_liked_by_current_user'] ?? false,
        ));
      }
      if (mounted) {
        setState(() {
          _galleryImages = fetchedImages;
        });
      }
    } on FunctionsException catch (e) {
      debugPrint('Error fetching gallery images (FunctionsException): ${e.message}, Details: ${e.details}');
      if (mounted) {
        final errorDetails = e.details is Map ? e.details as Map : {};
        setState(() {
          _errorMessage = 'Failed to fetch gallery: ${errorDetails['error'] ?? e.message}';
        });
      }
    } catch (e) {
      debugPrint('Error fetching gallery images (General): $e');
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
    if (_likeProcessing.contains(image.id)) return; // Prevent spamming
    setState(() { _likeProcessing.add(image.id); });
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;
    final wasLiked = image.isLikedByCurrentUser;
    setState(() {
      _galleryImages[index] = GalleryImage(
        id: image.id,
        imageUrl: image.imageUrl,
        prompt: image.prompt,
        createdAt: image.createdAt,
        userId: image.userId,
        likeCount: wasLiked ? image.likeCount - 1 : image.likeCount + 1,
        isLikedByCurrentUser: !wasLiked,
      );
    });
    try {
      if (!wasLiked) {
        await Supabase.instance.client
            .from('gallery_likes')
            .insert({
              'user_id': user.id,
              'gallery_image_id': image.id,
            });
      } else {
        await Supabase.instance.client
            .from('gallery_likes')
            .delete()
            .eq('user_id', user.id)
            .eq('gallery_image_id', image.id);
      }
    } catch (e) {
      // Revert UI on error
      setState(() {
        _galleryImages[index] = GalleryImage(
          id: image.id,
          imageUrl: image.imageUrl,
          prompt: image.prompt,
          createdAt: image.createdAt,
          userId: image.userId,
          likeCount: image.likeCount,
          isLikedByCurrentUser: wasLiked,
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update like: $e')),
      );
    }
    if (mounted) setState(() { _likeProcessing.remove(image.id); });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final lilacPurple = colorScheme.primary;
    final mutedPeach = colorScheme.error.withOpacity(0.12);
    final darkText = colorScheme.onSurface;
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
            unselectedLabelColor: darkText,
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
        child: Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }

  Widget _buildGalleryBody({required bool isMyCreations}) {
    final colorScheme = Theme.of(context).colorScheme;
    final lilacPurple = colorScheme.primary;
    final mutedPeach = colorScheme.error.withOpacity(0.12);
    final darkText = colorScheme.onSurface;
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
    if (_galleryImages.isEmpty) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            isMyCreations
                ? "You haven't created any images yet. Start creating!"
                : 'The gallery is empty. Share some images!',
            style: TextStyle(
              fontSize: 20,
              color: colorScheme.onSurface.withOpacity(0.7),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () => _fetchGalleryImages(isRefresh: true),
      backgroundColor: Colors.white,
      color: lilacPurple.withValues(alpha: 179),
      child: GridView.builder(
        padding: const EdgeInsets.all(16.0),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 16.0,
          mainAxisSpacing: 16.0,
          childAspectRatio: 0.95,
        ),
        itemCount: _galleryImages.length,
        itemBuilder: (context, index) {
          final galleryItem = _galleryImages[index];
          return Card(
            elevation: 4,
            color: colorScheme.surface,
            shadowColor: lilacPurple.withOpacity(0.10),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Stack(
              children: [
                InkWell(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (BuildContext context) {
                        return GalleryImageDetailDialog(galleryItem: galleryItem);
                      },
                    );
                  },
                  child: GridTile(
                    footer: galleryItem.prompt != null && galleryItem.prompt!.isNotEmpty
                        ? Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: lilacPurple.withOpacity(0.7),
                              borderRadius: const BorderRadius.only(
                                bottomLeft: Radius.circular(20),
                                bottomRight: Radius.circular(20),
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
                      borderRadius: BorderRadius.circular(20),
                      child: CachedNetworkImage(
                        imageUrl: galleryItem.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: colorScheme.surface,
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
                    onTap: _likeProcessing.contains(galleryItem.id) ? null : () => _toggleLike(galleryItem, index),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      transitionBuilder: (child, anim) => ScaleTransition(scale: anim, child: child),
                      child: Container(
                        key: ValueKey('${galleryItem.isLikedByCurrentUser}_${galleryItem.likeCount}'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
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
                                        : colorScheme.onSurface.withOpacity(0.6),
                                    size: 22,
                                  ),
                            const SizedBox(width: 4),
                            Text(
                              '${galleryItem.likeCount}',
                              style: TextStyle(
                                color: galleryItem.isLikedByCurrentUser
                                    ? colorScheme.primary
                                    : colorScheme.onSurface.withOpacity(0.8),
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