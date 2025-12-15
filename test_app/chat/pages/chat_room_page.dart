import 'package:core/core.dart';
import 'package:design/assets.dart';
import 'package:design/components/f_app_bar.dart';
import 'package:design/components/f_scaffold.dart';
import 'package:design/components/f_text_field.dart';
import 'package:design/f_svg.dart';
import 'package:design/themes/f_colors.dart';
import 'package:flutter/material.dart';
import 'package:juvis/feats/home/feats/chat/domain/entities/chat_room_page_params.dart';
import 'package:juvis/feats/home/feats/chat/presentation/signals/chat_room_signal.dart';
import 'package:juvis/feats/home/feats/chat/presentation/signals/chats_signal.dart';
import 'package:juvis/feats/home/feats/chat/presentation/widgets/message_list_view.dart';
import 'package:juvis/injectable.dart';

class ChatRoomPage extends StatefulWidget {
  const ChatRoomPage({
    required this.params,
    super.key,
  });

  final ChatRoomPageParams params;

  @override
  _ChatPageState createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatRoomPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late ChatRoomSignal _chatRoomSignal;
  late ChatsSignal _chatsSignal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatRoomSignal = sl<ChatRoomSignal>(param1: widget.params);
    _chatsSignal = sl<ChatsSignal>();
    _chatRoomSignal.init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.resumed:
        _chatRoomSignal.syncChatAfterResumed();
        break;
      case AppLifecycleState.inactive:
        break;
      case AppLifecycleState.paused:
        break;
      case AppLifecycleState.detached:
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chatRoomSignal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FScaffold(
      appBar: _buildAppBar(),
      backgroundColor: FColors.of(context).backgroundNormalA,
      body: Column(
        children: [
          Expanded(
            child: MessageListView(
              roomId: widget.params.roomId,
              userId: widget.params.userId,
              ctName: widget.params.ctName,
              chatRoomSignal: _chatRoomSignal,
              chatsSignal: _chatsSignal,
            ),
          ),
          _buildInputArea(),
        ],
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 12, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: .12),
            spreadRadius: 20,
            blurRadius: 15,
            offset: const Offset(0, 2),
          ),
        ],
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _chatRoomSignal.pickAndUploadImage(),
            child: Icon(Icons.image, color: FColors.current.labelAssistive, size: 24),
          ),
          const Gap(8),
          Expanded(child: _buildTextField()),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    return GestureDetector(
      onTap: () async {
        await _chatRoomSignal.sendMessage(widget.params.roomId);
      },
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: _chatRoomSignal.isSendingChatEnabled.value ? Colors.black : Colors.grey,
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.arrow_upward, color: Colors.white, size: 20),
      ),
    );
  }

  Widget _buildTextField() {
    return FTextField.contained(
      controller: _chatRoomSignal.textController,
      focusNode: _chatRoomSignal.focusNode,
      textInputType: TextInputType.multiline,
      maxLines: 5,
      minLines: 1,
      hintText: '컨설턴트와 이야기해보세요!',
      suffixIcon: Watch((_) => _buildSendButton()),
      borderRadius: BorderRadius.circular(24),
      onChanged: (value) => _chatRoomSignal.isSendingChatEnabled.value = value.isNotEmpty,
    );
  }

  /// 앱바
  FAppBar _buildAppBar() {
    return FAppBar.back(
      context,
      title: widget.params.ctName,
      actions: [
        GestureDetector(
          onTap: () {},
          child: FSvg.asset(
            Assets.iconsNormalSearch,
            width: 24,
          ),
        ),
      ],
    );
  }
}
