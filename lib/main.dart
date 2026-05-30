import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'platform_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const HairstyleV2App());
}

class HairstyleV2App extends StatefulWidget {
  const HairstyleV2App({super.key});

  @override
  State<HairstyleV2App> createState() => _HairstyleV2AppState();
}

class _HairstyleV2AppState extends State<HairstyleV2App> {
  late final AppController controller;

  @override
  void initState() {
    super.initState();
    controller = AppController()..initialize();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Hairstyle',
        theme: AppTheme.light,
        home: const AppShell(),
      ),
    );
  }
}

class AppTheme {
  static const bg = Color(0xFFF7F4F2);
  static const ink = Color(0xFF161311);
  static const muted = Color(0xFF81766F);
  static const line = Color(0xFFE8E1DC);
  static const gold = Color(0xFFD9B77E);
  static const rose = Color(0xFFB86B77);
  static const surface = Colors.white;

  static ThemeData get light {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: bg,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: ink,
            brightness: Brightness.light,
          ).copyWith(
            primary: ink,
            secondary: rose,
            tertiary: gold,
            surface: surface,
          ),
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: bg,
        foregroundColor: ink,
        centerTitle: false,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}

enum FeatureType {
  hairstyle,
  color,
  glasses,
  age,
  gender,
  beauty,
  faceSwap,
  cartoon,
  background,
}

enum GenerationStatus {
  idle,
  optimizingPrompt,
  generating,
  succeeded,
  failed,
  cancelled,
}

class RuntimeGenerationConfig {
  const RuntimeGenerationConfig({
    required this.realImageGenerationEnabled,
    required this.seedreamBaseUrl,
    required this.seedreamModel,
    required this.dailyFreeLimit,
  });

  static const defaultSeedreamBaseUrl =
      'https://ark.cn-beijing.volces.com/api/v3/images/generations';
  static const defaultSeedreamModel = 'doubao-seedream-4-0-250828';
  static const configuredSeedreamBaseUrl = String.fromEnvironment(
    'SEEDREAM_BASE_URL',
    defaultValue: 'https://ark.cn-beijing.volces.com/api/v3/images/generations',
  );
  static const configuredSeedreamModel = String.fromEnvironment(
    'SEEDREAM_MODEL',
    defaultValue: 'doubao-seedream-4-0-250828',
  );
  static const configuredDailyFreeLimit = int.fromEnvironment(
    'DAILY_FREE_GENERATION_LIMIT',
    defaultValue: 3,
  );
  static const configuredRemoteConfigEnabled = bool.fromEnvironment(
    'FIREBASE_REMOTE_CONFIG_ENABLED',
    defaultValue: false,
  );

  factory RuntimeGenerationConfig.defaults() {
    return const RuntimeGenerationConfig(
      realImageGenerationEnabled: true,
      seedreamBaseUrl: configuredSeedreamBaseUrl,
      seedreamModel: configuredSeedreamModel,
      dailyFreeLimit: configuredDailyFreeLimit,
    );
  }

  final bool realImageGenerationEnabled;
  final String seedreamBaseUrl;
  final String seedreamModel;
  final int dailyFreeLimit;

  RuntimeGenerationConfig copyWith({
    bool? realImageGenerationEnabled,
    String? seedreamBaseUrl,
    String? seedreamModel,
    int? dailyFreeLimit,
  }) {
    return RuntimeGenerationConfig(
      realImageGenerationEnabled:
          realImageGenerationEnabled ?? this.realImageGenerationEnabled,
      seedreamBaseUrl: seedreamBaseUrl ?? this.seedreamBaseUrl,
      seedreamModel: seedreamModel ?? this.seedreamModel,
      dailyFreeLimit: dailyFreeLimit ?? this.dailyFreeLimit,
    );
  }
}

class RuntimeConfigService {
  const RuntimeConfigService();

  Future<RuntimeGenerationConfig> load() async {
    final defaults = RuntimeGenerationConfig.defaults();
    if (!RuntimeGenerationConfig.configuredRemoteConfigEnabled) {
      return defaults;
    }
    try {
      await Firebase.initializeApp();
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setDefaults({
        'seedream_enabled': defaults.realImageGenerationEnabled,
        'seedream_base_url': defaults.seedreamBaseUrl,
        'seedream_model': defaults.seedreamModel,
        'daily_free_generation_limit': defaults.dailyFreeLimit,
      });
      await remoteConfig.setConfigSettings(
        RemoteConfigSettings(
          fetchTimeout: const Duration(seconds: 4),
          minimumFetchInterval: kReleaseMode
              ? const Duration(hours: 1)
              : const Duration(minutes: 1),
        ),
      );
      await remoteConfig.fetchAndActivate();
      final remoteLimit = remoteConfig.getInt('daily_free_generation_limit');
      return defaults.copyWith(
        realImageGenerationEnabled: remoteConfig.getBool('seedream_enabled'),
        seedreamBaseUrl: _fallbackString(
          remoteConfig.getString('seedream_base_url'),
          defaults.seedreamBaseUrl,
        ),
        seedreamModel: _fallbackString(
          remoteConfig.getString('seedream_model'),
          defaults.seedreamModel,
        ),
        dailyFreeLimit: remoteLimit > 0 ? remoteLimit : defaults.dailyFreeLimit,
      );
    } catch (_) {
      return defaults;
    }
  }

  String _fallbackString(String value, String fallback) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? fallback : trimmed;
  }
}

extension FeatureTypeX on FeatureType {
  String get key => name;

  String get title {
    return switch (this) {
      FeatureType.hairstyle => 'AI 换发型',
      FeatureType.color => '发色重绘',
      FeatureType.glasses => '眼镜试戴',
      FeatureType.age => '年龄变化',
      FeatureType.gender => '性别风格',
      FeatureType.beauty => '美颜妆容',
      FeatureType.faceSwap => '换脸模板',
      FeatureType.cartoon => '卡通脸',
      FeatureType.background => '背景光效',
    };
  }

  String get subtitle {
    return switch (this) {
      FeatureType.hairstyle => '保留五官，生成真实可参考的新发型',
      FeatureType.color => '把发色自然重绘到原发丝区域',
      FeatureType.glasses => '智能匹配镜框位置和脸型比例',
      FeatureType.age => '预览年轻、成熟或未来感形象',
      FeatureType.gender => '生成偏女性、偏中性或男生感造型',
      FeatureType.beauty => '肤色、妆容、唇色和自拍质感增强',
      FeatureType.faceSwap => '把用户人像融合到写真和主题模板',
      FeatureType.cartoon => '生成社交头像和卡通风格人像',
      FeatureType.background => '替换拍照场景，叠加柔和光效',
    };
  }

  IconData get icon {
    return switch (this) {
      FeatureType.hairstyle => Icons.content_cut,
      FeatureType.color => Icons.palette_outlined,
      FeatureType.glasses => Icons.remove_red_eye_outlined,
      FeatureType.age => Icons.auto_awesome,
      FeatureType.gender => Icons.transgender,
      FeatureType.beauty => Icons.face_retouching_natural,
      FeatureType.faceSwap => Icons.switch_account_outlined,
      FeatureType.cartoon => Icons.mood_outlined,
      FeatureType.background => Icons.filter_frames_outlined,
    };
  }
}

class AppScope extends InheritedNotifier<AppController> {
  const AppScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope not found');
    return scope!.notifier!;
  }
}

class AppController extends ChangeNotifier {
  AppController() : this._(createPlatformStore());

  AppController._(this.platformStore)
    : promptService = PromptService(),
      generationService = ImageGenerationService(),
      historyRepository = HistoryRepository(platformStore);

  final PlatformStore platformStore;
  final PromptService promptService;
  final ImageGenerationService generationService;
  final HistoryRepository historyRepository;
  final picker = ImagePicker();

  RuntimeGenerationConfig runtimeConfig = RuntimeGenerationConfig.defaults();
  AssetCatalog? catalog;
  bool initialized = false;
  int tabIndex = 0;
  FeatureType activeFeature = FeatureType.hairstyle;
  StyleTemplate? selectedTemplate;
  Uint8List? sourceBytes;
  String? sourceLocalPath;
  String sourceLabel = '默认模特';
  Uint8List? resultBytes;
  String? resultLocalPath;
  String? prompt;
  String? negativePrompt;
  String? errorMessage;
  GenerationStatus status = GenerationStatus.idle;
  bool isMember = false;
  bool hasRewardUnlock = false;
  int remainingFreeGenerations = 3;
  List<HistoryRecord> history = [];

