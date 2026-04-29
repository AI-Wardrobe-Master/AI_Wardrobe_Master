import 'package:flutter/material.dart';

/// Centralized app strings for en / zh. Use via [AppStringsProvider.of(context)].
class AppStrings {
  const AppStrings._(this._map);

  final Map<String, String> _map;

  String _t(String key) => _map[key] ?? key;

  static const AppStrings en = AppStrings._(_en);
  static const AppStrings zh = AppStrings._(_zh);

  static AppStrings of(Locale locale) {
    if (locale.languageCode == 'zh') return zh;
    return en;
  }

  // App & splash
  String get appTitle => _t('appTitle');
  String get splashTitle => _t('splashTitle');

  // Login
  String get loginSubtitle => _t('loginSubtitle');
  String get loginDemoHint => _t('loginDemoHint');
  String get continueButton => _t('continueButton');
  String get skipForNow => _t('skipForNow');

  // Add sheet
  String get addNew => _t('addNew');
  String get addNewSubtitle => _t('addNewSubtitle');
  String get addClothes => _t('addClothes');
  String get addClothesSubtitle => _t('addClothesSubtitle');
  String get openOutfitCanvas => _t('openOutfitCanvas');
  String get openOutfitCanvasSubtitle => _t('openOutfitCanvasSubtitle');

  // Nav
  String get navWardrobe => _t('navWardrobe');
  String get navDiscover => _t('navDiscover');
  String get navAdd => _t('navAdd');
  String get navVisualize => _t('navVisualize');
  String get navProfile => _t('navProfile');

  // Wardrobe
  String get wardrobeTitle => _t('wardrobeTitle');
  String get wardrobeSubtitle => _t('wardrobeSubtitle');
  String get searchWardrobe => _t('searchWardrobe');
  String get noClothesYet => _t('noClothesYet');
  String get useAddToStart => _t('useAddToStart');
  String get categoryAll => _t('categoryAll');
  String get categoryTops => _t('categoryTops');
  String get categoryBottoms => _t('categoryBottoms');
  String get categoryOuterwear => _t('categoryOuterwear');
  String get categoryAccessories => _t('categoryAccessories');
  String get manageWardrobes => _t('manageWardrobes');
  String get createWardrobe => _t('createWardrobe');
  String get renameWardrobe => _t('renameWardrobe');
  String get deleteWardrobe => _t('deleteWardrobe');
  String get wardrobeName => _t('wardrobeName');
  String get virtualWardrobeLabel => _t('virtualWardrobeLabel');
  String get regularWardrobeLabel => _t('regularWardrobeLabel');
  String get removeFromWardrobe => _t('removeFromWardrobe');
  String get noWardrobesYet => _t('noWardrobesYet');
  String get createFirstWardrobe => _t('createFirstWardrobe');
  String get deleteWardrobeConfirm => _t('deleteWardrobeConfirm');
  String get cancel => _t('cancel');
  String get save => _t('save');
  String get create => _t('create');
  String get addToCurrentWardrobe => _t('addToCurrentWardrobe');
  String get addedToWardrobe => _t('addedToWardrobe');
  String get createWardrobeFirst => _t('createWardrobeFirst');
  String get retry => _t('retry');
  String get wardrobeNameRequired => _t('wardrobeNameRequired');
  String get noMatchingClothes => _t('noMatchingClothes');
  String get clearSearchFilters => _t('clearSearchFilters');
  String deleteWardrobeConfirmNamed(String name, int count) => _t(
    'deleteWardrobeConfirmNamed',
  ).replaceAll('{name}', name).replaceAll('{count}', count.toString());

  // Discover
  String get discoverTitle => _t('discoverTitle');
  String get discoverSubtitle => _t('discoverSubtitle');
  String get noCreatorPacksYet => _t('noCreatorPacksYet');
  String get onceCreatorsShare => _t('onceCreatorsShare');

  // Profile
  String get profileTitle => _t('profileTitle');
  String get profileSubtitle => _t('profileSubtitle');
  String get yourName => _t('yourName');
  String get tapToConnectAccounts => _t('tapToConnectAccounts');
  String get statClothes => _t('statClothes');
  String get statOutfits => _t('statOutfits');
  String get statPacks => _t('statPacks');
  String get virtualWardrobes => _t('virtualWardrobes');
  String get keepImportedSeparate => _t('keepImportedSeparate');
  String get importedLooks => _t('importedLooks');
  String get settings => _t('settings');
  String get language => _t('language');
  String get darkMode => _t('darkMode');
  String get on => _t('on');
  String get off => _t('off');
  String get languageEnglish => _t('languageEnglish');
  String get languageZh => _t('languageZh');

