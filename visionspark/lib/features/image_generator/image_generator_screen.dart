import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../shared/design_system/design_system.dart';
import '../../shared/notifiers/subscription_status_notifier.dart';
import '../../shared/utils/snackbar_utils.dart';

const _kCachedLimit = 'cached_generation_limit';
const _kCachedGenerationsToday = 'cached_generations_today';
const _kCachedResetsAt = 'cached_resets_at_utc_iso';

class _AspectOption {
  final String label;
  final String value;
  final IconData icon;
  final double ratio;
  const _AspectOption(this.label, this.value, this.icon, this.ratio);
}

class _StyleOption {
  final String key;
  final String label;
  final IconData icon;
  const _StyleOption(this.key, this.label, this.icon);
}

class ImageGeneratorScreen extends StatefulWidget {
  const ImageGeneratorScreen({super.key});

  @override
  State<ImageGeneratorScreen> createState() => _ImageGeneratorScreenState();
}

class _ImageGeneratorScreenState extends State<ImageGeneratorScreen> {
  static const _channel = MethodChannel('com.visionspark.app/media');

  final _prompt = TextEditingController();
  final _negative = TextEditingController();
  final _promptFocus = FocusNode();
  final _negativeFocus = FocusNode();

  String? _imageUrl;
  String _lastPrompt = '';
  bool _isGenerating = false;
  bool _isImproving = false;
  bool _isFetchingRandom = false;
  bool _isSaving = false;
  bool _isSharing = false;
  bool _isShared = false;

  int _limit = 3;
  int _used = 0;
  String? _resetsIso;
  String _resetText = 'Calculating...';
  bool _statusLoading = true;
  String? _statusError;
  Timer? _resetTimer;

  bool _showAdvanced = false;
  bool _autoUpload = false;
  String _aspect = '1024x1024';
  String _style = 'None';

  SubscriptionStatusNotifier? _subNotifier;

  static const _aspects = [
    _AspectOption('Square', '1024x1024', Icons.crop_square_rounded, 1.0),
    _AspectOption('Landscape', '1792x1024', Icons.crop_landscape_rounded, 1792 / 1024),
    _AspectOption('Portrait', '1024x1792', Icons.crop_portrait_rounded, 1024 / 1792),
  ];

  static const _styles = {
    'None':    _StyleOption('None',    'Default', Icons.auto_awesome_outlined),
    'vivid':   _StyleOption('vivid',   'Vivid',   Icons.palette_outlined),
    'natural': _StyleOption('natural', 'Natural', Icons.eco_outlined),
  };

  @override
  void initState() {
    super.initState();
    _loadCachedStatus();
    _fetchStatus();
    _loadAutoUpload();
    _resetTimer = Timer.periodic(const Duration(seconds: 1), (_) => _tickReset());
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
    _negative.dispose();
    _promptFocus.dispose();
    _negativeFocus.dispose();
    _resetTimer?.cancel();
    _subNotifier?.removeListener(_fetchStatus);
    super.dispose();
  }

  // ── Status helpers ──────────────────────────────────────────────────────

