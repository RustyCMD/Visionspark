import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/design_system/design_system.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';
import '../../shared/utils/snackbar_utils.dart';

const _kCachedLimit = 'cached_enhancement_limit';
const _kCachedUsed  = 'cached_enhancements_today';
const _kCachedReset = 'cached_enhancement_resets_at_utc_iso';

class ImageEnhancementScreen extends StatefulWidget {
  const ImageEnhancementScreen({super.key});

  @override
  State<ImageEnhancementScreen> createState() => _ImageEnhancementScreenState();
}

class _ImageEnhancementScreenState extends State<ImageEnhancementScreen> {
  // Feature flag — left in place from the original codebase.
  static const bool _enabled = false;
  static const String _disabledMsg =
      'Enhancement is paused for maintenance — check back soon.';

  static const _channel = MethodChannel('com.visionspark.app/media');
  final _picker = ImagePicker();
  final _prompt = TextEditingController();

  File? _file;
  String? _enhancedUrl;
  bool _isLoading = false;
  bool _isImproving = false;
  bool _isFetchingRandom = false;
  bool _isSaving = false;
  bool _isSharing = false;
  bool _isShared = false;

  int _limit = 4;
  int _used = 0;
  String? _resetIso;
  String _resetText = 'Calculating...';
  bool _statusLoading = true;
  String? _statusError;
  Timer? _resetTimer;

  String _lastPrompt = '';
  bool _autoUpload = false;
  String _mode = 'enhance';
  double _strength = 0.7;

  SubscriptionStatusNotifier? _subNotifier;

