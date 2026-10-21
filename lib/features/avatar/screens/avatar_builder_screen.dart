import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:couple_app/core/utils/snackbar.dart';
import 'package:couple_app/core/widgets/animated_gradient_card.dart';
import 'package:couple_app/core/widgets/entrance_animation.dart';
import 'package:couple_app/core/widgets/floating_hearts.dart';
import 'package:couple_app/core/widgets/glass.dart';
import 'package:couple_app/core/widgets/gradient_preset.dart';
import 'package:couple_app/features/auth/providers/auth_providers.dart';
import 'package:couple_app/features/avatar/data/avatar_service.dart';
import 'package:couple_app/features/avatar/models/avatar_config.dart';
import 'package:couple_app/features/avatar/providers/avatar_providers.dart';
import 'package:couple_app/features/avatar/widgets/avatar_option_tile.dart';
import 'package:couple_app/features/avatar/widgets/avatar_swatch_picker.dart';
import 'package:couple_app/features/avatar/widgets/avatar_view.dart';

/// Make or edit my cartoon avatar: a live preview, "Surprise me", undo and
/// a tab per part. Starts from my saved avatar, or a friendly default.
class AvatarBuilderScreen extends ConsumerStatefulWidget {
  const AvatarBuilderScreen({super.key});

  @override
  ConsumerState<AvatarBuilderScreen> createState() =>
      _AvatarBuilderScreenState();
}

/// The look a first avatar starts from.
const _starter = AvatarConfig(
  hair: 'short',
  hairColor: 'darkBrown',
  outfitColor: 'teal',
  background: 'peach',
);

const _expressionLabels = {
  AvatarExpression.happy: 'Happy',
  AvatarExpression.neutral: 'Calm',
  AvatarExpression.laugh: 'Laugh',
  AvatarExpression.love: 'Love',
  AvatarExpression.wink: 'Wink',
  AvatarExpression.kiss: 'Kiss',
  AvatarExpression.blush: 'Shy',
  AvatarExpression.surprised: 'Wow',
  AvatarExpression.sad: 'Sad',
  AvatarExpression.crying: 'Crying',
  AvatarExpression.sleepy: 'Sleepy',
  AvatarExpression.pout: 'Pout',
};

class _AvatarBuilderScreenState extends ConsumerState<AvatarBuilderScreen> {
  late final AvatarService _avatars;
  late final String _uid;

  /// What is saved now, to tell whether there are unsaved changes.
  late AvatarConfig _savedConfig;
  late bool _savedAsPhoto;

