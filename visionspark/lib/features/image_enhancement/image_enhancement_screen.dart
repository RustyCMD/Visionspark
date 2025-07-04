import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
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

class ImageEnhancementScreen extends StatefulWidget {
  const ImageEnhancementScreen({super.key});

  @override
  State<ImageEnhancementScreen> createState() => _ImageEnhancementScreenState();
}

class _ImageEnhancementScreenState extends State<ImageEnhancementScreen> {
  final _promptController = TextEditingController();
  final _picker = ImagePicker();
  
  File? _selectedImage;
  String? _enhancedImageUrl;
  bool _isLoading = false;
  bool _isImproving = false;
  bool _isUploadingImage = false;
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
    setState(() { _isLoading = true; _enhancedImageUrl = null; });

    try {
      // Convert image to base64
      final imageBytes = await _selectedImage!.readAsBytes();
      final base64Image = base64Encode(imageBytes);

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
          showErrorSnackbar(context, data['error'].toString());
        } else if (data['data'] != null && data['data'][0]['url'] != null) {
          setState(() {
            _enhancedImageUrl = data['data'][0]['url'];
            _lastSuccessfulPrompt = _promptController.text;
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
      debugPrint('Image enhancement error: $e');
      if (mounted) showErrorSnackbar(context, 'An unexpected error occurred during image enhancement. Please try again.');
    }
    if (mounted) setState(() => _isLoading = false);
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
        final ByteData imageData = await NetworkAssetBundle(Uri.parse(_enhancedImageUrl!)).load('');
        final filename = 'Visionspark_Enhanced_${DateTime.now().millisecondsSinceEpoch}.png';
        await _channel.invokeMethod('saveImageToGallery', {
          'imageBytes': imageData.buffer.asUint8List(),
          'filename': filename,
          'albumName': 'Visionspark'
        });
        if (mounted) showSuccessSnackbar(context, 'Enhanced image saved to Gallery!');
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

      final ByteData imageData = await NetworkAssetBundle(Uri.parse(_enhancedImageUrl!)).load('');
      final imageBytes = imageData.buffer.asUint8List();
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

      if (mounted) showSuccessSnackbar(context, 'Enhanced image shared to gallery!');
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
              _buildImageUploadSection(context),
              const SizedBox(height: 24),
              _buildPromptInput(context),
              const SizedBox(height: 16),
              _buildEnhancementSettings(context),
              const SizedBox(height: 24),
              _buildResultSection(context),
              const SizedBox(height: 24),
              _buildLastPromptDisplay(context),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: (_selectedImage == null || _promptController.text.isEmpty || (remaining <= 0 && _generationLimit != -1) || _isLoading || _isFetchingRandomPrompt || _isImproving) ? null : _enhanceImage,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text('Enhance Image'),
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

    double progress = limit <= 0 ? 1.0 : (remaining / limit).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Enhancements Remaining', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
              Text(
                limit == -1 ? 'Unlimited' : '$remaining / $limit',
                style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: colorScheme.surfaceVariant,
            valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
          ),
          const SizedBox(height: 8),
          if (limit != -1)
            Text(_timeUntilReset, style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8))),
        ],
      ),
    );
  }

  Widget _buildImageUploadSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withOpacity(0.3)),
      ),
      child: _selectedImage == null 
        ? Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_outlined, size: 48, color: colorScheme.onSurfaceVariant.withOpacity(0.6)),
              const SizedBox(height: 16),
              Text('Select an image to enhance', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickImageFromGallery,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('Gallery'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _takePhoto,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text('Camera'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                  ),
                ],
              ),
            ],
          )
        : Stack(
            children: [
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: DecorationImage(
                    image: FileImage(_selectedImage!),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    onPressed: () => setState(() {
                      _selectedImage = null;
                      _enhancedImageUrl = null;
                    }),
                    icon: Icon(Icons.close, color: colorScheme.error),
                  ),
                ),
              ),
              Positioned(
                bottom: 8,
                right: 8,
                child: Row(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        onPressed: _pickImageFromGallery,
                        icon: Icon(Icons.photo_library, color: colorScheme.primary),
                        tooltip: 'Change from Gallery',
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surface.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: IconButton(
                        onPressed: _takePhoto,
                        icon: Icon(Icons.camera_alt, color: colorScheme.primary),
                        tooltip: 'Take New Photo',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
    );
  }

  Widget _buildPromptInput(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return TextField(
      controller: _promptController,
      minLines: 3,
      maxLines: 5,
      decoration: InputDecoration(
        hintText: 'Describe what you want to add or change in the image...',
        labelText: 'Enhancement Prompt',
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

  Widget _buildEnhancementSettings(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Enhancement Settings', style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurface)),
        const SizedBox(height: 16),
        
        // Enhancement Mode
        Text('Mode', style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedMode,
          items: _enhancementModes.map((String mode) {
            String displayName = mode == 'enhance' ? 'Enhance' : mode == 'edit' ? 'Edit' : 'Variation';
            return DropdownMenuItem<String>(
              value: mode,
              child: Text(displayName, style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface)),
            );
          }).toList(),
          onChanged: (String? newValue) {
            if (newValue != null) {
              setState(() {
                _selectedMode = newValue;
              });
            }
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          dropdownColor: colorScheme.surfaceContainerHigh,
        ),
        
        const SizedBox(height: 16),
        
        // Enhancement Strength
        Text('Enhancement Strength: ${(_enhancementStrength * 100).round()}%', 
             style: textTheme.titleSmall?.copyWith(color: colorScheme.onSurfaceVariant)),
        const SizedBox(height: 8),
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
          inactiveColor: colorScheme.surfaceVariant,
        ),
      ],
    );
  }

  Widget _buildResultSection(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return AspectRatio(
      aspectRatio: 1.0,
      child: Card(
        elevation: 2,
        color: colorScheme.surfaceContainerLowest,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_enhancedImageUrl == null && !_isLoading)
              Container(
                color: colorScheme.surfaceContainerLow,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.auto_fix_high, size: 64, color: colorScheme.onSurfaceVariant.withOpacity(0.6)),
                    const SizedBox(height: 16),
                    Text("Your enhanced image will appear here", style: textTheme.titleMedium?.copyWith(color: colorScheme.onSurfaceVariant.withOpacity(0.8))),
                  ],
                ),
              ),
            if (_enhancedImageUrl != null)
              Image.network(
                _enhancedImageUrl!,
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
                    Text("Enhancing...", style: textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                  ],
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
                        colorScheme.scrim.withOpacity(0.7),
                        colorScheme.scrim.withOpacity(0.0),
                      ],
                      stops: const [0.0, 1.0]
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildActionButton(context, 'Save', Icons.save_alt, _isSavingImage, _saveImage, colorScheme),
                      _buildActionButton(context, 'Share', Icons.ios_share, _isSharingToGallery, _shareToGallery, colorScheme),
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
    final TextTheme textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          onPressed: isLoading ? null : onPressed,
          heroTag: label,
          backgroundColor: colorScheme.surface.withOpacity(0.85),
          foregroundColor: colorScheme.onSurface,
          elevation: 2,
          child: isLoading
            ? SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary)))
            : Icon(icon, size: 22),
        ),
        const SizedBox(height: 6),
        Text(label, style: textTheme.labelSmall?.copyWith(color: Colors.white.withOpacity(0.9), fontWeight: FontWeight.w500)),
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
}