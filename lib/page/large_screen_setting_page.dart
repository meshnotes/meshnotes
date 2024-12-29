import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import 'package:my_log/my_log.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/setting/setting.dart';

class LargeScreenSettingPage extends StatefulWidget {
  final List<SettingData> settings;

  const LargeScreenSettingPage({
    super.key,
    required this.settings,
  });

  static void route(BuildContext context) {
    Navigator.push(context, CupertinoPageRoute(
      builder: (context) {
        return LargeScreenSettingPage(settings: Controller().setting.getSettings());
      },
      fullscreenDialog: true,
    ));
  }

  @override
  State<StatefulWidget> createState() => _LargeScreenSettingPageState();
}

class _LargeScreenSettingPageState extends State<LargeScreenSettingPage> {
  List<String> newValue = [];
  List<bool> hasChanged = [];
  final List<TextEditingController> _controllers = [];
  bool everChanged = false;

  @override
  void initState() {
    super.initState();
    for(var item in widget.settings) {
      if(item.type == SettingType.bool) {
        newValue.add(item.value?.toLowerCase() == 'true'? 'true': 'false');
      } else {
        newValue.add('');
      }
      hasChanged.add(false);
      _controllers.add(TextEditingController(text: item.value));
    }
    everChanged = false;
    CallbackRegistry.hideKeyboard();
  }

  @override
  Widget build(BuildContext context) {
    double padding = Constants.settingViewDesktopPadding.toDouble();
    var _ = _buildTopButtons(context); //TODO Perhaps better to delete this
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
  Widget _buildTopButtons(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        TextButton(
          child: const Icon(Icons.close),
          onPressed: () {
            _exitWithoutSaving();
          },
        ),
      ],
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
      itemCount: widget.settings.length,
      // shrinkWrap: true,
      itemBuilder: (context, index) {
        var settingItem = widget.settings[index];
        if(settingItem.type == SettingType.bool) {
          return _buildBoolSetting(settingItem, index);
        }
        return _buildInputSetting(settingItem, index);
      },
    );
    return list;
  }

  Widget _buildBoolSetting(SettingData settingItem, int index) {
    MyLogger.info('efantest: value=${newValue[index]}');
    var row = Row(
      key: ValueKey(settingItem.name),
      children: [
        Expanded(
          flex: 3,
          child: Container(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerRight,
            child: Text((hasChanged[index]? '*': '') + settingItem.displayName!),
          ),
        ),
        Expanded(
          flex: 7,
          child: Container(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerLeft,
            child: CupertinoSwitch(
              value: newValue[index].toLowerCase() == 'true',
              onChanged: (value) {
                _onBoolChanged(index, value);
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
          flex: 3,
          child: Container(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerRight,
            child: Text((hasChanged[index]? '*': '') + settingItem.displayName!),
          ),
        ),
        Expanded(
          flex: 7,
          child: Container(
            padding: const EdgeInsets.all(10),
            alignment: Alignment.centerLeft,
            child: CupertinoTextField(
              controller: _controllers[index],
              placeholder: settingItem.comment,
              // decoration: InputDecoration(
              //   hintText:
              //   border: const OutlineInputBorder(),
              // ),
              autofocus: true,
              inputFormatters: formatters,
              onChanged: (text) {
                _onTextChanged(index, text);
              },
            ),
          ),
        ),
      ],
    );
    return row;
  }

  void _onBoolChanged(int index, bool value) {
    if(index < 0 || index >= widget.settings.length) return;
    var item = widget.settings[index];
    setState(() {
      newValue[index] = value? 'true': 'false';
      hasChanged[index] = item.value != newValue[index];
      everChanged = item.value != newValue[index]? true: everChanged;
    });
  }

  void _onTextChanged(int index, String value) {
    if(index < 0 || index >= widget.settings.length) return;
    var item = widget.settings[index];
    setState(() {
      newValue[index] = value;
      hasChanged[index] = item.value != value;
      everChanged = item.value != value? true: everChanged;
    });
  }

  void _exitWithoutSaving() {
    Navigator.pop(context);
  }

  void _saveSettings() {
    if(!everChanged) return;
    var settingsToSave = <SettingData>[];
    for(var i = 0; i < hasChanged.length; i++) {
      if(hasChanged[i]) {
        widget.settings[i].value = newValue[i];
        hasChanged[i] = false;
        settingsToSave.add(widget.settings[i]);
      }
    }
    everChanged = false;
    //TODO Should use async save here
    Controller().setting.saveSettings(settingsToSave);
    setState(() {
    });
  }
}