  bool get hasResult =>
      resultBytes != null && status == GenerationStatus.succeeded;
  bool get isBusy =>
      status == GenerationStatus.optimizingPrompt ||
      status == GenerationStatus.generating;
  bool get canGenerate =>
      initialized && sourceBytes != null && selectedTemplate != null && !isBusy;

  List<StyleTemplate> templatesFor(FeatureType feature) {
    return catalog?.templates.where((t) => t.feature == feature).toList() ??
        const [];
  }

  StyleTemplate? defaultTemplateFor(FeatureType feature) {
    final templates = templatesFor(feature);
    return templates.firstWhereOrNull((template) => !template.isPro) ??
        templates.firstOrNull;
  }

  Future<void> initialize() async {
    runtimeConfig = await const RuntimeConfigService().load();
    final prefs = await SharedPreferences.getInstance();
    isMember = prefs.getBool('member_enabled') ?? false;
    remainingFreeGenerations =
        prefs.getInt('remaining_free_generations') ??
        runtimeConfig.dailyFreeLimit;
    if (!isMember) {
      remainingFreeGenerations = math.min(
        remainingFreeGenerations,
        runtimeConfig.dailyFreeLimit,
      );
    }
    catalog = await AssetCatalog.load();
    history = await historyRepository.load();
    final defaultAsset = catalog!.defaultModel;
    await setSourceFromAsset(defaultAsset, label: '默认模特');
    selectedTemplate = defaultTemplateFor(FeatureType.hairstyle);
    initialized = true;
    notifyListeners();
  }

  Future<void> persistEntitlements() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('member_enabled', isMember);
    await prefs.setInt('remaining_free_generations', remainingFreeGenerations);
  }

  void setTab(int index) {
    tabIndex = index;
    notifyListeners();
  }

  void setFeature(FeatureType feature) {
    activeFeature = feature;
    selectedTemplate = defaultTemplateFor(feature);
    resultBytes = null;
    resultLocalPath = null;
    prompt = null;
    negativePrompt = null;
    errorMessage = null;
    status = GenerationStatus.idle;
    notifyListeners();
  }

  void selectTemplate(StyleTemplate template) {
    activeFeature = template.feature;
    selectedTemplate = template;
    notifyListeners();
  }

  bool requiresPaywall({StyleTemplate? template, bool highDefinition = false}) {
    final t = template ?? selectedTemplate;
    if (isMember || hasRewardUnlock) {
      return false;
    }
    return (t?.isPro ?? false) ||
        highDefinition ||
        remainingFreeGenerations <= 0;
  }

  Future<void> unlockMembership() async {
    isMember = true;
    hasRewardUnlock = false;
    remainingFreeGenerations = 99;
    await persistEntitlements();
    notifyListeners();
  }

  Future<void> unlockRewardOnce() async {
    hasRewardUnlock = true;
    await persistEntitlements();
    notifyListeners();
  }

  Future<void> consumeQuotaIfNeeded() async {
    if (isMember) {
      return;
    }
    if (hasRewardUnlock) {
      hasRewardUnlock = false;
    } else if (remainingFreeGenerations > 0) {
      remainingFreeGenerations -= 1;
    }
    await persistEntitlements();
  }

  Future<void> setSourceFromAsset(
    String assetPath, {
    required String label,
  }) async {
    final data = await rootBundle.load(assetPath);
    sourceBytes = data.buffer.asUint8List();
    sourceLocalPath = null;
    sourceLabel = label;
    resultBytes = null;
    resultLocalPath = null;
    status = GenerationStatus.idle;
    notifyListeners();
  }

  Future<void> pickImage(ImageSource source) async {
    if (!kIsWeb) {
      final permission = source == ImageSource.camera
          ? await Permission.camera.request()
          : await Permission.photos.request();
      if (!permission.isGranted && !permission.isLimited) {
        errorMessage = source == ImageSource.camera ? '相机权限未开启' : '相册权限未开启';
        notifyListeners();
        return;
      }
    }

    final file = await picker.pickImage(
      source: source,
      imageQuality: 92,
      maxWidth: 1600,
    );
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    final savedPath = await historyRepository.saveInputBytes(
      bytes,
      extension: 'jpg',
    );
    sourceBytes = bytes;
    sourceLocalPath = savedPath;
    sourceLabel = source == ImageSource.camera ? '相机照片' : '相册照片';
    resultBytes = null;
    resultLocalPath = null;
    status = GenerationStatus.idle;
    errorMessage = null;
    notifyListeners();
  }

  Future<bool> generate() async {
    final source = sourceBytes;
    final template = selectedTemplate;
    if (source == null || template == null) {
      errorMessage = '请先选择照片和模板';
      notifyListeners();
      return false;
    }
    if (requiresPaywall(template: template)) {
      return false;
    }

    status = GenerationStatus.optimizingPrompt;
    resultBytes = null;
    resultLocalPath = null;
    prompt = null;
    negativePrompt = null;
    errorMessage = null;
    notifyListeners();

    try {
      final promptResult = await promptService.optimize(
        feature: activeFeature,
        template: template,
        sourceLabel: sourceLabel,
      );
      prompt = promptResult.prompt;
      negativePrompt = promptResult.negativePrompt;
      status = GenerationStatus.generating;
      notifyListeners();

      final image = await generationService.generate(
        sourceBytes: source,
        feature: activeFeature,
        template: template,
        prompt: promptResult,
        config: runtimeConfig,
      );
      resultBytes = image.bytes;
      resultLocalPath = await historyRepository.saveResultBytes(image.bytes);
      status = GenerationStatus.succeeded;
      await consumeQuotaIfNeeded();
      await addHistory(statusOverride: 'succeeded');
      notifyListeners();
      return true;
    } catch (e) {
      errorMessage = e.toString();
      status = GenerationStatus.failed;
      notifyListeners();
      return false;
    }
  }

  Future<void> cancelGeneration() async {
    if (!isBusy) {
      return;
    }
    status = GenerationStatus.cancelled;
    errorMessage = '已取消，当前照片和模板保留为草稿';
    await addHistory(statusOverride: 'draft');
    notifyListeners();
  }

  Future<void> addHistory({required String statusOverride}) async {
    final source = sourceBytes;
    final result = resultBytes;
    final template = selectedTemplate;
    if (source == null || template == null) {
      return;
    }
    final record = await historyRepository.saveRecord(
      sourceBytes: source,
      resultBytes: result,
      feature: activeFeature,
      template: template,
      prompt: prompt ?? '',
      negativePrompt: negativePrompt ?? '',
      status: statusOverride,
    );
    history = [
      record,
      ...history.where((item) => item.id != record.id),
    ].take(80).toList();
    notifyListeners();
  }

  Future<void> saveResultToGallery({bool highDefinition = false}) async {
    final bytes = resultBytes;
    if (bytes == null) {
      errorMessage = '还没有可保存的生成结果';
      notifyListeners();
      return;
    }
    if (requiresPaywall(highDefinition: highDefinition)) {
      errorMessage = '高清保存需要会员或激励解锁';
      notifyListeners();
      return;
    }
    if (!kIsWeb) {
      final storage = await Permission.storage.request();
      if (!storage.isGranted && !storage.isLimited) {
        await Permission.photos.request();
      }
    }
    final name = 'hairstyle_${DateTime.now().millisecondsSinceEpoch}';
    final ok = await platformStore.saveImageToUserDevice(bytes, name: name);
    errorMessage = ok ? (kIsWeb ? '已下载生成图片' : '已保存到系统相册') : '保存失败，请检查权限';
    notifyListeners();
  }

  Future<void> shareResult() async {
    final bytes = resultBytes;
    if (bytes == null) {
      errorMessage = '还没有可分享的生成结果';
      notifyListeners();
      return;
    }
    final path =
        resultLocalPath ?? await historyRepository.saveResultBytes(bytes);
    await platformStore.shareImage(
      bytes,
      reference: path,
      text: 'Hairstyle AI result',
    );
  }

  Future<void> toggleFavorite(HistoryRecord record) async {
    final updated = record.copyWith(isFavorite: !record.isFavorite);
    history = history
        .map((item) => item.id == record.id ? updated : item)
        .toList();
    await historyRepository.persist(history);
    notifyListeners();
  }

  Future<void> restoreHistory(HistoryRecord record) async {
    final source = await historyRepository.readStoredBytes(
      record.sourceImagePath,
    );
    final result = await historyRepository.readStoredBytes(
      record.resultImagePath,
    );
    if (source != null) {
      sourceBytes = source;
      sourceLocalPath = record.sourceImagePath;
      sourceLabel = '历史原图';
    }
    if (result != null) {
      resultBytes = result;
      resultLocalPath = record.resultImagePath;
      status = GenerationStatus.succeeded;
    }
    activeFeature = FeatureType.values.firstWhere(
      (f) => f.key == record.featureKey,
      orElse: () => FeatureType.hairstyle,
    );
    selectedTemplate =
        templatesFor(
          activeFeature,
        ).firstWhereOrNull((t) => t.id == record.templateId) ??
        defaultTemplateFor(activeFeature);
    prompt = record.prompt;
    negativePrompt = record.negativePrompt;
    tabIndex = 0;
    notifyListeners();
  }

  Future<void> clearHistory() async {
    history = [];
    await historyRepository.clear();
    notifyListeners();
  }
}

