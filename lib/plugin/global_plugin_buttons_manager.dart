import 'package:flutter/material.dart';
import 'package:my_log/my_log.dart';

import 'plugin_api.dart';

class GlobalPluginButtonsManager extends StatefulWidget {
  final List<GlobalToolbarInformation> tools;
  const GlobalPluginButtonsManager({super.key, required this.tools});
  @override
  GlobalPluginButtonsManagerState createState() => GlobalPluginButtonsManagerState();
}

enum _ButtonState {
  folded, // Show an arrow icon, press to unfold
  unfolded, // Show a button list, press to display dialog, and hide the button
  hidden, // Hidden buttons and show dialog
}

class GlobalPluginButtonsManagerState extends State<GlobalPluginButtonsManager> {
  // Vertical relative position of the right button
  double _rightButtonVerticalPosition = 0.5;
  static const buttonHeight = 32.0;
  static const buttonWidth = 20.0;
  static const foldIconSize = 24.0;
  static const buttonIconSize = 20.0;
  static const radiusSize = 20.0;
  _ButtonState _rightButtonState = _ButtonState.folded;
  Widget? _dialog;

  @override
  Widget build(BuildContext context) {
    final buttonTop = _calculateButtonTop();
    switch (_rightButtonState) {
      case _ButtonState.folded:
        return _buildFoldedMovableRightButton(buttonTop);
      case _ButtonState.unfolded:
        return _buildUnfoldedButtons(buttonTop);
      case _ButtonState.hidden:
        return _dialog ?? const SizedBox.shrink();
    }
  }
  
  double _calculateButtonTop() {
    final screenHeight = MediaQuery.of(context).size.height;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    
    // Calculate the safe area height for the button to move
    final safeHeight = screenHeight - safeAreaTop - safeAreaBottom - buttonHeight;
    
    // Calculate the actual position of the button
    final buttonTop = safeAreaTop + (_rightButtonVerticalPosition * safeHeight);
    return buttonTop;
  }
  double _calculateSafeHeight() {
    final screenHeight = MediaQuery.of(context).size.height;
    final safeAreaTop = MediaQuery.of(context).padding.top;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    return screenHeight - safeAreaTop - safeAreaBottom - buttonHeight;
  }
  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      final safeHeight = _calculateSafeHeight();
      // Calculate the new vertical position percentage
      final newPosition = _rightButtonVerticalPosition + (details.delta.dy / safeHeight);
      // Ensure the position is between 0 and 1
      _rightButtonVerticalPosition = newPosition.clamp(0.0, 1.0);
    });
  }
  Widget _buildFoldedMovableRightButton(double buttonTop) {
    return Positioned(
      top: buttonTop,
      right: 0, // Fix to right side
      child: GestureDetector(
        // Handle drag events
        onVerticalDragUpdate: _onDragUpdate,
        child: Container(
          height: buttonHeight,
          width: buttonWidth,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(radiusSize),
              bottomLeft: Radius.circular(radiusSize),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 5.0,
                offset: Offset(-2, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _onRightButtonPressed,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(radiusSize),
                bottomLeft: Radius.circular(radiusSize),
              ),
              child: const Icon(
                Icons.arrow_left,
                color: Colors.grey,
                size: foldIconSize,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnfoldedButtons(double buttonTop) {
    return Stack(
      children: [
        // Full screen transparent overlay to detect taps outside the toolbar
        Positioned.fill(
          child: GestureDetector(
            onTap: foldButtons,
            behavior: HitTestBehavior.translucent,
          ),
        ),
        // The actual toolbar
        Positioned(
          top: buttonTop,
          right: 0,
          child: GestureDetector(
            // Prevent taps on the toolbar from triggering the overlay
            onTap: () {},
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Tools container
                Container(
                  height: buttonHeight,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(radiusSize),
                      bottomLeft: Radius.circular(radiusSize),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black26,
                        blurRadius: 5.0,
                        offset: Offset(-2, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(width: 8),
                      // Display all tool buttons
                      ...widget.tools.map((tool) => Container(
                        child: IconButton(
                          icon: Icon(
                            tool.buttonIcon,
                            size: buttonIconSize,
                          ),
                          onPressed: () {
                            final dialog = tool.buildWidget(hideDialog);
                            if(dialog != null) {
                              showDialog(dialog);
                            }
                          },
                          tooltip: tool.tip,
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: EdgeInsets.zero,
                        ),
                      )).toList(),
                      const SizedBox(width: 4),
                      SizedBox(
                        height: buttonHeight,
                        width: buttonWidth,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _onRightButtonPressed,
                            child: const Icon(
                              Icons.arrow_right,
                              color: Colors.grey,
                              size: foldIconSize,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // Fold button
              ],
            ),
          ),
        ),
      ],
    );
  }

  void showDialog(Widget dialog) {
    setState(() {
      _dialog = dialog;
      _rightButtonState = _ButtonState.hidden;
    });
  }
  void hideDialog() {
    setState(() {
      _rightButtonState = _ButtonState.folded;
    });
  }
  void hideButtons() {
    setState(() {
      _rightButtonState = _ButtonState.hidden;
    });
  }
  void showButtons() {
    setState(() {
      _rightButtonState = _ButtonState.unfolded;
    });
  }
  void foldButtons() {
    setState(() {
      _rightButtonState = _ButtonState.folded;
    });
  }
  
  // Right button click handler
  void _onRightButtonPressed() {
    if (_rightButtonState == _ButtonState.folded) {
      showButtons();
    } else {
      foldButtons();
    }
  }
}

