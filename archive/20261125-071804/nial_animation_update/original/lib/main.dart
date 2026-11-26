import 'dart:typed_data';
import 'dart:async';
import 'dart:io';

import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';
import 'dart:ui' hide Image;

import 'package:material_ui/material_ui.dart';

import 'services/ai_config.dart';
import 'services/diary_storage.dart';
import 'services/nial_media.dart';
import 'services/nial_profile.dart';
import 'services/nial_profile_card.dart';

import 'package:video_player/video_player.dart';

import 'services/gigachat_service.dart';

void main() => runApp(const NialApp());

class Entry {
  Entry(
    this.title,
    this.text,
    this.date, {
    this.favorite = false,
    List<String>? photos,
    this.voice,
    this.video,
  }) : photos = List<String>.from(photos ?? const []);

  String title;
  String text;
  DateTime date;
  bool favorite;
  final List<String> photos;
  final String? voice;
  final String? video;
}

List<String> _readEntryPhotos(dynamic value) {
  if (value == null) return [];
  if (value is! List || value.length > 6) {
    throw const FormatException('Invalid photos');
  }
  return value.map<String>((item) {
    if (item is! String || item.length > 5592408) {
      throw const FormatException('Invalid photo size');
    }
    if (NialMedia.isRef(item) && !item.endsWith('.png')) {
      throw const FormatException('Invalid photo reference');
    }
    final bytes = NialMedia.read(item);
    if (bytes.length < 24 ||
        bytes.length > 4 * 1024 * 1024 ||
        bytes[0] != 137 ||
        bytes[1] != 80 ||
        bytes[2] != 78 ||
        bytes[3] != 71) {
      throw const FormatException('Invalid photo data');
    }
    final header = ByteData.sublistView(bytes);
    final width = header.getUint32(16);
    final height = header.getUint32(20);
    if (width == 0 || height == 0 || width > 1280 || height > 1280) {
      throw const FormatException('Invalid photo dimensions');
    }
    return item;
  }).toList();
}

Widget _photoStrip(
  BuildContext context,
  List<String> photos, {
  ValueChanged<int>? onRemove,
}) {
  if (photos.isEmpty) return const SizedBox.shrink();
  return Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (var i = 0; i < photos.length; i++)
        Stack(
          children: [
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      title: Text('Фото ${i + 1}'),
                    ),
                    body: Center(
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 5,
                        child: Image.memory(
                          NialMedia.read(photos[i]),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) =>
                              const Text(
                                'Не удалось открыть фото',
                                style: TextStyle(color: Colors.white),
                              ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  NialMedia.read(photos[i]),
                  width: 94,
                  height: 94,
                  fit: BoxFit.cover,
                  cacheWidth: 240,
                  errorBuilder: (context, error, stackTrace) => const SizedBox(
                    width: 94,
                    height: 94,
                    child: Icon(Icons.broken_image_outlined),
                  ),
                ),
              ),
            ),
            if (onRemove != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton.filled(
                  tooltip: 'Убрать фото из записи',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => onRemove(i),
                  icon: const Icon(Icons.close, size: 17),
                ),
              ),
          ],
        ),
    ],
  );
}

String? _readEntryVoice(dynamic value) {
  if (value == null) return null;
  if (value is! String || value.length > 5592408) {
    throw const FormatException('Invalid voice size');
  }
  if (NialMedia.isRef(value) && !value.endsWith('.m4a')) {
    throw const FormatException('Invalid voice reference');
  }
  final bytes = NialMedia.read(value);
  if (bytes.length < 32 ||
      bytes.length > 4 * 1024 * 1024 ||
      ascii.decode(bytes.sublist(4, 8), allowInvalid: true) != 'ftyp') {
    throw const FormatException('Invalid voice container');
  }
  return value;
}

class _VoiceNoteEditor extends StatefulWidget {
  const _VoiceNoteEditor({
    required this.value,
    required this.onChanged,
    required this.onLocked,
  });
  final String? value;
  final ValueChanged<String?> onChanged;
  final ValueChanged<bool> onLocked;
  @override
  State<_VoiceNoteEditor> createState() => _VoiceNoteEditorState();
}

