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

  // New state variables for advanced parameters
  late final TextEditingController _negativePromptController;
  final Map<String, String> _styleDisplayMap = {
    'None': 'None',
    'vivid': 'Vivid',
    'natural': 'Natural',
  };
  final List<String> _availableStyles = ['None', 'vivid', 'natural'];
  String _selectedStyle = 'None';

  static const MethodChannel _channel = MethodChannel('com.visionspark.app/media');

  @override
  void initState() {
    super.initState();
    _negativePromptController = TextEditingController(); // Initialize new controller
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
    _negativePromptController.dispose(); // Dispose new controller
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
      // Prepare the base body for the API call
      final Map<String, dynamic> requestBody = {
        'prompt': _promptController.text.trim(),
        'size': _selectedAspectRatioValue,
      };

      // Add negative_prompt if it's not empty
      final String negativePrompt = _negativePromptController.text.trim();
      if (negativePrompt.isNotEmpty) {
        requestBody['negative_prompt'] = negativePrompt;
      }

      // Add style if it's not 'None'
      if (_selectedStyle != 'None') {
        requestBody['style'] = _selectedStyle;
      }

      final response = await Supabase.instance.client.functions.invoke(
        'generate-image-proxy',
        body: requestBody,
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

          // Auto-upload to gallery if enabled
          final prefs = await SharedPreferences.getInstance();
          final autoUpload = prefs.getBool('auto_upload_to_gallery') ?? false;
          if (autoUpload) {
            await _shareToGallery();
          }
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
              const SizedBox(height: 16),
              _buildNegativePromptInput(context), // New Negative Prompt Field
              const SizedBox(height: 16),
              _buildAspectRatioSelector(context),
              const SizedBox(height: 16),
              _buildStyleSelector(context),
              const SizedBox(height: 24), // Increased spacing before result
              _buildResultSection(context),
              const SizedBox(height: 24), // Increased spacing
              _buildLastPromptDisplay(context),
              const SizedBox(height: 24), // Increased spacing
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

    double progress = limit <= 0 ? 1.0 : remaining / limit.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow, // M3 standard surface color
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Generations Remaining', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
              Text(
                limit == -1 ? 'Unlimited' : '$remaining / $limit',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8, // Slightly thicker for better visibility
            borderRadius: BorderRadius.circular(4),
            backgroundColor: colorScheme.surfaceVariant, // Themed background for progress bar
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary), // Explicitly use primary
          ),
          const SizedBox(height: 8),
          if (limit != -1)
            Text(_timeUntilReset, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8))),
        ],
      ),
    );
  }

  Widget _buildLastPromptDisplay(BuildContext context) {
    if (_lastSuccessfulPrompt.isEmpty) {
      return const SizedBox.shrink(); // Don't show if no prompt stored
    }
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest, // Use a very subtle background
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant) // Standard border
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Last Used Prompt:",
            style: textTheme.labelMedium?.copyWith( // Slightly larger label
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            _lastSuccessfulPrompt,
            style: textTheme.bodyMedium?.copyWith( // Slightly larger body
                  color: colorScheme.onSurfaceVariant.withOpacity(0.9),
                  fontStyle: FontStyle.italic,
                ),
            maxLines: 3,
            minLines: 1,
          ),
        ],
      ),
    );
  }

  Widget _buildAspectRatioSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    List<bool> _isSelected = _aspectRatioValues.map((value) => value == _selectedAspectRatioValue).toList();

    return Center(
      child: Column(
        children: [
          Text("Aspect Ratio", style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8), // Increased spacing slightly
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ToggleButtons(
              isSelected: _isSelected,
              onPressed: (int index) {
                if (_isLoading || _isImproving || _isFetchingRandomPrompt) return;
                setState(() {
                  _selectedAspectRatioValue = _aspectRatioValues[index];
                });
              },
              borderRadius: BorderRadius.circular(12),
              selectedColor: colorScheme.onPrimary,
              color: colorScheme.onSurfaceVariant,
              fillColor: colorScheme.primary,
              splashColor: colorScheme.primaryContainer.withOpacity(0.5),
              highlightColor: colorScheme.primaryContainer.withOpacity(0.3),
              borderColor: colorScheme.outline,
              selectedBorderColor: colorScheme.primary.withOpacity(0.8),
              constraints: const BoxConstraints(minHeight: 40.0, minWidth: 70.0), // reduced minWidth
              children: _aspectRatioLabels.map((label) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8.0), // reduced padding
                child: Text(label, style: textTheme.labelLarge),
              )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNegativePromptInput(BuildContext context) {
    // Uses global InputDecorationTheme by default
    return TextField(
      controller: _negativePromptController,
      minLines: 1,
      maxLines: 3,
      decoration: const InputDecoration(
        hintText: 'Negative prompt (e.g., "blurry, ugly, text")',
        labelText: 'Negative Prompt (Optional)',
      ),
    );
  }

  Widget _buildStyleSelector(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return DropdownButtonFormField<String>(
      value: _selectedStyle,
      items: _availableStyles.map((style) {
        return DropdownMenuItem<String>(
          value: style,
          child: Text(_styleDisplayMap[style] ?? style),
        );
      }).toList(),
      onChanged: (String? newValue) {
        if (newValue != null) {
          setState(() {
            _selectedStyle = newValue;
          });
        }
      },
      decoration: InputDecoration(
        labelText: 'Image Style',
        // Uses global InputDecorationTheme, but we can override parts if needed
        // For example, if we want a specific icon for the dropdown:
        // prefixIcon: Icon(Icons.style_outlined, color: colorScheme.onSurfaceVariant),
      ),
      dropdownColor: colorScheme.surfaceContainerHigh, // Background color of the dropdown menu
    );
  }

  Widget _buildPromptInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Uses global InputDecorationTheme, only specific overrides here
    return TextField(
      controller: _promptController,
      minLines: 3,
      maxLines: 5,
      decoration: InputDecoration(
        hintText: 'Describe the image you want to create...',
        labelText: 'Prompt', // Added label
        // fillColor is from global theme
        // border is from global theme
        // enabledBorder is from global theme
        // focusedBorder is from global theme
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: _isImproving
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))
                  : Icon(Icons.auto_awesome, color: colorScheme.onSurfaceVariant),
              tooltip: 'Improve Prompt',
              onPressed: _isFetchingRandomPrompt ? null : _improvePrompt,
            ),
            IconButton(
              icon: _isFetchingRandomPrompt
                  ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: colorScheme.primary))
                  : Icon(Icons.casino, color: colorScheme.onSurfaceVariant),
              tooltip: 'Surprise Me!',
              onPressed: _isImproving ? null : _fetchRandomPrompt,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    double cardAspectRatio = 1.0;
    if (_selectedAspectRatioValue == "1792x1024") {
      cardAspectRatio = 1792 / 1024;
    } else if (_selectedAspectRatioValue == "1024x1792") {
      cardAspectRatio = 1024 / 1792;
    }

    return AspectRatio(
      aspectRatio: cardAspectRatio,
      child: Card(
        elevation: 2, // Add a bit of elevation
        color: colorScheme.surfaceContainerLowest, // Use a very subtle background for the card itself
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_generatedImageUrl == null && !_isLoading)
              Container(
                color: colorScheme.surfaceContainerLow, // A bit darker than card for placeholder bg
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_search, size: 64, color: colorScheme.onSurfaceVariant.withOpacity(0.6)),
                    const SizedBox(height: 16),
                    Text("Your image will appear here", style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8))),
                  ],
                ),
              ),
            if (_generatedImageUrl != null)
              Image.network(
                _generatedImageUrl!,
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary)));
                },
                errorBuilder: (context, error, stackTrace) => Center(child: Icon(Icons.broken_image, size: 48, color: colorScheme.error)),
              ),
            Visibility(
              visible: _isLoading,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                color: colorScheme.scrim.withOpacity(0.6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
                    const SizedBox(height: 16),
                    Text("Generating...", style: textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            if (_generatedImageUrl != null && !_isLoading)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), // Adjusted padding
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        colorScheme.scrim.withOpacity(0.7), // Use scrim
                        colorScheme.scrim.withOpacity(0.0), // Fade to transparent
                      ],
                      stops: const [0.0, 1.0] // Ensure full gradient effect
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(
                          context, 'Save', Icons.save_alt, _isSavingImage, _saveImage, colorScheme),
                      _buildActionButton(
                          context, 'Share', Icons.ios_share, _isSharingToGallery, _shareToGallery, colorScheme),
                    ],
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButton(BuildContext context, String label, IconData icon, bool isLoading, VoidCallback onPressed, ColorScheme colorScheme) {
    // Action buttons on a scrim background, so light foreground color is appropriate.
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          onPressed: isLoading ? null : onPressed,
          heroTag: label, // Ensure heroTags are unique if multiple FABs are on screen (not the case here per button)
          backgroundColor: colorScheme.surface.withOpacity(0.85), // Semi-transparent surface
          foregroundColor: colorScheme.onSurface, // Text/icon color on that surface
          elevation: 2, // Subtle elevation
          child: isLoading
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary)))
            : Icon(icon, size: 22),
        ),
        const SizedBox(height: 6), // Slightly more space
        Text(label, style: textTheme.labelSmall?.copyWith(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w500)), // White text on scrim
      ],
    );
  }
}