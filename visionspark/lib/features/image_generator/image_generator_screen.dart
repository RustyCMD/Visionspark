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
import 'dart:ui';

const String _kCachedLimit = 'cached_generation_limit';
const String _kCachedGenerationsToday = 'cached_generations_today';
const String _kCachedResetsAt = 'cached_resets_at_utc_iso';

class ImageGeneratorScreen extends StatefulWidget {
  const ImageGeneratorScreen({super.key});

  @override
  State<ImageGeneratorScreen> createState() => _ImageGeneratorScreenState();
}

class _ImageGeneratorScreenState extends State<ImageGeneratorScreen> with TickerProviderStateMixin {
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

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _pulseController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _pulseAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _negativePromptController = TextEditingController();
    
    // Initialize animations
    _fadeController = AnimationController(duration: const Duration(milliseconds: 800), vsync: this);
    _pulseController = AnimationController(duration: const Duration(seconds: 2), vsync: this)..repeat(reverse: true);
    _slideController = AnimationController(duration: const Duration(milliseconds: 600), vsync: this);
    
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _fadeController, curve: Curves.easeOut),
    );
    _pulseAnimation = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic),
    );
    
    _loadCachedGenerationStatus();
    _fetchGenerationStatus();
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateResetsAtDisplay());
    
    _fadeController.forward();
    _slideController.forward();
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
    _fadeController.dispose();
    _pulseController.dispose();
    _slideController.dispose();
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
    final colorScheme = Theme.of(context).colorScheme;
    final size = MediaQuery.of(context).size;
    int remaining = _generationLimit == -1 ? 999 : _generationLimit - _generationsToday;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: const [0.0, 0.4, 1.0],
            colors: [
              colorScheme.surface,
              colorScheme.primary.withOpacity(0.02),
              colorScheme.secondary.withOpacity(0.03),
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: size.width * 0.05,
                  vertical: size.height * 0.02,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildGenerationStatus(context, remaining, _generationLimit, colorScheme, size),
                    SizedBox(height: size.height * 0.03),
                    _buildInputSection(context, colorScheme, size),
                    SizedBox(height: size.height * 0.03),
                    _buildResultSection(context, colorScheme, size),
                    SizedBox(height: size.height * 0.02),
                    _buildLastPromptDisplay(context, colorScheme),
                    SizedBox(height: size.height * 0.03),
                    _buildGenerateButton(context, remaining, colorScheme),
                    SizedBox(height: size.height * 0.02),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGenerationStatus(BuildContext context, int remaining, int limit, ColorScheme colorScheme, Size size) {
    final textTheme = Theme.of(context).textTheme;
    
    if (_isLoadingStatus) {
      return Container(
        height: 120,
        child: Center(
          child: CircularProgressIndicator(color: colorScheme.primary),
        ),
      );
    }
    
    if (_statusErrorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: colorScheme.error.withOpacity(0.2)),
        ),
        child: Text(_statusErrorMessage!, style: TextStyle(color: colorScheme.error)),
      );
    }

    double progress = limit <= 0 ? 1.0 : remaining / limit.clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primaryContainer.withOpacity(0.3),
            colorScheme.secondaryContainer.withOpacity(0.2),
          ],
        ),
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
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.auto_awesome,
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Generations Available',
                      style: textTheme.titleMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      limit == -1 ? 'Unlimited' : '$remaining of $limit remaining',
                      style: textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurface.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 12,
              backgroundColor: colorScheme.surfaceContainer.withOpacity(0.5),
              valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
            ),
          ),
          if (limit != -1) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.access_time,
                  size: 16,
                  color: colorScheme.onSurface.withOpacity(0.6),
                ),
                const SizedBox(width: 6),
                Text(
                  _timeUntilReset,
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInputSection(BuildContext context, ColorScheme colorScheme, Size size) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Create Your Vision', Icons.psychology, colorScheme),
          const SizedBox(height: 20),
          _buildPromptInput(context, colorScheme),
          const SizedBox(height: 16),
          _buildNegativePromptInput(context, colorScheme),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _buildAspectRatioSelector(context, colorScheme)),
              const SizedBox(width: 16),
              Expanded(child: _buildStyleSelector(context, colorScheme)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.primary.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            color: colorScheme.primary,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          title,
          style: textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  Widget _buildPromptInput(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withOpacity(0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _promptController,
        minLines: 3,
        maxLines: 5,
        style: TextStyle(
          color: colorScheme.onSurface,
          height: 1.4,
        ),
        decoration: InputDecoration(
          hintText: 'Describe the image you want to create...',
          hintStyle: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
          suffixIcon: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildIconButton(
                  icon: _isImproving ? null : Icons.auto_awesome,
                  tooltip: 'Improve Prompt',
                  onPressed: _isFetchingRandomPrompt ? null : _improvePrompt,
                  isLoading: _isImproving,
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 8),
                _buildIconButton(
                  icon: _isFetchingRandomPrompt ? null : Icons.casino,
                  tooltip: 'Surprise Me!',
                  onPressed: _isImproving ? null : _fetchRandomPrompt,
                  isLoading: _isFetchingRandomPrompt,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNegativePromptInput(BuildContext context, ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: TextField(
        controller: _negativePromptController,
        minLines: 1,
        maxLines: 3,
        style: TextStyle(color: colorScheme.onSurface),
        decoration: InputDecoration(
          hintText: 'What to avoid (e.g., "blurry, ugly, text")',
          hintStyle: TextStyle(
            color: colorScheme.onSurface.withOpacity(0.5),
          ),
          prefixIcon: Icon(
            Icons.block,
            color: colorScheme.onSurface.withOpacity(0.6),
            size: 20,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(16),
        ),
      ),
    );
  }

  Widget _buildIconButton({
    IconData? icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool isLoading = false,
    required ColorScheme colorScheme,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              )
            : Icon(icon, color: colorScheme.primary, size: 20),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildAspectRatioSelector(BuildContext context, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Aspect Ratio",
          style: textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: _aspectRatioLabels.asMap().entries.map((entry) {
              final index = entry.key;
              final label = entry.value;
              final isSelected = _aspectRatioValues[index] == _selectedAspectRatioValue;
              
              return Expanded(
                child: GestureDetector(
                  onTap: (_isLoading || _isImproving || _isFetchingRandomPrompt) ? null : () {
                    setState(() {
                      _selectedAspectRatioValue = _aspectRatioValues[index];
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected ? colorScheme.primary : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: textTheme.labelLarge?.copyWith(
                        color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface.withOpacity(0.7),
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildStyleSelector(BuildContext context, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "Style",
          style: textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurface.withOpacity(0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer.withOpacity(0.3),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outline.withOpacity(0.2),
              width: 1,
            ),
          ),
          child: DropdownButton<String>(
            value: _selectedStyle,
            isExpanded: true,
            underline: const SizedBox.shrink(),
            icon: Icon(Icons.keyboard_arrow_down, color: colorScheme.onSurface.withOpacity(0.6)),
            items: _availableStyles.map((String style) {
              return DropdownMenuItem<String>(
                value: style,
                child: Text(
                  style,
                  style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedStyle = newValue;
                });
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _buildResultSection(BuildContext context, ColorScheme colorScheme, Size size) {
    double cardAspectRatio = 1.0;
    if (_selectedAspectRatioValue == "1792x1024") {
      cardAspectRatio = 1792 / 1024;
    } else if (_selectedAspectRatioValue == "1024x1792") {
      cardAspectRatio = 1024 / 1792;
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _isLoading ? _pulseAnimation.value : 1.0,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withOpacity(_isLoading ? 0.2 : 0.1),
                  blurRadius: _isLoading ? 25 : 15,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: AspectRatio(
              aspectRatio: cardAspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Background
                    Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            colorScheme.surfaceContainer.withOpacity(0.5),
                            colorScheme.surfaceContainer.withOpacity(0.3),
                          ],
                        ),
                      ),
                    ),
                    
                    // Placeholder or generated image
                    if (_generatedImageUrl == null && !_isLoading)
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.auto_awesome,
                              size: 48,
                              color: colorScheme.primary,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Your AI creation will appear here",
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.6),
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    
                    // Generated image
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
                              color: colorScheme.primary,
                              strokeWidth: 3,
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) => Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image,
                                size: 48,
                                color: colorScheme.error,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Failed to load image',
                                style: TextStyle(color: colorScheme.error),
                              ),
                            ],
                          ),
                        ),
                      ),
                    
                    // Loading overlay
                    if (_isLoading)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            color: colorScheme.surface.withOpacity(0.8),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  color: colorScheme.primary,
                                  strokeWidth: 3,
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  "Creating your masterpiece...",
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    
                    // Action buttons for generated image
                    if (_generatedImageUrl != null && !_isLoading)
                      Positioned(
                        bottom: 16,
                        left: 16,
                        right: 16,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildFloatingActionButton(
                              label: 'Save',
                              icon: Icons.download_rounded,
                              onPressed: _saveImage,
                              isLoading: _isSavingImage,
                              colorScheme: colorScheme,
                            ),
                            _buildFloatingActionButton(
                              label: 'Share',
                              icon: Icons.ios_share,
                              onPressed: _shareToGallery,
                              isLoading: _isSharingToGallery,
                              colorScheme: colorScheme,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFloatingActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool isLoading = false,
    required ColorScheme colorScheme,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: colorScheme.primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: FloatingActionButton.small(
            onPressed: isLoading ? null : onPressed,
            heroTag: label,
            backgroundColor: colorScheme.primary,
            foregroundColor: colorScheme.onPrimary,
            child: isLoading
                ? SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  )
                : Icon(icon, size: 20),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.9),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildLastPromptDisplay(BuildContext context, ColorScheme colorScheme) {
    if (_lastSuccessfulPrompt.isEmpty) return const SizedBox.shrink();
    
    final textTheme = Theme.of(context).textTheme;
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer.withOpacity(0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.history,
                size: 16,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                "Last Generated",
                style: textTheme.labelLarge?.copyWith(
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SelectableText(
            _lastSuccessfulPrompt,
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.8),
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildGenerateButton(BuildContext context, int remaining, ColorScheme colorScheme) {
    final textTheme = Theme.of(context).textTheme;
    final isDisabled = (remaining <= 0 && _generationLimit != -1) || _isLoading || _isFetchingRandomPrompt || _isImproving;

    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: isDisabled
            ? null
            : LinearGradient(
                colors: [
                  colorScheme.primary,
                  colorScheme.primary.withOpacity(0.8),
                ],
              ),
        color: isDisabled ? colorScheme.surfaceContainer : null,
        boxShadow: isDisabled
            ? null
            : [
                BoxShadow(
                  color: colorScheme.primary.withOpacity(0.3),
                  blurRadius: 15,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ElevatedButton(
        onPressed: isDisabled ? null : _generateImage,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: isDisabled ? colorScheme.onSurface.withOpacity(0.4) : colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        child: _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Generating...',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.auto_awesome,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Generate Image',
                    style: textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}