class _VoiceNoteEditorState extends State<_VoiceNoteEditor>
    with WidgetsBindingObserver {
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final _watch = Stopwatch();
  Timer? _timer;
  StreamSubscription<void>? _completion;
  Directory? _temp;
  bool _recording = false;
  bool _busy = false;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _completion = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      if (_recording && !_busy) unawaited(_stopRecording());
      if (_playing) unawaited(_stopPlayback());
    }
  }

  Future<void> _stopPlayback() async {
    try {
      await _player.stop();
    } catch (_) {
      /* Keep the editor usable after a platform error. */
    }
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _startRecording() async {
    if (_busy || _recording || widget.value != null) return;
    setState(() => _busy = true);
    widget.onLocked(true);
    try {
      await _stopPlayback();
      if (!await _recorder.hasPermission()) {
        _notice(
          'Нет доступа к микрофону. Разреши его в запросе Android или настройках приложения.',
        );
        return;
      }
      if (!mounted) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      final temp = _temp ??= await Directory.systemTemp.createTemp(
        'nial_voice_',
      );
      if (!mounted) return;
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: '${temp.path}/voice.m4a',
      );
      if (!mounted) {
        await _recorder.cancel();
        return;
      }
      _watch
        ..reset()
        ..start();
      setState(() => _recording = true);
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_watch.elapsed.inSeconds >= 180) {
          unawaited(_stopRecording());
        } else {
          setState(() {});
        }
      });
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        // The finally block releases the busy flag before this task executes.
        scheduleMicrotask(() {
          if (mounted) unawaited(_stopRecording());
        });
      }
    } catch (_) {
      try {
        await _recorder.cancel();
      } catch (_) {
        /* Nothing else to release here. */
      }
      _notice('Не удалось начать запись. Проверь доступ к микрофону.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (!_recording) widget.onLocked(false);
      }
    }
  }

  Future<void> _stopRecording() async {
    if (_busy || !_recording) return;
    _timer?.cancel();
    _watch.stop();
    setState(() {
      _busy = true;
      _recording = false;
    });
    String? path;
    try {
      path = await _recorder.stop();
      if (path == null) throw const FormatException('No recording');
      final file = File(path);
      if (await file.length() > 4 * 1024 * 1024) {
        throw const FormatException('Recording too large');
      }
      final data = await file.readAsBytes();
      _readEntryVoice(base64Encode(data));
      final encoded = await NialMedia.store(data, 'm4a');
      if (!mounted) return;
      widget.onChanged(encoded);
      _notice(
        'Голосовая заметка добавлена в черновик. Нажми «Сохранить запись».',
      );
    } catch (_) {
      _notice(
        'Не удалось сохранить аудио в черновик. Попробуй записать снова.',
      );
    } finally {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {
          /* Cleaned with the temporary directory later. */
        }
      }
      if (mounted) {
        setState(() => _busy = false);
        widget.onLocked(false);
      }
    }
  }

  Future<void> _togglePlayback() async {
    if (_busy || _recording || widget.value == null) return;
    if (_playing) {
      await _stopPlayback();
      return;
    }
    setState(() => _busy = true);
    widget.onLocked(true);
    try {
      await _player.play(
        NialMedia.isRef(widget.value!)
            ? DeviceFileSource(
                NialMedia.file(widget.value!).path,
                mimeType: 'audio/mp4',
              )
            : BytesSource(base64Decode(widget.value!), mimeType: 'audio/mp4'),
      );
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      _notice('Не удалось воспроизвести голосовую заметку.');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onLocked(false);
      }
    }
  }

  Future<void> _removeVoice() async {
    if (_busy || _recording) return;
    setState(() => _busy = true);
    widget.onLocked(true);
    try {
      await _stopPlayback();
      if (mounted) widget.onChanged(null);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        widget.onLocked(false);
      }
    }
  }

  Future<void> _releaseResources() async {
    try {
      await _recorder.cancel();
    } catch (_) {
      /* Recorder may already be stopped. */
    }
    try {
      await _recorder.dispose();
    } catch (_) {
      /* Best-effort cleanup. */
    }
    try {
      await _player.dispose();
    } catch (_) {
      /* Best-effort cleanup. */
    }
    try {
      await _temp?.delete(recursive: true);
    } catch (_) {
      /* OS can clear remaining cache files. */
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _watch.stop();
    unawaited(_completion?.cancel() ?? Future<void>.value());
    unawaited(_releaseResources());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final seconds = _watch.elapsed.inSeconds;
    final time =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Голосовая заметка',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        const Text(
          'Одна заметка до 3 минут. Запись только на открытом экране; при сворачивании останавливается. Аудио не передаётся ассистенту.',
        ),
        const SizedBox(height: 8),
        if (_busy) const LinearProgressIndicator(),
        if (_recording) ...[
          Text('Идёт запись: $time / 03:00. Перед выходом останови запись.'),
          FilledButton.icon(
            onPressed: _busy ? null : _stopRecording,
            icon: const Icon(Icons.stop_rounded),
            label: const Text('Остановить запись'),
          ),
        ] else if (widget.value == null)
          OutlinedButton.icon(
            onPressed: _busy ? null : _startRecording,
            icon: const Icon(Icons.mic_none_rounded),
            label: const Text('Записать голосовую заметку'),
          )
        else ...[
          OutlinedButton.icon(
            onPressed: _busy ? null : _togglePlayback,
            icon: Icon(
              _playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
            ),
            label: Text(
              _playing ? 'Остановить прослушивание' : 'Прослушать заметку',
            ),
          ),
          TextButton(
            onPressed: _busy ? null : _removeVoice,
            child: const Text('Убрать аудио из записи'),
          ),
        ],
      ],
    );
  }
}

String? _readEntryVideo(dynamic value) {
  if (value == null) return null;
  if (value is! String || !NialMedia.isRef(value) || !value.endsWith('.mp4')) {
    throw const FormatException('Invalid video reference');
  }
  final source = NialMedia.file(value);
  final size = source.lengthSync();
  if (size <= 0 || size > NialMedia.maxVideo) {
    throw const FormatException('Invalid video size');
  }
  return value;
}

class _VideoScreen extends StatefulWidget {
  const _VideoScreen({required this.reference});
  final String reference;
  @override
  State<_VideoScreen> createState() => _VideoScreenState();
}

class _VideoScreenState extends State<_VideoScreen>
    with WidgetsBindingObserver {
  late final VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;
  bool _changing = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = VideoPlayerController.file(NialMedia.file(widget.reference));
    _controller.addListener(_refresh);
    unawaited(_initialize());
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _initialize() async {
    try {
      await _controller.initialize().timeout(const Duration(seconds: 30));
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _ready) unawaited(_pause());
  }

  Future<void> _pause() async {
    try {
      await _controller.pause();
    } catch (_) {
      /* Keep navigation available. */
    }
  }

  Future<void> _toggle() async {
    if (_changing || !_ready) return;
    setState(() => _changing = true);
    try {
      if (_controller.value.isPlaying) {
        await _controller.pause();
      } else {
        if (_controller.value.position >= _controller.value.duration) {
          await _controller.seekTo(Duration.zero);
        }
        await _controller.play();
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _changing = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_refresh);
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Видео')),
    body: Center(
      child: _failed || _controller.value.hasError
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Не удалось воспроизвести видео. Возможно, формат не поддерживается телефоном.',
              ),
            )
          : !_ready
          ? const CircularProgressIndicator()
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio > 0
                        ? _controller.value.aspectRatio
                        : 1,
                    child: VideoPlayer(_controller),
                  ),
                ),
                VideoProgressIndicator(
                  _controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.all(16),
                ),
                FilledButton.icon(
                  onPressed: _changing ? null : _toggle,
                  icon: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause
                        : Icons.play_arrow,
                  ),
                  label: Text(
                    _controller.value.isPlaying ? 'Пауза' : 'Воспроизвести',
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
    ),
  );
}

const prompts = [
  'Что сегодня хочется запомнить?',
  'Какая мысль не выходит из головы?',
  'Что тебя сегодня порадовало?',
  'О чём сейчас хочется выговориться?',
  'Какой момент дня ты бы сохранил?',
  'Чего тебе сейчас не хватает?',
  'За что ты можешь себя поблагодарить?',
];

class NialApp extends StatefulWidget {
  const NialApp({super.key});

  @override
  State<NialApp> createState() => _NialAppState();
}

class _NialAppState extends State<NialApp> {
  final _nialThemePreferences = SharedPreferencesAsync();

  final _messengerKey = GlobalKey<ScaffoldMessengerState>();

  Future<void> _themeSaveQueue = Future<void>.value();

  ThemeMode mode = ThemeMode.system;
  bool _themeLoaded = false;
  bool _themeLoadFailed = false;

