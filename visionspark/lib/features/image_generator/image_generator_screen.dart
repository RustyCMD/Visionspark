import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image/image.dart' as img;
import '../../shared/utils/snackbar_utils.dart';

class ImageGeneratorScreen extends StatefulWidget {
  const ImageGeneratorScreen({super.key});

  @override
  State<ImageGeneratorScreen> createState() => _ImageGeneratorScreenState();
}

class _ImageGeneratorScreenState extends State<ImageGeneratorScreen> {
  final TextEditingController _promptController = TextEditingController();
  String? _generatedImageUrl;
  bool _isLoading = false;
  bool _isImproving = false;

  int _generationLimit = 3;
  int _generationsToday = 0;
  int _remainingGenerations = 3;
  String? _resetsAtUtcIso;
  String _timeUntilReset = "Calculating...";
  bool _isLoadingStatus = true;
  String? _statusErrorMessage;
  Timer? _resetTimer;
  bool _isSavingImage = false;
  bool _isSharingToGallery = false;
  bool _autoUploadToGallery = false;

  static const MethodChannel _channel = MethodChannel('com.visionspark.app/media');

  // Define your fixed brand colors as static const
  static const Color _lightMutedPeach = Color(0xFFFFDAB9); // Primarily for warnings/errors

  // Original dark text color (useful for light mode elements)
  static const Color _originalDarkText = Color(0xFF22223B);


