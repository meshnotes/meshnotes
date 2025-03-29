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
  static const String blockTypeQuote = 'quote'; // quote block, unimplemented
  static const String blockTypeCode = 'code'; // code block, unimplemented

  static const String blockListTypeNone = 'none';
  static const String blockListTypeBulleted = 'bulleted_list';
  static const String blockListTypeChecked = 'checked_list_n';
  static const String blockListTypeCheckedConfirm = 'checked_list_y';

  static const int blockLevelDefault = 0;

  static const double tabWidth = 25;
  static const double bulletedSize = 6;

  static const widthThreshold = 600;

  static const int timeoutOfInputIdle = 5;
  static const int timeoutOfEditIdle = 15;
  static const int timeoutOfPeriodSync = 30;
  static const int timeoutOfCheckConsistency = 5 * 60 * 1000; // 5 minutes to check consistency

  static const String welcomeRouteName = '/';
  static const String navigatorRouteName = '/navigator';
  static const String documentRouteName = '/document';
  static const String largeScreenViewName = '/large';

  // Flags in db
  static const String flagNameCurrentVersion = 'current_version';
  static const String flagNameCurrentVersionTimestamp = 'current_version_timestamp';
  static const int createdFromLocal = 0;
  static const int createdFromPeer = 1;
  // Sync status in version table
  static const int syncStatusNew = 0; // not synced
  static const int syncStatusSyncing = 1; // syncing
  static const int syncStatusSynced = 2; // synced

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
  static const double styleSettingItemFontSize = 16.0;

  // Changeable setting related
  // static const String settingKeyServerIp = 'server_ip';
  // static const String settingCommentServerIp = 'Server IP(e.g. 192.168.1.10)';
  // static const String settingDefaultServerIp = '';
  // static const String settingKeyServerPort = 'server_port';
  // static const String settingCommentServerPort = 'Server Port(e.g. 12345)';
  // static const String settingDefaultServerPort = '0';
  static const String settingKeyServerList = 'server_list';
  static const String settingNameServerList = 'Server list';
  static const String settingCommentServerList = 'Separated by commas(e.g. my.com:12345,192.168.1.100:34567)';
  static const String settingDefaultServerList = '';
  static const String settingKeyLocalPort = 'local_port';
  static const String settingNameLocalPort = 'Local Port';
  static const String settingCommentLocalPort = 'Local UDP Port(0 for random, $settingDefaultLocalPort is default)';
  static const String settingDefaultLocalPort = '17974';
  static const String settingKeyUserInfo = 'user_info';
  static const String settingNameUserInfo = 'User private key';
  static const String settingCommentUserInfo = 'User name and private key information(formatted in base64)';
  static const String settingKeyPluginPrefix = 'plugin';
  static const String settingKeyShowDebugMenu = 'show_debug_menu';
  static const String settingNameShowDebugMenu = 'Debug menu';
  static const String settingCommentShowDebugMenu = 'Show debug functions in the menu';
  static const String settingDefaultShowDebugMenu = 'false';

  static const String settingKeyAllowSendingNotesToPlugins = 'allow_sending_notes_to_plugins';
  static const String settingNameAllowSendingNotesToPlugins = 'Allow sending notes to plugins';
  static const String settingCommentAllowSendingNotesToPlugins = 'To make plugins(like AI assistant) have knowledge of your notes(except for the private notes)';
  static const String settingDefaultAllowSendingNotesToPlugins = 'false';

  static const String userNameAndKeyOfGuest = 'guest';

  static const String resourceKeyVersionTree = 'version_tree';
}

class UiConstants {
  static const double menuItemIconSize = 16;
  static const double menuItemTextSize = 14;
  static const double menuItemPadding = 8;
  static const double menuItemBorderRadius = 8;
  static const double menuItemHeight = 36;
}