  @override
  void initState() {
    super.initState();
    _loadCached();
    _fetchStatus();
    _loadAutoUpload();
    _resetTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tickReset());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final n = Provider.of<SubscriptionStatusNotifier>(context, listen: false);
    if (_subNotifier != n) {
      _subNotifier?.removeListener(_fetchStatus);
      _subNotifier = n;
      _subNotifier?.addListener(_fetchStatus);
    }
    _loadAutoUpload();
  }

  @override
  void dispose() {
    _prompt.dispose();
    _resetTimer?.cancel();
    _subNotifier?.removeListener(_fetchStatus);
    super.dispose();
  }

  // ── Status ──────────────────────────────────────────────────────────────

  Future<void> _loadCached() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _limit = p.getInt(_kCachedLimit) ?? 4;
      _used = p.getInt(_kCachedUsed) ?? 0;
      _resetIso = p.getString(_kCachedReset);
      if (_resetIso != null) _tickReset();
    });
  }

  Future<void> _saveCached() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCachedLimit, _limit);
    await p.setInt(_kCachedUsed, _used);
    if (_resetIso != null) await p.setString(_kCachedReset, _resetIso!);
  }

  Future<void> _loadAutoUpload() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _autoUpload = p.getBool('auto_upload_to_gallery') ?? false);
  }

  Future<void> _fetchStatus() async {
    if (!mounted) return;
    setState(() => _statusLoading = true);
    try {
      final resp = await Supabase.instance.client.functions
          .invoke('get-generation-status');
      if (!mounted) return;
      final data = resp.data;
      if (data['error'] != null) {
        setState(() => _statusError = data['error'].toString());
      } else {
        setState(() {
          _limit = (data['enhancement_limit'] ?? data['limit'] ?? 4) as int;
          _used = (data['enhancements_today'] ?? data['generations_today'] ?? 0) as int;
          _resetIso = data['resets_at_utc_iso'] as String?;
          _statusError = null;
          _tickReset();
          _saveCached();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statusError = e.toString());
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  void _tickReset() {
    if (_resetIso == null) return;
    final reset = DateTime.tryParse(_resetIso!)?.toLocal();
    if (reset == null) return;
    final diff = reset.difference(DateTime.now());
    final next = diff.isNegative
        ? 'Limit reset!'
        : 'Resets in ${diff.inHours}h ${diff.inMinutes.remainder(60)}m';
    if (next != _resetText && mounted) {
      setState(() => _resetText = next);
    }
  }

  // ── Picker / actions ───────────────────────────────────────────────────

  Future<void> _pickFromGallery() async {
    try {
      final f = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
      if (f != null && mounted) setState(() {
        _file = File(f.path);
        _enhancedUrl = null;
      });
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not pick image: $e');
    }
  }

  Future<void> _takePhoto() async {
    try {
      final f = await _picker.pickImage(source: ImageSource.camera, imageQuality: 85);
      if (f != null && mounted) setState(() {
        _file = File(f.path);
        _enhancedUrl = null;
      });
    } catch (e) {
      if (mounted) showErrorSnackbar(context, 'Could not take photo: $e');
    }
  }

  Future<void> _improvePrompt() async {
    final text = _prompt.text.trim();
    if (text.isEmpty || _isLoading || _isImproving) return;
    FocusScope.of(context).unfocus();
    setState(() => _isImproving = true);
    try {
      final resp = await Supabase.instance.client.functions
          .invoke('improve-prompt-proxy', body: {'prompt': text});
      if (!mounted) return;
      if (resp.data['error'] != null) {
        showErrorSnackbar(context, resp.data['error'].toString());
      } else if (resp.data['improved_prompt'] != null) {
        _prompt.text = resp.data['improved_prompt'].toString().trim();
        showSuccessSnackbar(context, 'Prompt improved.');
      }
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not improve prompt.');
    } finally {
      if (mounted) setState(() => _isImproving = false);
    }
  }

  Future<void> _fetchRandom() async {
    if (_isLoading || _isImproving || _isFetchingRandom) return;
    FocusScope.of(context).unfocus();
    setState(() => _isFetchingRandom = true);
    try {
      final resp = await Supabase.instance.client.functions.invoke('get-random-prompt');
      if (!mounted) return;
      if (resp.data?['prompt'] != null) {
        _prompt.text = resp.data['prompt'] as String;
        showSuccessSnackbar(context, 'New prompt loaded.');
      } else if (resp.data?['error'] != null) {
        showErrorSnackbar(context, resp.data['error'].toString());
      } else {
        showErrorSnackbar(context, 'Could not fetch a prompt.');
      }
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not fetch a prompt.');
    } finally {
      if (mounted) setState(() => _isFetchingRandom = false);
    }
  }

  Future<void> _enhance() async {
    if (_file == null || _prompt.text.trim().isEmpty || _isLoading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isLoading = true;
      _enhancedUrl = null;
      _isShared = false;
    });
    try {
      final bytes = await _file!.readAsBytes();
      if (bytes.length > 10 * 1024 * 1024) {
        if (mounted) showErrorSnackbar(context, 'Image must be under 10MB.');
        return;
      }
      final base64 = await compute(_pngBase64, bytes);
      final resp = await Supabase.instance.client.functions.invoke(
        'enhance-image-proxy',
        body: {
          'image': base64,
          'prompt': _prompt.text.trim(),
          'mode': _mode,
          'strength': _strength,
        },
      );
      if (!mounted) return;
      final data = resp.data;
      if (data['error'] != null) {
        showErrorSnackbar(context, _readableError(data['error'].toString()));
      } else if (data['data']?[0]?['url'] != null) {
        setState(() {
          _enhancedUrl = data['data'][0]['url'] as String;
          _lastPrompt = _prompt.text;
        });
        await _fetchStatus();
        if (_autoUpload) {
          await _share();
          if (mounted) setState(() => _isShared = true);
        }
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, _readableError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _readableError(String s) {
    final l = s.toLowerCase();
    if (l.contains('safety system') || l.contains('content policy')) {
      return 'Content policy: please rephrase your prompt.';
    }
    return s;
  }

  Future<void> _save() async {
    if (_enhancedUrl == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final perm = Platform.isAndroid
          ? ((await DeviceInfoPlugin().androidInfo).version.sdkInt >= 33
              ? Permission.photos
              : Permission.storage)
          : Permission.photos;
      if (!(await perm.request()).isGranted) {
        if (mounted) showErrorSnackbar(context, 'Storage permission required.');
        return;
      }
      final res = await http.get(Uri.parse(_enhancedUrl!));
      if (res.statusCode != 200) throw Exception('Download failed');
      await _channel.invokeMethod('saveImageToGallery', {
        'imageBytes': res.bodyBytes,
        'filename': 'Visionspark_Enhanced_${DateTime.now().millisecondsSinceEpoch}.png',
        'albumName': 'Visionspark',
      });
      if (mounted) showSuccessSnackbar(context, 'Image saved.');
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not save image.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _share() async {
    if (_enhancedUrl == null || _isSharing) return;
    setState(() => _isSharing = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not signed in');
      final res = await http.get(Uri.parse(_enhancedUrl!));
      if (res.statusCode != 200) throw Exception('Download failed');
      final ts = DateTime.now().millisecondsSinceEpoch;
      final mainPath = 'public/${user.id}_enhanced_$ts.png';
      await Supabase.instance.client.storage
          .from('imagestorage')
          .uploadBinary(mainPath, res.bodyBytes);
      String? thumbPath;
      try {
        final thumb = await compute(_thumb, res.bodyBytes);
        thumbPath = 'public/${user.id}_enhanced_${ts}_thumb.png';
        await Supabase.instance.client.storage
            .from('imagestorage')
            .uploadBinary(thumbPath, thumb);
      } catch (_) {/* non-fatal */}
      await Supabase.instance.client.from('gallery_images').insert({
        'user_id': user.id,
        'image_path': mainPath,
        'prompt': _prompt.text,
        'thumbnail_url': thumbPath,
      });
      if (mounted) {
        setState(() => _isShared = true);
        showSuccessSnackbar(context, 'Shared to gallery.');
      }
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not share.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  static String _pngBase64(Uint8List bytes) {
    final dec = img.decodeImage(bytes);
    if (dec == null) throw Exception('Decode failed');
    return base64Encode(img.encodePng(dec));
  }

  static Uint8List _thumb(Uint8List bytes) {
    final dec = img.decodeImage(bytes);
    if (dec == null) throw Exception('Decode failed');
    return Uint8List.fromList(img.encodePng(img.copyResize(dec, width: 200)));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return _DisabledView(message: _disabledMsg);

    final remaining = _limit == -1 ? 999 : _limit - _used;
    final canEnhance = _file != null &&
        _prompt.text.trim().isNotEmpty &&
        !_isLoading &&
        !_isImproving &&
        !_isFetchingRandom &&
        (_limit == -1 || remaining > 0);

    return Scaffold(
      body: VSResponsiveLayout(
        child: SafeArea(
          child: ListView(
            padding: VSResponsive.getResponsivePadding(context),
            children: [
              _StatusCard(
                limit: _limit,
                remaining: remaining,
                isLoading: _statusLoading,
                error: _statusError,
                resetText: _resetText,
              ),
              const SizedBox(height: VSDesignTokens.space5),
              _imagePicker(),
              const SizedBox(height: VSDesignTokens.space5),
              _promptCard(),
              const SizedBox(height: VSDesignTokens.space5),
              _settingsCard(),
              const SizedBox(height: VSDesignTokens.space5),
              _resultCard(),
              if (_lastPrompt.isNotEmpty) ...[
                const SizedBox(height: VSDesignTokens.space4),
                _lastPromptCard(),
              ],
              const SizedBox(height: VSDesignTokens.space6),
              VSButton(
                text: _isLoading ? 'Enhancing…' : 'Enhance image',
                icon: _isLoading ? null : const Icon(Icons.auto_fix_high),
                onPressed: canEnhance ? _enhance : null,
                isLoading: _isLoading,
                isFullWidth: true,
                size: VSButtonSize.large,
              ),
              const SizedBox(height: VSDesignTokens.space12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _imagePicker() {
    final cs = Theme.of(context).colorScheme;
    return VSCard(
      padding: EdgeInsets.zero,
      borderRadius: VSDesignTokens.radiusXL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.outlineVariant),
      child: SizedBox(
        height: 220,
        child: _file == null
            ? VSEmptyState(
                icon: Icons.add_photo_alternate_outlined,
                title: 'Choose an image to enhance',
                subtitle: 'Pick from gallery or capture a new photo.',
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VSButton(
                      text: 'Gallery',
                      icon: const Icon(Icons.photo_library_outlined),
                      onPressed: _pickFromGallery,
                      variant: VSButtonVariant.outline,
                    ),
                    const SizedBox(width: VSDesignTokens.space3),
                    VSButton(
                      text: 'Camera',
                      icon: const Icon(Icons.camera_alt_outlined),
                      onPressed: _takePhoto,
                      variant: VSButtonVariant.outline,
                    ),
                  ],
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
                    child: Image.file(_file!, fit: BoxFit.cover),
                  ),
                  Positioned(
                    top: VSDesignTokens.space2,
                    right: VSDesignTokens.space2,
                    child: _circleAction(
                      icon: Icons.close_rounded,
                      tooltip: 'Remove',
                      onTap: () => setState(() {
                        _file = null;
                        _enhancedUrl = null;
                      }),
                    ),
                  ),
                  Positioned(
                    bottom: VSDesignTokens.space2,
                    right: VSDesignTokens.space2,
                    child: Row(
                      children: [
                        _circleAction(
                          icon: Icons.photo_library_outlined,
                          tooltip: 'Pick another',
                          onTap: _pickFromGallery,
                        ),
                        const SizedBox(width: VSDesignTokens.space2),
                        _circleAction(
                          icon: Icons.camera_alt_outlined,
                          tooltip: 'Retake',
                          onTap: _takePhoto,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _circleAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface.withValues(alpha: 0.9),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        icon: Icon(icon, color: cs.primary),
        onPressed: onTap,
      ),
    );
  }

  Widget _promptCard() {
    final cs = Theme.of(context).colorScheme;
    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      borderRadius: VSDesignTokens.radiusXL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.outlineVariant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const VSSectionHeader(
            icon: Icons.edit_note_rounded,
            title: 'Enhancement prompt',
            subtitle: 'Describe what to add, change, or stylize.',
          ),
          const SizedBox(height: VSDesignTokens.space4),
          VSAccessibleTextField(
            controller: _prompt,
            labelText: 'Prompt',
            hintText: 'Make it cinematic, golden hour…',
            maxLines: 5,
            textAlignVertical: TextAlignVertical.top,
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: VSDesignTokens.space3),
          Row(
            children: [
              Expanded(
                child: VSButton(
                  text: _isImproving ? 'Improving…' : 'Improve',
                  icon: _isImproving ? null : const Icon(Icons.auto_fix_high_outlined),
                  onPressed:
                      _isFetchingRandom || _isImproving ? null : _improvePrompt,
                  isLoading: _isImproving,
                  variant: VSButtonVariant.outline,
                ),
              ),
              const SizedBox(width: VSDesignTokens.space3),
              Expanded(
                child: VSButton(
                  text: _isFetchingRandom ? 'Loading…' : 'Surprise me',
                  icon: _isFetchingRandom ? null : const Icon(Icons.casino_outlined),
                  onPressed:
                      _isImproving || _isFetchingRandom ? null : _fetchRandom,
                  isLoading: _isFetchingRandom,
                  variant: VSButtonVariant.outline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingsCard() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      borderRadius: VSDesignTokens.radiusXL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.outlineVariant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const VSSectionHeader(
            icon: Icons.tune_rounded,
            title: 'Settings',
            subtitle: 'Choose mode and intensity.',
          ),
          const SizedBox(height: VSDesignTokens.space4),
          Wrap(
            spacing: VSDesignTokens.space2,
            runSpacing: VSDesignTokens.space2,
            children: [
              for (final m in const ['enhance', 'edit', 'variation'])
                _ModeChip(
                  label: m[0].toUpperCase() + m.substring(1),
                  selected: _mode == m,
                  onTap: () => setState(() => _mode = m),
                ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Strength',
                style: tt.titleSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: VSTypography.weightSemiBold,
                ),
              ),
              Text(
                '${(_strength * 100).round()}%',
                style: tt.titleSmall?.copyWith(
                  color: cs.primary,
                  fontWeight: VSTypography.weightBold,
                ),
              ),
            ],
          ),
          Slider(
            value: _strength,
            min: 0.1,
            max: 1.0,
            divisions: 9,
            onChanged: (v) => setState(() => _strength = v),
          ),
        ],
      ),
    );
  }

  Widget _resultCard() {
    final cs = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_enhancedUrl == null && !_isLoading)
                const VSEmptyState(
                  icon: Icons.auto_fix_high_outlined,
                  title: 'Your enhanced image will appear here',
                  subtitle: 'Pick an image and add a prompt to get started.',
                ),
              if (_enhancedUrl != null)
                Image.network(
                  _enhancedUrl!,
                  fit: BoxFit.cover,
                  loadingBuilder: (_, child, p) => p == null
                      ? child
                      : Center(
                          child: VSLoadingIndicator(
                            message: 'Loading enhanced image…',
                            color: cs.primary,
                          ),
                        ),
                  errorBuilder: (_, __, ___) => const Center(
                    child: VSEmptyState(
                      icon: Icons.broken_image_outlined,
                      title: 'Failed to load',
                    ),
                  ),
                ),
              if (_isLoading)
                Container(
                  color: Colors.black.withValues(alpha: 0.55),
                  child: Center(
                    child: VSLoadingIndicator(
                      message: 'Enhancing your image…',
                      color: Colors.white,
                    ),
                  ),
                ),
              if (_enhancedUrl != null && !_isLoading)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(VSDesignTokens.space3),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.65),
                          Colors.transparent,
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _MiniAction(
                          icon: Icons.download_rounded,
                          label: 'Save',
                          loading: _isSaving,
                          onTap: _save,
                        ),
                        if (!_autoUpload && !_isShared)
                          _MiniAction(
                            icon: Icons.share_rounded,
                            label: 'Share',
                            loading: _isSharing,
                            onTap: _share,
                          ),
                        if (!_autoUpload && _isShared)
                          _MiniAction(
                            icon: Icons.check_circle_rounded,
                            label: 'Shared',
                            loading: false,
                            onTap: null,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lastPromptCard() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space4),
      borderRadius: VSDesignTokens.radiusL,
      color: cs.surfaceContainerLow,
      border: Border.all(color: cs.outlineVariant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last enhancement prompt',
            style: tt.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: VSTypography.weightSemiBold,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            _lastPrompt,
            style: tt.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant.withValues(alpha: 0.9),
              fontStyle: FontStyle.italic,
            ),
            maxLines: 3,
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final int limit;
  final int remaining;
  final bool isLoading;
  final String? error;
  final String resetText;
  const _StatusCard({
    required this.limit,
    required this.remaining,
    required this.isLoading,
    required this.error,
    required this.resetText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (isLoading) {
      return VSCard(
        padding: const EdgeInsets.all(VSDesignTokens.space4),
        borderRadius: VSDesignTokens.radiusL,
        color: cs.surfaceContainer,
        child: Center(child: VSLoadingIndicator(message: 'Loading status…')),
      );
    }
    if (error != null) {
      return VSCard(
        padding: const EdgeInsets.all(VSDesignTokens.space4),
        borderRadius: VSDesignTokens.radiusL,
        color: cs.errorContainer,
        child: Text(
          error!,
          style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer),
          textAlign: TextAlign.center,
        ),
      );
    }
    final progress = limit < 0 ? 1.0 : limit == 0 ? 0.0 : (remaining / limit).clamp(0.0, 1.0);
    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space4),
      borderRadius: VSDesignTokens.radiusL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.outlineVariant),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Enhancements remaining',
                style: tt.titleSmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: VSTypography.weightSemiBold,
                ),
              ),
              Text(
                limit == -1 ? 'Unlimited' : '$remaining / $limit',
                style: tt.titleMedium?.copyWith(
                  color: cs.onSurface,
                  fontWeight: VSTypography.weightBold,
                ),
              ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space3),
          ClipRRect(
            borderRadius: BorderRadius.circular(VSDesignTokens.radiusXS),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: cs.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation(cs.primary),
            ),
          ),
          if (limit != -1) ...[
            const SizedBox(height: VSDesignTokens.space2),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                resetText,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _ModeChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onPrimary : cs.onSurface;
    final bg = selected ? cs.primary : cs.surfaceContainerHigh;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space4,
            vertical: VSDesignTokens.space3,
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: selected
                  ? VSTypography.weightSemiBold
                  : VSTypography.weightMedium,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: cs.surface.withValues(alpha: 0.9),
          shape: const CircleBorder(),
          child: IconButton(
            onPressed: loading ? null : onTap,
            icon: loading
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                  )
                : Icon(icon, color: cs.primary),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: VSTypography.weightSemiBold,
          ),
        ),
      ],
    );
  }
}

class _DisabledView extends StatelessWidget {
  final String message;
  const _DisabledView({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      body: VSResponsiveLayout(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: VSResponsive.getResponsivePadding(context),
              child: VSCard(
                padding: const EdgeInsets.all(VSDesignTokens.space6),
                borderRadius: VSDesignTokens.radiusXL,
                color: cs.surfaceContainer,
                border: Border.all(color: cs.outlineVariant),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(VSDesignTokens.space5),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.4),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.construction_rounded,
                        color: cs.primary,
                        size: VSDesignTokens.iconL,
                      ),
                    ),
                    const SizedBox(height: VSDesignTokens.space4),
                    Text(
                      'Paused for maintenance',
                      style: tt.headlineSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: VSTypography.weightBold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: VSDesignTokens.space2),
                    Text(
                      message,
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
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
}
