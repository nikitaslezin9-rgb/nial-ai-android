import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import 'package:file_picker/file_picker.dart';
import 'nial_profile.dart';

class NialProfileCard extends StatefulWidget {
  const NialProfileCard({super.key});
  @override
  State<NialProfileCard> createState() => _NialProfileCardState();
}

class _NialProfileCardState extends State<NialProfileCard> {
  NialProfile? _profile;
  bool _failed = false;
  bool _editing = false;
  @override
  void initState() {
    super.initState();
    _load();
  }
  Future<void> _load() async {
    try {
      final profile = await NialProfileStore.read();
      if (mounted) setState(() { _profile = profile; _failed = false; });
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }
  Future<void> _edit() async {
    if (_profile == null || _editing) return;
    setState(() => _editing = true);
    try {
      final saved = await showDialog<NialProfile>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _NialProfileEditor(initial: _profile!),
      );
      if (mounted && saved != null) setState(() => _profile = saved);
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Не удалось прочитать профиль. Данные не перезаписаны.'),
        TextButton(onPressed: _load, child: const Text('Повторить')),
      ]);
    }
    final profile = _profile;
    if (profile == null) return const LinearProgressIndicator();
    return Semantics(
      button: true,
      label: 'Редактировать профиль',
      child: InkWell(
        onTap: _editing ? null : _edit,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            _ProfileAvatar(profile: profile),
            const SizedBox(width: 16),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.displayName, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600)),
                const SizedBox(height: 5),
                Text(profile.about.isEmpty ? 'Пара слов о себе' : profile.about,
                  maxLines: 3, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text('Изменить профиль', style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.primary)),
              ],
            )),
            const SizedBox(width: 8),
            const Icon(Icons.edit_outlined, size: 20),
          ]),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile});
  final NialProfile profile;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fallback = Center(child: profile.name.isEmpty
      ? Icon(Icons.person_outline_rounded, size: 34, color: colors.onPrimaryContainer)
      : Text(profile.name.characters.first.toUpperCase(),
          style: TextStyle(fontSize: 28, color: colors.onPrimaryContainer)));
    return ClipOval(child: SizedBox(width: 76, height: 76,
      child: ColoredBox(color: colors.primaryContainer,
        child: profile.avatar == null ? fallback : Image.memory(
          profile.avatarBytes!, width: 76, height: 76, fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback))));
  }
}

class _NialProfileEditor extends StatefulWidget {
  const _NialProfileEditor({required this.initial});
  final NialProfile initial;
  @override
  State<_NialProfileEditor> createState() => _NialProfileEditorState();
}

class _NialProfileEditorState extends State<_NialProfileEditor> {
  late final TextEditingController _name;
  late final TextEditingController _about;
  String? _avatar;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.initial.name);
    _about = TextEditingController(text: widget.initial.about);
    _avatar = widget.initial.avatar;
  }
  @override
  void dispose() { _name.dispose(); _about.dispose(); super.dispose(); }

  Future<void> _pickAvatar() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final selected = await FilePicker.pickFile(type: FileType.image,
        dialogTitle: 'Выбрать аватар');
      if (selected == null) return;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in selected.readAsByteStream()) {
        if (builder.length + chunk.length > 20 * 1024 * 1024) {
          throw const FormatException('Фото больше 20 МиБ. Выбери другое.');
        }
        builder.add(chunk);
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(builder.takeBytes());
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          final width = descriptor.width;
          final height = descriptor.height;
          if (width <= 0 || height <= 0 || width * height > 60000000) {
            throw const FormatException('Слишком большое изображение. Выбери другое.');
          }
          final longest = width > height ? width : height;
          final scale = longest > 256 ? 256 / longest : 1.0;
          final codec = await descriptor.instantiateCodec(
            targetWidth: (width * scale).round().clamp(1, 256).toInt(),
            targetHeight: (height * scale).round().clamp(1, 256).toInt());
          try {
            final frame = await codec.getNextFrame();
            try {
              final bytes = await frame.image.toByteData(format: ui.ImageByteFormat.png);
              if (bytes == null || bytes.lengthInBytes > 512 * 1024) {
                throw const FormatException('Не удалось подготовить аватар.');
              }
              final avatar = base64Encode(bytes.buffer.asUint8List(
                bytes.offsetInBytes, bytes.lengthInBytes));
              if (mounted) setState(() => _avatar = avatar);
            } finally { frame.image.dispose(); }
          } finally { codec.dispose(); }
        } finally { descriptor.dispose(); }
      } finally { buffer.dispose(); }
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось открыть фото. Попробуй другое изображение.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final profile = NialProfile.fromJson({
        'name': _name.text.trim(), 'about': _about.text.trim(), 'avatar': _avatar});
      await NialProfileStore.save(profile);
      if (mounted) Navigator.of(context).pop(profile);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось сохранить профиль. Попробуй ещё раз.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: AlertDialog(
      title: const Text('Мой профиль'),
      content: SizedBox(width: 360, child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _ProfileAvatar(profile: NialProfile(name: _name.text.trim(), avatar: _avatar)),
          const SizedBox(height: 8),
          Wrap(alignment: WrapAlignment.center, spacing: 8, children: [
            TextButton.icon(onPressed: _busy ? null : _pickAvatar,
              icon: const Icon(Icons.photo_library_outlined), label: const Text('Выбрать фото')),
            if (_avatar != null) TextButton(onPressed: _busy ? null : () => setState(() => _avatar = null),
              child: const Text('Удалить фото')),
          ]),
          const SizedBox(height: 12),
          TextField(controller: _name, enabled: !_busy, maxLength: 60,
            textCapitalization: TextCapitalization.words,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Имя', hintText: 'Мой дневник')),
          const SizedBox(height: 12),
          TextField(controller: _about, enabled: !_busy, maxLength: 160, maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'О себе', hintText: 'Пара слов о себе')),
          const SizedBox(height: 8),
          const Text('Без регистрации. Профиль хранится на устройстве и входит в новые ZIP-копии.',
            style: TextStyle(fontSize: 12)),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      )),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.of(context).pop(), child: const Text('Отмена')),
        FilledButton(onPressed: _busy ? null : _save, child: const Text('Сохранить')),
      ],
    ),
  );
}
