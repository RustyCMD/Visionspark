import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import '../../shared/utils/snackbar_utils.dart';
import '../../shared/design_system/design_system.dart';
import 'package:provider/provider.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';

const String _kCachedLimit = 'cached_enhancement_limit';
const String _kCachedEnhancementsToday = 'cached_enhancements_today';
const String _kCachedResetsAt = 'cached_enhancement_resets_at_utc_iso';

class ImageEnhancementScreen extends StatefulWidget {
  const ImageEnhancementScreen({super.key});

  @override
  State<ImageEnhancementScreen> createState() => _ImageEnhancementScreenState();
}

class _ImageEnhancementScreenState extends State<ImageEnhancementScreen> {
  // Feature toggle - manually change this to enable/disable image enhancement
  static const bool _isImageEnhancementEnabled = false;
  static const String _disabledMessage = "Image enhancement is currently disabled for maintenance. Please check back later.";

  final _promptController = TextEditingController();
  final _picker = ImagePicker();
  
  File? _selectedImage;
  String? _enhancedImageUrl;
  bool _isLoading = false;
  bool _isImproving = false;
  bool _isUploadingImage = false;
  int _enhancementLimit = 4;
  int _enhancementsToday = 0;
  String? _resetsAtUtcIso;
  String _timeUntilReset = "Calculating...";
  bool _isLoadingStatus = true;
  String? _statusErrorMessage;
  Timer? _resetTimer;
  bool _isSavingImage = false;
  bool _isSharingToGallery = false;
  bool _isFetchingRandomPrompt = false;
  bool _isSharedToGallery = false; // Track if current image has been shared to gallery
  bool _autoUploadToGallery = false; // Track auto-upload setting
  SubscriptionStatusNotifier? _subscriptionStatusNotifierInstance;
  String _lastSuccessfulPrompt = "";

  // For enhancement strength
  double _enhancementStrength = 0.7;
  final List<String> _enhancementModes = ["enhance", "edit", "variation"];
  String _selectedMode = "enhance";

  static const MethodChannel _channel = MethodChannel('com.visionspark.app/media');

  @override
  void initState() {
    super.initState();
    _loadCachedGenerationStatus();
    _fetchGenerationStatus();
    _loadAutoUploadSetting();
    _resetTimer = Timer.periodic(const Duration(seconds: 30), (_) => _updateResetsAtDisplay());
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
    // Refresh auto-upload setting when dependencies change (e.g., returning from settings)
    _loadAutoUploadSetting();
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
        _enhancementLimit = prefs.getInt(_kCachedLimit) ?? 4;
        _enhancementsToday = prefs.getInt(_kCachedEnhancementsToday) ?? 0;
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
          // Use new enhancement fields if available, fall back to generation fields for backward compatibility
          _enhancementLimit = data['enhancement_limit'] ?? data['limit'] ?? 4;
          _enhancementsToday = data['enhancements_today'] ?? data['generations_today'] ?? 0;
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
    await prefs.setInt(_kCachedLimit, _enhancementLimit);
    await prefs.setInt(_kCachedEnhancementsToday, _enhancementsToday);
    if (_resetsAtUtcIso != null) {
      await prefs.setString(_kCachedResetsAt, _resetsAtUtcIso!);
    }
  }

  void _updateResetsAtDisplay() {
    if (_resetsAtUtcIso == null) return;
    final resetTime = DateTime.tryParse(_resetsAtUtcIso!)?.toLocal();
    if (resetTime == null) {
      final newTimeString = "Invalid reset time";
      if (_timeUntilReset != newTimeString) {
        _timeUntilReset = newTimeString;
        if (mounted) setState(() {});
      }
      return;
    }

    final difference = resetTime.difference(DateTime.now());
    final String newTimeString;
    if (difference.isNegative) {
      newTimeString = "Limit reset!";
    } else {
      final h = difference.inHours;
      final m = difference.inMinutes.remainder(60);
      final s = difference.inSeconds.remainder(60);
      newTimeString = "Resets in ${h}h ${m}m ${s}s";
    }

    // Only update state if the display string has changed
    if (_timeUntilReset != newTimeString) {
      _timeUntilReset = newTimeString;
      if (mounted) setState(() {});
    }
  }

