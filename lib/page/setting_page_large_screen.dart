import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/setting/setting.dart';

class SettingPageLargeScreen extends StatefulWidget {
  final List<SettingGroup> groups;

  const SettingPageLargeScreen({
    super.key,
    required this.groups,
  });

  static void route(BuildContext context) {
    Navigator.push(context, CupertinoPageRoute(
      builder: (context) {
        return SettingPageLargeScreen(groups: Controller().setting.getSettingsByGroup());
      },
      fullscreenDialog: true,
    ));
  }

  @override
  State<StatefulWidget> createState() => _SettingPageLargeScreenState();
}

class _SettingPageLargeScreenState extends State<SettingPageLargeScreen> {
  final Map<String, String> newValue = {};
  final Map<String, TextEditingController> _controllers = {};
  final Set<SettingData> changedSettings = {};
  bool everChanged = false;

  @override
  void initState() {
    super.initState();
    for(var group in widget.groups) {
      for(var setting in group.settings) {
        if(setting.type == SettingType.bool) {
          newValue[setting.name] = setting.value?.toLowerCase() == 'true'? 'true': 'false';
        } else {
          newValue[setting.name] = '';
        }
        _controllers[setting.name] = TextEditingController(text: setting.value);
      }
    }
    everChanged = false;
    CallbackRegistry.hideKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    double padding = Constants.settingViewDesktopPadding.toDouble();
    var settingBody = _buildSettings(context);
    var bottomButtons = _buildBottomButtons(context);
    return Scaffold(
      body: Column(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(0, 10, 0, 0)),
          Expanded(
            child: Container(
              padding: EdgeInsets.all(padding),
              child: settingBody,
            ),
          ),
          bottomButtons,
          const Padding(padding: EdgeInsets.fromLTRB(0, 0, 0, 10),),
        ],
      )
    );
  }
  Widget _buildBottomButtons(BuildContext context) {
    var row = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        TextButton.icon(
          icon: const Icon(Icons.check),
          label: const Text('Save'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
          ),
          // style: ElevatedButton.styleFrom(
          //   backgroundColor: Colors.green[50],
          // ),
          onPressed: everChanged? _saveSettings: null,
        ),
        const Padding(padding: EdgeInsets.all(10)),
        TextButton.icon(
          icon: const Icon(Icons.clear),
          label: const Text('Exit'),
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
          ),
          onPressed: () {
            _exitWithoutSaving();
          },
        ),
      ],
    );
    return row;
  }
  Widget _buildSettings(BuildContext context) {
    var list = ListView.builder(
      itemCount: widget.groups.length,
      // shrinkWrap: true,
      itemBuilder: (context, index) {
        var group = widget.groups[index];
        final result = _buildSettingGroupWidget(index, group);
        return result;
      },
    );
    return list;
  }

  Widget _buildSettingGroupWidget(int groupIndex, SettingGroup group) {
    final groupName = group.name;
    final listView = ListView.builder(
      shrinkWrap: true,
      itemCount: group.settings.length,
      itemBuilder: (context, index) {
        late Widget item;
        final settingItem = group.settings[index];
        if(!settingItem.needDisplay) return Container();
        if(settingItem.type == SettingType.bool) {
          item = _buildBoolSetting(settingItem, index);
        } else {
          item = _buildInputSetting(settingItem, index);
        }
        return item;
      }
    );
    final result = Column(
      children: [
        if(groupIndex > 0)
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey[200]!,
          ),
        if(groupName.isNotEmpty)
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  margin: const EdgeInsets.fromLTRB(10, 20, 10, 10),
                  alignment: Alignment.centerRight,
                  child: Text(
                    groupName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              Expanded(
                flex: 7,
                child: Container(),
              ),
            ],
          ),
        listView,
      ],
    );
    return result;
  }

  Widget _buildBoolSetting(SettingData settingItem, int index) {
    final settingKey = settingItem.name;
    var row = Row(
      key: ValueKey(settingKey),
      children: [
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text((changedSettings.contains(settingItem)? '*': '') + settingItem.displayName!),
                if (settingItem.comment != null && settingItem.comment!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: settingItem.comment!,
                      child: const Icon(
                        Icons.help_outline,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 7,
          child: Container(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerLeft,
            child: Transform.scale(
              scale: 0.8,
              child: CupertinoSwitch(
                value: newValue[settingKey]?.toLowerCase() == 'true',
                onChanged: (value) {
                  _onBoolChanged(settingItem, value);
                },
              ),
            ),
          ),
        ),
      ],
    );
    return row;
  }

  Widget _buildInputSetting(SettingData settingItem, int index) {
    final settingKey = settingItem.name;
    var formatters = <TextInputFormatter>[];
    if(settingItem.type == SettingType.number) {
      formatters.add(FilteringTextInputFormatter.digitsOnly);
    }
    var row = Row(
      key: ValueKey(settingKey),
      children: [
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text((changedSettings.contains(settingItem)? '*': '') + settingItem.displayName!),
                if (settingItem.comment != null && settingItem.comment!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: settingItem.comment!,
                      child: const Icon(
                        Icons.help_outline,
                        size: 16,
                        color: Colors.grey,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          flex: 7,
          child: Container(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerLeft,
            child: CupertinoTextField(
              controller: _controllers[settingKey],
              placeholder: 'Default: ${settingItem.defaultValue.isEmpty? 'None': settingItem.defaultValue}',
              autofocus: true,
              inputFormatters: formatters,
              onChanged: (text) {
                _onTextChanged(settingItem, text);
              },
            ),
          ),
        ),
      ],
    );
    return row;
  }

  void _onBoolChanged(SettingData settingItem, bool boolValue) {
    final settingKey = settingItem.name;   
    final value = boolValue? 'true': 'false';
    if(settingItem.value != value) {
      newValue[settingKey] = value;
      changedSettings.add(settingItem);
      everChanged = true;
      setState(() {
      });
    }
  }

  void _onTextChanged(SettingData settingItem, String value) {
    final settingKey = settingItem.name;
    if(settingItem.value != value) {
      newValue[settingKey] = value;
      changedSettings.add(settingItem);
      everChanged = true;
      setState(() {
      });
    }
  }

  void _exitWithoutSaving() {
    Navigator.pop(context);
  }

  void _saveSettings() {
    if(!everChanged) return;
    var settingsToSave = <SettingData>[];
    for(var settingItem in changedSettings) {
      settingItem.value = newValue[settingItem.name];
      settingsToSave.add(settingItem);
    }
    everChanged = false;
    changedSettings.clear();
    Controller().setting.saveSettings(settingsToSave);
    setState(() {
    });
  }
}