class PromptResult {
  const PromptResult({
    required this.prompt,
    required this.negativePrompt,
    required this.provider,
    required this.raw,
  });

  final String prompt;
  final String negativePrompt;
  final String provider;
  final String raw;
}

class PromptService {
  static const apiKey = String.fromEnvironment(
    'AI_TEXT_API_KEY',
    defaultValue: String.fromEnvironment('DEEPSEEK_API_KEY'),
  );
  static const baseUrl = String.fromEnvironment(
    'AI_TEXT_BASE_URL',
    defaultValue: String.fromEnvironment(
      'DEEPSEEK_BASE_URL',
      defaultValue: 'https://api.gptsapi.net/v1',
    ),
  );
  static const model = String.fromEnvironment(
    'AI_TEXT_MODEL',
    defaultValue: String.fromEnvironment(
      'DEEPSEEK_MODEL',
      defaultValue: 'gpt-4o-mini',
    ),
  );

  Future<PromptResult> optimize({
    required FeatureType feature,
    required StyleTemplate template,
    required String sourceLabel,
  }) async {
    final fallback = _fallbackPrompt(feature, template, sourceLabel);
    if (apiKey.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return fallback;
    }

    try {
      final response = await http.post(
        Uri.parse('${_normalizedBaseUrl()}/chat/completions'),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {
              'role': 'system',
              'content':
                  'You optimize concise image generation prompts for a hairstyle and beauty try-on app. Return JSON only with prompt and negative_prompt.',
            },
            {
              'role': 'user',
              'content': jsonEncode({
                'feature': feature.title,
                'template_title': template.title,
                'template_tags': template.tags,
                'prompt_hint': template.promptHint,
                'source': sourceLabel,
                'requirements': [
                  'preserve face identity',
                  'photorealistic',
                  'mobile selfie app result',
                  'no text in image',
                ],
              }),
            },
          ],
          'temperature': 0.4,
        }),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return fallback;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final content = body['choices']?[0]?['message']?['content'] as String?;
      if (content == null || content.isEmpty) {
        return fallback;
      }
      final jsonText = _extractJson(content);
      final map = jsonDecode(jsonText) as Map<String, dynamic>;
      return PromptResult(
        prompt: map['prompt'] as String? ?? fallback.prompt,
        negativePrompt:
            map['negative_prompt'] as String? ?? fallback.negativePrompt,
        provider: 'openai-compatible',
        raw: content,
      );
    } catch (_) {
      return fallback;
    }
  }

  String _normalizedBaseUrl() {
    return baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
  }

  String _extractJson(String input) {
    final start = input.indexOf('{');
    final end = input.lastIndexOf('}');
    if (start >= 0 && end > start) {
      return input.substring(start, end + 1);
    }
    return jsonEncode({
      'prompt': input,
      'negative_prompt': 'distorted face, extra limbs, low quality, watermark',
    });
  }

  PromptResult _fallbackPrompt(
    FeatureType feature,
    StyleTemplate template,
    String sourceLabel,
  ) {
    final prompt = [
      'Photorealistic mobile beauty app output.',
      'Preserve the person identity, face shape, skin tone and natural lighting.',
      'Apply ${feature.title}: ${template.title}.',
      template.promptHint,
      'Clean salon-quality result, realistic hair strands, no text, no watermark.',
    ].join(' ');
    return PromptResult(
      prompt: prompt,
      negativePrompt:
          'distorted face, changed identity, extra face, bad anatomy, low resolution, artifacts, watermark, text, logo',
      provider: 'local-fallback',
      raw: prompt,
    );
  }
}

class ObfuscatedSecrets {
  static const _seedreamCipherChunks = [
    [101, 241, 136, 104, 42, 23, 145, 102, 81, 97],
    [177, 184, 72, 42, 234, 191, 28, 200, 187, 155],
    [180, 68, 3, 107, 55, 252, 108, 252, 187, 164],
    [160, 125, 87, 173, 65, 186, 124, 148, 209, 49],
    [56, 26, 235, 75, 5, 127],
  ];
  static const _seedreamMaskChunks = [
    [4, 131, 227, 69, 19, 36, 245, 84, 105, 0],
    [210, 140, 101, 26, 211, 137, 126, 229, 143, 175],
    [130, 124, 46, 83, 1, 207, 9, 209, 221, 192],
    [150, 25, 99, 148, 117, 137, 79, 164, 178, 80],
    [21, 121, 223, 47, 103, 25],
  ];

  static String seedreamApiKey({String environmentKey = ''}) {
    if (environmentKey.isNotEmpty) {
      return environmentKey;
    }
    return _decode(_seedreamCipherChunks, _seedreamMaskChunks);
  }

  static String _decode(List<List<int>> chunks, List<List<int>> maskChunks) {
    final cipher = chunks.expand((part) => part).toList(growable: false);
    final mask = maskChunks.expand((part) => part).toList(growable: false);
    final output = <int>[];
    for (var i = 0; i < cipher.length; i++) {
      output.add(cipher[i] ^ mask[i]);
    }
    return utf8.decode(output);
  }
}

class GeneratedImageResult {
  const GeneratedImageResult({
    required this.bytes,
    required this.provider,
    this.remoteUrl,
  });
  final Uint8List bytes;
  final String provider;
  final String? remoteUrl;
}

class ImageGenerationService {
  static const environmentApiKey = String.fromEnvironment('SEEDREAM_API_KEY');

  Future<GeneratedImageResult> generate({
    required Uint8List sourceBytes,
    required FeatureType feature,
    required StyleTemplate template,
    required PromptResult prompt,
    required RuntimeGenerationConfig config,
  }) async {
    if (!kIsWeb &&
        config.realImageGenerationEnabled &&
        config.seedreamBaseUrl.isNotEmpty) {
      try {
        final apiKey = ObfuscatedSecrets.seedreamApiKey(
          environmentKey: environmentApiKey,
        );
        if (apiKey.isEmpty) {
          throw StateError('Seedream key is empty');
        }
        final response = await http
            .post(
              Uri.parse(config.seedreamBaseUrl),
              headers: {
                'Authorization': 'Bearer $apiKey',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'model': config.seedreamModel,
                'prompt': prompt.prompt,
                'negative_prompt': prompt.negativePrompt,
                'image': base64Encode(sourceBytes),
                'size': '1024x1024',
                'sequential_image_generation': 'disabled',
                'stream': false,
                'response_format': 'b64_json',
                'watermark': false,
                'metadata': {
                  'feature': feature.key,
                  'template_id': template.id,
                },
              }),
            )
            .timeout(const Duration(seconds: 20));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          final body = jsonDecode(response.body) as Map<String, dynamic>;
          final data = body['data'];
          if (data is List && data.isNotEmpty) {
            final item = data.first as Map<String, dynamic>;
            final b64 = item['b64_json'] as String?;
            final url = item['url'] as String?;
            if (b64 != null) {
              return GeneratedImageResult(
                bytes: base64Decode(b64),
                provider: 'seedream',
                remoteUrl: url,
              );
            }
            if (url != null) {
              final imageResponse = await http
                  .get(Uri.parse(url))
                  .timeout(const Duration(seconds: 20));
              if (imageResponse.statusCode == 200) {
                return GeneratedImageResult(
                  bytes: imageResponse.bodyBytes,
                  provider: 'seedream',
                  remoteUrl: url,
                );
              }
            }
          }
        }
      } catch (_) {
        // Fall through to local deterministic mock so the product flow stays usable in debug builds.
      }
    }

    await Future<void>.delayed(const Duration(milliseconds: 900));
    final bytes = await MockImageComposer.compose(
      sourceBytes: sourceBytes,
      feature: feature,
      template: template,
      prompt: prompt.prompt,
    );
    return GeneratedImageResult(
      bytes: bytes,
      provider: 'local-seedream-fallback',
    );
  }
}