  @override
  void initState() {
    super.initState();
    _fetchGenerationStatus();
    _loadAutoUploadSetting();
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _updateResetsAtDisplay();
    });
  }

  Future<void> _fetchGenerationStatus() async {
    setState(() {
      _isLoadingStatus = true;
      _statusErrorMessage = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke('get-generation-status');
      if (response.data != null) {
        final data = response.data;
        if (data['error'] != null) {
          setStateIfMounted(() {
            _statusErrorMessage = data['error'].toString();
          });
        } else {
          setStateIfMounted(() {
            _generationLimit = data['limit'] ?? 3;
            _generationsToday = data['generations_today'] ?? 0;
            _remainingGenerations = data['remaining'] ?? _generationLimit - _generationsToday;
            _resetsAtUtcIso = data['resets_at_utc_iso'];
            _updateResetsAtDisplay();
          });
        }
      } else {
        setStateIfMounted(() {
          _statusErrorMessage = 'Failed to fetch generation status: No data received.';
        });
      }
    } catch (e) {
      setStateIfMounted(() {
        _statusErrorMessage = 'Error fetching status: ${e.toString()}';
      });
    }
    setStateIfMounted(() {
      _isLoadingStatus = false;
    });
  }

  void _updateResetsAtDisplay() {
    if (_resetsAtUtcIso == null) {
      setStateIfMounted(() {
        _timeUntilReset = "Reset time: N/A";
      });
      return;
    }
    try {
      final resetTime = DateTime.parse(_resetsAtUtcIso!).toLocal();
      final now = DateTime.now();
      final difference = resetTime.difference(now);

      if (difference.isNegative) {
        _fetchGenerationStatus(); 
        setStateIfMounted(() {
          _timeUntilReset = "Limit has reset or resetting now...";
        });
      } else {
        final hours = difference.inHours;
        final minutes = difference.inMinutes.remainder(60);
        final seconds = difference.inSeconds.remainder(60);
        setStateIfMounted(() {
          _timeUntilReset = "Resets in $hours h $minutes m $seconds s";
        });
      }
    } catch (e) {
      setStateIfMounted(() {
        _timeUntilReset = "Error parsing reset time.";
      });
    }
  }

  Future<void> _generateImage() async {
    if (_promptController.text.isEmpty) {
      showErrorSnackbar(context, 'Please enter a prompt');
      return;
    }

    if (_isImproving) {
      showErrorSnackbar(context, 'Please wait for prompt improvement to finish.');
      return;
    }
    if (_isLoading) {
      return;
    }

    setStateIfMounted(() {
      _isLoading = true;
      _generatedImageUrl = null;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'generate-image-proxy',
        body: {'prompt': _promptController.text},
      );
      if (response.data != null) {
        final data = response.data;
        if (data['error'] != null) {
          String errorMsg = data['error'] is Map ? data['error']['message'] ?? data['error'].toString() : data['error'].toString();
          if (data['resets_at_utc_iso'] != null) {
            _resetsAtUtcIso = data['resets_at_utc_iso'];
            _updateResetsAtDisplay();
          }
          showErrorSnackbar(context, errorMsg);
        } else if (data['data'] != null && data['data'][0]['url'] != null) {
          setStateIfMounted(() {
            _generatedImageUrl = data['data'][0]['url'];
          });
          _fetchGenerationStatus(); 
          if (_autoUploadToGallery) {
            await _shareToGallery();
          }
          setStateIfMounted(() {
            _promptController.clear();
          });
        } else {
          showErrorSnackbar(context, 'Failed to parse image URL from response.');
        }
      } else {
        showErrorSnackbar(context, 'No data received from image generation.');
      }
    } catch (e) {
      showErrorSnackbar(context, 'Image generation error: ${e.toString()}');
    }
    setStateIfMounted(() {
      _isLoading = false;
    });
  }

  Future<Permission> _getAndroidStoragePermission() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final sdkInt = androidInfo.version.sdkInt;
    if (sdkInt >= 33) {
      return Permission.photos;
    } else {
      return Permission.storage; 
    }
  }

  Future<PermissionStatus> _getStoragePermissionStatus() async {
    if (Platform.isIOS) {
      return await Permission.photos.status;
    } else if (Platform.isAndroid) {
      final permission = await _getAndroidStoragePermission();
      return await permission.status;
    }
    return PermissionStatus.denied;
  }

  Future<PermissionStatus> _requestStoragePermission() async {
    if (Platform.isIOS) {
      return await Permission.photos.request();
    } else if (Platform.isAndroid) {
      final permission = await _getAndroidStoragePermission();
      return await permission.request();
    }
    return PermissionStatus.denied;
  }

  Future<void> _saveImage() async {
    if (_generatedImageUrl == null) {
      showErrorSnackbar(context, 'No image to save.');
      return;
    }
    if (_isSavingImage) return;

    setStateIfMounted(() {
      _isSavingImage = true;
    });

    try {
      PermissionStatus status = await _getStoragePermissionStatus();

      if (!status.isGranted) {
         if (status.isPermanentlyDenied) {
          showErrorSnackbar(context, 'Storage permission is permanently denied. Please enable it in app settings.');
          setStateIfMounted(() => _isSavingImage = false);
          return;
        }
        status = await _requestStoragePermission();
      }

      if (status.isGranted) {
        final ByteData imageData = await NetworkAssetBundle(Uri.parse(_generatedImageUrl!)).load('');
        final Uint8List bytes = imageData.buffer.asUint8List();

        final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
        final String filename = 'Visionspark_$timestamp.png';

        try {
          final bool? saveSuccess = await _channel.invokeMethod('saveImageToGallery', {
            'imageBytes': bytes,
            'filename': filename,
            'albumName': 'Visionspark'
          });

          if (saveSuccess == true) {
            showSuccessSnackbar(context, 'Image saved to Gallery as $filename');
          } else {
            showErrorSnackbar(context, 'Failed to save image via native code.');
          }
        } on PlatformException catch (e) {
            showErrorSnackbar(context, 'Failed to save image: ${e.message}');
        }
      } else if (status.isPermanentlyDenied) {
        showErrorSnackbar(context, 'Storage permission is permanently denied. Please enable it in app settings.');
      } else {
         showErrorSnackbar(context, 'Storage permission denied. Cannot save image.');
      }
    } catch (e, s) {
      debugPrint("Error saving image: $e\n$s");
      showErrorSnackbar(context, 'Error saving image: ${e.toString()}');
    } finally {
      setStateIfMounted(() {
        _isSavingImage = false;
      });
    }
  }

  Future<void> _shareToGallery() async {
    if (_generatedImageUrl == null) {
      showErrorSnackbar(context, 'Please generate an image first.');
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      showErrorSnackbar(context, 'You must be logged in to share to the gallery.');
      return;
    }

    setStateIfMounted(() {
      _isSharingToGallery = true;
    });

    String? mainImageStoragePath;
    String? thumbnailStoragePath;

    try {
      final ByteData imageData = await NetworkAssetBundle(Uri.parse(_generatedImageUrl!)).load('');
      final Uint8List imageBytes = imageData.buffer.asUint8List();
      
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      mainImageStoragePath = 'public/${user.id}_${timestamp}.png';

      await Supabase.instance.client.storage
          .from('imagestorage')
          .uploadBinary(
            mainImageStoragePath,
            imageBytes,
            fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
          );

      try {
        final decodedImage = img.decodeImage(imageBytes);
        if (decodedImage != null) {
          final thumbnailImage = img.copyResize(decodedImage, width: 200);
          final thumbnailBytes = Uint8List.fromList(img.encodePng(thumbnailImage));
          thumbnailStoragePath = 'public/${user.id}_${timestamp}_thumb.png';

          await Supabase.instance.client.storage
              .from('imagestorage')
              .uploadBinary(
                thumbnailStoragePath,
                thumbnailBytes,
                fileOptions: const FileOptions(cacheControl: '3600', upsert: false),
              );
          debugPrint('Thumbnail uploaded successfully: $thumbnailStoragePath');
        } else {
          debugPrint('Failed to decode image for thumbnail generation.');
        }
      } catch (thumbError) {
        debugPrint('Error generating or uploading thumbnail: $thumbError');
        thumbnailStoragePath = null;
      }

      await Supabase.instance.client.from('gallery_images').insert({
        'user_id': user.id,
        'image_path': mainImageStoragePath,
        'prompt': _promptController.text,
        'thumbnail_url': thumbnailStoragePath,
      });
      showSuccessSnackbar(context, 'Image shared to gallery successfully!');
    } catch (e) {
      debugPrint('Error sharing to gallery: $e');
      final errorString = e.toString();
      showErrorSnackbar(context, 'Failed to share to gallery: $errorString');
    }
    setStateIfMounted(() {
      _isSharingToGallery = false;
    });
  }


  Future<void> _improvePrompt() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      showErrorSnackbar(context, 'Please enter a prompt to improve.');
      return;
    }

    if (_isLoading) {
      showErrorSnackbar(context, 'Please wait for image generation to finish.');
      return;
    }
    if (_isImproving) {
      return;
    }

    setStateIfMounted(() {
      _isImproving = true;
    });
    try {
      final response = await Supabase.instance.client.functions.invoke(
        'improve-prompt-proxy',
        body: {'prompt': prompt},
      );
      if (response.data != null) {
        final data = response.data;
        if (data['error'] != null) {
          showErrorSnackbar(context, data['error'].toString());
        } else if (data['improved_prompt'] != null) {
          setStateIfMounted(() {
            _promptController.text = data['improved_prompt'].trim();
          });
        } else {
          showErrorSnackbar(context, 'Edge function did not return an improved prompt or an error.');
        }
      } else {
        showErrorSnackbar(context, 'Failed to improve prompt: No data received.');
      }
    } catch (e) {
      showErrorSnackbar(context, 'Error improving prompt: ${e.toString()}');
    }
    setStateIfMounted(() {
      _isImproving = false;
    });
  }

  Future<void> _loadAutoUploadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    setStateIfMounted(() {
      _autoUploadToGallery = prefs.getBool('auto_upload_to_gallery') ?? false;
    });
  }

  void setStateIfMounted(VoidCallback f) {
    if (mounted) {
      setState(f);
    }
  }

  // --- UI Builder Methods ---
  Widget _buildCard({required Widget child}) {
    final Brightness brightness = Theme.of(context).brightness;
    final Color cardBackgroundColor = Theme.of(context).colorScheme.surface;
    final Color shadowColor = brightness == Brightness.light
        ? Colors.grey.withAlpha((255 * 0.1).round())
        : Colors.black.withAlpha((255 * 0.3).round());

    return Container(
      margin: const EdgeInsets.only(bottom: 24.0),
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: cardBackgroundColor,
        borderRadius: BorderRadius.circular(16.0),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildPromptSection({
    required Color primaryContentTextColor,
    required Color secondaryContentTextColor,
    required Color textFieldFillColor,
    required Color textFieldHintColor,
    required Color textFieldInputColor,
  }) {
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enter your prompt below:',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: primaryContentTextColor,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _promptController,
            decoration: InputDecoration(
              hintText: 'Describe your image... (e.g. "A futuristic keyboard")',
              hintStyle: TextStyle(color: textFieldHintColor, fontSize: 15),
              filled: true,
              fillColor: textFieldFillColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.0),
                borderSide: BorderSide(color: _lightMutedPeach, width: 2.0),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            style: TextStyle(fontSize: 15, color: textFieldInputColor),
            maxLines: 3,
            minLines: 1,
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }

  Widget _buildControlsSection({
    required Color primaryContentTextColor,
    required Color secondaryContentTextColor,
    required Color onAccentButtonColor,
    required Color errorBackgroundColor,
    required Color errorTextColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return _buildCard(
      child: Column(
        children: [
          if (_isLoadingStatus)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              child: CircularProgressIndicator(color: colorScheme.primary),
            )
          else if (_statusErrorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: errorBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: errorBackgroundColor.withAlpha((255 * 0.5).round()))
              ),
              child: Text(
                'Error: $_statusErrorMessage',
                style: TextStyle(color: errorTextColor, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            )
          else
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _lightMutedPeach.withAlpha((255 * 0.1).round()),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Generations: $_remainingGenerations/$_generationLimit remaining',
                    style: TextStyle(color: primaryContentTextColor, fontWeight: FontWeight.w500, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeUntilReset,
                    style: TextStyle(color: secondaryContentTextColor, fontSize: 13),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isImproving || _isLoading || _remainingGenerations <= 0 ? null : _improvePrompt,
                  icon: _isImproving
                      ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: onAccentButtonColor))
                      : const Icon(Icons.auto_awesome_outlined, size: 20),
                  label: const Text('Improve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.secondary,
                    foregroundColor: onAccentButtonColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 1,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isLoading || _remainingGenerations <= 0 || _isImproving ? null : _generateImage,
                  icon: _isLoading
                      ? SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: onAccentButtonColor))
                      : const Icon(Icons.image_outlined, size: 20),
                  label: const Text('Generate'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: onAccentButtonColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    elevation: 1,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImageDisplaySection({
    required Color primaryContentTextColor,
    required Color secondaryContentTextColor,
  }) {
    final Color imagePlaceholderBg = Theme.of(context).colorScheme.surface;
    final Color imageBorderColor = Theme.of(context).colorScheme.onSurface.withAlpha((255 * 0.08).round());
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      height: 300,
      margin: const EdgeInsets.only(bottom: 24.0),
      decoration: BoxDecoration(
        color: imagePlaceholderBg,
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(color: imageBorderColor, width: 1.5),
      ),
      child: _generatedImageUrl != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14.5),
              child: Image.network(
                _generatedImageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Center(
                    child: CircularProgressIndicator(
                      value: loadingProgress.expectedTotalBytes != null
                          ? loadingProgress.cumulativeBytesLoaded /
                              loadingProgress.expectedTotalBytes!
                          : null,
                      color: colorScheme.primary,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.broken_image_outlined, size: 48, color: secondaryContentTextColor),
                          const SizedBox(height: 8),
                          Text(
                            'Error loading image',
                            style: TextStyle(color: primaryContentTextColor, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.image_search_outlined, size: 60, color: secondaryContentTextColor),
                    const SizedBox(height: 12),
                    Text(
                      'Your generated image will appear here',
                      style: TextStyle(color: secondaryContentTextColor, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildActionButtons({
    required Color onAccentButtonColor,
  }) {
    if (_generatedImageUrl == null) return const SizedBox.shrink();
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 24.0),
      child: Column(
        children: [
           ElevatedButton.icon(
            onPressed: _isSavingImage ? null : _saveImage,
            icon: _isSavingImage
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: onAccentButtonColor))
                : const Icon(Icons.save_alt_outlined, size: 20),
            label: const Text('Save to Device'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.secondary,
              foregroundColor: onAccentButtonColor,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _isSharingToGallery ? null : _shareToGallery,
            icon: _isSharingToGallery
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: onAccentButtonColor))
                : const Icon(Icons.ios_share_outlined, size: 20),
            label: const Text('Share to Gallery'),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: onAccentButtonColor,
              minimumSize: const Size(double.infinity, 48),
              padding: const EdgeInsets.symmetric(vertical: 12),
              textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Brightness brightness = Theme.of(context).brightness;
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    final Color scaffoldBackgroundColor = colorScheme.surface;
    final Color appBarBackgroundColor = brightness == Brightness.light ? Colors.white : colorScheme.surface;
    final Color appBarIconColor = brightness == Brightness.light ? _originalDarkText : Colors.white.withAlpha((255 * 0.9).round());
    final Color appBarTitleColor = appBarIconColor;

    final Color primaryContentTextColor = brightness == Brightness.light ? _originalDarkText : Colors.white.withAlpha((255 * 0.9).round());
    final Color secondaryContentTextColor = brightness == Brightness.light ? Colors.grey.shade600 : Colors.grey.shade400;

    final Color onAccentButtonColor = brightness == Brightness.light ? _originalDarkText : Colors.white;

    final Color textFieldFillColor = brightness == Brightness.light ? colorScheme.surface : colorScheme.surfaceContainerHighest.withAlpha((255 * 0.3).round());
    final Color textFieldHintColor = secondaryContentTextColor;
    final Color textFieldInputColor = primaryContentTextColor;

    final Color errorBackgroundColor = brightness == Brightness.light ? _lightMutedPeach.withAlpha((255 * 0.8).round()) : Colors.red.shade900.withAlpha((255 * 0.4).round());
    final Color errorTextColor = brightness == Brightness.light ? primaryContentTextColor.withAlpha((255 * 0.8).round()) : Colors.red.shade100;


    return Scaffold(
      backgroundColor: scaffoldBackgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildPromptSection(
                primaryContentTextColor: primaryContentTextColor,
                secondaryContentTextColor: secondaryContentTextColor,
                textFieldFillColor: textFieldFillColor,
                textFieldHintColor: textFieldHintColor,
                textFieldInputColor: textFieldInputColor,
              ),
              _buildControlsSection(
                primaryContentTextColor: primaryContentTextColor,
                secondaryContentTextColor: secondaryContentTextColor,
                onAccentButtonColor: onAccentButtonColor,
                errorBackgroundColor: errorBackgroundColor,
                errorTextColor: errorTextColor,
              ),
              _buildImageDisplaySection(
                primaryContentTextColor: primaryContentTextColor,
                secondaryContentTextColor: secondaryContentTextColor,
              ),
              _buildActionButtons(
                onAccentButtonColor: onAccentButtonColor,
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _promptController.dispose();
    _resetTimer?.cancel();
    super.dispose();
  }
}