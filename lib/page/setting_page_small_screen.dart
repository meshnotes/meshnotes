import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/setting/setting.dart';
import 'widget_templates.dart';

class SettingPageSmallScreen extends StatefulWidget {
  final List<SettingGroup> groups;

  const SettingPageSmallScreen({
    super.key,
    required this.groups,
  });

  static void route(BuildContext context) {
    Navigator.push(context, CupertinoPageRoute(
      builder: (context) {
        return SettingPageSmallScreen(groups: Controller().setting.getSettingsByGroup());
      },
      fullscreenDialog: true,
    ));
  }

  @override
  State<StatefulWidget> createState() => _SettingPageSmallScreenState();
}

const _verticalPadding = 16.0;
const _horizonPadding = 4.0;
class _SettingPageSmallScreenState extends State<SettingPageSmallScreen> {
  final Map<String, String> newValue = {};
  final Map<String, TextEditingController> _controllers = {};
  final Set<SettingData> changedSettings = {};
  bool everChanged = false;
  static const _settingBodyFlexValue = 7;

  @override
  void initState() {
    super.initState();
    for(var group in widget.groups) {
      for(var item in group.settings) {
        newValue[item.name] = item.value?? '';
        _controllers[item.name] = TextEditingController(text: item.value);
      }
    }
    everChanged = false;
    CallbackRegistry.hideKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    double padding = Constants.settingViewPhonePadding.toDouble();
    var settingBody = _buildSettingList(context);
    var bottomButtons = _buildBottomButtons(context);
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.fromLTRB(0, padding, 0, padding),
              child: settingBody,
            ),
          ),
          bottomButtons,
          // const Padding(padding: EdgeInsets.fromLTRB(0, 0, 0, 10),),
        ],
      ),
    );
  }
  Widget _buildBottomButtons(BuildContext context) {
    var row = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        WidgetTemplate.buildInsignificantButton(Icons.arrow_back, 'Exit', () { _exitWithoutSaving(); }, alignment: MainAxisAlignment.end),
      ],
    );
    return row;
  }
  Widget _buildSettingList(BuildContext context) {
    var list = ListView.separated(
      itemCount: widget.groups.length + 1,
      shrinkWrap: true,
      itemBuilder: (context, index) {
        if(index == 0) { // A padding before the first item
          return Container(
            alignment: Alignment.center,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(_horizonPadding, _verticalPadding, _horizonPadding, _verticalPadding),
            child: const Text('Settings', style: TextStyle(fontSize: Constants.styleSettingItemFontSize, fontWeight: FontWeight.bold),),
          );
        }
        index -= 1;
        var groupWidget = _buildSettingGroupWidget(widget.groups[index]);
        return groupWidget;
      },
      separatorBuilder: (BuildContext context, int index) {
        return Divider(height: 1.0, color: Colors.grey[100],);
      },
    );
    return list;
  }

  Widget _buildSettingGroupWidget(SettingGroup group) {
    final groupName = group.name;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if(groupName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(_horizonPadding, _verticalPadding, _horizonPadding, _verticalPadding),
              child: Text(
                groupName,
                style: const TextStyle(
                  fontSize: Constants.styleSettingItemFontSize,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            color: Colors.white,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: group.settings.length,
              separatorBuilder: (context, index) => Divider(
                height: 1,
                indent: _horizonPadding,
                endIndent: _horizonPadding,
                color: Colors.grey[200],
              ),
              itemBuilder: (context, index) {
                var settingItem = group.settings[index];
                if(!settingItem.needDisplay) return Container();
                late Widget settingWidget;
                if(settingItem.type == SettingType.bool) {
                  settingWidget = _buildSwitchSetting(settingItem);
                } else {
                  settingWidget = _buildInputSetting(settingItem, index);
                }
                final container = Container(
                  padding: const EdgeInsets.symmetric(horizontal: _horizonPadding),
                  child: settingWidget,
                );
                return container;
              }
            ),
          ),
        ],
      ),
    );
  }
  Widget _buildSwitchSetting(SettingData settingItem) {
    var row = Row(
      key: ValueKey(settingItem.name),
      children: [
        Expanded(
          flex: _settingBodyFlexValue,
          child: Container(
            padding: const EdgeInsets.fromLTRB(_horizonPadding, _verticalPadding, _horizonPadding, _verticalPadding),
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settingItem.displayName!,
                  style: const TextStyle(fontSize: Constants.styleSettingItemFontSize),
                ),
                if (settingItem.comment != null && settingItem.comment!.isNotEmpty)
                  Text(
                    settingItem.comment!,
                    style: TextStyle(
                      fontSize: Constants.styleSettingItemFontSize - 2,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
        ),
        Container(
          // padding: const EdgeInsets.all(4),
          alignment: Alignment.centerRight,
          child: Transform.scale(
            scale: 0.8,
            child: CupertinoSwitch(
              value: settingItem.value?.toLowerCase() == 'true',
              onChanged: (value) {
                setState(() {
                  settingItem.value = value ? 'true' : 'false';
                });
                _saveSettings(settingItem);
              },
            ),
          ),
        ),
      ],
    );
    return row;
  }
  Widget _buildInputSetting(SettingData settingItem, int index) {
    var formatters = <TextInputFormatter>[];
    if(settingItem.type == SettingType.number) {
      formatters.add(FilteringTextInputFormatter.digitsOnly);
    }
    var row = Row(
      key: ValueKey(settingItem.name),
      children: [
        Expanded(
          flex: _settingBodyFlexValue,
          child: Container(
            padding: const EdgeInsets.fromLTRB(_horizonPadding, _verticalPadding, _horizonPadding, _verticalPadding),
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  settingItem.displayName!,
                  style: const TextStyle(fontSize: Constants.styleSettingItemFontSize),
                ),
                if (settingItem.comment != null && settingItem.comment!.isNotEmpty)
                  Text(
                    settingItem.comment!,
                    style: TextStyle(
                      fontSize: Constants.styleSettingItemFontSize - 2,
                      color: Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ),
        Container(
          // padding: const EdgeInsets.all(4),
          alignment: Alignment.centerRight,
          child: const Icon(Icons.navigate_next, color: Colors.grey,),
        ),
      ],
    );
    var gesture = GestureDetector(
      child: row,
      behavior: HitTestBehavior.opaque,
      onTap: () {
        _gotoDetail(settingItem);
      },
    );
    return gesture;
  }

  void _gotoDetail(SettingData settingData) {
    Navigator.push(context, CupertinoPageRoute(
      builder: (context) {
        return _DetailSettingPage(
          settingData: settingData,
          onSave: _onSave,
        );
        // return SmallScreenSettingPage(settings: widget.settings);
      },
      fullscreenDialog: true,
    ));
  }
  void _onSave(SettingData settingItem) {
    _saveSettings(settingItem);
  }
  void _exitWithoutSaving() {
    Navigator.pop(context);
  }
  void _saveSettings(SettingData settingItem) {
    Controller().setting.saveSettings([settingItem]);
  }
}

class _DetailSettingPage extends StatelessWidget {
  final SettingData settingData;
  late final TextEditingController _controller;
  final Function onSave;

  _DetailSettingPage({
    required this.settingData,
    required this.onSave,
  }) {
    _controller = TextEditingController(text: settingData.value);
  }

  @override
  Widget build(BuildContext context) {
    double padding = Constants.settingViewPhonePadding.toDouble();
    var settingDetail = _buildSetting(context);
    var bottomButtons = _buildBottomButtons(context);
    var scaffold = Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.all(padding),
              child: settingDetail,
            ),
          ),
          Container(
            padding: EdgeInsets.all(padding),
            child: bottomButtons,
          ),
        ],
      ),
    );
    return scaffold;
  }
  Widget _buildSetting(BuildContext context) {
    var list = ListView(
      shrinkWrap: true,
      children: [
        Container(
          alignment: Alignment.center,
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(_horizonPadding, _verticalPadding, _horizonPadding, _verticalPadding),
          child: Column(
            children: [
              Text(
                'Editing ${settingData.displayName}',
                style: const TextStyle(
                  fontSize: Constants.styleSettingItemFontSize,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (settingData.comment != null && settingData.comment!.isNotEmpty)
                Text(
                  settingData.comment!,
                  style: TextStyle(
                    fontSize: Constants.styleSettingItemFontSize - 2,
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),
        ),
        WidgetTemplate.buildNormalInputField('Default: ${settingData.defaultValue.isEmpty? 'None': settingData.defaultValue}', _controller),
      ],
    );
    return list;
  }
  Widget _buildBottomButtons(BuildContext context) {
    var column = Column(
      children: [
        WidgetTemplate.buildNormalButton(context, Icons.save, 'Save', _saveSetting),
        WidgetTemplate.buildInsignificantButton(Icons.arrow_back, 'Exit', () { _exitWithoutSaving(context); }, alignment: MainAxisAlignment.end),
      ],
    );
    return column;
  }
  void _exitWithoutSaving(BuildContext context) {
    Navigator.pop(context);
  }
  void _saveSetting() {
    String value = _controller.text;
    if(value == settingData.value) return;

    settingData.value = value;
    onSave(settingData);
  }
}