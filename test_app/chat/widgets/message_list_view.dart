import 'package:cached_network_image/cached_network_image.dart';
import 'package:core/core.dart';
import 'package:core/injectable.dart';
import 'package:core/local_storage/models/chat_message.dart';
import 'package:flutter/material.dart';
import 'package:juvis/core/router/router.dart';
import 'package:juvis/feats/auth/presentation/signals/user_signal.dart';
import 'package:juvis/feats/home/feats/chat/domain/entities/message_detail_page_params.dart';
import 'package:juvis/feats/home/feats/chat/presentation/signals/chat_room_signal.dart';
import 'package:juvis/feats/home/feats/chat/presentation/signals/chats_signal.dart';
import 'package:juvis/feats/home/feats/chat/presentation/widgets/empty_message.dart';

class MessageListView extends StatefulWidget {
  const MessageListView({
    super.key,
    required this.chatRoomSignal,
    required this.chatsSignal,
    required this.roomId,
    required this.userId,
    required this.ctName,
  });

  final ChatRoomSignal chatRoomSignal;
  final ChatsSignal chatsSignal;

  final String roomId;
  final String userId;
  final String ctName;

  @override
  State<MessageListView> createState() => _MessageListViewState();
}

class _MessageListViewState extends State<MessageListView> with SingleTickerProviderStateMixin {
  late Animation<Offset> _slideAnimation;
  late Animation<double> _opacityAnimation;
  late ChatRoomSignal _chatRoomSignal;
  late ChatsSignal _chatsSignal;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _chatRoomSignal = widget.chatRoomSignal;
    _chatRoomSignal.scrollController.addListener(() => _onScroll());
    _chatsSignal = widget.chatsSignal;
    _setupAnimations();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: _chatRoomSignal.minAnimationDuration),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 1),
      end: const Offset(0, 0),
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _opacityAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.dismissed) setState(() {});
    });
  }

  void _onScroll() {
    // 기존 스크롤 로직
    if (_chatRoomSignal.scrollController.position.pixels < _chatRoomSignal.minScrollPoint) {
      _chatsSignal.hasNewMessage.value = false;
    }
    if (_chatRoomSignal.scrollController.position.pixels > _chatRoomSignal.minScrollPoint) {
      if (!_animationController.isCompleted) _animationController.forward();
    } else {
      if (_animationController.isCompleted) _animationController.reverse();
    }
    // 상단 스크롤 감지 및 이전 메시지 로드
    if (_chatRoomSignal.scrollController.position.pixels == _chatRoomSignal.scrollController.position.maxScrollExtent) {
      _chatRoomSignal.loadMoreMessages();
    }
  }

  @override
  Widget build(BuildContext context) {
    // messages와 hasNewMessage를 각각 추적
    return Stack(
      children: [
        Align(
          alignment: Alignment.topCenter,
          child: Watch(
            (_) {
              final messages = _chatRoomSignal.messages.value;
              if (messages.isEmpty) {
                return EmptyMessage(ctName: widget.ctName);
              }
              // expandedStates 관리
              for (var message in messages) {
                final messageId = message.index ?? 0;
                _chatRoomSignal.expandedStates.putIfAbsent(messageId, () => false);
              }
              _chatRoomSignal.expandedStates
                  .removeWhere((key, _) => !messages.any((m) => m.index == key || m.id == key));

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                controller: _chatRoomSignal.scrollController,
                reverse: true,
                itemCount: messages.length,
                itemBuilder: (context, index) {
                  final reversedIndex = messages.length - 1 - index;
                  final message = messages[reversedIndex];
                  final showDateDivider = shouldShowDateDivider(reversedIndex, messages);
                  return Column(
                    children: [
                      if (showDateDivider) _buildDateDivider(message.timestamp),
                      _buildMessageItem(message, index, messages),
                    ],
                  );
                },
              );
            },
          ),
        ),
        Watch(
          (context) {
            return Positioned(
              // hasNewMessage에 따라 위치와 버튼 UI가 변경되므로 여기에도 Watch 적용
              left: _chatsSignal.hasNewMessage.value
                  ? MediaQuery.of(context).size.width / 2 - 80
                  : MediaQuery.of(context).size.width / 2 - 24,

              bottom: 20,
              child: scrollBottomButton(_chatsSignal.hasNewMessage.value),
            );
          },
        ),
      ],
    );
  }

  AnimatedBuilder scrollBottomButton(bool hasNewMessage) {
    return AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        return AnimatedOpacity(
          opacity: _opacityAnimation.value,
          duration: Duration(milliseconds: _chatRoomSignal.minAnimationDuration),
          child: SlideTransition(
            position: _slideAnimation,
            child: GestureDetector(
              onTap: () {
                _chatRoomSignal.scrollToBottom();
                setState(() {});
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                width: hasNewMessage ? 160 : 48,
                height: 48,
                decoration: BoxDecoration(
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: .08),
                      spreadRadius: 15,
                      blurRadius: 15,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  color: Colors.white,
                  shape: hasNewMessage ? BoxShape.rectangle : BoxShape.circle,
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: hasNewMessage
                    ? const Center(
                        child: Text(
                          '세 메세지 확인하기',
                        ),
                      )
                    : const Icon(Icons.arrow_downward, color: Colors.black, size: 22),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageItem(ChatMessage message, int index, List<ChatMessage> messages) {
    final isMyMessage = message.userId != widget.userId;
    final reversedIndex = messages.length - 1 - index; // 이미 계산된 값 활용
    final isFirstMessageOrDifferentTime = shouldShowProfile(reversedIndex, messages);
    final showTime = shouldShowTime(reversedIndex, messages);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.only(
            top: isFirstMessageOrDifferentTime ? 20.0 : 8.0,
            bottom: index == messages.length - 1 ? 20.0 : 0.0,
          ),
          child: _buildMessageRow(message, isMyMessage, isFirstMessageOrDifferentTime, showTime),
        ),
      ],
    );
  }

  Widget _buildMessageRow(ChatMessage message, bool isMyMessage, bool isFirstMessageOrDifferentTime, bool showTime) {
    return Row(
      mainAxisAlignment: isMyMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isMyMessage) _buildProfileSection(isFirstMessageOrDifferentTime),
        Flexible(
          child: Column(
            crossAxisAlignment: isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (!isMyMessage && isFirstMessageOrDifferentTime) _buildUserName(),
              _buildMessageContent(message, isMyMessage, showTime),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfileSection(bool isFirstMessageOrDifferentTime) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isFirstMessageOrDifferentTime) ...[
          const CircleAvatar(radius: 20, child: Icon(Icons.person)),
          const SizedBox(width: 8),
        ] else ...[
          const SizedBox(width: 48),
        ],
      ],
    );
  }

  Widget _buildUserName() {
    return Padding(
      padding: const EdgeInsets.only(left: 4.0, bottom: 4.0),
      child: Text(widget.ctName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
    );
  }

  Widget _buildMessageContent(ChatMessage message, bool isMyMessage, bool showTime) {
    final messageId = message.index;
    final isExpanded = _chatRoomSignal.expandedStates[messageId] ?? false;
    final content = message.content ?? '';

    return Column(
      crossAxisAlignment: isMyMessage ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!isMyMessage) _buildReceivedMessage(message, showTime, isExpanded),
        if (isMyMessage) ...[
          Row(
            mainAxisSize: MainAxisSize.min, // 추가
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Watch((_) {
                if (messageId != null && _chatsSignal.lastCheckedMessageIndex.value < messageId) return const Text('1');
                return const SizedBox.shrink();
              }),
              Flexible(
                // 추가
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Container(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.9,
                      ),
                      child: _buildSentMessage(isExpanded, content, message.contentType, message.id.toString()),
                    );
                  },
                ),
              ),
            ],
          ),
          if (showTime) ...[
            const SizedBox(height: 4),
            _buildTimeStamp(
              message.timestamp,
              isRight: true,
            ),
          ],
        ],
      ],
    );
  }

  Widget _buildReceivedMessage(
    ChatMessage message,
    bool showTime,
    bool isExpanded,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(right: 16),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE5E5E5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              message.contentType == ContentType.image
                  ? GestureDetector(
                      onTap: () => context.pushNamed(
                        AppRoutePath.messageDetail.name,
                        extra: MessageDetailPageParams(
                          userName: widget.ctName,
                          content: message.content!,
                          contentType: message.contentType.type,
                          messageId: message.id.toString(),
                        ),
                      ),
                      child: Hero(
                        tag: message.id.toString(),
                        child: CachedNetworkImage(
                          imageUrl: message.content!,
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  : Text(message.content!, maxLines: 5, style: const TextStyle(fontSize: 14, color: Colors.black)),
              if (!isExpanded && (message.content!.length) > _chatRoomSignal.limitedMessageLength) ...[
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.center,
                  child: GestureDetector(
                    onTap: () => context.pushNamed(
                      AppRoutePath.messageDetail.name,
                      extra: MessageDetailPageParams(
                        userName: widget.ctName,
                        content: message.content!,
                        contentType: message.contentType.type,
                        messageId: message.id.toString(),
                      ),
                    ),
                    child: const SizedBox(
                      height: 24,
                      child: Row(
                        children: [
                          Text(
                            '전체보기',
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 14,
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (showTime) ...[
          const SizedBox(height: 4),
          _buildTimeStamp(
            message.timestamp,
            isRight: false,
          ),
        ],
      ],
    );
  }

  Widget _buildSentMessage(bool isExpanded, String displayText, ContentType contentType, String messageId) {
    return Container(
      margin: const EdgeInsets.only(left: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFE6E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFFDADA)),
      ),
      child: Column(
        children: [
          contentType == ContentType.image
              ? GestureDetector(
                  onTap: () => context.pushNamed(
                    AppRoutePath.messageDetail.name,
                    extra: MessageDetailPageParams(
                      userName: sl<UserSignal>().userInfo?.name ?? '',
                      content: displayText,
                      contentType: contentType.type,
                      messageId: messageId,
                    ),
                  ),
                  child: Hero(
                    tag: messageId,
                    child: CachedNetworkImage(
                      imageUrl: displayText,
                      fit: BoxFit.cover,
                    ),
                  ),
                )
              : Text(displayText, maxLines: 5, style: const TextStyle(fontSize: 14, color: Colors.black)),
          if (!isExpanded && (displayText.length) > _chatRoomSignal.limitedMessageLength) ...[
            Align(
              alignment: Alignment.center,
              child: GestureDetector(
                onTap: () => context.pushNamed(
                  AppRoutePath.messageDetail.name,
                  extra: MessageDetailPageParams(
                    userName: widget.ctName,
                    content: displayText,
                    contentType: contentType.type,
                    messageId: messageId,
                  ),
                ),
                child: const SizedBox(
                  height: 24,
                  child: Row(
                    children: [
                      Text('전체보기', style: TextStyle(color: Colors.black, fontSize: 14)),
                      Icon(Icons.chevron_right, size: 22),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTimeStamp(DateTime timestamp, {required bool isRight}) {
    return Padding(
      padding: EdgeInsets.only(
        right: isRight ? 0 : 8,
        left: isRight ? 8 : 0,
        top: 2, // 시간과 메시지 사이에 간격
      ),
      child: Text(
        formatMessageTime(timestamp),
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      ),
    );
  }

  Widget _buildDateDivider(DateTime timestamp) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Text(
          '${timestamp.year}년 ${timestamp.month}월 ${timestamp.day}일',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.grey, fontSize: 12),
        ),
      ),
    );
  }

  bool shouldShowDateDivider(int index, List<ChatMessage> messages) {
    if (index == 0) return true;
    final currentMessage = messages[index];
    final previousMessage = messages[index - 1];
    final currentDate = currentMessage.timestamp;
    final previousDate = previousMessage.timestamp;
    return currentDate.year != previousDate.year ||
        currentDate.month != previousDate.month ||
        currentDate.day != previousDate.day;
  }

  bool shouldShowProfile(int index, List<ChatMessage> messages) {
    if (index == 0) return true;
    final currentMessage = messages[index];
    final previousMessage = messages[index - 1];
    return currentMessage.userId != previousMessage.userId ||
        (currentMessage.timestamp.millisecondsSinceEpoch - previousMessage.timestamp.millisecondsSinceEpoch).abs() >=
            60000;
  }

  bool shouldShowTime(int index, List<ChatMessage> messages) {
    if (index == messages.length - 1) return true;
    final currentMessage = messages[index];
    final nextMessage = messages[index + 1];
    return currentMessage.userId != nextMessage.userId ||
        (nextMessage.timestamp.millisecondsSinceEpoch - currentMessage.timestamp.millisecondsSinceEpoch).abs() >= 60000;
  }

  String formatMessageTime(DateTime timestamp) {
    final hour = timestamp.hour;
    final period = hour < 12 ? '오전' : '오후';
    final hour12 = hour == 12 ? 12 : hour % 12;
    final minute = timestamp.minute.toString().padLeft(2, '0');
    return '$period ${hour12.toString()}:$minute';
  }
}