  static const _themeKey = 'nial_theme_mode_v1';

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    try {
      final saved = await _nialThemePreferences.getString(_themeKey);

      if (!mounted) return;

      setState(() {
        mode = switch (saved) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };

        _themeLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        mode = ThemeMode.system;
        _themeLoaded = true;
        _themeLoadFailed = true;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_themeLoadFailed) return;

        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось загрузить тему. '
              'Временно используется системное оформление.',
            ),
          ),
        );
      });
    }
  }

  void _changeTheme(ThemeMode value) {
    setState(() {
      mode = value;
    });

    final savedValue = switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

    _themeSaveQueue = _themeSaveQueue.then<void>((_) async {
      try {
        await _nialThemePreferences.setString(_themeKey, savedValue);
      } catch (_) {
        if (!mounted) return;

        _messengerKey.currentState?.showSnackBar(
          const SnackBar(
            content: Text(
              'Тема применена, но сохранить её не удалось. '
              'Попробуй выбрать оформление ещё раз.',
            ),
          ),
        );
      }
    });
  }

  ThemeData theme(bool dark) => ThemeData(
    useMaterial3: true,
    brightness: dark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: dark
        ? const Color(0xff171d18)
        : const Color(0xfff3f2e9),
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: const Color(0xff819576),
          brightness: dark ? Brightness.dark : Brightness.light,
        ).copyWith(
          surface: dark ? const Color(0xff222b23) : const Color(0xfffffdf8),
          onSurface: dark ? const Color(0xffedf0e6) : const Color(0xff344635),
          primary: dark ? const Color(0xffc8d8b9) : const Color(0xff344635),
          onPrimary: dark ? const Color(0xff1e2a1d) : const Color(0xfffffdf7),
        ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nial Dairy',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _messengerKey,
      theme: theme(false),
      darkTheme: theme(true),
      themeMode: mode,
      home: _themeLoaded
          ? Home(mode: mode, changeTheme: _changeTheme)
          : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}

class Home extends StatefulWidget {
  const Home({super.key, required this.mode, required this.changeTheme});

  final ThemeMode mode;
  final ValueChanged<ThemeMode> changeTheme;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  bool _backupBusy = false;
  int _profileRevision = 0;
  static const _backupLimit = NialMedia.maxArchive;

