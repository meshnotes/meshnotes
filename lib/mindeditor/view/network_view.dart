import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../net/status.dart';
import '../controller/controller.dart';
import '../setting/constants.dart';

class NetworkDetailView extends StatelessWidget {
  final List<NodeInfo> nodes;
  final String myPublicKey;

  const NetworkDetailView({
    super.key,
    required this.nodes,
    required this.myPublicKey,
  });

  static void route(BuildContext context) {
    Navigator.push(context, CupertinoPageRoute(
      builder: (context) {
        return NetworkDetailView(nodes: Controller().network.getNetworkDetails(), myPublicKey: Controller().userPrivateInfo?.publicKey?? '');
      },
      fullscreenDialog: false,
    ));
  }

  @override
  Widget build(BuildContext context) {
    double padding = Constants.settingViewPhonePadding.toDouble();
    if(Controller().environment.isDesktop()) {
      padding = Constants.settingViewDesktopPadding.toDouble();
    }
    var topButtons = _buildTopButtons(context);
    var viewBody = _buildNetworkDetails(context);
    return Scaffold(
      body: Column(
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(0, 10, 0, 0)),
          topButtons,
          Expanded(
            child: Container(
              padding: EdgeInsets.all(padding),
              child: viewBody,
            ),
          ),
          const Padding(padding: EdgeInsets.fromLTRB(0, 0, 0, 10),),
        ],
      ),
    );
  }

  Widget _buildTopButtons(BuildContext context) {
    return Row(
      children: [
        const Spacer(),
        TextButton(
          child: const Icon(Icons.close),
          onPressed: () {
            Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Widget _buildNetworkDetails(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth > 600;

    return Column(
      children: [
        // Header
        if (isWideScreen)
          _buildWideHeader()
        else
          _buildCompactHeader(),
        // List
        Expanded(
          child: ListView.separated(
            itemCount: nodes.length,
            separatorBuilder: (context, index) => Divider(
              height: 1,
              color: Colors.grey[200],
            ),
            itemBuilder: (ctx, idx) {
              final item = nodes[idx];
              return _buildNetworkCard(item, isWideScreen);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildWideHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(40, 16, 24, 8),
      child: const Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Public Key',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Name',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Device ID',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Connection Info',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Network Nodes',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[800],
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Showing all connected and available nodes',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNetworkCard(NodeInfo item, bool isWideScreen) {
    return Card(
      margin: EdgeInsets.symmetric(
        horizontal: isWideScreen ? 16 : 8,
        vertical: 4,
      ),
      elevation: 0, // Flat design
      color: Colors.grey[50], // Lighter background color
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: Colors.grey[200]!), // Light gray border
      ),
      child: Padding(
        padding: EdgeInsets.all(isWideScreen ? 20 : 16),
        child: isWideScreen
            ? _buildWideLayout(item)
            : _buildCompactLayout(item),
      ),
    );
  }

  Widget _buildWideLayout(NodeInfo item) {
    final isCurrentUser = item.getPublicKeyComplete() == myPublicKey;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left column: public key and name
        Expanded(
          flex: 3,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Tooltip(
                message: item.getPublicKeyComplete(),
                child: RichText(
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                    ),
                    children: [
                      TextSpan(text: item.getPublicKeyForShort()),
                      const TextSpan(text: '('),
                      TextSpan(
                        text: item.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const TextSpan(text: ')'),
                    ],
                  ),
                ),
              ),
              if (isCurrentUser) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: const Text(
                    'Current User',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Middle column: device ID
        Expanded(
          flex: 2,
          child: Text(
            item.device,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[800],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // Right column: peer info and status
        Expanded(
          flex: 2,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.peer,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 4),
              _buildStatusChip(item.status),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactLayout(NodeInfo item) {
    final isCurrentUser = item.getPublicKeyComplete() == myPublicKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Public key and name with current user tag
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Tooltip(
                message: item.getPublicKeyComplete(),
                child: RichText(
                  overflow: TextOverflow.ellipsis,
                  text: TextSpan(
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[800],
                    ),
                    children: [
                      TextSpan(text: item.getPublicKeyForShort()),
                      const TextSpan(text: '('),
                      TextSpan(
                        text: item.name,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      const TextSpan(text: ')'),
                    ],
                  ),
                ),
              ),
            ),
            if (isCurrentUser) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: const Text(
                  'Current User',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.blue,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        _buildInfoRow(Icons.devices, 'Device ID', item.device),
        const SizedBox(height: 8),
        _buildInfoRow(Icons.public, 'Address', item.peer),
        const SizedBox(height: 8),
        Row(
          children: [
            Icon(
              Icons.wifi_tethering,
              size: 16,
              color: Colors.grey[400],
            ),
            const SizedBox(width: 8),
            Text(
              'Status: ',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
            _buildStatusChip(item.status),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusChip(NodeStatus status) {
    Color chipColor;
    String statusText;
    
    switch (status) {
      case NodeStatus.inContact:
        chipColor = Colors.green[700]!;
        statusText = 'Connected';
        break;
      case NodeStatus.unknown:
        chipColor = Colors.grey[700]!;
        statusText = 'Unknown';
        break;
      case NodeStatus.lost:
        chipColor = Colors.red[700]!;
        statusText = 'Lost';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: chipColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: chipColor.withOpacity(0.2)),
      ),
      child: Text(
        statusText,
        style: TextStyle(
          color: chipColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, {bool isLabel = false}) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: Colors.grey[400], // Lighter icon color
        ),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 13,
            fontWeight: isLabel ? FontWeight.w500 : FontWeight.normal,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[800],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}