  // Outfit canvas
  String get visualizeTitle => _t('visualizeTitle');
  String get tapMannequinHint => _t('tapMannequinHint');
  String get clear => _t('clear');
  String get saveLook => _t('saveLook');
  String get generatePreview => _t('generatePreview');
  String selectItem(String slot) => _t('selectItem').replaceAll('{slot}', slot);
  String get selectItemHint => _t('selectItemHint');
  String get createCardPack => _t('createCardPack');
  String get cardPackName => _t('cardPackName');
  String get cardPackDescription => _t('cardPackDescription');
  String get selectItems => _t('selectItems');
  String get addCoverImage => _t('addCoverImage');
  String get publish => _t('publish');
  String get saveAsDraft => _t('saveAsDraft');

  static const Map<String, String> _en = {
    'appTitle': 'AI Wardrobe Master',
    'splashTitle': 'AI Wardrobe Master',
    'loginSubtitle':
        'Sign in to keep your clothes and outfits in sync across devices.',
    'loginDemoHint':
        'No account setup required for the demo.\nJust continue to your wardrobe.',
    'continueButton': 'Continue',
    'skipForNow': 'Skip for now',
    'addNew': 'Add new',
    'addNewSubtitle': 'Quickly add clothes or start a new outfit.',
    'addClothes': 'Add clothes',
    'addClothesSubtitle': 'Capture or pick photos to add items.',
    'openOutfitCanvas': 'Open outfit canvas',
    'openOutfitCanvasSubtitle': 'Play with pieces on a 2.5D canvas.',
    'navWardrobe': 'Wardrobe',
    'navDiscover': 'Discover',
    'navAdd': 'Add',
    'navVisualize': 'Visualize',
    'navProfile': 'Profile',
    'wardrobeTitle': 'Your wardrobe',
    'wardrobeSubtitle': 'A calm, structured overview of your clothes.',
    'searchWardrobe': 'Search in your wardrobe',
    'noClothesYet': 'No clothes yet.',
    'useAddToStart': 'Use Add to start building your wardrobe.',
    'categoryAll': 'All',
    'categoryTops': 'Tops',
    'categoryBottoms': 'Bottoms',
    'categoryOuterwear': 'Outerwear',
    'categoryAccessories': 'Accessories',
    'manageWardrobes': 'Manage wardrobes',
    'createWardrobe': 'Create wardrobe',
    'renameWardrobe': 'Rename',
    'deleteWardrobe': 'Delete wardrobe',
    'wardrobeName': 'Wardrobe name',
    'virtualWardrobeLabel': 'Virtual',
    'regularWardrobeLabel': 'Regular',
    'removeFromWardrobe': 'Remove from wardrobe',
    'noWardrobesYet': 'No wardrobes yet.',
    'createFirstWardrobe': 'Create your first wardrobe to get started.',
    'deleteWardrobeConfirm':
        'Delete this wardrobe? Items inside will not be deleted.',
    'cancel': 'Cancel',
    'save': 'Save',
    'create': 'Create',
    'addToCurrentWardrobe': 'Add to current wardrobe',
    'addedToWardrobe': 'Added to wardrobe',
    'createWardrobeFirst': 'Create a wardrobe first',
    'retry': 'Retry',
    'wardrobeNameRequired': 'Please enter a wardrobe name.',
    'noMatchingClothes': 'No matching clothes.',
    'clearSearchFilters': 'Clear search and filters',
    'deleteWardrobeConfirmNamed':
        'Delete "{name}"? {count} clothes will stay in your account and only the wardrobe grouping will be removed.',
    'discoverTitle': 'Discover',
    'discoverSubtitle': 'Browse creator packs and styling ideas.',
    'noCreatorPacksYet': 'No creator packs yet.',
    'onceCreatorsShare': 'Once creators share outfits, they will appear here.',
    'profileTitle': 'Profile',
    'profileSubtitle': 'Your digital wardrobe identity.',
    'yourName': 'Your name',
    'tapToConnectAccounts': 'Tap to connect accounts later',
    'statClothes': 'Clothes',
    'statOutfits': 'Outfits',
    'statPacks': 'Packs',
    'virtualWardrobes': 'Virtual wardrobes',
    'keepImportedSeparate':
        'Keep imported looks separate from your physical wardrobe.',
    'importedLooks': 'Imported looks',
    'settings': 'Settings',
    'language': 'Language',
    'darkMode': 'Dark mode',
    'on': 'On',
    'off': 'Off',
    'languageEnglish': 'English',
    'languageZh': '中文',
    'visualizeTitle': 'Visualize',
    'tapMannequinHint': 'Tap on the mannequin to choose pieces.',
    'clear': 'Clear',
    'saveLook': 'Save look',
    'generatePreview': 'Generate Preview',
    'selectItem': 'Select {slot} item',
    'selectItemHint':
        'Here we will show hats, tops, pants, shoes, etc. connected to your wardrobe.',
    'createCardPack': 'Create Card Pack',
    'cardPackName': 'Card Pack Name',
    'cardPackDescription': 'Card Pack Description',
    'selectItems': 'Select Items',
    'addCoverImage': 'Add Cover Image',
    'publish': 'Publish',
    'saveAsDraft': 'Save as Draft',
  };