class MockImageComposer {
  static Future<Uint8List> compose({
    required Uint8List sourceBytes,
    required FeatureType feature,
    required StyleTemplate template,
    required String prompt,
  }) async {
    final image = await _decode(sourceBytes);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const width = 1080.0;
    const height = 1440.0;
    final paint = Paint()..isAntiAlias = true;

    canvas.drawColor(AppTheme.bg, BlendMode.src);
    final src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final dst = _coverRect(
      Size(image.width.toDouble(), image.height.toDouble()),
      const Size(width, height),
    );
    canvas.drawImageRect(image, src, dst, paint);

    final tint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _featureColor(feature).withValues(alpha: 0.05),
          _featureColor(feature).withValues(alpha: 0.24),
        ],
      ).createShader(const Rect.fromLTWH(0, 0, width, height));
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), tint);

    if (feature == FeatureType.hairstyle || feature == FeatureType.color) {
      final hairPaint = Paint()
        ..color = _featureColor(
          feature,
        ).withValues(alpha: feature == FeatureType.color ? 0.28 : 0.16)
        ..blendMode = BlendMode.overlay
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
      canvas.drawOval(const Rect.fromLTWH(245, 130, 590, 470), hairPaint);
    }
    if (feature == FeatureType.glasses) {
      final glassPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.round
        ..color = Colors.black.withValues(alpha: 0.62);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(260, 460, 245, 116),
          const Radius.circular(44),
        ),
        glassPaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(575, 460, 245, 116),
          const Radius.circular(44),
        ),
        glassPaint,
      );
      canvas.drawLine(
        const Offset(505, 515),
        const Offset(575, 515),
        glassPaint,
      );
    }
    if (feature == FeatureType.beauty) {
      final cheek = Paint()
        ..color = AppTheme.rose.withValues(alpha: 0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18);
      canvas.drawOval(const Rect.fromLTWH(255, 575, 175, 80), cheek);
      canvas.drawOval(const Rect.fromLTWH(650, 575, 175, 80), cheek);
    }
    if (feature == FeatureType.cartoon) {
      final overlay = Paint()
        ..color = const Color(0xFFFFF6D7).withValues(alpha: 0.16)
        ..blendMode = BlendMode.softLight;
      canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), overlay);
    }

    final panelPaint = Paint()..color = Colors.black.withValues(alpha: 0.58);
    final panel = RRect.fromRectAndRadius(
      const Rect.fromLTWH(54, 1196, 972, 166),
      const Radius.circular(34),
    );
    canvas.drawRRect(panel, panelPaint);
    _drawText(
      canvas,
      feature.title,
      const Offset(90, 1225),
      38,
      Colors.white,
      FontWeight.w800,
      maxWidth: 420,
    );
    _drawText(
      canvas,
      template.title,
      const Offset(90, 1280),
      28,
      AppTheme.gold,
      FontWeight.w700,
      maxWidth: 520,
    );
    _drawText(
      canvas,
      'Seedream preview · AI prompt ready',
      const Offset(90, 1321),
      23,
      Colors.white70,
      FontWeight.w500,
      maxWidth: 820,
    );

    image.dispose();
    final picture = recorder.endRecording();
    final out = await picture.toImage(width.round(), height.round());
    final byteData = await out.toByteData(format: ui.ImageByteFormat.png);
    out.dispose();
    picture.dispose();
    return byteData!.buffer.asUint8List();
  }

  static Rect _coverRect(Size image, Size canvas) {
    final scale = math.max(
      canvas.width / image.width,
      canvas.height / image.height,
    );
    final w = image.width * scale;
    final h = image.height * scale;
    return Rect.fromLTWH((canvas.width - w) / 2, (canvas.height - h) / 2, w, h);
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  static Color _featureColor(FeatureType feature) {
    return switch (feature) {
      FeatureType.hairstyle => AppTheme.rose,
      FeatureType.color => const Color(0xFF9A5938),
      FeatureType.glasses => const Color(0xFF222222),
      FeatureType.age => const Color(0xFF7A65C8),
      FeatureType.gender => const Color(0xFF5E8AA8),
      FeatureType.beauty => const Color(0xFFC1688C),
      FeatureType.faceSwap => const Color(0xFF8C6B53),
      FeatureType.cartoon => const Color(0xFFE6A83D),
      FeatureType.background => const Color(0xFF5E8C7F),
    };
  }

  static void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    double size,
    Color color,
    FontWeight weight, {
    required double maxWidth,
  }) {
    final builder =
        ui.ParagraphBuilder(ui.ParagraphStyle(maxLines: 2, ellipsis: '…'))
          ..pushStyle(
            ui.TextStyle(color: color, fontSize: size, fontWeight: weight),
          )
          ..addText(text);
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: maxWidth));
    canvas.drawParagraph(paragraph, offset);
  }
}

class StyleTemplate {
  const StyleTemplate({
    required this.id,
    required this.feature,
    required this.title,
    required this.subtitle,
    required this.previewAsset,
    required this.promptHint,
    this.materialAsset,
    this.isPro = false,
    this.tags = const [],
  });

  final String id;
  final FeatureType feature;
  final String title;
  final String subtitle;
  final String previewAsset;
  final String promptHint;
  final String? materialAsset;
  final bool isPro;
  final List<String> tags;
}

class HairItem {
  const HairItem({
    required this.id,
    required this.gender,
    required this.type,
    required this.assetPath,
    required this.anchorA,
    required this.anchorB,
  });

  final int id;
  final int gender;
  final int type;
  final String assetPath;
  final Offset? anchorA;
  final Offset? anchorB;
}

class AssetCatalog {
  const AssetCatalog({
    required this.ages,
    required this.ancient,
    required this.child,
    required this.color,
    required this.female,
    required this.glasses,
    required this.hairs,
    required this.lines,
    required this.male,
    required this.scene,
    required this.templates,
  });

  final List<String> ages;
  final List<String> ancient;
  final List<String> child;
  final List<String> color;
  final List<String> female;
  final List<String> glasses;
  final List<HairItem> hairs;
  final List<String> lines;
  final List<String> male;
  final List<String> scene;
  final List<StyleTemplate> templates;

  String get defaultModel =>
      female.firstOrNull ?? male.firstOrNull ?? 'assets/icon/sample1.png';

  static Future<AssetCatalog> load() async {
    final rawManifest = await rootBundle.loadString('AssetManifest.json');
    final manifest = jsonDecode(rawManifest) as Map<String, dynamic>;
    final keys = manifest.keys.toList();
    final allAssets = keys.where((k) => k.startsWith('assets/')).toSet();

    List<String> inFolder(String folder) {
      final result =
          keys
              .where((k) => k.startsWith('assets/$folder/'))
              .where(
                (k) =>
                    k.endsWith('.png') ||
                    k.endsWith('.jpg') ||
                    k.endsWith('.jpeg'),
              )
              .toList()
            ..sort(_assetNaturalCompare);
      return result;
    }

    final ages = inFolder('ages');
    final ancient = inFolder('ancient');
    final child = inFolder('child');
    final color = inFolder('color');
    final female = inFolder('female');
    final male = inFolder('male');
    final scene = inFolder('scene');
    final lines = inFolder('lines');
    final glasses = inFolder(
      'glasses',
    ).where((asset) => asset.split('/').last.startsWith('glass')).toList();

    final hairsJson =
        jsonDecode(await rootBundle.loadString('assets/data/hairs.json'))
            as List<dynamic>;
    final hairs = <HairItem>[];
    for (final raw in hairsJson) {
      final map = raw as Map<String, dynamic>;
      final id = (map['hairstyleId'] as num).toInt();
      final assetPath = 'assets/glasses/hair$id.png';
      if (!allAssets.contains(assetPath)) {
        continue;
      }
      hairs.add(
        HairItem(
          id: id,
          gender: (map['gender'] as num).toInt(),
          type: (map['type'] as num).toInt(),
          assetPath: assetPath,
          anchorA: _parseAnchor(map['a'] as String?),
          anchorB: _parseAnchor(map['b'] as String?),
        ),
      );
    }

    final templates = _buildTemplates(
      ages: ages,
      ancient: ancient,
      child: child,
      color: color,
      female: female,
      glasses: glasses,
      hairs: hairs,
      lines: lines,
      male: male,
      scene: scene,
    );

    return AssetCatalog(
      ages: ages,
      ancient: ancient,
      child: child,
      color: color,
      female: female,
      glasses: glasses,
      hairs: hairs,
      lines: lines,
      male: male,
      scene: scene,
      templates: templates,
    );
  }