  void _backupNotice(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _saveBackupFile(String payload, String prefix) async {
    final bytes = await NialMedia.exportZip(
      payload, profile: (await NialProfileStore.read()).toJson(),
    );
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final result = await FilePicker.saveFile(
      dialogTitle: 'Сохранить ZIP-копию дневника',
      fileName: '${prefix}_$stamp.zip',
      bytes: bytes,
    );
    return result != null;
  }

  Future<void> _exportDiaryBackup() async {
    if (_backupBusy || _isSending || !_storageReady) return;
    setState(() => _backupBusy = true);
    try {
      await _saveQueue;
      if (!mounted) return;
      final saved = await _saveBackupFile(_encodeDiary(), 'nial_diary');
      if (saved) _backupNotice('Копия сохранена в выбранном месте.');
    } on FormatException catch (error) {
      _backupNotice(error.message);
    } catch (_) {
      _backupNotice(
        'Не удалось сохранить копию. Проверь место сохранения и попробуй снова.',
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Future<(List<Entry>, NialProfile?)> _validateDiaryBackup(Uint8List bytes) async {
    final decoded = jsonDecode(await NialMedia.unpack(bytes));
    if (decoded is! Map<String, dynamic> ||
        decoded['format'] != 'nial_diary_backup' ||
        decoded['version'] is! int ||
        (decoded['version'] != 1 &&
            decoded['version'] != 2 &&
            decoded['version'] != 3 &&
            decoded['version'] != 4 &&
            decoded['version'] != 5) ||
        decoded['entries'] is! List) {
      throw const FormatException('Это не поддерживаемая копия Nial Dairy.');
    }
    final items = decoded['entries'] as List;
    if (items.length > 20000) {
      throw const FormatException('В копии больше 20 000 записей.');
    }
    final profile = decoded.containsKey('profile')
        ? NialProfile.fromJson(decoded['profile']) : null;
    final restored = items.map((item) {
      if (item is! Map<String, dynamic> ||
          item['title'] is! String ||
          item['text'] is! String ||
          item['date'] is! String ||
          item['favorite'] is! bool) {
        throw const FormatException('В копии найдена некорректная запись.');
      }
      final parsedDate = DateTime.tryParse(item['date'] as String);
      if (parsedDate == null) {
        throw const FormatException('В копии найдена некорректная дата.');
      }
      return Entry(
        item['title'] as String,
        item['text'] as String,
        parsedDate,
        favorite: item['favorite'] as bool,
        photos: _readEntryPhotos(item['photos']),
        video: _readEntryVideo(item['video']),
        voice: _readEntryVoice(item['voice']),
      );
    }).toList();
    return (restored, profile);
  }

  Future<void> _importDiaryBackup() async {
    if (_backupBusy || _isSending || !_storageReady) return;
    setState(() => _backupBusy = true);
    try {
      await _saveQueue;
      if (!mounted) return;
      final selected = await FilePicker.pickFile(
        dialogTitle: 'Выбрать копию дневника',
      );
      if (selected == null) return;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in selected.readAsByteStream()) {
        if (builder.length + chunk.length > _backupLimit) {
          throw const FormatException(
            'Файл больше 100 МиБ. Восстановление отменено.',
          );
        }
        builder.add(chunk);
      }
      final (restored, restoredProfile) = await _validateDiaryBackup(builder.takeBytes());
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Заменить записи дневника?'),
          content: SingleChildScrollView(
            child: Text(
              'Сейчас записей: ${entries.length}. В копии: ${restored.length}.\n\n'
              'Текущие записи будут заменены, а не объединены с копией. '
              'Сначала потребуется сохранить текущий дневник в отдельный файл. '
              'Выбери для него новое имя, не перезаписывай исходную копию. '
              'Если отменить сохранение, восстановление не начнётся.\n\n'
              'Беседа и черновик сообщения будут очищены, доступ ассистента к дневнику выключен. '
              'Файлы копий не зашифрованы и содержат тексты и медиа.\n\n'
              '${restoredProfile == null ? 'В этой копии нет профиля — текущий профиль останется.' : 'Имя, описание и аватар будут заменены профилем из копии.'}',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Сохранить текущие и заменить'),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;
      final savedCurrent = await _saveBackupFile(
        _encodeDiary(),
        'nial_before_restore',
      );
      if (!savedCurrent) {
        _backupNotice('Восстановление отменено: текущая копия не сохранена.');
        return;
      }
      if (!mounted) return;
      final payload = jsonEncode(
        restored
            .map(
              (e) => {
                'title': e.title,
                'text': e.text,
                'date': e.date.toIso8601String(),
                'favorite': e.favorite,
                'photos': e.photos,
                'voice': e.voice,
                'video': e.video,
              },
            )
            .toList(),
      );
      final migratedPayload = await NialMedia.migratePayload(payload);
      final previousProfile = restoredProfile == null
          ? null : await NialProfileStore.read();
      if (restoredProfile != null) await NialProfileStore.save(restoredProfile);
      final operation = _saveQueue.then((_) async {
        try {
          await _diaryStorage.writeWithRecovery(migratedPayload);
        } catch (_) {
          if (previousProfile != null) await NialProfileStore.save(previousProfile);
          rethrow;
        }
      });
      _saveQueue = operation.then<void>(
        (_) {},
        onError: (Object error, StackTrace stackTrace) {},
      );
      await operation;
      if (!mounted) return;
      setState(() {
        _profileRevision++;
        entries
          ..clear()
          ..addAll(restored);
        _useDiaryContext = false;
        _chatMessages.clear();
        _messageController.clear();
        _chatError = null;
        _diaryQuery = '';
        _diarySearchController.clear();
        onlyFavorites = false;
      });
      _backupNotice(
        'Восстановлено записей: ${restored.length}. Контекст ассистента выключен.',
      );
    } on FormatException {
      _backupNotice(
        'Файл повреждён, имеет неподдерживаемый формат или превышает лимиты. Дневник не заменён.',
      );
    } catch (_) {
      _backupNotice(
        'Не удалось восстановить дневник. Попробуй снова. Если ошибка повторится, сохрани файл копии.',
      );
    } finally {
      if (mounted) setState(() => _backupBusy = false);
    }
  }

  Widget _diaryBackupPanel() => box(
    Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Резервная копия',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        Text(
          'Записи, избранное, фото, аудио и видео в ZIP-архиве. Без чата, ключа ИИ и разрешения на контекст. '
          'ZIP-архив не зашифрован: храни его в надёжном месте. Лимит: 100 МиБ, 20 000 записей и 4999 медиафайлов. Поддерживаются старые JSON-копии.',
          style: small,
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _isSending || !_storageReady || _backupBusy
              ? null
              : _exportDiaryBackup,
          icon: const Icon(Icons.save_alt_rounded),
          label: const Text('Сохранить копию'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isSending || !_storageReady || _backupBusy
              ? null
              : _importDiaryBackup,
          icon: const Icon(Icons.restore_rounded),
          label: const Text('Восстановить из файла'),
        ),
      ],
    ),
  );

  bool _useDiaryContext = false;

  String _buildDiaryContext() {
    final sorted = List<Entry>.from(entries)
      ..sort((a, b) => b.date.compareTo(a.date));
    final encoded = jsonEncode(
      sorted
          .map(
            (e) => {
              'date': e.date.toIso8601String(),
              'title': e.title,
              'text': e.text,
            },
          )
          .toList(),
    );
    if (encoded.length <= 24000) return encoded;
    var end = 24000;
    final unit = encoded.codeUnitAt(end - 1);
    if (unit >= 0xD800 && unit <= 0xDBFF) end--;
    return '${encoded.substring(0, end)}\n[Контекст обрезан по лимиту объёма.]';
  }

  Future<void> _changeDiaryContext(bool enabled) async {
    if (_isSending || !_storageReady || enabled == _useDiaryContext) return;
    final description = enabled
        ? 'С каждым сообщением в GigaChat будут передаваться даты, названия и тексты записей, включая демонстрационные. Приоритет у новых записей; объём ограничен, текст может обрезаться. Поиск и избранное не ограничивают передачу. Медиа не отправляются. Разрешение действует до полного перезапуска.'
        : 'Записи больше не будут добавляться в новые запросы.';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          enabled ? 'Разрешить контекст дневника?' : 'Выключить контекст?',
        ),
        content: SingleChildScrollView(
          child: Text(
            '$description\n\nТекущая беседа в приложении будет очищена, чтобы история не переносила прежний контекст. Это не удаляет уже переданные данные у провайдера.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(enabled ? 'Разрешить' : 'Выключить'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || _isSending) return;
    setState(() {
      _useDiaryContext = enabled;
      _chatMessages.clear();
      _chatError = null;
    });
  }

  final _diarySearchController = TextEditingController();
  String _diaryQuery = '';

  final _diaryStorage = DiaryStorage();
  Future<void> _saveQueue = Future<void>.value();

  bool _storageReady = false;
  String? _storageError;

  @override
  void initState() {
    super.initState();
    _loadDiary();
  }

  Future<void> _loadDiary() async {
    if (mounted) {
      setState(() {
        _storageReady = false;
        _storageError = null;
      });
    }

    try {
      await NialMedia.prepare();
      final originalSaved = await _diaryStorage.read();
      final saved = originalSaved == null
          ? null
          : await NialMedia.migratePayload(originalSaved);

      if (!mounted) return;

      if (saved != null) {
        final decoded = jsonDecode(saved);

        if (decoded is! List) {
          throw const FormatException('Invalid diary data');
        }

        final restored = decoded.map<Entry>((item) {
          final map = Map<String, dynamic>.from(item as Map);

          return Entry(
            map['title'] as String,
            map['text'] as String,
            DateTime.parse(map['date'] as String),
            favorite: map['favorite'] as bool? ?? false,
            photos: _readEntryPhotos(map['photos']),
            video: _readEntryVideo(map['video']),
            voice: _readEntryVoice(map['voice']),
          );
        }).toList();

        if (saved != originalSaved) {
          await _diaryStorage.writeWithRecovery(saved);
          if (!mounted) return;
        }
        entries
          ..clear()
          ..addAll(restored);
      } else {
        await _diaryStorage.write(_encodeDiary());
      }

      if (!mounted) return;

      setState(() {
        _storageReady = true;
        _storageError = null;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _storageReady = false;
        _storageError =
            'Не удалось открыть сохранённый дневник. '
            'Существующая база не перезаписана. '
            'Попробуй повторить загрузку.';
      });
    }
  }

  String _encodeDiary() {
    return jsonEncode(
      entries
          .map(
            (entry) => {
              'title': entry.title,
              'text': entry.text,
              'date': entry.date.toIso8601String(),
              'favorite': entry.favorite,
              'photos': entry.photos,
              'voice': entry.voice,
              'video': entry.video,
            },
          )
          .toList(),
    );
  }

  Future<void> _saveDiary() async {
    if (_backupBusy) return;
    final snapshot = _encodeDiary();

    final operation = _saveQueue.then((_) => _diaryStorage.write(snapshot));

    _saveQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );

    try {
      await operation;
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 8),
          content: const Text(
            'Не удалось сохранить последние изменения. '
            'Не закрывай приложение и попробуй ещё раз.',
          ),
          action: SnackBarAction(
            label: 'Повторить',
            onPressed: () {
              _saveDiary();
            },
          ),
        ),
      );
    }
  }