  static const Map<String, String> _zh = {
    'appTitle': 'AI 智能衣柜',
    'splashTitle': 'AI 智能衣柜',
    'loginSubtitle': '登录后可在多设备间同步你的衣物与搭配。',
    'loginDemoHint': '演示无需注册账号，直接进入衣柜即可。',
    'continueButton': '继续',
    'skipForNow': '暂不登录',
    'addNew': '添加',
    'addNewSubtitle': '快速添加衣物或创建新搭配。',
    'addClothes': '添加衣物',
    'addClothesSubtitle': '拍照或从相册选择以添加。',
    'openOutfitCanvas': '打开搭配画布',
    'openOutfitCanvasSubtitle': '在 2.5D 画布上搭配单品。',
    'navWardrobe': '衣柜',
    'navDiscover': '发现',
    'navAdd': '添加',
    'navVisualize': '搭配',
    'navProfile': '我的',
    'wardrobeTitle': '我的衣柜',
    'wardrobeSubtitle': '一目了然的衣物总览。',
    'searchWardrobe': '在衣柜中搜索',
    'noClothesYet': '还没有衣物。',
    'useAddToStart': '点击「添加」开始整理衣柜。',
    'categoryAll': '全部',
    'categoryTops': '上装',
    'categoryBottoms': '下装',
    'categoryOuterwear': '外套',
    'categoryAccessories': '配饰',
    'manageWardrobes': '管理衣柜',
    'createWardrobe': '新建衣柜',
    'renameWardrobe': '重命名',
    'deleteWardrobe': '删除衣柜',
    'wardrobeName': '衣柜名称',
    'virtualWardrobeLabel': '虚拟',
    'regularWardrobeLabel': '常规',
    'removeFromWardrobe': '从衣柜移除',
    'noWardrobesYet': '还没有衣柜。',
    'createFirstWardrobe': '创建第一个衣柜开始使用。',
    'deleteWardrobeConfirm': '确定删除该衣柜？其中的衣物不会被删除。',
    'cancel': '取消',
    'save': '保存',
    'create': '创建',
    'addToCurrentWardrobe': '加入当前衣柜',
    'addedToWardrobe': '已加入衣柜',
    'createWardrobeFirst': '请先创建一个衣柜',
    'retry': '重试',
    'wardrobeNameRequired': '请输入衣柜名称。',
    'noMatchingClothes': '没有匹配的衣物。',
    'clearSearchFilters': '清除搜索和筛选',
    'deleteWardrobeConfirmNamed':
        '确定删除「{name}」？其中 {count} 件衣物仍会保留在账号中，只会移除这个衣柜分组。',
    'discoverTitle': '发现',
    'discoverSubtitle': '浏览创作者搭配包与穿搭灵感。',
    'noCreatorPacksYet': '暂无创作者搭配包。',
    'onceCreatorsShare': '创作者分享的搭配会出现在这里。',
    'profileTitle': '我的',
    'profileSubtitle': '你的数字衣柜身份。',
    'yourName': '你的名字',
    'tapToConnectAccounts': '点击后可绑定账号',
    'statClothes': '衣物',
    'statOutfits': '搭配',
    'statPacks': '搭配包',
    'virtualWardrobes': '虚拟衣柜',
    'keepImportedSeparate': '将导入的搭配与实体衣柜分开管理。',
    'importedLooks': '已导入搭配',
    'settings': '设置',
    'language': '语言',
    'darkMode': '深色模式',
    'on': '开启',
    'off': '关闭',
    'languageEnglish': 'English',
    'languageZh': '中文',
    'visualizeTitle': '搭配',
    'tapMannequinHint': '点击人台选择单品。',
    'clear': '清空',
    'saveLook': '保存搭配',
    'generatePreview': '生成预览',
    'selectItem': '选择{slot}',
    'selectItemHint': '此处将展示与衣柜关联的帽子、上装、裤装、鞋等。',
    'createCardPack': '创建搭配包',
    'cardPackName': '搭配包名称',
    'cardPackDescription': '搭配包描述',
    'selectItems': '选择衣物',
    'addCoverImage': '添加封面图',
    'publish': '发布',
    'saveAsDraft': '保存为草稿',
  };
}