  Future<void> _loadCachedStatus() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _limit = p.getInt(_kCachedLimit) ?? 3;
      _used = p.getInt(_kCachedGenerationsToday) ?? 0;
      _resetsIso = p.getString(_kCachedResetsAt);
      if (_resetsIso != null) _tickReset();
    });
  }

  Future<void> _saveCachedStatus() async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kCachedLimit, _limit);
    await p.setInt(_kCachedGenerationsToday, _used);
    if (_resetsIso != null) await p.setString(_kCachedResetsAt, _resetsIso!);
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
      final resp = await Supabase.instance.client.functions.invoke('get-generation-status');
      if (!mounted) return;
      final data = resp.data;
      if (data['error'] != null) {
        setState(() => _statusError = data['error'].toString());
      } else {
        setState(() {
          _limit = (data['generation_limit'] ?? data['limit'] ?? 3) as int;
          _used = (data['generations_today'] ?? 0) as int;
          _resetsIso = data['resets_at_utc_iso'] as String?;
          _statusError = null;
          _tickReset();
          _saveCachedStatus();
        });
      }
    } catch (e) {
      if (mounted) setState(() => _statusError = e.toString());
    } finally {
      if (mounted) setState(() => _statusLoading = false);
    }
  }

  void _tickReset() {
    if (_resetsIso == null) return;
    final reset = DateTime.tryParse(_resetsIso!)?.toLocal();
    if (reset == null) return;
    final diff = reset.difference(DateTime.now());
    final next = diff.isNegative
        ? 'Limit reset!'
        : 'Resets in ${diff.inHours}h ${diff.inMinutes.remainder(60)}m ${diff.inSeconds.remainder(60)}s';
    if (next != _resetText && mounted) {
      setState(() => _resetText = next);
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────

  Future<void> _improvePrompt() async {
    final text = _prompt.text.trim();
    if (text.isEmpty || _isGenerating || _isImproving) return;
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
      if (mounted) showErrorSnackbar(context, 'Could not improve prompt. Try again.');
    } finally {
      if (mounted) setState(() => _isImproving = false);
    }
  }

  Future<void> _fetchRandom() async {
    if (_isGenerating || _isImproving || _isFetchingRandom) return;
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
        showErrorSnackbar(context, 'Failed to fetch a random prompt.');
      }
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not fetch a prompt. Try again.');
    } finally {
      if (mounted) setState(() => _isFetchingRandom = false);
    }
  }

  Future<void> _generate() async {
    if (_prompt.text.trim().isEmpty || _isGenerating || _isImproving || _isFetchingRandom) {
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _isGenerating = true;
      _imageUrl = null;
      _isShared = false;
    });

    try {
      final body = <String, dynamic>{
        'prompt': _prompt.text.trim(),
        'size': _aspect,
      };
      final neg = _negative.text.trim();
      if (neg.isNotEmpty) body['negative_prompt'] = neg;
      if (_style != 'None') body['style'] = _style;

      final resp = await Supabase.instance.client.functions
          .invoke('generate-image-proxy', body: body);
      if (!mounted) return;

      final data = resp.data;
      if (data['error'] != null) {
        showErrorSnackbar(context, _readableApiError(data));
      } else if (data['data']?[0]?['url'] != null) {
        setState(() {
          _imageUrl = data['data'][0]['url'] as String;
          _lastPrompt = _prompt.text;
        });
        await _fetchStatus();
        if (_autoUpload) {
          await _share();
          if (mounted) setState(() => _isShared = true);
        }
      }
    } catch (e) {
      if (mounted) showErrorSnackbar(context, _readableExceptionError(e));
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  String _readableApiError(Map<String, dynamic> data) {
    final raw = data['error']?.toString() ?? '';
    if (_isPolicy(raw)) return _policyMessage();
    final details = data['details'];
    if (details is Map &&
        details['type'] == 'image_generation_user_error' &&
        details['code'] == 'content_policy_violation') {
      return _policyMessage();
    }
    return raw.isNotEmpty ? raw : 'Image generation failed. Please try again.';
  }

  String _readableExceptionError(Object error) {
    if (error is FunctionException) {
      final d = error.details;
      if (d is Map) {
        final inner = d['error'];
        if (inner is Map) {
          final type = inner['type']?.toString();
          final code = inner['code']?.toString();
          final message = inner['message']?.toString() ?? '';
          if (type == 'image_generation_user_error' && code == 'content_policy_violation') {
            return _policyMessage();
          }
          if (_isPolicy(message)) return _policyMessage();
        } else if (inner is String) {
          if (_isPolicy(inner)) return _policyMessage();
          if (inner.isNotEmpty) return inner;
        }
      }
      if ((error.reasonPhrase ?? '').isNotEmpty) return 'Generation failed: ${error.reasonPhrase}';
    }
    final s = error.toString();
    if (_isPolicy(s)) return _policyMessage();
    return 'Image generation failed. Please try again.';
  }

  bool _isPolicy(String s) {
    final l = s.toLowerCase();
    return l.contains('safety system') || l.contains('content policy');
  }

  String _policyMessage() =>
      'Content policy: your prompt was rejected by the safety system. Please rephrase and try again.';

  Future<void> _save() async {
    if (_imageUrl == null || _isSaving) return;
    setState(() => _isSaving = true);
    try {
      final perm = Platform.isAndroid
          ? ((await DeviceInfoPlugin().androidInfo).version.sdkInt >= 33
              ? Permission.photos
              : Permission.storage)
          : Permission.photos;
      final status = await perm.request();
      if (!status.isGranted) {
        if (mounted) showErrorSnackbar(context, 'Storage permission required to save.');
        return;
      }
      final bytes = (await NetworkAssetBundle(Uri.parse(_imageUrl!)).load(''))
          .buffer
          .asUint8List();
      await _channel.invokeMethod('saveImageToGallery', {
        'imageBytes': bytes,
        'filename': 'Visionspark_${DateTime.now().millisecondsSinceEpoch}.png',
        'albumName': 'Visionspark',
      });
      if (mounted) showSuccessSnackbar(context, 'Image saved to gallery.');
    } catch (_) {
      if (mounted) showErrorSnackbar(context, 'Could not save image. Try again.');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _share() async {
    if (_imageUrl == null || _isSharing) return;
    setState(() => _isSharing = true);
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Not signed in');
      final bytes = (await NetworkAssetBundle(Uri.parse(_imageUrl!)).load(''))
          .buffer
          .asUint8List();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final mainPath = 'public/${user.id}_$ts.png';
      await Supabase.instance.client.storage
          .from('imagestorage')
          .uploadBinary(mainPath, bytes);

      String? thumbPath;
      try {
        final thumb = _makeThumb(bytes);
        thumbPath = 'public/${user.id}_${ts}_thumb.png';
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
      if (mounted) showErrorSnackbar(context, 'Could not share. Try again.');
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  Uint8List _makeThumb(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) throw Exception('decode');
    return Uint8List.fromList(img.encodePng(img.copyResize(decoded, width: 200)));
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final remaining = _limit == -1 ? 999 : _limit - _used;
    final canGenerate = (remaining > 0 || _limit == -1) &&
        !_isGenerating &&
        !_isFetchingRandom &&
        !_isImproving &&
        _prompt.text.trim().isNotEmpty;

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
              _promptCard(),
              const SizedBox(height: VSDesignTokens.space4),
              _advancedToggle(),
              if (_showAdvanced) ...[
                const SizedBox(height: VSDesignTokens.space4),
                _advancedPanel(),
              ],
              const SizedBox(height: VSDesignTokens.space5),
              _resultCard(),
              if (_lastPrompt.isNotEmpty) ...[
                const SizedBox(height: VSDesignTokens.space4),
                _lastPromptCard(),
              ],
              const SizedBox(height: VSDesignTokens.space6),
              VSButton(
                text: _isGenerating ? 'Generating...' : 'Generate image',
                icon: _isGenerating ? null : const Icon(Icons.auto_awesome),
                onPressed: canGenerate ? _generate : null,
                isLoading: _isGenerating,
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

  Widget _promptCard() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final length = _prompt.text.length;
    const maxLen = 4000;
    final near = length > maxLen * 0.8;

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
            title: 'Describe your image',
            subtitle: 'Be specific — colors, mood, lighting, composition.',
          ),
          const SizedBox(height: VSDesignTokens.space4),
          TextField(
            controller: _prompt,
            focusNode: _promptFocus,
            minLines: 3,
            maxLines: 6,
            maxLength: maxLen,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              hintText: 'A glowing aurora over a quiet mountain lake at dawn…',
              counterText: '',
            ),
          ),
          const SizedBox(height: VSDesignTokens.space2),
          Row(
            children: [
              Expanded(
                child: VSButton(
                  text: _isImproving ? 'Improving…' : 'Improve',
                  icon: _isImproving ? null : const Icon(Icons.auto_fix_high_outlined),
                  onPressed: _isImproving || _isGenerating ? null : _improvePrompt,
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
                      _isFetchingRandom || _isGenerating ? null : _fetchRandom,
                  isLoading: _isFetchingRandom,
                  variant: VSButtonVariant.outline,
                ),
              ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space2),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Detail = better results',
                style: tt.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.8),
                ),
              ),
              Text(
                '$length / $maxLen',
                style: tt.bodySmall?.copyWith(
                  color: near ? cs.error : cs.onSurfaceVariant,
                  fontWeight: near ? VSTypography.weightSemiBold : VSTypography.weightRegular,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _advancedToggle() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
      child: InkWell(
        onTap: () => setState(() => _showAdvanced = !_showAdvanced),
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
        child: Padding(
          padding: const EdgeInsets.all(VSDesignTokens.space4),
          child: Row(
            children: [
              Icon(Icons.tune_rounded, color: cs.primary, size: VSDesignTokens.iconM),
              const SizedBox(width: VSDesignTokens.space3),
              Expanded(
                child: Text(
                  'Advanced options',
                  style: tt.titleMedium?.copyWith(
                    color: cs.onSurface,
                    fontWeight: VSTypography.weightSemiBold,
                  ),
                ),
              ),
              AnimatedRotation(
                turns: _showAdvanced ? 0.5 : 0,
                duration: VSDesignTokens.durationFast,
                child: Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _advancedPanel() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final disabled = _isGenerating || _isImproving || _isFetchingRandom;

    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      borderRadius: VSDesignTokens.radiusXL,
      color: cs.surfaceContainer,
      border: Border.all(color: cs.outlineVariant),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Aspect ratio',
            style: tt.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: VSTypography.weightSemiBold,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space2),
          Wrap(
            spacing: VSDesignTokens.space2,
            runSpacing: VSDesignTokens.space2,
            children: [
              for (final a in _aspects)
                _ChipChoice(
                  icon: a.icon,
                  label: a.label,
                  selected: _aspect == a.value,
                  onTap: disabled ? null : () => setState(() => _aspect = a.value),
                ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space5),
          Text(
            'Style',
            style: tt.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: VSTypography.weightSemiBold,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space2),
          Wrap(
            spacing: VSDesignTokens.space2,
            runSpacing: VSDesignTokens.space2,
            children: [
              for (final s in _styles.values)
                _ChipChoice(
                  icon: s.icon,
                  label: s.label,
                  selected: _style == s.key,
                  onTap: disabled ? null : () => setState(() => _style = s.key),
                ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space5),
          Text(
            'Negative prompt (optional)',
            style: tt.titleSmall?.copyWith(
              color: cs.onSurface,
              fontWeight: VSTypography.weightSemiBold,
            ),
          ),
          const SizedBox(height: VSDesignTokens.space2),
          TextField(
            controller: _negative,
            focusNode: _negativeFocus,
            minLines: 2,
            maxLines: 3,
            maxLength: 1000,
            decoration: const InputDecoration(
              hintText: 'blurry, low quality, watermark…',
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultCard() {
    final cs = Theme.of(context).colorScheme;
    final aspect = _aspects.firstWhere(
      (a) => a.value == _aspect,
      orElse: () => _aspects.first,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
      child: AspectRatio(
        aspectRatio: aspect.ratio,
        child: Container(
          decoration: BoxDecoration(
            color: cs.surfaceContainer,
            border: Border.all(color: cs.outlineVariant),
            borderRadius: BorderRadius.circular(VSDesignTokens.radiusXL),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (_imageUrl == null && !_isGenerating) _placeholder(aspect),
              if (_imageUrl != null)
                Hero(
                  tag: 'generated_image',
                  child: Image.network(
                    _imageUrl!,
                    fit: BoxFit.cover,
                    loadingBuilder: (_, child, p) => p == null
                        ? child
                        : Center(
                            child: VSLoadingIndicator(
                              message: 'Loading image…',
                              color: cs.primary,
                            ),
                          ),
                    errorBuilder: (_, __, ___) => Container(
                      color: cs.errorContainer,
                      child: Center(
                        child: Icon(
                          Icons.broken_image_outlined,
                          color: cs.onErrorContainer,
                          size: VSDesignTokens.iconL,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_isGenerating) _generatingOverlay(),
              if (_imageUrl != null && !_isGenerating) _actionsOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(_AspectOption a) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VSDesignTokens.space5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(VSDesignTokens.space5),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(a.icon, size: VSDesignTokens.iconXL, color: cs.primary),
            ),
            const SizedBox(height: VSDesignTokens.space4),
            Text(
              'Your ${a.label.toLowerCase()} image will appear here',
              style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VSDesignTokens.space2),
            Text(
              'Type a prompt and tap Generate.',
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _generatingOverlay() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.18),
            cs.secondary.withValues(alpha: 0.18),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(VSDesignTokens.space4),
              decoration: BoxDecoration(
                color: cs.surface.withValues(alpha: 0.9),
                shape: BoxShape.circle,
              ),
              child: CircularProgressIndicator(strokeWidth: 3, color: cs.primary),
            ),
            const SizedBox(height: VSDesignTokens.space5),
            Text(
              'Painting pixels…',
              style: tt.titleMedium?.copyWith(
                color: cs.onSurface,
                fontWeight: VSTypography.weightSemiBold,
              ),
            ),
            const SizedBox(height: VSDesignTokens.space2),
            Text(
              'This usually takes a few seconds.',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionsOverlay() {
    final cs = Theme.of(context).colorScheme;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(VSDesignTokens.space4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _ActionPill(
              icon: Icons.download_rounded,
              label: 'Save',
              loading: _isSaving,
              onTap: _save,
            ),
            if (!_autoUpload && !_isShared)
              _ActionPill(
                icon: Icons.share_rounded,
                label: 'Share',
                loading: _isSharing,
                onTap: _share,
              ),
            if (!_autoUpload && _isShared)
              _ActionPill(
                icon: Icons.check_circle_rounded,
                label: 'Shared',
                loading: false,
                onTap: null,
                accent: cs.secondary,
              ),
          ],
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
          Row(
            children: [
              Icon(Icons.history_rounded, size: VSDesignTokens.iconS, color: cs.primary),
              const SizedBox(width: VSDesignTokens.space2),
              Text(
                'Last prompt',
                style: tt.titleSmall?.copyWith(
                  color: cs.onSurface,
                  fontWeight: VSTypography.weightSemiBold,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: 'Reuse',
                onPressed: () {
                  _prompt.text = _lastPrompt;
                  _promptFocus.requestFocus();
                },
                icon: Icon(Icons.refresh_rounded, color: cs.onSurfaceVariant),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: VSDesignTokens.space2),
          SelectableText(
            _lastPrompt,
            maxLines: 3,
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
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
        padding: const EdgeInsets.all(VSDesignTokens.space5),
        borderRadius: VSDesignTokens.radiusXL,
        color: cs.surfaceContainer,
        child: Center(
          child: VSLoadingIndicator(message: 'Loading status…'),
        ),
      );
    }

    if (error != null) {
      return VSCard(
        padding: const EdgeInsets.all(VSDesignTokens.space5),
        borderRadius: VSDesignTokens.radiusXL,
        color: cs.errorContainer,
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
            const SizedBox(width: VSDesignTokens.space3),
            Expanded(
              child: Text(
                error!,
                style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer),
              ),
            ),
          ],
        ),
      );
    }

    final unlimited = limit == -1;
    final progress = unlimited ? 1.0 : (remaining / limit.toDouble()).clamp(0.0, 1.0);
    final low = !unlimited && remaining <= 1;

    return VSCard(
      padding: const EdgeInsets.all(VSDesignTokens.space5),
      borderRadius: VSDesignTokens.radiusXL,
      color: cs.surfaceContainer,
      border: Border.all(
        color: low ? cs.error.withValues(alpha: 0.4) : cs.outlineVariant,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(VSDesignTokens.space2),
                decoration: BoxDecoration(
                  color: low
                      ? cs.errorContainer
                      : cs.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(VSDesignTokens.radiusS),
                ),
                child: Icon(
                  unlimited ? Icons.all_inclusive_rounded : Icons.bolt_rounded,
                  color: low ? cs.onErrorContainer : cs.primary,
                  size: VSDesignTokens.iconM,
                ),
              ),
              const SizedBox(width: VSDesignTokens.space3),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Generations',
                      style: tt.titleSmall?.copyWith(
                        color: cs.onSurface,
                        fontWeight: VSTypography.weightSemiBold,
                      ),
                    ),
                    Text(
                      unlimited ? 'Unlimited' : '$remaining of $limit remaining',
                      style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (!unlimited) ...[
            const SizedBox(height: VSDesignTokens.space4),
            ClipRRect(
              borderRadius: BorderRadius.circular(VSDesignTokens.radiusXS),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: cs.surfaceContainerHigh,
                valueColor:
                    AlwaysStoppedAnimation(low ? cs.error : cs.primary),
              ),
            ),
            const SizedBox(height: VSDesignTokens.space3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  low ? 'Almost out' : 'Resets daily',
                  style: tt.bodySmall?.copyWith(
                    color: low ? cs.error : cs.onSurfaceVariant,
                    fontWeight: low ? VSTypography.weightSemiBold : VSTypography.weightRegular,
                  ),
                ),
                Text(
                  resetText,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ChipChoice extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;
  const _ChipChoice({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

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
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: VSDesignTokens.iconS, color: fg),
              const SizedBox(width: VSDesignTokens.space2),
              Text(
                label,
                style: TextStyle(
                  color: fg,
                  fontWeight: selected
                      ? VSTypography.weightSemiBold
                      : VSTypography.weightMedium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool loading;
  final VoidCallback? onTap;
  final Color? accent;
  const _ActionPill({
    required this.icon,
    required this.label,
    required this.loading,
    required this.onTap,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = accent ?? cs.primary;
    return Material(
      color: Colors.white.withValues(alpha: 0.95),
      borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
      child: InkWell(
        onTap: loading ? null : onTap,
        borderRadius: BorderRadius.circular(VSDesignTokens.radiusM),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: VSDesignTokens.space4,
            vertical: VSDesignTokens.space3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: VSColors.ink,
                  fontWeight: VSTypography.weightSemiBold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