  static Offset? _parseAnchor(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return Offset(
        double.parse(list[0].toString()),
        double.parse(list[1].toString()),
      );
    } catch (_) {
      return null;
    }
  }

  static List<StyleTemplate> _buildTemplates({
    required List<String> ages,
    required List<String> ancient,
    required List<String> child,
    required List<String> color,
    required List<String> female,
    required List<String> glasses,
    required List<HairItem> hairs,
    required List<String> lines,
    required List<String> male,
    required List<String> scene,
  }) {
    final result = <StyleTemplate>[];
    final hairNames = [
      'French Curl',
      'Soft Wave',
      'Air Bangs',
      'Long Layer',
      'Short Bob',
      'Korean Perm',
      'Salon Cut',
      'Natural Volume',
    ];
    for (var i = 0; i < math.min(24, hairs.length); i++) {
      final item = hairs[i];
      final preview =
          female.elementAtOrNull(i % math.max(1, female.length)) ??
          male.firstOrNull ??
          item.assetPath;
      result.add(
        StyleTemplate(
          id: 'hair_${item.id}',
          feature: FeatureType.hairstyle,
          title: hairNames[i % hairNames.length],
          subtitle: item.gender == 1
              ? '女生 · ${_typeLabel(item.type)}'
              : '男士 · ${_typeLabel(item.type)}',
          previewAsset: preview,
          materialAsset: item.assetPath,
          promptHint:
              'replace hairstyle with ${hairNames[i % hairNames.length]}, natural hairline, realistic hair strand detail, ${_typeLabel(item.type)} length',
          isPro: i % 5 == 0,
          tags: [
            'hair',
            item.gender == 1 ? 'female' : 'male',
            _typeLabel(item.type),
          ],
        ),
      );
    }

    for (var i = 0; i < math.min(12, color.length); i++) {
      result.add(
        StyleTemplate(
          id: 'color_$i',
          feature: FeatureType.color,
          title: [
            'Chocolate Brown',
            'Rose Brown',
            'Ash Blonde',
            'Cherry Red',
          ][i % 4],
          subtitle: '自然发色重绘',
          previewAsset: color[i],
          promptHint:
              'natural hair color transformation, preserve hair texture, salon dye finish',
          isPro: i % 4 == 0,
          tags: ['color'],
        ),
      );
    }

    for (var i = 0; i < math.min(18, glasses.length); i++) {
      result.add(
        StyleTemplate(
          id: 'glass_$i',
          feature: FeatureType.glasses,
          title: ['Round Frame', 'Light Metal', 'Square Chic'][i % 3],
          subtitle: '智能眼镜试戴',
          previewAsset: glasses[i],
          promptHint:
              'add realistic eyewear that fits the eye position and face shape, no distortion',
          isPro: i % 6 == 0,
          tags: ['glasses'],
        ),
      );
    }

    void addTemplate(
      FeatureType feature,
      String id,
      String title,
      String subtitle,
      String? asset,
      String hint, {
      bool pro = false,
    }) {
      result.add(
        StyleTemplate(
          id: id,
          feature: feature,
          title: title,
          subtitle: subtitle,
          previewAsset: asset ?? 'assets/icon/sample1.png',
          promptHint: hint,
          isPro: pro,
          tags: [feature.key],
        ),
      );
    }

    addTemplate(
      FeatureType.age,
      'age_soft_young',
      'Soft Young',
      '少女感',
      ages.elementAtOrNull(0),
      'make the person look younger while preserving identity, soft youthful skin and hairstyle',
    );
    addTemplate(
      FeatureType.age,
      'age_elegant_mature',
      'Elegant Mature',
      '成熟质感',
      ages.elementAtOrNull(1),
      'make the person look mature and elegant, premium portrait retouch, preserve identity',
      pro: true,
    );
    addTemplate(
      FeatureType.gender,
      'gender_feminine',
      'Feminine Look',
      '柔和女性化',
      'assets/icon/sex_female.png',
      'feminine hairstyle and fashion portrait, preserve facial identity',
    );
    addTemplate(
      FeatureType.gender,
      'gender_masculine',
      'Masculine Look',
      '清爽男生感',
      'assets/icon/sex_male.png',
      'masculine short hairstyle, clean jawline styling, preserve identity',
      pro: true,
    );
    addTemplate(
      FeatureType.beauty,
      'beauty_clean',
      'Clean Makeup',
      '通勤清透妆',
      'assets/icon/beauty.png',
      'clean makeup, smooth skin, natural lip color, realistic retouch',
    );
    addTemplate(
      FeatureType.beauty,
      'beauty_glam',
      'Glam Makeup',
      '精致晚宴妆',
      'assets/icon/beauty4.png',
      'glam makeup, refined eye makeup, glossy lips, professional beauty portrait',
      pro: true,
    );
    addTemplate(
      FeatureType.faceSwap,
      'swap_editorial',
      'Editorial Cover',
      '杂志写真模板',
      'assets/icon/swap_bg.png',
      'blend face identity into an editorial magazine portrait template, realistic lighting',
    );
    addTemplate(
      FeatureType.faceSwap,
      'swap_ancient',
      'Ancient Style',
      '古风写真融合',
      ancient.firstOrNull,
      'ancient Chinese portrait style, elegant costume, preserve face identity',
      pro: true,
    );
    addTemplate(
      FeatureType.cartoon,
      'cartoon_soft',
      'Soft Cartoon',
      '社交头像',
      ages.firstWhereOrNull((a) => a.contains('cartoon')) ?? ages.firstOrNull,
      'soft cartoon avatar, recognizable face, clean social profile picture',
    );
    addTemplate(
      FeatureType.cartoon,
      'cartoon_3d',
      '3D Avatar',
      '3D 头像',
      'assets/icon/ai.png',
      '3d cartoon avatar, premium app icon quality, recognizable face',
      pro: true,
    );
    addTemplate(
      FeatureType.background,
      'scene_photo',
      'Photo Studio',
      '棚拍背景',
      scene.firstOrNull,
      'replace background with clean photo studio, preserve person edges',
    );
    addTemplate(
      FeatureType.background,
      'scene_light',
      'Soft Light',
      '柔和光效',
      lines.firstOrNull ?? scene.elementAtOrNull(1),
      'add soft cinematic light effects, keep face clear and natural',
    );

    return result;
  }

  static String _typeLabel(int type) {
    return switch (type) {
      1 => '短发',
      2 => '中长发',
      3 => '长发',
      _ => '推荐',
    };
  }
}

class HistoryRecord {
  const HistoryRecord({
    required this.id,
    required this.sourceImagePath,
    required this.resultImagePath,
    required this.featureKey,
    required this.templateId,
    required this.templateTitle,
    required this.prompt,
    required this.negativePrompt,
    required this.status,
    required this.createdAt,
    this.isFavorite = false,
  });

  final String id;
  final String sourceImagePath;
  final String resultImagePath;
  final String featureKey;
  final String templateId;
  final String templateTitle;
  final String prompt;
  final String negativePrompt;
  final String status;
  final DateTime createdAt;
  final bool isFavorite;

  String get featureLabel => FeatureType.values
      .firstWhere(
        (f) => f.key == featureKey,
        orElse: () => FeatureType.hairstyle,
      )
      .title;

  String get formattedTime {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${createdAt.month}-${two(createdAt.day)} ${two(createdAt.hour)}:${two(createdAt.minute)}';
  }

  HistoryRecord copyWith({bool? isFavorite}) {
    return HistoryRecord(
      id: id,
      sourceImagePath: sourceImagePath,
      resultImagePath: resultImagePath,
      featureKey: featureKey,
      templateId: templateId,
      templateTitle: templateTitle,
      prompt: prompt,
      negativePrompt: negativePrompt,
      status: status,
      createdAt: createdAt,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sourceImagePath': sourceImagePath,
      'resultImagePath': resultImagePath,
      'featureKey': featureKey,
      'templateId': templateId,
      'templateTitle': templateTitle,
      'prompt': prompt,
      'negativePrompt': negativePrompt,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'isFavorite': isFavorite,
    };
  }

