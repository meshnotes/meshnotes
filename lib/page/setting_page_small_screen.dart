import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mesh_note/mindeditor/controller/callback_registry.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';
import '../mindeditor/setting/constants.dart';
import '../mindeditor/setting/setting.dart';
import 'widget_templates.dart';

class SettingPageSmallScreen extends StatefulWidget {
  final List<SettingData> settings;

  const SettingPageSmallScreen({
    super.key,
    required this.settings,
  });

  static void route(BuildContext context) {
    Navigator.push(context, CupertinoPageRoute(
      builder: (context) {
        return SettingPageSmallScreen(settings: Controller().setting.getSettings());
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
  List<String> newValue = [];
  List<bool> hasChanged = [];
  final List<TextEditingController> _controllers = [];
  bool everChanged = false;
  static const _settingBodyFlexValue = 7;

  @override
  void initState() {
    super.initState();
    for(var item in widget.settings) {
      newValue.add('');
      hasChanged.add(false);
      _controllers.add(TextEditingController(text: item.value));
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
      body: Column(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.all(padding),
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
        TextButton.icon(
          icon: Icon(Icons.arrow_back, color: Colors.grey[600],),
          label: Text('Exit', style: TextStyle(color: Colors.grey[600]),),
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
          ),
          // style: ElevatedButton.styleFrom(
          //   backgroundColor: Colors.green[50],
          // ),
          onPressed: () {
            _exitWithoutSaving();
          },
        ),
      ],
    );
    return row;
  }
  Widget _buildSettingList(BuildContext context) {
    var list = ListView.separated(
      itemCount: widget.settings.length + 1,
      shrinkWrap: true,
      itemBuilder: (context, index) {
        if(index == 0) { // A padding before the first item
          return Container(
            alignment: Alignment.center,
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(_horizonPadding, _verticalPadding, _horizonPadding, _verticalPadding),
            child: const Text('Settings', style: TextStyle(fontSize: Constants.styleTitleFontSize, fontWeight: FontWeight.bold),),
          );
        }
        index -= 1;
        var settingItem = widget.settings[index];
        if(settingItem.type == SettingType.bool) {
          return _buildSwitchSetting(settingItem);
        }
        return _buildInputSetting(settingItem, index);
      },
      separatorBuilder: (BuildContext context, int index) {
        return Divider(height: 1.0, color: Colors.grey[100],);
      },
    );
    return list;
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
            child: Text(
              settingItem.displayName!,
              style: const TextStyle(fontSize: Constants.styleTitleFontSize,),
            ),
          ),
        ),
        Container(
          // padding: const EdgeInsets.all(4),
          alignment: Alignment.centerRight,
          child: CupertinoSwitch(
            value: settingItem.value?.toLowerCase() == 'true',
            onChanged: (value) {
              setState(() {
                settingItem.value = value ? 'true' : 'false';
              });
              Controller().setting.saveSettings(widget.settings);
            },
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
            child: Text(
              settingItem.displayName!,
              style: const TextStyle(fontSize: Constants.styleTitleFontSize,),
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
        _gotoDetail(widget.settings[index]);
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
  void _onSave() {
    Controller().setting.saveSettings(widget.settings);
  }
  void _exitWithoutSaving() {
    Navigator.pop(context);
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
          // const Padding(padding: EdgeInsets.fromLTRB(0, 0, 0, 10),),
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
          child: Text('Editing ${settingData.displayName}', style: const TextStyle(fontSize: Constants.styleTitleFontSize, fontWeight: FontWeight.bold),),
        ),
        WidgetTemplate.buildNormalInputField(settingData.comment!, _controller),
      ],
    );
    return list;
  }
  Widget _buildBottomButtons(BuildContext context) {
    var column = Column(
      children: [
        WidgetTemplate.buildNormalButton(Icons.save, 'Save', _saveSetting),
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
    onSave();
  }
}