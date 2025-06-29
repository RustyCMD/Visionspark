import 'dart:async';
import 'dart:io'; // Fix: Import for 'Platform'
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import '../../shared/utils/snackbar_utils.dart';
import 'package:provider/provider.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';

const String _kCachedLimit = 'cached_generation_limit';
const String _kCachedGenerationsToday = 'cached_generations_today';
const String _kCachedResetsAt = 'cached_resets_at_utc_iso';

class ImageGeneratorScreen extends StatefulWidget {
  const ImageGeneratorScreen({super.key});

  @override
  State<ImageGeneratorScreen> createState() => _ImageGeneratorScreenState();
}

class _ImageGeneratorScreenState extends State<ImageGeneratorScreen> {
  final _promptController = TextEditingController();
  String? _generatedImageUrl;
  bool _isLoading = false;
  bool _isImproving = false;
  int _generationLimit = 3;
  int _generationsToday = 0;
  String? _resetsAtUtcIso;
  String _timeUntilReset = "Calculating...";
  bool _isLoadingStatus = true;
  String? _statusErrorMessage;
  Timer? _resetTimer;
  bool _isSavingImage = false;
  bool _isSharingToGallery = false;
  bool _isFetchingRandomPrompt = false;
  SubscriptionStatusNotifier? _subscriptionStatusNotifierInstance;

  // For Aspect Ratio Selection
  // DALL-E 3 sizes: 1024x1024 (Square), 1792x1024 (Landscape), 1024x1792 (Portrait)
  final List<String> _aspectRatioLabels = ["Square", "Landscape", "Portrait"];
  final List<String> _aspectRatioValues = ["1024x1024", "1792x1024", "1024x1792"];
  String _selectedAspectRatioValue = "1024x1024"; // Default to square
  String _lastSuccessfulPrompt = ""; // For displaying the last used prompt

  static const MethodChannel _channel = MethodChannel('com.visionspark.app/media');