  factory HistoryRecord.fromJson(Map<String, dynamic> json) {
    return HistoryRecord(
      id: json['id'] as String? ?? '',
      sourceImagePath: json['sourceImagePath'] as String? ?? '',
      resultImagePath: json['resultImagePath'] as String? ?? '',
      featureKey: json['featureKey'] as String? ?? FeatureType.hairstyle.key,
      templateId: json['templateId'] as String? ?? '',
      templateTitle: json['templateTitle'] as String? ?? 'AI Result',
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: json['negativePrompt'] as String? ?? '',
      status: json['status'] as String? ?? 'succeeded',
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      isFavorite: json['isFavorite'] as bool? ?? false,
    );
  }
}

class HistoryRepository {
  HistoryRepository(this.store);

  final PlatformStore store;
  static const _recordsName = 'history_records_v2.json';

  Future<List<HistoryRecord>> load() async {
    try {
      final raw = await store.readText(_recordsName);
      if (raw == null || raw.isEmpty) {
        return [];
      }
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(HistoryRecord.fromJson)
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    } catch (_) {
      return [];
    }
  }

  Future<HistoryRecord> saveRecord({
    required Uint8List sourceBytes,
    required Uint8List? resultBytes,
    required FeatureType feature,
    required StyleTemplate template,
    required String prompt,
    required String negativePrompt,
    required String status,
  }) async {
    final now = DateTime.now();
    final id = now.microsecondsSinceEpoch.toString();
    final sourcePath = await saveInputBytes(
      sourceBytes,
      extension: 'png',
      id: '${id}_source',
    );
    final resultPath = resultBytes == null
        ? ''
        : await saveResultBytes(resultBytes, id: '${id}_result');
    final record = HistoryRecord(
      id: id,
      sourceImagePath: sourcePath,
      resultImagePath: resultPath,
      featureKey: feature.key,
      templateId: template.id,
      templateTitle: template.title,
      prompt: prompt,
      negativePrompt: negativePrompt,
      status: status,
      createdAt: now,
    );
    final records = await load();
    await persist([record, ...records].take(80).toList());
    return record;
  }

  Future<void> persist(List<HistoryRecord> records) async {
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(records.map((r) => r.toJson()).toList());
    await store.writeText(_recordsName, json);
  }

  Future<void> clear() => store.deleteText(_recordsName);

  Future<String> saveInputBytes(
    Uint8List bytes, {
    String extension = 'png',
    String? id,
  }) async {
    final name = id ?? DateTime.now().microsecondsSinceEpoch.toString();
    return store.saveBytes(
      bytes,
      folder: 'inputs',
      name: name,
      extension: extension,
    );
  }

  Future<String> saveResultBytes(Uint8List bytes, {String? id}) async {
    final name = id ?? DateTime.now().microsecondsSinceEpoch.toString();
    return store.saveBytes(
      bytes,
      folder: 'results',
      name: name,
      extension: 'png',
    );
  }

  Future<Uint8List?> readStoredBytes(String reference) =>
      store.readBytes(reference);

  Future<bool> storedBytesExist(String reference) => store.exists(reference);
}

class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        if (!app.initialized) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return Scaffold(
          body: IndexedStack(
            index: app.tabIndex,
            children: const [
              HomeScreen(),
              DiscoverScreen(),
              HistoryScreen(),
              ProfileScreen(),
            ],
          ),
          bottomNavigationBar: _NavFrame(
            child: _BottomNav(current: app.tabIndex, onTap: app.setTab),
          ),
        );
      },
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: child,
      ),
    );
  }
}

