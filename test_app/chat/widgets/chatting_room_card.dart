import 'package:core/core.dart';
import 'package:core/local_storage/models/chat_message.dart';
import 'package:core/local_storage/models/chat_room.dart';
import 'package:design/themes/f_colors.dart'; // Import FColors directly
import 'package:design/themes/f_font_styles.dart'; // Import FTextStyles directly
import 'package:flutter/material.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:juvis/feats/home/feats/chat/presentation/signals/chats_signal.dart';
import 'package:juvis/injectable.dart';

class ChattingRoomCard extends StatefulWidget {
  const ChattingRoomCard({
    required this.room,
    required this.onDismissed,
    required this.addController,
    required this.onTap,
    super.key,
  });

  final ChatRoom room;
  final Function(ChatRoom) onDismissed;
  final Function(SlidableController) addController;
  final VoidCallback onTap;

  @override
  State<ChattingRoomCard> createState() => _ChattingRoomCardState();
}

class _ChattingRoomCardState extends State<ChattingRoomCard> with SingleTickerProviderStateMixin {
  late final SlidableController _slidableController;

  @override
  void initState() {
    super.initState();
    _slidableController = SlidableController(this); // Correct TickerProvider
    widget.addController(_slidableController);
  }

  @override
  void dispose() {
    _slidableController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Slidable(
      key: widget.key,
      controller: _slidableController,
      groupTag: 'chat-list',
      endActionPane: ActionPane(
        extentRatio: 0.2,
        motion: const StretchMotion(),
        dismissible: DismissiblePane(
          onDismissed: () {
            widget.onDismissed(widget.room);
          },
        ),
        dragDismissible: false,
        children: [
          SlidableAction(
            onPressed: (context) {
              sl<ChatsSignal>().leaveRoom(roomId: widget.room.roomId);
              widget.onDismissed(widget.room);
            },
            backgroundColor: FColors.of(context).red,
            foregroundColor: Colors.white,
            label: '나가기',
          ),
        ],
      ),
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const CircleAvatar(
                backgroundImage: NetworkImage('https://picsum.photos/200'),
              ),
              const Gap(10),
              Expanded(
                flex: 8,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${widget.room.user.name}님과의 채팅',
                          style: FTextStyles.titleS,
                        ),
                        const Gap(4),
                        Text(getRelativeTime(widget.room.lastMessage?.timestamp)),
                      ],
                    ),
                    Text(
                      _getContent,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Flexible(
                flex: 0,
                child: FutureBuilder(
                  future: sl<ChatsSignal>().countNewMessages(widget.room.roomId),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData || snapshot.data == 0) {
                      return const SizedBox.shrink();
                    }
                    final count = snapshot.data;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: FColors.of(context).red, // Use FColors
                        borderRadius: const BorderRadius.all(Radius.circular(20)),
                      ),
                      child: Center(
                        child: Text(
                          count! >= 300 ? '300+' : '$count',
                          style: FTextStyles.bodyS.copyWith(color: Colors.white), // Changed to bodyS
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String getRelativeTime(DateTime? inputTime) {
    if (inputTime == null) {
      return '';
    }
    final now = DateTime.now();
    final difference = now.difference(inputTime);

    if (difference.inSeconds < 60) {
      return '지금';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}분 전';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}시간 전';
    } else if (difference.inDays < 30) {
      return '${difference.inDays}일 전';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months달 전';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years년 전';
    }
  }

  String get _getContent {
    final ContentType? contentType = ContentType.fromString(widget.room.lastMessage?.contentType ?? 'text');

    switch (contentType) {
      case ContentType.text:
        return widget.room.lastMessage?.content ?? '';
      case ContentType.image:
        return '사진';
      case ContentType.file:
        return '파일';
      default:
        return '';
    }
  }
}