  Future<void> _toggleFavorite(Entry entry) async {
    if (!_storageReady) return;

    setState(() {
      entry.favorite = !entry.favorite;
    });

    await _saveDiary();
  }

  int page = 0;
  int question = 0;
  bool onlyFavorites = false;

  final _aiService = GigaChatService(
    authorizationKey: gigaChatAuthorizationKey,
  );

  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _composerKey = GlobalKey();

  final List<Map<String, String>> _chatMessages = [];

  bool _isSending = false;
  String? _chatError;

  final entries = <Entry>[
    Entry(
      'Маленькие хорошие вещи',
      'Утро без спешки, любимая музыка и немного времени для себя. '
          'Иногда именно из таких мелочей складывается хороший день.',
      DateTime.now(),
      favorite: true,
    ),
    Entry(
      'Просто выговориться',
      'Не обязательно сразу находить ответы. Сегодня захотелось '
          'просто оставить мысли здесь и немного выдохнуть.',
      DateTime.now().subtract(const Duration(days: 1)),
    ),
    Entry(
      'Планы без спешки',
      'Хочу чаще замечать то, что уже получается. '
          'Не требовать от себя всего сразу и оставить место '
          'для простых радостей.',
      DateTime.now().subtract(const Duration(days: 2)),
    ),
    Entry(
      'То, за что я благодарен',
      'За людей, с которыми можно быть собой. '
          'За спокойный вечер и возможность начать заново.',
      DateTime.now().subtract(const Duration(days: 3)),
      favorite: true,
    ),
  ];

  bool get dark => Theme.of(context).brightness == Brightness.dark;

  Color get sage => dark ? const Color(0xff334535) : const Color(0xffdce5d3);

  Color get muted => dark ? const Color(0xffa1ae9b) : const Color(0xff798571);

  Color get accent => dark ? const Color(0xffd8b79a) : const Color(0xfff1dbc9);

  TextStyle get small => TextStyle(color: muted, fontSize: 12, height: 1.7);

  @override
  void dispose() {
    _diarySearchController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _aiService.dispose();
    super.dispose();
  }

  String date(DateTime d) {
    const months = [
      'января',
      'февраля',
      'марта',
      'апреля',
      'мая',
      'июня',
      'июля',
      'августа',
      'сентября',
      'октября',
      'ноября',
      'декабря',
    ];

    return '${d.day} ${months[d.month - 1]}';
  }

  Future<void> edit([Entry? old]) async {
    if (!_storageReady) return;

    final result = await Navigator.of(context).push<Entry>(
      MaterialPageRoute(
        builder: (_) => Editor(entry: old, question: question),
      ),
    );

    if (!mounted || result == null) return;

    setState(() {
      if (old == null) {
        entries.insert(0, result);
      } else {
        final index = entries.indexOf(old);
        if (index >= 0) {
          entries[index] = result;
        }
      }
    });

    await _saveDiary();
  }