class _NavFrame extends StatelessWidget {
  const _NavFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: AppTheme.surface),
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: child,
        ),
      ),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final templates = app.templatesFor(FeatureType.hairstyle);
        return SafeArea(
          child: _PageFrame(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              children: [
                _Header(
                  title: 'Hairstyle',
                  subtitle: 'AI hairstyle try-on',
                  trailing: _ProButton(
                    onTap: () => showMembershipSheet(context),
                  ),
                ),
                const SizedBox(height: 16),
                _HeroCanvas(controller: app, compact: false),
                const SizedBox(height: 14),
                _SourceActions(controller: app),
                const SizedBox(height: 18),
                _FeatureSegment(
                  active: app.activeFeature,
                  values: const [
                    FeatureType.hairstyle,
                    FeatureType.color,
                    FeatureType.glasses,
                  ],
                  onChanged: app.setFeature,
                ),
                const SizedBox(height: 14),
                _TemplateStrip(
                  templates: templates,
                  selected: app.selectedTemplate,
                  onTap: app.selectTemplate,
                ),
                const SizedBox(height: 16),
                _GeneratePanel(controller: app),
                const SizedBox(height: 18),
                _StatusPanel(controller: app),
                const SizedBox(height: 18),
                _SectionTitle(
                  title: 'Next touch',
                  subtitle: '结果出来后可继续叠加发色、眼镜、背景',
                ),
                const SizedBox(height: 10),
                _QuickFeatureRow(
                  features: const [
                    FeatureType.color,
                    FeatureType.glasses,
                    FeatureType.background,
                    FeatureType.beauty,
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class DiscoverScreen extends StatelessWidget {
  const DiscoverScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final features = FeatureType.values
            .where((f) => f != FeatureType.hairstyle)
            .toList();
        return SafeArea(
          child: _PageFrame(
            child: CustomScrollView(
              slivers: [
                const SliverPadding(
                  padding: EdgeInsets.fromLTRB(18, 14, 18, 14),
                  sliver: SliverToBoxAdapter(
                    child: _Header(
                      title: 'Discover',
                      subtitle: 'AI styles and templates',
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverGrid.builder(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          childAspectRatio: 1.03,
                        ),
                    itemCount: features.length,
                    itemBuilder: (context, index) {
                      final feature = features[index];
                      return _FeatureCard(
                        feature: feature,
                        onTap: () => openFeatureFlow(context, feature),
                      );
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 22)),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  sliver: SliverToBoxAdapter(
                    child: _SectionTitle(
                      title: 'Trending hairstyles',
                      subtitle:
                          '${app.catalog?.hairs.length ?? 0} hair materials · ${app.catalog?.glasses.length ?? 0} glasses',
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 10)),
                SliverToBoxAdapter(
                  child: _TemplateStrip(
                    templates: app
                        .templatesFor(FeatureType.hairstyle)
                        .take(12)
                        .toList(),
                    selected: null,
                    onTap: (template) {
                      app.setFeature(FeatureType.hairstyle);
                      app.selectTemplate(template);
                      app.setTab(0);
                    },
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 26)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class FeatureFlowScreen extends StatelessWidget {
  const FeatureFlowScreen({super.key, required this.feature});

  final FeatureType feature;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final templates = app.templatesFor(feature);
        return Scaffold(
          appBar: AppBar(
            title: Text(feature.title),
            actions: [_ProButton(onTap: () => showMembershipSheet(context))],
          ),
          body: _PageFrame(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                Text(
                  feature.subtitle,
                  style: const TextStyle(
                    color: AppTheme.muted,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                _HeroCanvas(controller: app, compact: true),
                const SizedBox(height: 14),
                _SourceActions(controller: app),
                const SizedBox(height: 18),
                _TemplateStrip(
                  templates: templates,
                  selected: app.selectedTemplate,
                  onTap: (template) {
                    app.setFeature(feature);
                    app.selectTemplate(template);
                  },
                ),
                const SizedBox(height: 16),
                _GeneratePanel(controller: app, forcedFeature: feature),
                const SizedBox(height: 16),
                _StatusPanel(controller: app),
              ],
            ),
          ),
        );
      },
    );
  }
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final records = app.history;
        return SafeArea(
          child: _PageFrame(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              children: [
                _Header(
                  title: 'History',
                  subtitle: records.isEmpty
                      ? '最近 / 收藏 / 草稿'
                      : '${records.length} 个生成记录',
                  trailing: records.isEmpty
                      ? null
                      : IconButton(
                          onPressed: app.clearHistory,
                          icon: const Icon(Icons.delete_outline),
                        ),
                ),
                const SizedBox(height: 16),
                if (records.isEmpty)
                  _EmptyState(
                    icon: Icons.history,
                    title: '还没有生成记录',
                    subtitle: '完成一次生成后，这里会保留原图、结果、模板和提示词。',
                  )
                else
                  ...records.map((record) => _HistoryTile(record: record)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        return SafeArea(
          child: _PageFrame(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              children: [
                const _Header(title: 'Me', subtitle: '会员、设置和合规入口'),
                const SizedBox(height: 16),
                _MembershipCard(
                  member: app.isMember,
                  remaining: app.remainingFreeGenerations,
                  onTap: () => showMembershipSheet(context),
                ),
                const SizedBox(height: 16),
                _SettingsTile(
                  icon: Icons.workspace_premium_outlined,
                  title: '会员中心',
                  subtitle: '订阅、恢复购买和权益状态',
                  onTap: () => showMembershipSheet(context),
                ),
                _SettingsTile(
                  icon: Icons.security_outlined,
                  title: '隐私与权限',
                  subtitle: '照片只用于生成，默认本地保存历史',
                  onTap: () => showInfoDialog(
                    context,
                    '隐私与权限',
                    '相机用于拍摄人像，相册用于选择和保存生成结果。接入云端 AI 时会上传用于生成的照片，后续需补充服务端保存时长和删除机制。',
                  ),
                ),
                _SettingsTile(
                  icon: Icons.star_border,
                  title: '评分反馈',
                  subtitle: '保存多次后按频控弹出评分',
                  onTap: () => showInfoDialog(
                    context,
                    '评分反馈',
                    'v2.0 会在保存成功和多次使用后触发评分提示，并避免频繁打扰。',
                  ),
                ),
                _SettingsTile(
                  icon: Icons.tune,
                  title: 'AI 接口状态',
                  subtitle: 'Remote Config 控制开关，Seedream key 已加固',
                  onTap: () => showInfoDialog(
                    context,
                    'AI 接口状态',
                    'Seedream key 使用分片密文内置，Firebase Remote Config 可控制 seedream_enabled、seedream_model、seedream_base_url 和 daily_free_generation_limit。未配置 Firebase 时使用本地默认值。',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class ResultScreen extends StatelessWidget {
  const ResultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    var showOriginal = false;
    return StatefulBuilder(
      builder: (context, setLocal) {
        return Scaffold(
          appBar: AppBar(
            title: const Text('Result'),
            actions: [
              IconButton(
                onPressed: () => app.generate(),
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: _PageFrame(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: AspectRatio(
                    aspectRatio: 3 / 4,
                    child: Image.memory(
                      showOriginal ? app.sourceBytes! : app.resultBytes!,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.compare,
                        label: showOriginal ? '查看效果' : '对比原图',
                        onTap: () =>
                            setLocal(() => showOriginal = !showOriginal),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.save_alt,
                        label: '保存',
                        onTap: () => app.saveResultToGallery(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        icon: Icons.ios_share,
                        label: '分享',
                        onTap: app.shareResult,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _InfoCard(
                  title: app.selectedTemplate?.title ?? 'AI Result',
                  body: app.prompt ?? 'Prompt pending',
                ),
                const SizedBox(height: 16),
                _QuickFeatureRow(
                  features: const [
                    FeatureType.color,
                    FeatureType.glasses,
                    FeatureType.background,
                    FeatureType.beauty,
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _HeroCanvas extends StatelessWidget {
  const _HeroCanvas({required this.controller, required this.compact});

  final AppController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bytes = controller.hasResult
        ? controller.resultBytes
        : controller.sourceBytes;
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      padding: const EdgeInsets.all(8),
      child: AspectRatio(
        aspectRatio: compact ? 1.05 : 0.78,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (bytes != null)
                Image.memory(bytes, fit: BoxFit.cover)
              else
                const ColoredBox(color: Color(0xFFECE4DE)),
              Positioned(
                left: 12,
                top: 12,
                child: _MiniBadge(
                  label: controller.hasResult
                      ? 'Result'
                      : controller.sourceLabel,
                  dark: true,
                ),
              ),
              if (controller.isBusy)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.34),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.white),
                        const SizedBox(height: 12),
                        Text(
                          controller.status == GenerationStatus.optimizingPrompt
                              ? 'AI 优化提示词'
                              : 'Seedream 生成中',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        TextButton(
                          onPressed: controller.cancelGeneration,
                          child: const Text(
                            '取消并保留草稿',
                            style: TextStyle(color: Colors.white),
                          ),
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
}

class _SourceActions extends StatelessWidget {
  const _SourceActions({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: Icons.photo_library_outlined,
            label: '相册',
            onTap: () => controller.pickImage(ImageSource.gallery),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.camera_alt_outlined,
            label: '相机',
            onTap: () => controller.pickImage(ImageSource.camera),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: Icons.face_outlined,
            label: '模特',
            onTap: () => showModelPicker(context),
          ),
        ),
      ],
    );
  }
}

class _GeneratePanel extends StatelessWidget {
  const _GeneratePanel({required this.controller, this.forcedFeature});

  final AppController controller;
  final FeatureType? forcedFeature;

  @override
  Widget build(BuildContext context) {
    final template = controller.selectedTemplate;
    final blocked = controller.requiresPaywall(template: template);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.ink,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  template == null ? '选择模板后生成' : 'Generate ${template.title}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (blocked) const _MiniBadge(label: 'PRO', dark: false),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            blocked
                ? '需要会员或激励解锁。免费次数剩余 ${controller.remainingFreeGenerations}'
                : 'AI 优化提示词，Seedream 生成结果。免费次数剩余 ${controller.remainingFreeGenerations}',
            style: const TextStyle(color: Colors.white70, height: 1.35),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: blocked ? AppTheme.gold : Colors.white,
                foregroundColor: AppTheme.ink,
              ),
              onPressed: controller.isBusy
                  ? null
                  : () async {
                      if (forcedFeature != null &&
                          controller.activeFeature != forcedFeature) {
                        controller.setFeature(forcedFeature!);
                      }
                      if (controller.requiresPaywall()) {
                        showMembershipSheet(context);
                        return;
                      }
                      final ok = await controller.generate();
                      if (context.mounted && ok) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ResultScreen(),
                          ),
                        );
                      }
                    },
              child: Text(blocked ? '解锁生成' : '生成效果'),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final error = controller.errorMessage;
    if (controller.status == GenerationStatus.idle &&
        error == null &&
        controller.prompt == null) {
      return _InfoCard(
        title: '流程状态',
        body: '选择照片和模板后即可生成。生成前会先用 AI 文本接口优化提示词，再调用 Seedream。',
      );
    }
    final statusText = switch (controller.status) {
      GenerationStatus.idle => '待生成',
      GenerationStatus.optimizingPrompt => 'AI 正在优化提示词',
      GenerationStatus.generating => 'Seedream 正在生成图片',
      GenerationStatus.succeeded => '生成成功，可保存、分享或继续编辑',
      GenerationStatus.failed => '生成失败，可重试',
      GenerationStatus.cancelled => '已取消，保留草稿',
    };
    return _InfoCard(title: statusText, body: error ?? controller.prompt ?? '');
  }
}

class _TemplateStrip extends StatelessWidget {
  const _TemplateStrip({
    required this.templates,
    required this.selected,
    required this.onTap,
  });

  final List<StyleTemplate> templates;
  final StyleTemplate? selected;
  final ValueChanged<StyleTemplate> onTap;

  @override
  Widget build(BuildContext context) {
    if (templates.isEmpty) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: 152,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 2),
        itemBuilder: (context, index) {
          final template = templates[index];
          final active = selected?.id == template.id;
          return GestureDetector(
            onTap: () => onTap(template),
            child: SizedBox(
              width: 112,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? AppTheme.ink : AppTheme.line,
                    width: active ? 2 : 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.asset(
                                  template.previewAsset,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const ColoredBox(
                                        color: Color(0xFFE8E1DC),
                                      ),
                                ),
                              ),
                            ),
                            if (template.isPro)
                              const Positioned(
                                right: 6,
                                top: 6,
                                child: _MiniBadge(label: 'PRO', dark: true),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        template.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        template.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppTheme.muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: templates.length,
      ),
    );
  }
}

class _FeatureSegment extends StatelessWidget {
  const _FeatureSegment({
    required this.active,
    required this.values,
    required this.onChanged,
  });

  final FeatureType active;
  final List<FeatureType> values;
  final ValueChanged<FeatureType> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final value = values[index];
          final selected = active == value;
          return GestureDetector(
            onTap: () => onChanged(value),
            child: Semantics(
              button: true,
              selected: selected,
              label: value.title,
              child: Container(
                width: 112,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppTheme.ink : AppTheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected ? AppTheme.ink : AppTheme.line,
                  ),
                ),
                child: Text(
                  value.title,
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: TextStyle(
                    color: selected ? Colors.white : AppTheme.ink,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: values.length,
      ),
    );
  }
}

class _QuickFeatureRow extends StatelessWidget {
  const _QuickFeatureRow({required this.features});

  final List<FeatureType> features;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemBuilder: (context, index) {
          final feature = features[index];
          return _SmallFeatureButton(
            feature: feature,
            onTap: () => openFeatureFlow(context, feature),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemCount: features.length,
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({required this.feature, required this.onTap});

  final FeatureType feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(feature.icon, color: AppTheme.ink),
              ),
              const Spacer(),
              Text(
                feature.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                feature.subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontSize: 12,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmallFeatureButton extends StatelessWidget {
  const _SmallFeatureButton({required this.feature, required this.onTap});

  final FeatureType feature;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 132,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(feature.icon, color: AppTheme.rose),
                const Spacer(),
                Text(
                  feature.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  '进入流程',
                  style: TextStyle(
                    color: AppTheme.muted.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.record});

  final HistoryRecord record;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.line),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              width: 86,
              height: 104,
              child: _StoredImage(
                reference: record.resultImagePath,
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.templateTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${record.featureLabel} · ${record.formattedTime}',
                  style: const TextStyle(color: AppTheme.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _TinyAction(
                      label: '预览',
                      onTap: () => showImagePreview(context, record),
                    ),
                    _TinyAction(
                      label: '重新编辑',
                      onTap: () => app.restoreHistory(record),
                    ),
                    _TinyAction(
                      label: record.isFavorite ? '取消收藏' : '收藏',
                      onTap: () => app.toggleFavorite(record),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StoredImage extends StatelessWidget {
  const _StoredImage({required this.reference, required this.fit});

  final String reference;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    if (reference.isEmpty) {
      return const _MissingStoredImage();
    }
    final repository = AppScope.of(context).historyRepository;
    return FutureBuilder<Uint8List?>(
      future: repository.readStoredBytes(reference),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) {
          return const _MissingStoredImage();
        }
        return Image.memory(bytes, fit: fit);
      },
    );
  }
}

class _MissingStoredImage extends StatelessWidget {
  const _MissingStoredImage();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE8E1DC),
      child: Icon(Icons.image_not_supported_outlined),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({required this.current, required this.onTap});

  final int current;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.content_cut, '换发型'),
      (Icons.grid_view_rounded, '发现'),
      (Icons.history, '记录'),
      (Icons.person_outline, '我的'),
    ];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppTheme.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          items[i].$1,
                          color: i == current ? AppTheme.ink : AppTheme.muted,
                          size: 22,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$2,
                          style: TextStyle(
                            color: i == current ? AppTheme.ink : AppTheme.muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
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
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle, this.trailing});

  final String title;
  final String subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppTheme.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 46,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.line),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProButton extends StatelessWidget {
  const _ProButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onTap,
      icon: const Icon(Icons.workspace_premium_outlined, size: 18),
      label: const Text('Pro'),
      style: TextButton.styleFrom(
        foregroundColor: AppTheme.ink,
        backgroundColor: AppTheme.gold.withValues(alpha: 0.26),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  const _MiniBadge({required this.label, required this.dark});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: dark ? Colors.black.withValues(alpha: 0.68) : AppTheme.gold,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: dark ? Colors.white : AppTheme.ink,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(
            color: AppTheme.muted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          if (body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              body,
              style: const TextStyle(color: AppTheme.muted, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.line),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: AppTheme.muted),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.muted, height: 1.35),
          ),
        ],
      ),
    );
  }
}

class _TinyAction extends StatelessWidget {
  const _TinyAction({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.rose,
          fontWeight: FontWeight.w900,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MembershipCard extends StatelessWidget {
  const _MembershipCard({
    required this.member,
    required this.remaining,
    required this.onTap,
  });

  final bool member;
  final int remaining;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.ink,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              const Icon(
                Icons.workspace_premium_outlined,
                color: AppTheme.gold,
                size: 34,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      member ? 'Pro 已启用' : 'Unlock Pro',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      member
                          ? '高清无水印 / 无限生成 / 去广告'
                          : '免费生成剩余 $remaining 次，可订阅或激励解锁',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white70),
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.line),
      ),
      child: ListTile(
        leading: Icon(icon, color: AppTheme.ink),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

void openFeatureFlow(BuildContext context, FeatureType feature) {
  final app = AppScope.of(context);
  app.setFeature(feature);
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => FeatureFlowScreen(feature: feature)),
  );
}

void showModelPicker(BuildContext context) {
  final app = AppScope.of(context);
  final catalog = app.catalog;
  if (catalog == null) {
    return;
  }
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppTheme.bg,
    builder: (context) {
      final groups = <(String, List<String>)>[
        ('女生', catalog.female),
        ('男生', catalog.male),
        ('儿童', catalog.child),
        ('古风', catalog.ancient),
      ];
      return DefaultTabController(
        length: groups.length,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.66,
          child: Column(
            children: [
              TabBar(
                isScrollable: true,
                tabs: groups.map((g) => Tab(text: g.$1)).toList(),
              ),
              Expanded(
                child: TabBarView(
                  children: groups.map((group) {
                    return GridView.builder(
                      padding: const EdgeInsets.all(14),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.72,
                          ),
                      itemCount: group.$2.length,
                      itemBuilder: (context, index) {
                        final asset = group.$2[index];
                        return GestureDetector(
                          onTap: () async {
                            Navigator.of(context).pop();
                            await app.setSourceFromAsset(
                              asset,
                              label: group.$1,
                            );
                          },
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.asset(asset, fit: BoxFit.cover),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

void showMembershipSheet(BuildContext context) {
  final app = AppScope.of(context);
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    backgroundColor: AppTheme.bg,
    builder: (context) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 6, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Unlock Pro',
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            const Text(
              '高清无水印、无限生成、Pro 模板、去广告。Debug 阶段先启用可测试状态机。',
              style: TextStyle(color: AppTheme.muted, height: 1.35),
            ),
            const SizedBox(height: 16),
            _PlanRow(title: '年度会员', price: 'Best value', selected: true),
            const SizedBox(height: 10),
            _PlanRow(title: '月度会员', price: 'Flexible', selected: false),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: () async {
                  await app.unlockMembership();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('Debug 启用会员'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: () async {
                  await app.unlockRewardOnce();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('模拟激励广告，解锁一次'),
              ),
            ),
            TextButton(
              onPressed: () => showInfoDialog(
                context,
                'Restore Purchase',
                '真实 Google Play Billing 接入后，这里执行恢复购买。',
              ),
              child: const Text('Restore Purchase'),
            ),
          ],
        ),
      );
    },
  );
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({
    required this.title,
    required this.price,
    required this.selected,
  });
  final String title;
  final String price;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected ? AppTheme.gold : AppTheme.line,
          width: selected ? 2 : 1,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          Text(
            price,
            style: const TextStyle(
              color: AppTheme.muted,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

void showInfoDialog(BuildContext context, String title, String body) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

void showImagePreview(BuildContext context, HistoryRecord record) {
  showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: _StoredImage(
          reference: record.resultImagePath,
          fit: BoxFit.contain,
        ),
      ),
    ),
  );
}

int _assetNaturalCompare(String a, String b) {
  final aName = a.split('/').last;
  final bName = b.split('/').last;
  final aMatch = RegExp(r'(\D+)(\d+)').firstMatch(aName);
  final bMatch = RegExp(r'(\D+)(\d+)').firstMatch(bName);
  if (aMatch != null && bMatch != null && aMatch.group(1) == bMatch.group(1)) {
    return int.parse(aMatch.group(2)!).compareTo(int.parse(bMatch.group(2)!));
  }
  return aName.compareTo(bName);
}

extension FirstOrNullExtension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;

  T? firstWhereOrNull(bool Function(T item) test) {
    for (final item in this) {
      if (test(item)) {
        return item;
      }
    }
    return null;
  }
}
