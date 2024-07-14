class Constants {
  // Key for some maps
  static const String keyTitleId = 'title';
  static const String keyRootBlockId = 'root';

  static const String newDocumentTitle = 'New document';

  static const String blockTypeTitleTag = 'title';
  static const String blockTypeTextTag = 'text';
  static const String blockTypeHeadlinePrefix = 'headline';
  static const String blockTypeHeadline1 = blockTypeHeadlinePrefix + '1';
  static const String blockTypeHeadline2 = blockTypeHeadlinePrefix + '2';
  static const String blockTypeHeadline3 = blockTypeHeadlinePrefix + '3';
  static const String blockTypeQuote = 'quote'; // 引用类型，未实现
  static const String blockTypeCode = 'code'; // 代码块类型，未实现

  static const String blockListTypeNone = 'none';
  static const String blockListTypeBulleted = 'bulleted_list';
  static const String blockListTypeChecked = 'checked_list_n';
  static const String blockListTypeCheckedConfirm = 'checked_list_y';

  static const int blockLevelDefault = 0;

  static const double tabWidth = 25;
  static const double bulletedSize = 6;

  static const widthThreshold = 600;

  static const int timeoutOfInputIdle = 5;
  static const int timeoutOfSyncIdle = 15;

  static const String welcomeRouteName = '/';
  static const String navigatorRouteName = '/navigator';
  static const String documentRouteName = '/document';
  static const String largeScreenViewName = '/large';

  // Flags in db
  static const String flagNameCurrentVersion = 'current_version';
  static const String flagNameCurrentVersionTimestamp = 'current_version_timestamp';
  static const int createdFromLocal = 0;
  static const int createdFromPeer = 1;
  static const int statusAvailable = 0;
  static const int statusUnavailable = -1;

  // InspiredCard related
  static const int cardMaximumWidth = 800;
  static const int cardMaximumHeight = 600;
  static const double cardMinimalPaddingHorizontal = 20.0;
  static const double cardMinimalPaddingVertical = 10.0;
  static const double cardViewDragThreshold = 150;
  static const int cardViewScrollAnimationDuration = 300;
  static const int cardViewDesktopInnerPadding = 64;

  // SettingView related
  static const int settingViewPhonePadding = 8;
  static const int settingViewDesktopPadding = 40;

  // Global style
  static const double styleTitleFontSize = 18.0;

  // Changeable setting related
  // static const String settingKeyServerIp = 'server_ip';
  // static const String settingCommentServerIp = 'Server IP(e.g. 192.168.1.10)';
  // static const String settingDefaultServerIp = '';
  // static const String settingKeyServerPort = 'server_port';
  // static const String settingCommentServerPort = 'Server Port(e.g. 12345)';
  // static const String settingDefaultServerPort = '0';
  static const String settingKeyServerList = 'server_list';
  static const String settingNameServerList = 'Server list';
  static const String settingCommentServerList = 'Server List, separated by commas(e.g. my.com:12345,192.168.1.100:34567)';
  static const String settingDefaultServerList = '';
  static const String settingKeyLocalPort = 'local_port';
  static const String settingNameLocalPort = 'Local Port';
  static const String settingCommentLocalPort = 'Local Port(0 for random)';
  static const String settingDefaultLocalPort = '17974';
  static const String settingKeyTest = 'just_for_test';
  static const String settingNameTest = 'Just for test';
  static const String settingCommentTest = 'Just for test';
  static const String settingKeyUserInfo = 'user_info';
  static const String settingNameUserInfo = 'User private key';
  static const String settingCommentUserInfo = 'User name and private key information(formatted in base64)';
  static const String settingKeyPluginPrefix = 'plugin';

  static const String userNameAndKeyOfGuest = 'guest';

  static const String resourceKeyVersionTree = 'version_tree';
}