  Future<void> _pickImageFromGallery() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _enhancedImageUrl = null;
        });
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to pick image from gallery: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
          _enhancedImageUrl = null;
        });
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Failed to take photo: $e');
    }
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

  Future<void> _enhanceImage() async {
    if (_selectedImage == null || _promptController.text.isEmpty || _isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _enhancedImageUrl = null;
      _isSharedToGallery = false; // Reset share state for new image
    });

    try {
      // Read and validate image size
      final imageBytes = await _selectedImage!.readAsBytes();

      // Validate image size before processing
      if (!_validateImageSize(imageBytes)) {
        if (mounted) showErrorSnackbar(context, 'Image too large. Please select an image smaller than 10MB.');
        return;
      }

      // Convert image to PNG format and then to base64 using isolate to prevent blocking UI
      final base64Image = await compute(_convertToPngAndEncode, imageBytes);

      final Map<String, dynamic> requestBody = {
        'image': base64Image,
        'prompt': _promptController.text.trim(),
        'mode': _selectedMode,
        'strength': _enhancementStrength,
      };

      final response = await Supabase.instance.client.functions.invoke(
        'enhance-image-proxy',
        body: requestBody,
      );

      if (mounted) {
        final data = response.data;
        if (data['error'] != null) {
          final errorMessage = _getApiErrorMessage(data);
          showErrorSnackbar(context, errorMessage);
        } else if (data['data'] != null && data['data'][0]['url'] != null) {
          setState(() {
            _enhancedImageUrl = data['data'][0]['url'];
            _lastSuccessfulPrompt = _promptController.text;
          });
          await _fetchGenerationStatus();

          // Auto-upload to gallery if enabled
          if (_autoUploadToGallery) {
            await _shareToGallery();
            // Set share state to true after successful auto-share
            if (mounted) {
              setState(() {
                _isSharedToGallery = true;
              });
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Image enhancement error: $e');
      if (mounted) {
        final errorMessage = _getImageEnhancementErrorMessage(e);
        showErrorSnackbar(context, errorMessage);
      }
    }
    if (mounted) setState(() => _isLoading = false);
  }

  /// Extracts user-friendly error messages from API response data
  String _getApiErrorMessage(Map<String, dynamic> data) {
    final error = data['error'];
    if (error == null) return 'An unexpected error occurred during image enhancement. Please try again.';

    final errorString = error.toString();

    // Check for content policy violations in the error message
    if (errorString.toLowerCase().contains('safety system') ||
        errorString.toLowerCase().contains('content policy')) {
      return 'Content Policy Violation: Your prompt was rejected by our safety system. Please modify your prompt to avoid potentially harmful or inappropriate content and try again.';
    }

    // Check for details object with more specific error information
    final details = data['details'];
    if (details != null && details is Map<String, dynamic>) {
      final errorType = details['type'];
      final errorCode = details['code'];

      if (errorType == 'image_generation_user_error' &&
          errorCode == 'content_policy_violation') {
        return 'Content Policy Violation: Your prompt contains content that is not allowed by our safety system. Please try rephrasing your prompt to avoid violent, harmful, or inappropriate content.';
      }
    }

    // Return the original error message if it's user-friendly
    if (errorString.isNotEmpty && !errorString.toLowerCase().contains('unexpected')) {
      return errorString;
    }

    return 'An unexpected error occurred during image enhancement. Please try again.';
  }

  /// Extracts user-friendly error messages from image enhancement exceptions
  String _getImageEnhancementErrorMessage(dynamic error) {
    // Handle FunctionException from Supabase
    if (error is FunctionException) {
      final details = error.details;

      // Check if it's a content policy violation
      if (details != null && details is Map<String, dynamic>) {
        final errorDetails = details['error'];
        if (errorDetails != null && errorDetails is Map<String, dynamic>) {
          final errorType = errorDetails['type'];
          final errorCode = errorDetails['code'];
          final errorMessage = errorDetails['message'] ?? '';

          // Check for content policy violations
          if (errorType == 'image_generation_user_error' &&
              errorCode == 'content_policy_violation') {
            return 'Content Policy Violation: Your prompt contains content that is not allowed by our safety system. Please try rephrasing your prompt to avoid violent, harmful, or inappropriate content.';
          }

          // Check for safety system rejection in message
          if (errorMessage.toLowerCase().contains('safety system') ||
              errorMessage.toLowerCase().contains('content policy')) {
            return 'Content Policy Violation: Your prompt was rejected by our safety system. Please modify your prompt to avoid potentially harmful or inappropriate content and try again.';
          }
        }

        // Check for error message directly in details
        final directError = details['error'];
        if (directError is String) {
          if (directError.toLowerCase().contains('safety system') ||
              directError.toLowerCase().contains('content policy')) {
            return 'Content Policy Violation: Your prompt was rejected by our safety system. Please modify your prompt to avoid potentially harmful or inappropriate content and try again.';
          }
          // Return the direct error message if it's user-friendly
          if (directError.isNotEmpty && !directError.toLowerCase().contains('unexpected')) {
            return directError;
          }
        }
      }

      // Handle other FunctionException cases
      if (error.reasonPhrase != null && error.reasonPhrase!.isNotEmpty) {
        return 'Enhancement failed: ${error.reasonPhrase}';
      }
    }

    // Handle other exception types
    final errorString = error.toString();
    if (errorString.toLowerCase().contains('safety system') ||
        errorString.toLowerCase().contains('content policy')) {
      return 'Content Policy Violation: Your prompt was rejected by our safety system. Please modify your prompt to avoid potentially harmful or inappropriate content and try again.';
    }

    // Default fallback message
    return 'An unexpected error occurred during image enhancement. Please try again.';
  }

  Future<void> _saveImage() async {
    if (_enhancedImageUrl == null || _isSavingImage) return;
    setState(() => _isSavingImage = true);

    try {
      final photosPermission = Platform.isAndroid
          ? (await DeviceInfoPlugin().androidInfo).version.sdkInt >= 33 ? Permission.photos : Permission.storage
          : Permission.photos;

      PermissionStatus status = await photosPermission.request();
      if (status.isGranted) {
        // Use proper HTTP client to download the image
        final response = await http.get(Uri.parse(_enhancedImageUrl!));
        if (response.statusCode != 200) {
          throw Exception('Failed to download image from server');
        }

        final filename = 'Visionspark_Enhanced_${DateTime.now().millisecondsSinceEpoch}.png';
        final result = await _channel.invokeMethod('saveImageToGallery', {
          'imageBytes': response.bodyBytes,
          'filename': filename,
          'albumName': 'Visionspark'
        });

        if (result == true) {
          if (mounted) showSuccessSnackbar(context, 'Enhanced image saved to Gallery!');
        } else {
          throw Exception('Failed to save image to gallery');
        }
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
    if (_enhancedImageUrl == null || _isSharingToGallery) return;
    setState(() => _isSharingToGallery = true);

    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('You must be logged in to share.');

      // Use proper HTTP client to download the image
      final response = await http.get(Uri.parse(_enhancedImageUrl!));
      if (response.statusCode != 200) {
        throw Exception('Failed to download image from server');
      }

      final imageBytes = response.bodyBytes;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final mainPath = 'public/${user.id}_enhanced_$timestamp.png';

      await Supabase.instance.client.storage.from('imagestorage').uploadBinary(mainPath, imageBytes);

      String? thumbPath;
      try {
        final thumbBytes = await _createThumbnail(imageBytes);
        thumbPath = 'public/${user.id}_enhanced_${timestamp}_thumb.png';
        await Supabase.instance.client.storage.from('imagestorage').uploadBinary(thumbPath, thumbBytes);
      } catch (e) {
        debugPrint('Thumbnail generation failed: $e');
      }

      await Supabase.instance.client.from('gallery_images').insert({
        'user_id': user.id, 'image_path': mainPath,
        'prompt': _promptController.text, 'thumbnail_url': thumbPath,
      });

      if (mounted) {
        setState(() {
          _isSharedToGallery = true; // Mark image as shared
        });
        showSuccessSnackbar(context, 'Enhanced image shared to gallery!');
      }
    } catch (e) {
      debugPrint('Failed to share to gallery: $e');
      if (mounted) showErrorSnackbar(context, 'An unexpected error occurred while sharing the image. Please try again.');
    }
    if (mounted) setState(() => _isSharingToGallery = false);
  }

  Future<Uint8List> _createThumbnail(Uint8List imageBytes) async {
    return await compute(_createThumbnailInIsolate, imageBytes);
  }

  Future<void> _loadAutoUploadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoUploadToGallery = prefs.getBool('auto_upload_to_gallery') ?? false;
      });
    }
  }

  // Static methods for isolate processing
  static String _convertToPngAndEncode(Uint8List imageBytes) {
    // Decode the image from any format
    final originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) {
      throw Exception('Failed to decode image. Please ensure the image is in a supported format.');
    }

    // Encode as PNG to ensure compatibility with OpenAI API
    final pngBytes = img.encodePng(originalImage);

    // Convert to base64
    return base64Encode(pngBytes);
  }

  static Uint8List _createThumbnailInIsolate(Uint8List imageBytes) {
    final originalImage = img.decodeImage(imageBytes);
    if (originalImage == null) throw Exception('Failed to decode image.');
    final thumbnail = img.copyResize(originalImage, width: 200);
    return Uint8List.fromList(img.encodePng(thumbnail));
  }

  // Helper method to validate image size
  bool _validateImageSize(Uint8List imageBytes) {
    const int maxSizeBytes = 10 * 1024 * 1024; // 10MB limit
    return imageBytes.length <= maxSizeBytes;
  }

  // Computed getter for enhance button state
  bool get _canEnhanceImage {
    if (_selectedImage == null || _promptController.text.isEmpty) return false;
    final remaining = _enhancementLimit == -1 ? 999 : _enhancementLimit - _enhancementsToday;
    if (_enhancementLimit != -1 && remaining <= 0) return false;
    if (_isLoading || _isFetchingRandomPrompt || _isImproving) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    // Check if feature is disabled
    if (!_isImageEnhancementEnabled) {
      return Scaffold(
        body: VSResponsiveLayout(
          child: SafeArea(
            child: Padding(
              padding: VSResponsive.getResponsivePadding(context),
              child: Center(
                child: VSCard(
                  padding: const EdgeInsets.all(VSDesignTokens.space6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.construction,
                        size: 64,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(height: VSDesignTokens.space4),
                      Text(
                        'Feature Temporarily Disabled',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: VSTypography.weightBold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: VSDesignTokens.space3),
                      Text(
                        _disabledMessage,
                        style: Theme.of(context).textTheme.bodyLarge,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    int remaining = _enhancementLimit == -1 ? 999 : _enhancementLimit - _enhancementsToday;

    return Scaffold(
      body: VSResponsiveLayout(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: VSResponsive.getResponsivePadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildEnhancementStatus(context, remaining, _enhancementLimit),
                const VSResponsiveSpacing(),
                _buildImageUploadSection(context),
                const VSResponsiveSpacing(),
                _buildPromptInput(context),
                const VSResponsiveSpacing(mobile: VSDesignTokens.space4),
                _buildEnhancementSettings(context),
                const VSResponsiveSpacing(),
                _buildResultSection(context),
                const VSResponsiveSpacing(),
                _buildLastPromptDisplay(context),
                const VSResponsiveSpacing(),
                VSButton(
                  text: 'Enhance Image',
                  onPressed: _canEnhanceImage ? _enhanceImage : null,
                  isLoading: _isLoading,
                  isFullWidth: true,
                  size: VSButtonSize.large,
                  variant: VSButtonVariant.primary,
                ),
                const VSResponsiveSpacing(desktop: VSDesignTokens.space12),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEnhancementStatus(BuildContext context, int remaining, int limit) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoadingStatus) {
      return Center(
        child: VSLoadingIndicator(
          message: 'Loading status...',
          size: VSDesignTokens.iconL,
        ),
      );
    }

    if (_statusErrorMessage != null) {
      return Center(
        child: VSCard(
          padding: const EdgeInsets.all(VSDesignTokens.space4),
          color: colorScheme.errorContainer.withValues(alpha: 0.1),
          child: Text(
            _statusErrorMessage!,
            style: textTheme.bodyMedium?.copyWith(color: colorScheme.error),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    double progress = limit < 0 ? 1.0 : limit == 0 ? 0.0 : (remaining / limit).clamp(0.0, 1.0);

    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space4),
      color: colorScheme.surfaceContainerLow,
      borderRadius: VSDesignTokens.radiusL,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              VSResponsiveText(
                text: 'Enhancements Remaining',
                baseStyle: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: VSTypography.weightMedium,
                ),
              ),
              Text(
                limit == -1 ? 'Unlimited' : '$remaining / $limit',
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: VSTypography.weightBold,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space3),
          LinearProgressIndicator(
            value: progress,
            minHeight: VSDesignTokens.space2,
            borderRadius: BorderRadius.circular(VSDesignTokens.radiusXS),
            backgroundColor: colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
          const SizedBox(height: VSDesignTokens.space2),
          if (limit != -1)
            Text(
              _timeUntilReset,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageUploadSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return VSCard(
      padding: EdgeInsets.zero,
      color: colorScheme.surfaceContainerLow,
      borderRadius: VSDesignTokens.radiusL,
      border: Border.all(
        color: colorScheme.outline.withValues(alpha: 0.3),
        width: 1,
      ),
      child: Container(
        height: VSResponsive.isMobile(context) ? 200 : 250,
        child: _selectedImage == null
          ? VSEmptyState(
              icon: Icons.image_outlined,
              title: 'Select an image to enhance',
              subtitle: 'Choose from gallery or take a new photo',
              action: VSResponsiveBuilder(
                builder: (context, breakpoint) {
                  if (breakpoint == VSBreakpoint.mobile) {
                    return Column(
                      children: [
                        VSButton(
                          text: 'Gallery',
                          icon: const Icon(Icons.photo_library),
                          onPressed: _pickImageFromGallery,
                          variant: VSButtonVariant.outline,
                          size: VSButtonSize.small, // Smaller button
                          isFullWidth: true,
                        ),
                        const SizedBox(height: VSDesignTokens.space1), // Reduced spacing
                        VSButton(
                          text: 'Camera',
                          icon: const Icon(Icons.camera_alt),
                          onPressed: _takePhoto,
                          variant: VSButtonVariant.outline,
                          size: VSButtonSize.small, // Smaller button
                          isFullWidth: true,
                        ),
                      ],
                    );
                  } else {
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        VSButton(
                          text: 'Gallery',
                          icon: const Icon(Icons.photo_library),
                          onPressed: _pickImageFromGallery,
                          variant: VSButtonVariant.outline,
                        ),
                        VSButton(
                          text: 'Camera',
                          icon: const Icon(Icons.camera_alt),
                          onPressed: _takePhoto,
                          variant: VSButtonVariant.outline,
                        ),
                      ],
                    );
                  }
                },
              ),
            )
          : Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(VSDesignTokens.radiusL),
                    image: DecorationImage(
                      image: FileImage(_selectedImage!),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                Positioned(
                  top: VSDesignTokens.space2,
                  right: VSDesignTokens.space2,
                  child: VSAccessibleButton(
                    onPressed: () => setState(() {
                      _selectedImage = null;
                      _enhancedImageUrl = null;
                    }),
                    semanticLabel: 'Remove selected image',
                    tooltip: 'Remove image',
                    backgroundColor: colorScheme.surface.withValues(alpha: 0.9),
                    borderRadius: VSDesignTokens.radiusXL,
                    child: Icon(Icons.close, color: colorScheme.error),
                  ),
                ),
                Positioned(
                  bottom: VSDesignTokens.space2,
                  right: VSDesignTokens.space2,
                  child: Row(
                    children: [
                      VSAccessibleButton(
                        onPressed: _pickImageFromGallery,
                        semanticLabel: 'Change image from gallery',
                        tooltip: 'Change from Gallery',
                        backgroundColor: colorScheme.surface.withValues(alpha: 0.9),
                        borderRadius: VSDesignTokens.radiusXL,
                        child: Icon(Icons.photo_library, color: colorScheme.primary),
                      ),
                      const SizedBox(width: VSDesignTokens.space2),
                      VSAccessibleButton(
                        onPressed: _takePhoto,
                        semanticLabel: 'Take new photo',
                        tooltip: 'Take New Photo',
                        backgroundColor: colorScheme.surface.withValues(alpha: 0.9),
                        borderRadius: VSDesignTokens.radiusXL,
                        child: Icon(Icons.camera_alt, color: colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _buildPromptInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        VSAccessibleTextField(
          controller: _promptController,
          labelText: 'Enhancement Prompt',
          hintText: 'Describe what you want to add or change in the image...',
          semanticLabel: 'Enhancement prompt input field',
          maxLines: 5,
          textAlignVertical: TextAlignVertical.top,
          onChanged: (value) {
            // Optional: Add real-time validation or suggestions
          },
        ),
        const SizedBox(height: VSDesignTokens.space3),
        Row(
          children: [
            Expanded(
              child: VSButton(
                text: 'Improve Prompt',
                icon: _isImproving
                  ? null
                  : const Icon(Icons.auto_awesome),
                onPressed: _isFetchingRandomPrompt ? null : _improvePrompt,
                isLoading: _isImproving,
                variant: VSButtonVariant.outline,
                size: VSButtonSize.medium,
              ),
            ),
            const SizedBox(width: VSDesignTokens.space3),
            Expanded(
              child: VSButton(
                text: 'Surprise Me!',
                icon: _isFetchingRandomPrompt
                  ? null
                  : const Icon(Icons.casino),
                onPressed: _isImproving ? null : _fetchRandomPrompt,
                isLoading: _isFetchingRandomPrompt,
                variant: VSButtonVariant.outline,
                size: VSButtonSize.medium,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEnhancementSettings(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space4),
      color: colorScheme.surfaceContainerLow,
      borderRadius: VSDesignTokens.radiusL,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.tune,
                color: colorScheme.primary,
                size: VSDesignTokens.iconM,
              ),
              const SizedBox(width: VSDesignTokens.space2),
              VSResponsiveText(
                text: 'Enhancement Settings',
                baseStyle: textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: VSTypography.weightSemiBold,
                ),
              ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space4),

          // Enhancement Mode
          Text(
            'Mode',
            style: textTheme.titleSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: VSTypography.weightMedium,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space2),
          DropdownButtonFormField<String>(
            value: _selectedMode,
            items: _enhancementModes.map((String mode) {
              String displayName = mode == 'enhance' ? 'Enhance' : mode == 'edit' ? 'Edit' : 'Variation';
              return DropdownMenuItem<String>(
                value: mode,
                child: Text(
                  displayName,
                  style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
                ),
              );
            }).toList(),
            onChanged: (String? newValue) {
              if (newValue != null) {
                setState(() {
                  _selectedMode = newValue;
                });
              }
            },
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: VSDesignTokens.space3,
                vertical: VSDesignTokens.space2,
              ),
            ),
            dropdownColor: colorScheme.surfaceContainerHigh,
          ),

          const SizedBox(height: VSDesignTokens.space4),

          // Enhancement Strength
          Container(
            padding: const EdgeInsets.all(VSDesignTokens.space3),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
              border: Border.all(
                color: colorScheme.outlineVariant,
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Enhancement Strength: ${(_enhancementStrength * 100).round()}%',
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: VSTypography.weightMedium,
                  ),
                ),
                const SizedBox(height: VSDesignTokens.space2),
                Slider(
                  value: _enhancementStrength,
                  min: 0.1,
                  max: 1.0,
                  divisions: 9,
                  onChanged: (double value) {
                    setState(() {
                      _enhancementStrength = value;
                    });
                  },
                  activeColor: colorScheme.primary,
                  inactiveColor: colorScheme.surfaceContainerHighest,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AspectRatio(
      aspectRatio: 1.0,
      child: VSCard(
        elevation: VSDesignTokens.elevation2,
        color: colorScheme.surfaceContainerLowest,
        margin: EdgeInsets.zero,
        borderRadius: VSDesignTokens.radiusXL,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_enhancedImageUrl == null && !_isLoading)
              VSEmptyState(
                icon: Icons.auto_fix_high,
                title: "Your enhanced image will appear here",
                subtitle: "Select an image and add a prompt to get started",
              ),
            if (_enhancedImageUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
                child: Image.network(
                  _enhancedImageUrl!,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Center(
                      child: VSLoadingIndicator(
                        message: 'Loading enhanced image...',
                        size: VSDesignTokens.iconL,
                        color: colorScheme.primary,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Center(
                    child: VSEmptyState(
                      icon: Icons.broken_image,
                      title: 'Failed to load enhanced image',
                      subtitle: 'Please try again',
                    ),
                  ),
                ),
              ),
            Visibility(
              visible: _isLoading,
              maintainState: true,
              maintainAnimation: true,
              maintainSize: true,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: colorScheme.scrim.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
                ),
                child: Center(
                  child: VSLoadingIndicator(
                    message: 'Enhancing your image...',
                    size: VSDesignTokens.iconXL,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            if (_enhancedImageUrl != null && !_isLoading)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        colorScheme.scrim.withValues(alpha: 0.7),
                        colorScheme.scrim.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 1.0]
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(context, 'Save', Icons.save_alt, _isSavingImage, _saveImage, colorScheme),
                      // Share button logic based on auto-upload setting and share state
                      if (!_autoUploadToGallery && !_isSharedToGallery)
                        // Show share button when auto-upload is OFF and image hasn't been shared
                        _buildActionButton(context, 'Share', Icons.ios_share, _isSharingToGallery, _shareToGallery, colorScheme),
                      if (!_autoUploadToGallery && _isSharedToGallery)
                        // Show "Shared" indicator when auto-upload is OFF and image has been shared
                        _buildActionButton(context, 'Shared', Icons.check_circle_rounded, false, null, colorScheme),
                      // When auto-upload is ON, no share button is shown since it's automatically shared
                    ],
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(BuildContext context, String label, IconData icon, bool isLoading, VoidCallback? onPressed, ColorScheme colorScheme) {
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          onPressed: isLoading ? null : onPressed,
          heroTag: label,
          backgroundColor: colorScheme.surface.withValues(alpha: 0.85),
          foregroundColor: colorScheme.onSurface,
          elevation: 2,
          child: isLoading
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary)))
            : Icon(icon, size: 22),
        ),
        const SizedBox(height: 6),
        Text(label, style: textTheme.labelSmall?.copyWith(color: VSColors.white87, fontWeight: VSTypography.weightMedium)),
      ],
    );
  }

  Widget _buildLastPromptDisplay(BuildContext context) {
    if (_lastSuccessfulPrompt.isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant)
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Last Enhancement Prompt:",
            style: textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            _lastSuccessfulPrompt,
            style: textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.9),
                  fontStyle: FontStyle.italic,
                ),
            maxLines: 3,
            minLines: 1,
          ),
        ],
      ),
    );
  }
}