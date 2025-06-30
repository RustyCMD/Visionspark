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
  String _selectedStyle = 'None'; // Default style
  final List<String> _availableStyles = [
    'None', 'Cartoon', 'Photorealistic', 'Fantasy Art', 'Abstract',
    'Anime', 'Comic Book', 'Impressionistic', 'Pixel Art', 'Watercolor'
  ];

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
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;

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
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(height: size.height * 0.02),
                _buildModernGenerationStatus(context, remaining, _generationLimit),
                SizedBox(height: size.height * 0.04),
                _buildModernResultSection(context),
                SizedBox(height: size.height * 0.04),
                _buildModernPromptInput(context),
                const SizedBox(height: 20),
                _buildNegativePromptInput(context),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(child: _buildAspectRatioSelector(context)),
                    const SizedBox(width: 16),
                    Expanded(child: _buildStyleSelector(context)),
                  ],
                ),
                SizedBox(height: size.height * 0.04),
                _buildLastPromptDisplay(context),
                SizedBox(height: size.height * 0.04),
                _buildModernGenerateButton(context, remaining),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernGenerationStatus(BuildContext context, int remaining, int limit) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    
    if (_isLoadingStatus) return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
    if (_statusErrorMessage != null) return Center(child: Text(_statusErrorMessage!, style: TextStyle(color: colorScheme.error)));

    double progress = limit <= 0 ? 1.0 : remaining / limit.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
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
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Generations',
                    style: textTheme.titleMedium?.copyWith(
                      color: colorScheme.onSurface.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    limit == -1 ? 'Unlimited' : '$remaining / $limit',
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Available',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            height: 8,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
              ),
            ),
          ),
          if (limit != -1) ...[
            const SizedBox(height: 12),
            Text(
              _timeUntilReset,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModernResultSection(BuildContext context) {
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
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface.withOpacity(0.9),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withOpacity(0.15),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (_generatedImageUrl == null && !_isLoading)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.surfaceContainer.withOpacity(0.5),
                        colorScheme.surfaceContainer.withOpacity(0.2),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer.withOpacity(0.8),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.image_search_rounded,
                          size: 40,
                          color: colorScheme.onSurface.withOpacity(0.6),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Your AI creation will appear here",
                        style: textTheme.titleMedium?.copyWith(
                          color: colorScheme.onSurface.withOpacity(0.7),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
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
                    return Center(
                      child: CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                        strokeWidth: 3,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.broken_image_rounded,
                          size: 48,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Failed to load image',
                          style: textTheme.titleMedium?.copyWith(
                            color: colorScheme.error,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (_isLoading)
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        colorScheme.scrim.withOpacity(0.8),
                        colorScheme.scrim.withOpacity(0.6),
                      ],
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: CircularProgressIndicator(
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                          strokeWidth: 3,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        "Creating your masterpiece...",
                        style: textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "This may take a few moments",
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_generatedImageUrl != null && !_isLoading)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          colorScheme.scrim.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildModernActionButton(
                            context, 'Save', Icons.download_rounded, _isSavingImage, _saveImage, colorScheme,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildModernActionButton(
                            context, 'Share', Icons.share_rounded, _isSharingToGallery, _shareToGallery, colorScheme,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModernPromptInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _promptController,
        minLines: 3,
        maxLines: 5,
        style: TextStyle(
          fontSize: 16,
          color: colorScheme.onSurface,
          height: 1.4,
        ),
        decoration: InputDecoration(
          hintText: 'Describe your vision... Be creative and detailed!',
          hintStyle: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
          labelText: 'Prompt',
          labelStyle: TextStyle(
            color: colorScheme.primary,
            fontWeight: FontWeight.w600,
          ),
          contentPadding: const EdgeInsets.all(20),
          border: InputBorder.none,
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPromptActionButton(
                  icon: _isImproving ? null : Icons.auto_awesome_rounded,
                  onPressed: _isFetchingRandomPrompt ? null : _improvePrompt,
                  isLoading: _isImproving,
                  tooltip: 'Improve Prompt',
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 8),
                _buildPromptActionButton(
                  icon: _isFetchingRandomPrompt ? null : Icons.casino_rounded,
                  onPressed: _isImproving ? null : _fetchRandomPrompt,
                  isLoading: _isFetchingRandomPrompt,
                  tooltip: 'Surprise Me!',
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromptActionButton({
    IconData? icon,
    required VoidCallback? onPressed,
    bool isLoading = false,
    required String tooltip,
    required ColorScheme colorScheme,
  }) {
    return Tooltip(
      message: tooltip,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.outline.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(12),
            child: Center(
              child: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                : Icon(
                    icon,
                    size: 20,
                    color: colorScheme.onSurface,
                  ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernGenerateButton(BuildContext context, int remaining) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDisabled = (remaining <= 0 && _generationLimit != -1) || _isLoading || _isFetchingRandomPrompt || _isImproving;
    
    return Container(
      height: 64,
      decoration: BoxDecoration(
        gradient: !isDisabled
          ? LinearGradient(
              colors: [colorScheme.primary, colorScheme.secondary],
            )
          : null,
        color: isDisabled ? colorScheme.surfaceContainer : null,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDisabled 
            ? colorScheme.outline.withOpacity(0.2)
            : Colors.transparent,
          width: 1,
        ),
        boxShadow: !isDisabled ? [
          BoxShadow(
            color: colorScheme.primary.withOpacity(0.3),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isDisabled ? null : _generateImage,
          borderRadius: BorderRadius.circular(20),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_isLoading)
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDisabled ? colorScheme.onSurface.withOpacity(0.4) : colorScheme.onPrimary,
                      ),
                    ),
                  )
                else ...[
                  Icon(
                    Icons.auto_awesome_rounded,
                    size: 24,
                    color: isDisabled ? colorScheme.onSurface.withOpacity(0.4) : colorScheme.onPrimary,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Generate',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: isDisabled ? colorScheme.onSurface.withOpacity(0.4) : colorScheme.onPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildModernActionButton(BuildContext context, String label, IconData icon, bool isLoading, VoidCallback onPressed, ColorScheme colorScheme) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: colorScheme.surface.withOpacity(0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    ),
                  )
                else ...[
                  Icon(
                    icon,
                    size: 20,
                    color: colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
          ToggleButtons(
            isSelected: _isSelected,
            onPressed: (int index) {
              if (_isLoading || _isImproving || _isFetchingRandomPrompt) return;
              setState(() {
                _selectedAspectRatioValue = _aspectRatioValues[index];
              });
            },
            borderRadius: BorderRadius.circular(12),
            selectedColor: colorScheme.onPrimary,
            color: colorScheme.onSurfaceVariant, // Color for unselected text & icons
            fillColor: colorScheme.primary, // Background for selected button
            splashColor: colorScheme.primaryContainer.withOpacity(0.5), // Use primaryContainer for splash
            highlightColor: colorScheme.primaryContainer.withOpacity(0.3), // Use primaryContainer for highlight
            borderColor: colorScheme.outline, // Standard border color
            selectedBorderColor: colorScheme.primary.withOpacity(0.8), // Slightly subtler selected border
            constraints: const BoxConstraints(minHeight: 40.0, minWidth: 80.0), // Ensure buttons are easy to tap
            children: _aspectRatioLabels.map((label) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0), // Adjusted padding
              child: Text(label, style: textTheme.labelLarge), // Use a standard text style
            )).toList(),
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
      items: _availableStyles.map((String style) {
        return DropdownMenuItem<String>(
          value: style,
          child: Text(style, style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface)),
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
}