  late AvatarConfig _config;
  late bool _asPhoto;
  final _history = <AvatarConfig>[];
  AvatarExpression _expression = AvatarExpression.happy;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _avatars = ref.read(avatarServiceProvider);
    final me = ref.read(currentUserProvider);
    _uid = me.uid;
    // Older avatars kept the bindi with the head accessories.
    _savedConfig = me.avatar?.withBindiOnFace ?? _starter;
    // A first avatar becomes the profile picture only if there's no photo.
    _savedAsPhoto = me.avatar == null ? me.photoUrl == null : me.showsAvatar;
    _config = _savedConfig;
    _asPhoto = _savedAsPhoto;
  }

  bool get _dirty => _config != _savedConfig || _asPhoto != _savedAsPhoto;

  void _apply(AvatarConfig next) {
    if (next == _config) return;
    setState(() {
      _history.add(_config);
      if (_history.length > 60) _history.removeAt(0);
      _config = next;
    });
  }

  void _undo() {
    if (_history.isEmpty) return;
    setState(() => _config = _history.removeLast());
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await _avatars.save(
        uid: _uid,
        avatar: _config,
        asProfilePicture: _asPhoto,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showSnackMessage('Couldn\'t save your avatar. Try again.');
      return;
    }
    if (!mounted) return;
    context.showSnackMessage('Avatar saved');
    Navigator.of(context).pop();
  }

  Future<void> _confirmDiscard() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Discard changes?'),
        content: const Text('Your avatar changes haven\'t been saved.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = _tabs();

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: DefaultTabController(
        length: tabs.length,
        child: Scaffold(
          extendBodyBehindAppBar: true,
          backgroundColor: _stagePreset.colors(theme.brightness).first,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            title: const Text('Your avatar'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  // The app theme makes filled buttons full width; an app
                  // bar action needs a normal size.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(72, 40),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
          body: Stack(
            children: [
              Positioned.fill(
                child: AnimatedGradientBackground(
                  preset: _stagePreset,
                  duration: const Duration(seconds: 14),
                ),
              ),
              Positioned.fill(
                child: FloatingHearts(
                  style: ParticleStyle.confetti,
                  count: 10,
                  opacity: .5,
                  seed: 11,
                ),
              ),
              SafeArea(
                bottom: false,
                child: Column(
                  children: [
                    _stage(context),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        child: _optionsPanel(context, tabs),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The gradient behind the builder.
  static const _stagePreset = GradientPreset.lavender;

  /// The live preview, undo and "Surprise me", the expression chips and
  /// the profile-picture switch, straight on the gradient.
  Widget _stage(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      children: [
        const SizedBox(height: 4),
        Row(
          children: [
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Undo',
              onPressed: _history.isEmpty ? null : _undo,
              icon: const Icon(Icons.undo),
            ),
            Expanded(
              child: Center(
                child: Bobbing(
                  amplitude: 3,
                  duration: const Duration(milliseconds: 3600),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: dark ? .14 : .7),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: dark ? .25 : .95),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _stagePreset
                              .accent(theme.brightness)
                              .withValues(alpha: .25),
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: RepaintBoundary(
                      child: AvatarView(
                        config: _config,
                        expression: _expression,
                        size: 132,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Surprise me',
              onPressed: () => _apply(AvatarConfig.random()),
              style: IconButton.styleFrom(
                backgroundColor: Colors.white.withValues(
                  alpha: dark ? .16 : .75,
                ),
              ),
              icon: const Icon(Icons.casino_outlined),
            ),
            const SizedBox(width: 8),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              for (final entry in _expressionLabels.entries)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: ChoiceChip(
                    label: Text(entry.value),
                    selected: _expression == entry.key,
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.white.withValues(
                      alpha: dark ? .08 : .5,
                    ),
                    side: BorderSide(
                      color: Colors.white.withValues(alpha: dark ? .2 : .9),
                    ),
                    onSelected: (_) => setState(() => _expression = entry.key),
                  ),
                ),
            ],
          ),
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Use as my profile picture'),
          value: _asPhoto,
          onChanged: (value) => setState(() => _asPhoto = value),
        ),
      ],
    );
  }

  /// The part tabs and their options, on a frosted panel.
  Widget _optionsPanel(BuildContext context, List<_Category> tabs) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassPanel(
      dark: dark,
      radius: 28,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          const SizedBox(height: 4),
          TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            dividerColor: Colors.transparent,
            tabs: [for (final tab in tabs) Tab(text: tab.label)],
          ),
          Expanded(
            child: TabBarView(children: [for (final tab in tabs) tab.build()]),
          ),
        ],
      ),
    );
  }

  List<_Category> _tabs() => [
    _Category(
      'Skin',
      () => _page(
        name: 'skin',
        swatches: AvatarSwatchPicker(
          part: 'skin',
          swatches: AvatarConfig.skins,
          selected: _config.skin,
          onSelected: (id) => _apply(_config.copyWith(skin: id)),
          size: 44,
        ),
      ),
    ),
    _Category(
      'Face',
      () => _page(
        part: 'face',
        options: AvatarConfig.faces,
        selected: _config.face,
        apply: (id) => _config.copyWith(face: id),
      ),
    ),
    _Category(
      'Hair',
      () => _page(
        swatches: AvatarSwatchPicker(
          part: 'hairColor',
          swatches: AvatarConfig.hairColors,
          selected: _config.hairColor,
          onSelected: (id) => _apply(_config.copyWith(hairColor: id)),
        ),
        part: 'hair',
        options: AvatarConfig.hairs,
        selected: _config.hair,
        apply: (id) => _config.copyWith(hair: id),
        showShoulders: true,
      ),
    ),
    _Category(
      'Eyes',
      () => _page(
        swatches: AvatarSwatchPicker(
          part: 'eyeColor',
          swatches: AvatarConfig.eyeColors,
          selected: _config.eyeColor,
          onSelected: (id) => _apply(_config.copyWith(eyeColor: id)),
        ),
        part: 'eyes',
        options: AvatarConfig.eyeStyles,
        selected: _config.eyes,
        apply: (id) => _config.copyWith(eyes: id),
        expression: AvatarExpression.neutral,
      ),
    ),
    _Category(
      'Brows',
      () => _page(
        part: 'brows',
        options: AvatarConfig.browStyles,
        selected: _config.brows,
        apply: (id) => _config.copyWith(brows: id),
        expression: AvatarExpression.neutral,
      ),
    ),
    _Category(
      'Facial hair',
      () => _page(
        part: 'facialHair',
        options: AvatarConfig.facialHairs,
        selected: _config.facialHair,
        apply: (id) => _config.copyWith(facialHair: id),
      ),
    ),
    _Category(
      'Glasses',
      () => _page(
        part: 'glasses',
        options: AvatarConfig.glassesStyles,
        selected: _config.glasses,
        apply: (id) => _config.copyWith(glasses: id),
      ),
    ),
    _Category('Extras', _extrasPage),
    _Category(
      'Outfit',
      () => _page(
        swatches: AvatarSwatchPicker(
          part: 'outfitColor',
          swatches: AvatarConfig.outfitColors,
          selected: _config.outfitColor,
          onSelected: (id) => _apply(_config.copyWith(outfitColor: id)),
        ),
        part: 'outfit',
        options: AvatarConfig.outfits,
        selected: _config.outfit,
        apply: (id) => _config.copyWith(outfit: id),
        showShoulders: true,
      ),
    ),
    _Category(
      'Background',
      () => _page(
        name: 'background',
        swatches: AvatarSwatchPicker(
          part: 'background',
          swatches: AvatarConfig.backgrounds,
          selected: _config.background,
          onSelected: (id) => _apply(_config.copyWith(background: id)),
          size: 44,
        ),
      ),
    ),
  ];

  /// Face and head accessories, in two groups so a bindi can go with
  /// earrings, a flower, a headscarf and so on.
  Widget _extrasPage() {
    return CustomScrollView(
      key: const PageStorageKey('avatar-tab-extras'),
      slivers: [
        _sectionTitle('Face'),
        _optionGrid(
          part: 'faceAccessory',
          options: AvatarConfig.faceAccessories,
          selected: _config.faceAccessory,
          apply: (id) => _config.copyWith(faceAccessory: id),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        ),
        _sectionTitle('Head & ears'),
        _optionGrid(
          part: 'accessory',
          options: AvatarConfig.headAccessories,
          selected: _config.accessory,
          apply: (id) => _config.copyWith(accessory: id),
        ),
      ],
    );
  }

  Widget _sectionTitle(String title) {
    final theme = Theme.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      sliver: SliverToBoxAdapter(
        child: Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// A grid of [options] for [part], each previewed on the current avatar.
  Widget _optionGrid({
    required String part,
    required List<AvatarOption> options,
    required String selected,
    required AvatarConfig Function(String id) apply,
    bool showShoulders = false,
    AvatarExpression expression = AvatarExpression.happy,
    EdgeInsets padding = const EdgeInsets.fromLTRB(12, 12, 12, 24),
  }) {
    return SliverPadding(
      padding: padding,
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 96,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: .82,
        ),
        itemCount: options.length,
        itemBuilder: (context, i) {
          final option = options[i];
          return AvatarOptionTile(
            key: ValueKey('avatar-option-$part-${option.id}'),
            config: apply(option.id),
            label: option.label,
            selected: option.id == selected,
            expression: expression,
            showShoulders: showShoulders,
            onTap: () => _apply(apply(option.id)),
          );
        },
      ),
    );
  }

  /// One tab: an optional row of colour swatches over a grid of options,
  /// each previewed on the current avatar.
  Widget _page({
    String? name,
    Widget? swatches,
    String? part,
    List<AvatarOption> options = const [],
    String? selected,
    AvatarConfig Function(String id)? apply,
    bool showShoulders = false,
    AvatarExpression expression = AvatarExpression.happy,
  }) {
    return CustomScrollView(
      key: PageStorageKey('avatar-tab-${name ?? part}'),
      slivers: [
        if (swatches != null)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            sliver: SliverToBoxAdapter(child: swatches),
          ),
        if (apply != null && part != null && selected != null)
          _optionGrid(
            part: part,
            options: options,
            selected: selected,
            apply: apply,
            showShoulders: showShoulders,
            expression: expression,
          ),
      ],
    );
  }
}

class _Category {
  const _Category(this.label, this.build);
  final String label;
  final Widget Function() build;
}
