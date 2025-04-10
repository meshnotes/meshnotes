import 'package:my_log/my_log.dart';
import 'package:mesh_note/mindeditor/setting/constants.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/appearance_setting.dart';
import 'package:mesh_note/mindeditor/view/toolbar/base/block_format_button.dart';
import 'package:flutter/material.dart';
import 'package:mesh_note/mindeditor/controller/controller.dart';

class BlockListingButton extends StatelessWidget {
  final Controller controller;
  final AppearanceSetting appearance;
  final IconData icon;
  final String tips;
  final List<String> listing;
  final String targetListing;

  const BlockListingButton({
    Key? key,
    required this.controller,
    required this.appearance,
    required this.icon,
    required this.tips,
    required this.listing,
    required this.targetListing,
  }): super(key: key);

  @override
  Widget build(BuildContext context) {
    return BlockFormatButton(
      controller: controller,
      appearance: appearance,
      iconData: icon,
      tip: tips,
      activeOrNot: (String? _type, String? _listing, int? _level) {
        MyLogger.info('BlockListingButton: key=$targetListing, activeOrNot: $_listing, listing=$listing');
        return listing.contains(_listing);
      },
      onPressed: () {
        var blockState = controller.getEditingBlockState();
        if(blockState == null) {
          MyLogger.debug('Unable to set block listing: current editing block state is null!');
          return;
        }
        var newListing = targetListing;
        var currentListing = blockState.getBlockListing();
        if(listing.contains(currentListing)) { // Clear listing if it is already set
          newListing = Constants.blockListTypeNone;
        }
        MyLogger.debug('Setting block(id=${blockState.getBlockId()}\'s listing to: $newListing');
        blockState.setBlockListing(newListing);
      },
      buttonKey: targetListing,
    );
  }

}