  void _showComposer() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || page != 1) return;

      final target = _composerKey.currentContext;
      if (target == null) return;

      Scrollable.ensureVisible(
        target,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        alignment: 0.6,
      );
    });
  }

  Future<void> _sendMessage() async {
    final message = _messageController.text.trim();

    if (message.isEmpty || _isSending) return;

    final history = _chatMessages
        .map((item) => Map<String, String>.from(item))
        .toList();

    FocusScope.of(context).unfocus();

    setState(() {
      _isSending = true;
      _chatError = null;
      _chatMessages.add({'role': 'user', 'content': message});
      _messageController.clear();
    });

    _showComposer();

    try {
      final answer = await _aiService.getResponse(
        message,
        history: history,
        diaryContext: _useDiaryContext ? _buildDiaryContext() : '',
      );

      if (!mounted) return;

      setState(() {
        _chatMessages.add({'role': 'assistant', 'content': answer});
        _isSending = false;
      });

      _showComposer();
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _chatMessages.removeLast();
        _messageController.text = message;
        _isSending = false;
        _chatError = error.toString().replaceFirst('Exception: ', '');
      });

      _showComposer();
    }
  }

  Future<void> _confirmClearChat() async {
    if (_isSending || _chatMessages.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Очистить беседу?'),
        content: const Text(
          'Сообщения исчезнут из текущего чата приложения. '
          'Записи дневника останутся без изменений. '
          'Это не запрос на удаление данных у провайдера ИИ.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Очистить'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;

    setState(() {
      _chatMessages.clear();
      _chatError = null;
    });
  }

  Widget box(Widget child, {Color? color}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(25),
      border: Border.all(
        color: dark ? const Color(0xff354036) : const Color(0xffe1e6d8),
      ),
    ),
    child: child,
  );

  Widget filter(String label, bool favorite) => TextButton(
    onPressed: () => setState(() => onlyFavorites = favorite),
    style: TextButton.styleFrom(
      backgroundColor: onlyFavorites == favorite
          ? Theme.of(context).colorScheme.surface
          : Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
    ),
    child: Text(label, style: const TextStyle(fontSize: 12)),
  );

  Future<void> _confirmDeleteEntry(Entry entry) async {
    if (!_storageReady) return;

    final title = entry.title.trim().isEmpty
        ? 'Без названия'
        : entry.title.trim();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить запись?'),
        content: Text(
          'Запись «$title» будет удалена из дневника '
          'и избранного. Отменить удаление нельзя.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('Оставить'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () {
              Navigator.of(dialogContext).pop(true);
            },
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (!mounted || confirmed != true) return;
    if (!entries.contains(entry)) return;

    setState(() {
      entries.remove(entry);
    });

    await _saveDiary();
  }

  Widget entryCard(Entry e) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: box(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(date(e.date), style: small)),
              IconButton(
                tooltip: 'Удалить запись',
                onPressed: () => _confirmDeleteEntry(e),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: muted,
                ),
              ),
              IconButton(
                tooltip: e.favorite
                    ? 'Убрать из избранного'
                    : 'Добавить в избранное',
                style: IconButton.styleFrom(
                  backgroundColor: e.favorite ? accent : sage,
                  foregroundColor: e.favorite ? const Color(0xff584536) : null,
                ),
                onPressed: () => _toggleFavorite(e),
                icon: Icon(
                  e.favorite
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 20,
                ),
              ),
            ],
          ),
          InkWell(
            onTap: () => edit(e),
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title.isEmpty ? 'Без названия' : e.title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (e.video != null) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => _VideoScreen(reference: e.video!),
                          ),
                        ),
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Смотреть видео'),
                      ),
                    ],
                    if (e.voice != null) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'Голосовая заметка — открой запись для прослушивания',
                      ),
                    ],
                    if (e.photos.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _photoStrip(context, e.photos),
                    ],
                    if (e.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        e.text,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.7,
                          color: muted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget diary() {
    final visible = entries.where((e) {
      final matchesFavorite = !onlyFavorites || e.favorite;

      final query = _diaryQuery.trim().toLowerCase().replaceAll('ё', 'е');

      final content = '${e.title}\n${e.text}'.toLowerCase().replaceAll(
        'ё',
        'е',
      );

      final matchesSearch = query.isEmpty || content.contains(query);

      return matchesFavorite && matchesSearch;
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        box(
          Column(
            children: [
              Text(
                'ТВОЁ ЛИЧНОЕ ПРОСТРАНСТВО',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.5,
                  color: muted,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Твоя история.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 33,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Мысли, которые хочется сохранить.',
                textAlign: TextAlign.center,
                style: small,
              ),
              const SizedBox(height: 24),
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 58),
                child: Center(
                  child: Text(
                    prompts[question],
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 19, height: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 6,
                children: [
                  FilledButton(
                    onPressed: () => edit(),
                    child: const Text('Написать'),
                  ),
                  TextButton(
                    onPressed: () => setState(
                      () => question = (question + 1) % prompts.length,
                    ),
                    child: const Text('Другой вопрос ↻'),
                  ),
                ],
              ),
            ],
          ),
          color: sage,
        ),
        const SizedBox(height: 22),
        TextField(
          controller: _diarySearchController,
          onChanged: (value) {
            setState(() {
              _diaryQuery = value;
            });
          },
          textInputAction: TextInputAction.search,
          onSubmitted: (_) {
            FocusScope.of(context).unfocus();
          },
          decoration: InputDecoration(
            hintText: 'Найти в своих записях…',
            prefixIcon: const Icon(Icons.search_rounded, size: 22),
            suffixIcon: _diaryQuery.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Очистить поиск',
                    onPressed: () {
                      _diarySearchController.clear();

                      setState(() {
                        _diaryQuery = '';
                      });

                      FocusScope.of(context).unfocus();
                    },
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 17,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(
                color: dark ? const Color(0xff354036) : const Color(0xffe1e6d8),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(20),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            filter('Все записи', false),
            filter('Избранное', true),
            const Spacer(),
            Text('${visible.length}', style: small),
          ],
        ),
        const SizedBox(height: 16),
        if (visible.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 45),
            child: Text(
              _diaryQuery.trim().isNotEmpty
                  ? 'Ничего не найдено. Попробуй другое слово.'
                  : onlyFavorites
                  ? 'В избранном пока нет записей.'
                  : 'Здесь пока нет записей.',
              textAlign: TextAlign.center,
              style: small,
            ),
          ),
        ...visible.map(entryCard),
        Text(
          'Записи и избранное сохраняются на устройстве. '
          'Выбранное оформление также сохраняется.',
          style: small,
        ),
      ],
    );
  }

  Widget chatBubble(Map<String, String> message) {
    final isUser = message['role'] == 'user';

    return Padding(
      padding: EdgeInsets.only(
        bottom: 14,
        left: isUser ? 24 : 0,
        right: isUser ? 0 : 24,
      ),
      child: box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isUser
                      ? Icons.person_outline_rounded
                      : Icons.auto_awesome_outlined,
                  size: 16,
                  color: muted,
                ),
                const SizedBox(width: 7),
                Text(
                  isUser ? 'Ты' : 'Ассистент',
                  style: TextStyle(
                    color: muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SelectableText(
              message['content'] ?? '',
              style: const TextStyle(fontSize: 15, height: 1.65),
            ),
          ],
        ),
        color: isUser ? sage : null,
      ),
    );
  }

  Widget assistant() {
    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Давай поговорим.',
                style: TextStyle(fontSize: 29, fontWeight: FontWeight.w600),
              ),
            ),
            IconButton(
              tooltip: 'Очистить беседу',
              onPressed: _isSending || _chatMessages.isEmpty
                  ? null
                  : _confirmClearChat,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          'Отправляя сообщение, ты передаёшь его и историю '
          'текущей беседы сервису GigaChat для создания ответа. '
          'Передача записей включается переключателем ниже.',
          style: small,
        ),
        const SizedBox(height: 20),
        if (_chatMessages.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome_outlined, size: 28),
                  const SizedBox(height: 14),
                  const Text(
                    'Здесь можно начать с любой мысли.',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Расскажи, как прошёл день, или попроси '
                    'помочь сформулировать первую запись.',
                    style: TextStyle(color: muted, height: 1.7),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('Начать запись'),
                        onPressed: () {
                          _messageController.text =
                              'Помоги мне начать запись в дневнике. '
                              'Задай один простой вопрос.';
                          _showComposer();
                        },
                      ),
                      ActionChip(
                        label: const Text('Разобраться в мыслях'),
                        onPressed: () {
                          _messageController.text =
                              'Хочу разобраться в своих мыслях. '
                              'Помоги начать разговор.';
                          _showComposer();
                        },
                      ),
                    ],
                  ),
                ],
              ),
              color: sage,
            ),
          ),
        box(
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            title: const Text('Использовать записи дневника'),
            subtitle: Text(
              _useDiaryContext
                  ? 'Включено: записи отправляются с сообщениями. Приоритет у новых.'
                  : 'Выключено: записи не добавляются в запросы.',
            ),
            value: _useDiaryContext,
            onChanged: _isSending || !_storageReady
                ? null
                : (value) {
                    _changeDiaryContext(value);
                  },
          ),
          color: _useDiaryContext ? sage : null,
        ),
        const SizedBox(height: 16),
        ..._chatMessages.map(chatBubble),
        if (_isSending)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: box(
              Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Думаю…'),
                ],
              ),
            ),
          ),
        if (_chatError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: box(
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Не удалось получить ответ',
                    style: TextStyle(
                      color: colors.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    _chatError!,
                    style: TextStyle(
                      color: colors.error,
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Сообщение возвращено в поле ввода. '
                    'Можно попробовать отправить его ещё раз.',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        Container(
          key: _composerKey,
          child: box(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _messageController,
                  enabled: !_isSending,
                  minLines: 2,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  style: const TextStyle(fontSize: 15, height: 1.6),
                  decoration: const InputDecoration(
                    hintText: 'О чём сейчас думаешь?',
                    border: InputBorder.none,
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isSending ? null : _sendMessage,
                    icon: Icon(
                      _isSending
                          ? Icons.hourglass_empty_rounded
                          : Icons.arrow_upward_rounded,
                      size: 19,
                    ),
                    label: Text(_isSending ? 'Отправляется…' : 'Отправить'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Беседа не сохраняется после полного перезапуска. '
          'ИИ может ошибаться.',
          style: small,
        ),
      ],
    );
  }

  Widget settings() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      box(NialProfileCard(key: ValueKey(_profileRevision))),
      const SizedBox(height: 16),
      _diaryBackupPanel(),
      const SizedBox(height: 16),
      const Text(
        'Твоё пространство.',
        style: TextStyle(fontSize: 29, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 22),
      box(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Оформление',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                for (final item in [
                  (ThemeMode.system, 'Система'),
                  (ThemeMode.light, 'Светлая'),
                  (ThemeMode.dark, 'Тёмная'),
                ])
                  ChoiceChip(
                    label: Text(item.$2),
                    selected: widget.mode == item.$1,
                    onSelected: (_) => widget.changeTheme(item.$1),
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
      box(
        const Text(
          'Nial Dairy\n\n'
          'Личный дневник без карт и прогулок.\n\n'
          'Ассистент подключён к сервису GigaChat через API. '
          'Для ответов требуется интернет. '
          'Передача записей включается отдельно во вкладке ассистента.\n\n'
          'Фотографии сохраняются в записях и новых копиях дневника. '
          'Голосовые заметки сохраняются локально. Видео сохраняется локально и входит в ZIP-копии.',
          style: TextStyle(height: 1.7),
        ),
      ),
    ],
  );

  Widget navItem(IconData icon, String text, int index) => Expanded(
    child: Semantics(
      selected: page == index,
      child: InkWell(
        onTap: () {
          FocusScope.of(context).unfocus();
          setState(() => page = index);
        },
        borderRadius: BorderRadius.circular(19),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: page == index
                ? Colors.white.withValues(alpha: dark ? .07 : .22)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(19),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22),
              const SizedBox(height: 5),
              Text(text, style: const TextStyle(fontSize: 10)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget navigation() => Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .15),
          blurRadius: 30,
          offset: const Offset(0, 12),
        ),
      ],
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 9, sigmaY: 9),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: dark
                ? const Color(0xff131c15).withValues(alpha: .22)
                : const Color(0xfffffff9).withValues(alpha: .13),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: Colors.white.withValues(alpha: dark ? .16 : .6),
            ),
          ),
          child: Row(
            children: [
              navItem(Icons.auto_stories_outlined, 'Дневник', 0),
              const SizedBox(width: 5),
              SizedBox(
                width: 48,
                height: 48,
                child: IconButton.filled(
                  onPressed: () => edit(),
                  tooltip: 'Создать запись',
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  icon: const Icon(Icons.add, size: 28),
                ),
              ),
              const SizedBox(width: 5),
              navItem(Icons.auto_awesome_outlined, 'Ассистент', 1),
              navItem(Icons.tune_rounded, 'Настройки', 2),
            ],
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_backupBusy) {
      return const PopScope(
        canPop: false,
        child: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Работа с резервной копией…'),
              ],
            ),
          ),
        ),
      );
    }

    if (!_storageReady) {
      return Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: _storageError == null
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 18),
                        Text('Открываем твой дневник…'),
                      ],
                    )
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_storageError!, textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                        FilledButton(
                          onPressed: _loadDiary,
                          child: const Text('Повторить загрузку'),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    }

    final bottom = MediaQuery.paddingOf(context).bottom;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  22,
                  26,
                  22,
                  keyboardOpen ? 28 : 145 + bottom,
                ),
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Nial Dairy',
                                    style: TextStyle(
                                      fontSize: 25,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -1,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    'МЕСТО ДЛЯ ТВОИХ МЫСЛЕЙ',
                                    style: TextStyle(
                                      fontSize: 9,
                                      letterSpacing: 1.4,
                                      color: muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              width: 44,
                              height: 44,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(17),
                              ),
                              child: const Text(
                                'N',
                                style: TextStyle(color: Color(0xff584536)),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        if (page == 0) diary(),
                        if (page == 1) assistant(),
                        if (page == 2) settings(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (!keyboardOpen)
            Positioned(
              left: 18,
              right: 18,
              bottom: 18 + bottom,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 436),
                  child: navigation(),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class Editor extends StatefulWidget {
  const Editor({super.key, this.entry, required this.question});

  final Entry? entry;
  final int question;

  @override
  State<Editor> createState() => _EditorState();
}

class _EditorState extends State<Editor> {
  late final TextEditingController title;
  late final TextEditingController text;
  late bool favorite;
  late int question;
  late final List<String> _photos;
  bool _photoBusy = false;
  String? _voice;
  String? _video;
  bool _voiceLocked = false;

  @override
  void initState() {
    super.initState();
    title = TextEditingController(text: widget.entry?.title ?? '');
    text = TextEditingController(text: widget.entry?.text ?? '');
    favorite = widget.entry?.favorite ?? false;
    question = widget.question;
    _photos = List<String>.from(widget.entry?.photos ?? const []);
    _voice = widget.entry?.voice;
    _video = widget.entry?.video;
  }

  @override
  void dispose() {
    title.dispose();
    text.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    if (_photoBusy || _voiceLocked || _photos.length >= 6) return;
    setState(() => _photoBusy = true);
    var failed = 0;
    var skipped = 0;
    final added = <String>[];
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.image,
        dialogTitle: 'Выбрать фотографии',
      );
      for (final file in files) {
        if (_photos.length + added.length >= 6) {
          skipped++;
          continue;
        }
        try {
          final builder = BytesBuilder(copy: false);
          await for (final chunk in file.readAsByteStream()) {
            if (builder.length + chunk.length > 20 * 1024 * 1024) {
              throw const FormatException('Image too large');
            }
            builder.add(chunk);
          }
          final buffer = await ImmutableBuffer.fromUint8List(
            builder.takeBytes(),
          );
          try {
            final descriptor = await ImageDescriptor.encoded(buffer);
            try {
              final width = descriptor.width;
              final height = descriptor.height;
              if (width <= 0 || height <= 0 || width * height > 60000000) {
                throw const FormatException('Image dimensions too large');
              }
              final longest = width > height ? width : height;
              final scale = longest > 1280 ? 1280 / longest : 1.0;
              final codec = await descriptor.instantiateCodec(
                targetWidth: (width * scale).round().clamp(1, 1280).toInt(),
                targetHeight: (height * scale).round().clamp(1, 1280).toInt(),
              );
              try {
                final frame = await codec.getNextFrame();
                try {
                  final bytes = await frame.image.toByteData(
                    format: ImageByteFormat.png,
                  );
                  if (bytes == null || bytes.lengthInBytes > 4 * 1024 * 1024) {
                    throw const FormatException('Processed image too large');
                  }
                  added.add(
                    await NialMedia.store(
                      bytes.buffer.asUint8List(
                        bytes.offsetInBytes,
                        bytes.lengthInBytes,
                      ),
                      'png',
                    ),
                  );
                } finally {
                  frame.image.dispose();
                }
              } finally {
                codec.dispose();
              }
            } finally {
              descriptor.dispose();
            }
          } finally {
            buffer.dispose();
          }
        } catch (_) {
          failed++;
        }
      }
      if (!mounted) return;
      setState(() => _photos.addAll(added));
      if (failed > 0 || skipped > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Добавлено: ${added.length}. Не удалось обработать: $failed. Сверх лимита: $skipped.',
            ),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Не удалось открыть выбор фото. Попробуй снова.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  Future<void> _addVideo() async {
    if (_photoBusy || _voiceLocked || _video != null) return;
    setState(() => _photoBusy = true);
    try {
      final selected = await FilePicker.pickFile(
        type: FileType.video,
        dialogTitle: 'Выбрать видео до 25 МиБ',
      );
      if (selected == null) return;
      final builder = BytesBuilder(copy: false);
      await for (final chunk in selected.readAsByteStream()) {
        if (builder.length + chunk.length > NialMedia.maxVideo) {
          throw const FormatException(
            'Видео больше 25 МиБ. Выбери более короткий файл.',
          );
        }
        builder.add(chunk);
      }
      final ref = await NialMedia.store(builder.takeBytes(), 'mp4');
      final controller = VideoPlayerController.file(NialMedia.file(ref));
      try {
        await controller.initialize().timeout(const Duration(seconds: 30));
        if (controller.value.duration > const Duration(minutes: 5) ||
            controller.value.duration <= Duration.zero) {
          throw const FormatException(
            'Нужно видео длительностью от 1 секунды до 5 минут.',
          );
        }
      } finally {
        await controller.dispose();
      }
      if (mounted) setState(() => _video = ref);
    } on FormatException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось добавить видео. Попробуй обычный MP4, который воспроизводится на телефоне.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _photoBusy = false);
    }
  }

  void save() {
    if (_voiceLocked || _photoBusy) return;
    if (title.text.trim().isEmpty &&
        text.text.trim().isEmpty &&
        _photos.isEmpty &&
        _voice == null &&
        _video == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Добавь текст или вложение')),
      );
      return;
    }

    Navigator.of(context).pop(
      Entry(
        title.text.trim(),
        text.text.trim(),
        widget.entry?.date ?? DateTime.now(),
        favorite: favorite,
        photos: _photos,
        voice: _voice,
        video: _video,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_photoBusy) {
      return const PopScope(
        canPop: false,
        child: Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Подготавливаем медиа…'),
              ],
            ),
          ),
        ),
      );
    }

    return PopScope(
      canPop: !_voiceLocked,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: theme.scaffoldBackgroundColor,
          surfaceTintColor: Colors.transparent,
          title: Text(widget.entry == null ? 'Новая запись' : 'Твоя запись'),
          actions: [
            IconButton(
              tooltip: 'Избранное',
              onPressed: () => setState(() => favorite = !favorite),
              icon: Icon(
                favorite
                    ? Icons.bookmark_rounded
                    : Icons.bookmark_border_rounded,
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: ListView(
                padding: const EdgeInsets.all(22),
                children: [
                  TextField(
                    controller: title,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      fontSize: 25,
                      fontWeight: FontWeight.w600,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Дай мысли название…',
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (text.text.trim().isEmpty)
                    Container(
                      padding: const EdgeInsets.all(17),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: .12),
                        borderRadius: BorderRadius.circular(19),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prompts[question],
                            style: const TextStyle(height: 1.6),
                          ),
                          TextButton(
                            onPressed: () => setState(
                              () => question = (question + 1) % prompts.length,
                            ),
                            child: const Text('Другой вопрос ↻'),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: text,
                    onChanged: (_) => setState(() {}),
                    minLines: 8,
                    maxLines: null,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 16, height: 1.7),
                    decoration: const InputDecoration(
                      hintText: 'Здесь можно быть собой…',
                      border: InputBorder.none,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Видео',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                  if (_video == null)
                    OutlinedButton.icon(
                      onPressed: _voiceLocked || _photoBusy ? null : _addVideo,
                      icon: const Icon(Icons.video_library_outlined),
                      label: const Text('Добавить видео'),
                    )
                  else ...[
                    OutlinedButton.icon(
                      onPressed: _voiceLocked
                          ? null
                          : () => Navigator.of(context).push(
                              MaterialPageRoute<void>(
                                builder: (_) =>
                                    _VideoScreen(reference: _video!),
                              ),
                            ),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Смотреть видео'),
                    ),
                    TextButton(
                      onPressed: _voiceLocked
                          ? null
                          : () => setState(() => _video = null),
                      child: const Text('Убрать видео из записи'),
                    ),
                  ],
                  const Text(
                    'Одно видео до 25 МиБ и 5 минут. Без сжатия; поддержка формата зависит от телефона.',
                  ),
                  const SizedBox(height: 16),
                  _VoiceNoteEditor(
                    value: _voice,
                    onChanged: (value) => setState(() => _voice = value),
                    onLocked: (locked) => setState(() => _voiceLocked = locked),
                  ),
                  const SizedBox(height: 16),
                  _photoStrip(
                    context,
                    _photos,
                    onRemove: (index) {
                      setState(() => _photos.removeAt(index));
                    },
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _photoBusy || _voiceLocked || _photos.length >= 6
                        ? null
                        : _addPhotos,
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text('Добавить фото (${_photos.length}/6)'),
                  ),
                  const Text(
                    'До 6 фото. Копии уменьшаются до 1280 пикселей по длинной стороне. '
                    'Исходные файлы в галерее не изменяются.',
                    style: TextStyle(fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _voiceLocked ? null : save,
                    child: const Text('Сохранить запись'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Записи сохраняются в локальной базе на устройстве. '
                    'Фотографии входят в новые резервные копии. Голосовые заметки также входят в новые копии. Видео также входит в ZIP-копии.',
                    style: TextStyle(fontSize: 12, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