  @override
  void initState() {
    super.initState();
    _loadCachedGenerationStatus();
    _fetchGenerationStatus();
    // Listener will be added in didChangeDependencies
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateResetsAtDisplay());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final notifier = Provider.of<SubscriptionStatusNotifier>(context, listen: false);
    if (_subscriptionStatusNotifierInstance != notifier) {
      _subscriptionStatusNotifierInstance?.removeListener(_fetchGenerationStatus);
      _subscriptionStatusNotifierInstance = notifier;
      _subscriptionStatusNotifierInstance?.addListener(_fetchGenerationStatus);
    }
  }
  
  @override
  void dispose() {
    _promptController.dispose();
    _resetTimer?.cancel();
    _subscriptionStatusNotifierInstance?.removeListener(_fetchGenerationStatus);
    super.dispose();
  }

  Future<void> _loadCachedGenerationStatus() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _generationLimit = prefs.getInt(_kCachedLimit) ?? 3;
        _generationsToday = prefs.getInt(_kCachedGenerationsToday) ?? 0;
        _resetsAtUtcIso = prefs.getString(_kCachedResetsAt);
        if (_resetsAtUtcIso != null) _updateResetsAtDisplay();
      });
    }
  }

  Future<void> _fetchGenerationStatus() async {
    if (!mounted) return;
    setState(() => _isLoadingStatus = true);
    try {
      final response = await Supabase.instance.client.functions.invoke('get-generation-status');
      if (!mounted) return;

      final data = response.data;
      if (data['error'] != null) {
        setState(() => _statusErrorMessage = data['error'].toString());
      } else {
        setState(() {
          _generationLimit = data['limit'] ?? 3;
          _generationsToday = data['generations_today'] ?? 0;
          _resetsAtUtcIso = data['resets_at_utc_iso'];
          _statusErrorMessage = null;
          _updateResetsAtDisplay();
          _saveGenerationStatusToCache();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statusErrorMessage = 'Error: ${e.toString()}');
    }
    if (mounted) setState(() => _isLoadingStatus = false);
  }

  Future<void> _saveGenerationStatusToCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCachedLimit, _generationLimit);
    await prefs.setInt(_kCachedGenerationsToday, _generationsToday);
    if (_resetsAtUtcIso != null) {
      // Fix: Removed unnecessary '!' on a non-nullable const
      await prefs.setString(_kCachedResetsAt, _resetsAtUtcIso!);
    }
  }

  void _updateResetsAtDisplay() {
    if (_resetsAtUtcIso == null) return;
    final resetTime = DateTime.tryParse(_resetsAtUtcIso!)?.toLocal();
    if (resetTime == null) return;
    
    final difference = resetTime.difference(DateTime.now());
    if (difference.isNegative) {
      _timeUntilReset = "Limit reset!";
    } else {
      final h = difference.inHours;
      final m = difference.inMinutes.remainder(60);
      final s = difference.inSeconds.remainder(60);
      _timeUntilReset = "Resets in ${h}h ${m}m ${s}s";
    }
    if (mounted) setState(() {});
  }

  Future<void> _improvePrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty || _isLoading || _isImproving) return;
    FocusScope.of(context).unfocus();
    setState(() => _isImproving = true);

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'improve-prompt-proxy', body: {'prompt': prompt},
      );
      if (mounted) {
        if (response.data['error'] != null) {
          showErrorSnackbar(context, response.data['error'].toString());
        } else if (response.data['improved_prompt'] != null) {
          _promptController.text = response.data['improved_prompt'].trim();
          showSuccessSnackbar(context, 'Prompt improved!');
        }
      }
    } catch (e) {
      debugPrint('Error improving prompt: $e');
      if (mounted) showErrorSnackbar(context, 'An unexpected error occurred while improving the prompt. Please try again.');
    }
    if (mounted) setState(() => _isImproving = false);
  }

  Future<void> _fetchRandomPrompt() async {
    if (_isLoading || _isImproving || _isFetchingRandomPrompt) return;
    FocusScope.of(context).unfocus();
    setState(() => _isFetchingRandomPrompt = true);

    try {
      final response = await Supabase.instance.client.functions.invoke('get-random-prompt');
      if (mounted) {
        if (response.data != null && response.data['prompt'] != null) {
          _promptController.text = response.data['prompt'];
          showSuccessSnackbar(context, 'New prompt loaded!');
        } else if (response.data['error'] != null) {
          showErrorSnackbar(context, response.data['error'].toString());
        } else {
          showErrorSnackbar(context, 'Failed to get a random prompt. No data.');
        }
      }
    } catch (e) {
      debugPrint('Error fetching random prompt: $e');
      if (mounted) showErrorSnackbar(context, 'An unexpected error occurred while fetching a new prompt.');
    }
    if (mounted) setState(() => _isFetchingRandomPrompt = false);
  }

  Future<void> _generateImage() async {
    if (_promptController.text.isEmpty || _isLoading || _isImproving || _isFetchingRandomPrompt) return;
    FocusScope.of(context).unfocus();
    setState(() { _isLoading = true; _generatedImageUrl = null; });

    try {
      final response = await Supabase.instance.client.functions.invoke(
        'generate-image-proxy',
        body: {
          'prompt': _promptController.text,
          'size': _selectedAspectRatioValue, // Pass selected size
        },
      );
      if (mounted) {
        final data = response.data;
        if (data['error'] != null) {
          showErrorSnackbar(context, data['error'].toString());
        } else if (data['data'] != null && data['data'][0]['url'] != null) {
          setState(() {
            _generatedImageUrl = data['data'][0]['url'];
            _lastSuccessfulPrompt = _promptController.text; // Store the successful prompt
          });
          await _fetchGenerationStatus();
        }
      }
    } catch (e) {
      debugPrint('Image generation error: $e');
      if (mounted) showErrorSnackbar(context, 'An unexpected error occurred during image generation. Please try again.');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveImage() async {
    if (_generatedImageUrl == null || _isSavingImage) return;
    setState(() => _isSavingImage = true);

    try {
      final photosPermission = Platform.isAndroid 
          ? (await DeviceInfoPlugin().androidInfo).version.sdkInt >= 33 ? Permission.photos : Permission.storage
          : Permission.photos;
      
      PermissionStatus status = await photosPermission.request();
      if (status.isGranted) {
        final ByteData imageData = await NetworkAssetBundle(Uri.parse(_generatedImageUrl!)).load('');
        final filename = 'Visionspark_${DateTime.now().millisecondsSinceEpoch}.png';
        await _channel.invokeMethod('saveImageToGallery', {
          'imageBytes': imageData.buffer.asUint8List(),
          'filename': filename,
          'albumName': 'Visionspark'
        });
        if (mounted) showSuccessSnackbar(context, 'Image saved to Gallery!');
      } else {
        if (mounted) showErrorSnackbar(context, 'Storage permission is required to save images.');
      }
    } catch (e) {
      debugPrint('Error saving image: $e');
      if (mounted) showErrorSnackbar(context, 'An unexpected error occurred while saving the image. Please try again.');
    }
    if (mounted) setState(() => _isSavingImage = false);
  }

  Future<void> _shareToGallery() async {
    if (_generatedImageUrl == null || _isSharingToGallery) return;
    setState(() => _isSharingToGallery = true);
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('You must be logged in to share.');

      final ByteData imageData = await NetworkAssetBundle(Uri.parse(_generatedImageUrl!)).load('');
      final imageBytes = imageData.buffer.asUint8List();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final mainPath = 'public/${user.id}_$timestamp.png';

      await Supabase.instance.client.storage.from('imagestorage').uploadBinary(mainPath, imageBytes);

      String? thumbPath;
      try {
        final thumbBytes = await _createThumbnail(imageBytes);
        thumbPath = 'public/${user.id}_${timestamp}_thumb.png';
        await Supabase.instance.client.storage.from('imagestorage').uploadBinary(thumbPath, thumbBytes);
      } catch (e) {
        debugPrint('Thumbnail generation failed: $e');
      }

      await Supabase.instance.client.from('gallery_images').insert({
        'user_id': user.id, 'image_path': mainPath,
        'prompt': _promptController.text, 'thumbnail_url': thumbPath,
      });

      if (mounted) showSuccessSnackbar(context, 'Image shared to gallery!');
    } catch (e) {
      debugPrint('Failed to share to gallery: $e');
      if (mounted) showErrorSnackbar(context, 'An unexpected error occurred while sharing the image. Please try again.');
    }
    if (mounted) setState(() => _isSharingToGallery = false);
  }

  Future<Uint8List> _createThumbnail(Uint8List imageBytes) async {
      final originalImage = img.decodeImage(imageBytes);
      if (originalImage == null) throw Exception('Failed to decode image.');
      final thumbnail = img.copyResize(originalImage, width: 200);
      return Uint8List.fromList(img.encodePng(thumbnail));
  }
  
  // --- UI Builder Methods ---

  @override
  Widget build(BuildContext context) {
    int remaining = _generationLimit == -1 ? 999 : _generationLimit - _generationsToday;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildGenerationStatus(context, remaining, _generationLimit),
              const SizedBox(height: 24),
              _buildPromptInput(context),
              const SizedBox(height: 16), // Reduced space a bit
              _buildAspectRatioSelector(context), // Added Aspect Ratio Selector
              const SizedBox(height: 16), // Reduced space a bit
              _buildResultSection(context),
              const SizedBox(height: 16),
              _buildLastPromptDisplay(context), // Added Last Prompt Display
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: (remaining <= 0 && _generationLimit != -1) || _isLoading || _isFetchingRandomPrompt || _isImproving ? null : _generateImage,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Generate'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGenerationStatus(BuildContext context, int remaining, int limit) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_isLoadingStatus) return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
    if (_statusErrorMessage != null) return Center(child: Text(_statusErrorMessage!, style: TextStyle(color: colorScheme.error)));

    double progress = limit <= 0 ? 1.0 : remaining / limit;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Fix: Replaced deprecated surfaceVariant
        color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Generations Remaining', style: textTheme.titleMedium),
              Text(
                limit == -1 ? 'Unlimited' : '$remaining / $limit',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          const SizedBox(height: 8),
          if (limit != -1)
            // Fix: Replaced deprecated withOpacity
            Text(_timeUntilReset, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurface.withOpacity(0.7))),
        ],
      ),
    );
  }

  Widget _buildLastPromptDisplay(BuildContext context) {
    if (_lastSuccessfulPrompt.isEmpty) {
      return const SizedBox.shrink(); // Don't show if no prompt stored
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5))
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Last Used Prompt:",
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            _lastSuccessfulPrompt,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant.withOpacity(0.9),
                  fontStyle: FontStyle.italic,
                ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildAspectRatioSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    List<bool> _isSelected = _aspectRatioValues.map((value) => value == _selectedAspectRatioValue).toList();

    return Center( // Center the ToggleButtons
      child: Column(
        children: [
          Text("Aspect Ratio", style: Theme.of(context).textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          ToggleButtons(
            isSelected: _isSelected,
            onPressed: (int index) {
              if (_isLoading || _isImproving || _isFetchingRandomPrompt) return; // Disable during other operations
              setState(() {
                _selectedAspectRatioValue = _aspectRatioValues[index];
              });
            },
            borderRadius: BorderRadius.circular(12),
            selectedColor: colorScheme.onPrimary,
            color: colorScheme.onSurfaceVariant,
            fillColor: colorScheme.primary,
            splashColor: colorScheme.primary.withOpacity(0.2),
            highlightColor: colorScheme.primary.withOpacity(0.1),
            borderColor: colorScheme.outlineVariant,
            selectedBorderColor: colorScheme.primary,
            children: _aspectRatioLabels.map((label) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Text(label),
            )).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptInput(BuildContext context) {
    return TextField(
      controller: _promptController,
      minLines: 3,
      maxLines: 5,
      decoration: InputDecoration(
        hintText: 'Describe the image you want to create...',
        filled: true,
        // Fix: Replaced deprecated surfaceVariant
        fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.3),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min, // Important to keep icons tight
          children: [
            IconButton(
              icon: _isImproving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.auto_awesome),
              tooltip: 'Improve Prompt',
              onPressed: _isFetchingRandomPrompt ? null : _improvePrompt, // Disable if fetching random
            ),
            IconButton(
              icon: _isFetchingRandomPrompt
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.casino), // Using casino icon for "Surprise Me"
              tooltip: 'Surprise Me!',
              onPressed: _isImproving ? null : _fetchRandomPrompt, // Disable if improving
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // Determine aspect ratio for the placeholder/result Card
    double cardAspectRatio = 1.0; // Default square
    if (_selectedAspectRatioValue == "1792x1024") { // Landscape
      cardAspectRatio = 1792 / 1024;
    } else if (_selectedAspectRatioValue == "1024x1792") { // Portrait
      cardAspectRatio = 1024 / 1792;
    }

    return AspectRatio(
      aspectRatio: cardAspectRatio, // Use dynamic aspect ratio
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Placeholder
            if (_generatedImageUrl == null && !_isLoading)
              Container(
                // Fix: Replaced deprecated surfaceVariant
                color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Fix: Replaced deprecated withOpacity
                    Icon(Icons.image_search, size: 64, color: colorScheme.onSurface.withOpacity(0.4)),
                    const SizedBox(height: 16),
                    // Fix: Replaced deprecated withOpacity
                    Text("Your image will appear here", style: TextStyle(color: colorScheme.onSurface.withOpacity(0.7))),
                  ],
                ),
              ),
            // Generated Image
            if (_generatedImageUrl != null)
              Image.network(
                _generatedImageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
              ),
            // Loading Overlay
            if (_isLoading)
              Container(
                color: Colors.black.withOpacity(0.5),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text("Generating...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            // Action Buttons Overlay
            if (_generatedImageUrl != null && !_isLoading)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        // Fix: Replaced deprecated withOpacity
                        Colors.black.withOpacity(0.7),
                        Colors.transparent
                      ],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(
                          context, 'Save', Icons.save_alt, _isSavingImage, _saveImage),
                      _buildActionButton(
                          context, 'Share', Icons.ios_share, _isSharingToGallery, _shareToGallery),
                    ],
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButton(BuildContext context, String label, IconData icon, bool isLoading, VoidCallback onPressed) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          onPressed: isLoading ? null : onPressed,
          heroTag: label,
          child: isLoading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon),
        ),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 12)),
      ],
    );
  }
}